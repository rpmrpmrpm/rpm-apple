import Foundation
import Testing
import RPMCast
@testable import RPMAudio

/// **What the pause key reads while the music plays in a room.**
///
/// `Player.holding` is the only input `Transport` uses. It asks the engine three questions.
/// While casting, there is no audio node to ask, so each question has a second answer that
/// comes from the room. If one question reads the node instead, the key shows the wrong state,
/// and the user has to press it twice.
@Suite("A pause read from another room")
struct CastPauseTests {

    /// The three lines of `Player.holding`, in the order it runs them.
    private func holding(_ engine: PcmEngine) -> Loaded {
        guard engine.playing != nil else { return .nothing }
        if engine.isPaused { return .paused }
        return (engine.isPlaying || engine.priming) ? .playing : .paused
    }

    @Test func theKeyIsRightTheFirstTimeItIsPressed() throws {
        let engine = PcmEngine(normalize: NormalizeContext())
        let room = RoomFeed(ring: PcmRing(seconds: 1), named: "a speaker")
        defer { room.release() }

        let url = try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
        let feed = StreamedPcm()
        try feed.take(try Data(contentsOf: url))
        feed.finish(.theFileRanOut)

        try engine.play(feed, loudness: .unmeasured, because: .somebodyAskedForIt)
        engine.send(to: room, from: 0)

        // Playing in the room: the next press must pause.
        var transport = Transport()
        #expect(holding(engine) == .playing)
        #expect(transport.toggle(starting: false, loaded: holding(engine)) == .pause)

        engine.pause()

        // Paused in the room: the next press must resume.
        #expect(holding(engine) == .paused)
        #expect(transport.toggle(starting: false, loaded: holding(engine)) == .resume)
    }

    /// **A paused cast decodes nothing.**
    ///
    /// The pump checks for pause before it reads. If it read first, a paused record would be
    /// decoded and dropped, and the record would run on unheard. This test loads a record under
    /// a pause, the way a seek does (`.carryOnAsBefore` keeps the pause). The ring never makes
    /// the pump wait, so the pause check is the only thing that stops decoding.
    @Test func aPausedCastDoesNotRunThroughTheRecord() async throws {
        let engine = PcmEngine(normalize: NormalizeContext())
        let room = RoomFeed(ring: PcmRing(seconds: 30), named: "a speaker")
        defer { room.release(); engine.stop() }

        engine.send(to: room, from: 0)
        try engine.play(try SilentRecord.source(seconds: 5), loudness: .unmeasured,
                        because: .somebodyAskedForIt)
        engine.pause()

        let record = try SilentRecord.source(seconds: 20)
        try engine.play(record, loudness: .unmeasured, because: .carryOnAsBefore)
        #expect(engine.isPaused)

        try await Task.sleep(for: .milliseconds(400))

        #expect(record.produced == 0, "decoded \(record.produced) frames while paused")
    }

    /// **A paused cast that comes back to the handset stays paused.**
    ///
    /// `comeHome` clears `started` and starts the engine. The pump's pause check reads
    /// `paused && toTheRoom != nil`. When the room is gone, nothing holds the silence. Without
    /// a guard, the first buffer that arrives would start the node, even though `paused` is
    /// still true.
    @Test func aPausedCastBroughtHomeStaysPaused() throws {
        let engine = PcmEngine(normalize: NormalizeContext())
        let room = RoomFeed(ring: PcmRing(seconds: 1), named: "a speaker")
        defer { room.release() }

        let url = try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
        let feed = StreamedPcm()
        try feed.take(try Data(contentsOf: url))
        feed.finish(.theFileRanOut)

        try engine.play(feed, loudness: .unmeasured, because: .somebodyAskedForIt)
        engine.send(to: room, from: 0)
        engine.pause()
        #expect(engine.isPaused)

        // **The room is released first, then the engine comes home.** This is the order
        // `CastSink.end` uses. The pump may be waiting inside the room, and only `release`
        // reaches a thread that is waiting there. When the pump runs again, it sees that the
        // room is gone. That is what this test checks.
        //
        // `comeHome` can throw, for example on a machine with no output device. The test checks
        // the silence either side of that call.
        room.release()
        try? engine.comeHome(at: 0)

        // **The test reads `priming`**, which is `!started && !coming.isEmpty`. A test machine
        // has no audio device, so `comeHome` throws while it connects the node. A node that was
        // never attached reports that it is not playing, whatever the pump did. `startIfThereIsEnough`
        // sets `started` inside the lock, before it calls `node.play()`, so `priming` shows what
        // the pump did.
        Thread.sleep(forTimeInterval: 0.3)

        #expect(engine.isPaused, "coming home is not somebody pressing play")
        #expect(engine.priming, "the pump started the node again under a paused player")
        #expect(holding(engine) == .paused, "and the key would have drawn a lie over it")
    }

    /// **Moving to the next track does not clear a pause.**
    ///
    /// Only a choice from the user starts playback, such as tapping a track. When the queue
    /// moves on by itself, the pause stays. While casting, the queue also moves on through
    /// `Player.play`, because the look-ahead is not ready while the pump is parked. That path
    /// must keep the pause.
    @Test func theQueueMovingOnDoesNotTakeThePauseWithIt() throws {
        let engine = PcmEngine(normalize: NormalizeContext())

        let url = try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
        func tone() throws -> StreamedPcm {
            let source = StreamedPcm()
            try source.take(try Data(contentsOf: url))
            source.finish(.theFileRanOut)
            return source
        }

        try engine.play(try tone(), id: 1, loudness: .unmeasured, because: .somebodyAskedForIt)
        engine.pause()
        #expect(engine.isPaused)

        // The queue moves on by itself.
        try engine.play(try tone(), id: 2, loudness: .unmeasured, because: .carryOnAsBefore)
        #expect(engine.isPaused, "the next track started under a paused player")

        // A tap on a track still starts playback, so the pause is cleared.
        try engine.play(try tone(), id: 3, loudness: .unmeasured, because: .somebodyAskedForIt)
        #expect(engine.isPaused == false, "picking a track is asking for it to play")
    }

    @Test func castThenPauseActuallyReachesEverything() throws {
        let engine = PcmEngine(normalize: NormalizeContext())
        let room = RoomFeed(ring: PcmRing(seconds: 1), named: "a speaker")
        defer { room.release() }

        let url = try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
        let feed = StreamedPcm()
        try feed.take(try Data(contentsOf: url))
        feed.finish(.theFileRanOut)

        try engine.play(feed, loudness: .unmeasured, because: .somebodyAskedForIt)
        print("DIAG after play: doing=\(engine.playback.doing) loaded=\(engine.playback.loaded)")

        engine.send(to: room, from: 0)
        print("DIAG after cast: doing=\(engine.playback.doing) sent=\(engine.playback.sent) loaded=\(engine.playback.loaded)")

        engine.pause()
        print("DIAG after pause: doing=\(engine.playback.doing) roomPaused=\(room.paused)")
    }
}
