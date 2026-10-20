import Foundation
import AVFAudio
import os
import Testing
@testable import RPMAudio

/// Polls until `done` is true, or records an issue after `within`.
///
/// These tests play through the machine's real output device. On a shared CI Mac the device can
/// start late, by more than a second. A fixed sleep then fails on a slow start, so the tests wait
/// for the state they need and check the result after that.
private func until(_ what: String, within: Duration = .seconds(10),
                   _ done: @Sendable () -> Bool) async throws {
    let end = ContinuousClock.now.advanced(by: within)
    while ContinuousClock.now < end {
        if done() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("timed out waiting for \(what)")
}

/// Checks that sound is actually output.
///
/// These tests run on macOS, which has an output device and no audio session to claim. They check
/// what can be checked from inside the process: the node's own clock moving. **A clock that
/// advances means sound is leaving the engine.** The node reports the position of the renderer,
/// not the position of the scheduler.
@Suite("The engine plays what the decoder makes", .serialized)
struct PcmEngineTests {

    private func tone() throws -> StreamedPcm {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
        let source = StreamedPcm()

        // In pieces, because that is how it will arrive.
        let bytes = try Data(contentsOf: url)
        for at in stride(from: 0, to: bytes.count, by: 4096) {
            try source.take(bytes[at..<min(at + 4096, bytes.count)])
        }
        source.finish(.theFileRanOut)

        return source
    }

    @Test func aStreamWithNoFormatYetIsNotSomethingToPlay() {
        let engine = PcmEngine(normalize: NormalizeContext())
        #expect(throws: PcmEngine.Trouble.noFormat) { try engine.play(StreamedPcm(), loudness: .unmeasured, because: .somebodyAskedForIt) }
    }

    @Test func theNeedleMovesWhileItPlays() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())
        try engine.play(try tone(), loudness: .unmeasured, because: .somebodyAskedForIt)

        // **The node does not start yet, on purpose.** It waits until a cushion of audio is
        // buffered. Starting on the first buffer made a track cut in and out during its first few
        // seconds.
        #expect(engine.priming)
        #expect(!engine.isPlaying)

        try await until("the engine to start") { engine.isPlaying && engine.position > 0 }
        #expect(!engine.priming)
        let early = engine.position

        try await Task.sleep(for: .milliseconds(600))
        let later = engine.position

        engine.stop()

        #expect(early > 0, "nothing had been rendered after half a second")
        #expect(later > early, "the clock stopped: \(early) then \(later)")
    }

    @Test func aPauseStopsTheClockAndAResumeStartsItAgain() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())
        try engine.play(try tone(), loudness: .unmeasured, because: .somebodyAskedForIt)

        try await until("the engine to start") { engine.position > 0 }
        engine.pause()

        let held = engine.position
        try await Task.sleep(for: .milliseconds(300))
        #expect(engine.position == held, "it kept going after pause")

        try engine.resume()
        try await until("the clock to start again") { engine.position > held }

        engine.stop()
    }

    /// **A seek on a paused record.** The needle is moved, and the same track is asked for again
    /// from another second. The node starts as soon as a cushion of audio is buffered.
    /// `startIfThereIsEnough` does not check whether the engine is paused. If `paused` stayed set
    /// from the previous source, sound would play while `isPaused` said it did not. The play
    /// control would then show a play icon over a record that is playing.
    @Test func aSourceBegunOnAPausedEngineIsNotPaused() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())
        try engine.play(try tone(), loudness: .unmeasured, because: .somebodyAskedForIt)

        try await Task.sleep(for: .milliseconds(400))
        engine.pause()
        #expect(engine.isPaused)

        // The same track, asked for again as a seek does. The source starts at its own start,
        // as `TrackFeed.moveTo` returns it. The engine's `from` gives the position of the source
        // on the record's clock, so a source that starts at zero is started at zero.
        try engine.play(try tone(), loudness: .unmeasured, because: .somebodyAskedForIt)

        #expect(!engine.isPaused, "the pause outlived the source it was pressed against")

        // This waits for the position to move, instead of sleeping for a fixed time. A fixed
        // 600 ms wait failed when the full suite ran in parallel, because the decoder starts late.
        // If the position is still zero after five seconds, the engine is not playing.
        let end = ContinuousClock.now.advanced(by: .seconds(5))
        while engine.position == 0, ContinuousClock.now < end {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(engine.position > 0, "it said it was not paused and played nothing")

        engine.stop()
    }

    /// A pause pressed while the source is still loading is not lost. `Transport.arrives` hands
    /// the pause back, and it is applied again when the source arrives. This must keep working.
    @Test func aPauseCanStillBeAppliedTheMomentASourceArrives() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())
        try engine.play(try tone(), loudness: .unmeasured, because: .somebodyAskedForIt)
        engine.pause()

        try await Task.sleep(for: .milliseconds(300))
        let held = engine.position
        try await Task.sleep(for: .milliseconds(300))

        #expect(engine.isPaused)
        #expect(engine.position == held, "it played through a pause applied on arrival")

        engine.stop()
    }

    /// A stop removes the audio that was scheduled but not yet heard. This makes it an immediate
    /// stop, not a fade.
    @Test func aStopIsImmediate() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())
        try engine.play(try tone(), loudness: .unmeasured, because: .somebodyAskedForIt)

        try await Task.sleep(for: .milliseconds(400))
        engine.stop()

        #expect(!engine.isPlaying)
    }
}

/// One record after another with no gap between them.
///
/// The fixture is three seconds long, so two of them make six seconds. The engine must know
/// **which of the two is being heard**, not which one was handed over last. The two differ by the
/// audio still buffered in front of the speaker.
@Suite("One record follows another", .serialized)
struct GaplessTests {

    private func tone() throws -> StreamedPcm {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
        let source = StreamedPcm()
        try source.take(try Data(contentsOf: url))
        source.finish(.theFileRanOut)
        return source
    }

    @Test func theSecondRecordIsNotSaidToBePlayingWhileTheFirstStillIs() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())

        let moved = OSAllocatedUnfairLock(initialState: [Int]())
        engine.moved = { id in moved.withLock { $0.append(id) } }

        try engine.play(try tone(), id: 1, loudness: .unmeasured, because: .somebodyAskedForIt)
        engine.queue(try tone(), id: 2, loudness: .unmeasured)

        // Both records are handed over almost at once, because three seconds of AAC decodes in a
        // few milliseconds. The engine must not report a track change at this point.
        try await Task.sleep(for: .milliseconds(700))

        #expect(engine.playing == 1, "it moved on before the first record had played")
        #expect(engine.position < 3, "the needle is past the end of the first record")
        #expect(moved.withLock { $0 } == [1])

        engine.stop()
    }

    /// **The position counts from the start of the record that is playing.** When the second
    /// record starts, the position goes back to zero. Otherwise the needle would show the first
    /// record's time.
    @Test func theNeedleRestartsWithTheRecordRatherThanWithTheNode() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())

        let moved = OSAllocatedUnfairLock(initialState: [Int]())
        engine.moved = { id in moved.withLock { $0.append(id) } }

        try engine.play(try tone(), id: 1, loudness: .unmeasured, because: .somebodyAskedForIt)
        engine.queue(try tone(), id: 2, loudness: .unmeasured)

        // The first record is three seconds long. Wait for the second to be in and announced: the
        // engine sets playing before it calls moved, so waiting for playing alone can check moved
        // too early.
        try await until("the second record") { engine.playing == 2 && moved.withLock { $0 }.count == 2 }

        #expect(engine.playing == 2, "it never moved on")
        #expect(engine.position < 1.5, "the needle carried the first record's time over")
        #expect(moved.withLock { $0 } == [1, 2], "the change was announced \(moved.withLock { $0 })")

        engine.stop()
    }

    // ── the queue is changed while a record is loaded ──

    /// **The next record was loaded for an order that no longer exists.** The look-ahead hands the
    /// next record over early, a whole track in advance. If the queue is rearranged before the
    /// current track ends, that record stays loaded behind the needle. Nothing above this engine
    /// can see it.
    @Test func aRearrangedListTakesBackWhatWasLoadedForTheOldOne() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())

        try engine.play(try tone(), id: 4, loudness: .unmeasured, because: .somebodyAskedForIt)
        engine.queue(try tone(), id: 5, loudness: .unmeasured)
        try await Task.sleep(for: .milliseconds(300))

        #expect(engine.hasSomethingNext)

        // A drag moved the playing record from 4 to 3, and something else moved into 4.
        #expect(engine.rearranged(4, isNow: 3))

        #expect(!engine.hasSomethingNext,
                "the record loaded for the old order is still behind the needle")
        #expect(engine.playing == 3,
                "the record playing kept a number the list has given to something else")

        engine.stop()
    }

    /// Once the pump has moved on, the audio is already in front of the node and cannot be taken
    /// back. So nothing is dropped, and no record is renamed on a guess.
    @Test func aRearrangedListLeavesAloneARecordItIsNoLongerTheFrontOf() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())

        try engine.play(try tone(), id: 4, loudness: .unmeasured, because: .somebodyAskedForIt)
        engine.queue(try tone(), id: 5, loudness: .unmeasured)
        try await Task.sleep(for: .milliseconds(300))

        #expect(!engine.rearranged(9, isNow: 3))
        #expect(engine.hasSomethingNext)
        #expect(engine.playing == 4)

        engine.stop()
    }

    /// **The same number is used twice. The playing record gives up its number.** A drag from
    /// above the needle to below it moves the current record down by one. So the record after it
    /// takes the number the current one had. If nothing changed, the two would look like one run.
    /// The change would never be announced, and the needle would never return to zero.
    @Test func theRecordAfterCanTakeTheNumberTheCurrentOneHeld() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())

        let moved = OSAllocatedUnfairLock(initialState: [Int]())
        engine.moved = { id in moved.withLock { $0.append(id) } }

        try engine.play(try tone(), id: 1, loudness: .unmeasured, because: .somebodyAskedForIt)
        engine.queue(try tone(), id: 2, loudness: .unmeasured)
        try await Task.sleep(for: .milliseconds(300))

        #expect(engine.rearranged(1, isNow: 0))
        engine.queue(try tone(), id: 1, loudness: .unmeasured)

        // The first record is three seconds long. Wait for the change to be announced.
        try await until("the second record") { moved.withLock { $0 }.count == 2 }

        #expect(engine.playing == 1, "it never moved on")
        #expect(engine.position < 1.5, "the needle carried the first record's time over")
        #expect(moved.withLock { $0 } == [1, 1],
                "the change was announced \(moved.withLock { $0 })")

        engine.stop()
    }

    @Test func itSaysWhenThereIsNothingLeft() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())

        let empty = OSAllocatedUnfairLock(initialState: false)
        engine.ranOut = { _ in empty.withLock { $0 = true } }

        try engine.play(try tone(), id: 1, loudness: .unmeasured, because: .somebodyAskedForIt)
        try await until("the end of the record") { empty.withLock { $0 } }

        #expect(empty.withLock { $0 }, "it never said it had run out")
        engine.stop()
    }
}
