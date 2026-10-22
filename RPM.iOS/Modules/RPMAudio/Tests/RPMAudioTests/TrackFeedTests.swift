import Foundation
import Testing
@testable import RPMAudio

/// The whole chain, with nothing mocked: bytes arrive, become PCM, and become sound.
///
/// The fixture is read through `URLSession`, not from the disk, because the delegate is what
/// is under test. The bytes arrive in whatever pieces the session gives, as they do from the
/// store.
@Suite("Bytes off a URL, all the way to the needle", .serialized)
struct TrackFeedTests {

    private func toneUrl() throws -> URL {
        try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
    }

    /// Polls until the condition is true, or gives up. A feed is asynchronous, so a fixed sleep
    /// is either too short (flaky) or too long (slow).
    private func until(_ what: String, _ ready: @Sendable () -> Bool) async throws {
        for _ in 0..<100 {
            if ready() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("gave up waiting: \(what)")
    }

    @Test func aTrackArrivesAndBecomesSomethingToPlay() async throws {
        let feed = TrackFeed()
        feed.start(try toneUrl(), kind: .stored)

        try await until("the header to arrive") { feed.pcm.ready }

        #expect(feed.pcm.format?.sampleRate == 44100)
        #expect(feed.trouble == nil)

        try await until("the stream to finish") { feed.complete }
        #expect(feed.received > 20_000)

        feed.stop()
    }

    /// A copy on the phone uses the same decoder, and nothing is fetched.
    @Test func aCopyOnThePhoneArrivesWhole() async throws {
        let feed = TrackFeed()
        feed.start(file: try toneUrl())

        try await until("the header to arrive") { feed.pcm.ready }
        try await until("the file to be read") { feed.complete }

        #expect(feed.pcm.format?.sampleRate == 44100)
        #expect(feed.trouble == nil)
        #expect(feed.pcm.ending.why == .theFileRanOut)
        feed.stop()
    }

    /// A seek in a phone copy reads from another byte offset, and the read lands on the target.
    @Test func aCopyOnThePhoneCanBeMovedThrough() async throws {
        let feed = TrackFeed()
        feed.start(file: try toneUrl())
        try await until("the header to arrive") { feed.pcm.ready }
        try await until("the file to be read") { feed.complete }

        let landed = try #require(feed.moveTo(1.5))
        #expect(abs(landed - 1.5) < 0.1)

        try await until("the rest of the file to be read") { feed.complete }
        #expect(feed.trouble == nil)
        #expect(feed.reached > feed.received, "the read did not begin part way into the file")
        feed.stop()
    }

    /// Stopping a phone copy's read is normal when a track is skipped. It is not an error.
    @Test func stoppingACopyIsNotTrouble() async throws {
        let feed = TrackFeed()
        feed.start(file: try toneUrl())
        try await until("the header to arrive") { feed.pcm.ready }

        feed.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(feed.trouble == nil)
    }

    @Test func itPlays() async throws {
        let feed = TrackFeed()
        feed.start(try toneUrl(), kind: .stored)
        try await until("the header to arrive") { feed.pcm.ready }

        let engine = PcmEngine(normalize: NormalizeContext())
        try engine.play(feed.pcm, loudness: .unmeasured, because: .somebodyAskedForIt)

        try await until("the needle to move") { engine.position > 0.2 }
        let early = engine.position

        try await Task.sleep(for: .milliseconds(500))
        #expect(engine.position > early)

        engine.stop()
        feed.stop()
    }

    /// The store answers an expired signature with HTTP 403. This must be reported as a
    /// refusal, not confused with a slow track.
    @Test func anAddressThatIsRefusedSaysSo() async throws {
        let feed = TrackFeed()
        feed.start(try #require(URL(string: "https://api.rpmrpmrpm.com/cloud/stream/nothing-here")),
                   kind: .stored)

        try await until("the refusal") { feed.trouble != nil }

        guard case .refused = feed.trouble else {
            Issue.record("expected a refusal, got \(String(describing: feed.trouble))")
            return
        }
        feed.stop()
    }

    /// **Pressing next is not an error.** Every skipped track ends this way. If the feed
    /// recorded it as trouble, the screen would show an error each time.
    @Test func stoppingItIsNotTrouble() async throws {
        let feed = TrackFeed()
        feed.start(try toneUrl(), kind: .stored)
        try await until("something to arrive") { feed.received > 0 }

        feed.stop()
        try await Task.sleep(for: .milliseconds(200))

        #expect(feed.trouble == nil)
    }
}

/// Seeking in a stream that is only read forwards.
@Suite("A seek is a new request", .serialized)
struct SeekTests {

    private func toneUrl() throws -> URL {
        try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
    }

    private func ready(_ feed: TrackFeed) async throws {
        for _ in 0..<100 where !feed.pcm.ready {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func nothingCanBeSeekedBeforeTheHeaderHasArrived() {
        #expect(StreamedPcm().byteToHear(1) == nil)
        #expect(TrackFeed().moveTo(1) == nil)
    }

    /// The byte offset grows with the time. The start of the file is not the start of the
    /// audio, because a header comes first.
    @Test func aLaterSecondIsALaterByte() async throws {
        let feed = TrackFeed()
        feed.start(try toneUrl(), kind: .stored)
        try await ready(feed)

        let start = try #require(feed.pcm.byteToHear(0))
        let later = try #require(feed.pcm.byteToHear(2))

        #expect(later.byte > start.byte)
        #expect(start.byte > 0, "the audio does not begin at byte nought")

        feed.stop()
    }

    /// **The second it lands on is not exactly the one asked for.** It is short by two amounts.
    /// First, a seek goes to the start of a packet, and a packet is 1024 frames. Second, the time
    /// returned counts the music only, while the packet index also counts the encoder's priming.
    /// See `PrimingTests`.
    @Test func itLandsOnAPacketRatherThanOnTheNumberAskedFor() async throws {
        let feed = TrackFeed()
        feed.start(try toneUrl(), kind: .stored)
        try await ready(feed)

        let asked = 1.5
        let landing = try #require(feed.pcm.byteToHear(asked))

        // One packet, plus AAC's 2112 frames of priming.
        let most = (1024.0 + 2112.0) / 44100.0

        #expect(landing.second <= asked)
        #expect(asked - landing.second < most, "landed \(asked - landing.second)s short")

        feed.stop()
    }

    /// **Playing is not the same as playing the right thing.** A byte offset that lands inside
    /// the container's own bookkeeping decodes to noise or to nothing. The position still moves
    /// either way.
    ///
    /// This test feeds the bytes by hand, not through the feed, because **a `file://` URL ignores
    /// a Range header.** The session returns the whole file from the start. The parser then reads
    /// it as if it were the requested range, and the decoder fails with `bada`. This behaves like
    /// a store that does not support ranges. The feed's own range handling is checked against the
    /// real store, which does support them.
    @Test func whatComesBackAfterAJumpIsStillTheRecording() async throws {
        let bytes = try Data(contentsOf: try toneUrl())
        let source = StreamedPcm()

        try source.take(bytes)
        while try source.read() != nil {}

        let landing = try #require(source.byteToHear(1.5))

        source.expectAJump(landingAt: landing.second)
        try source.take(bytes[Int(landing.byte)...])
        source.finish(.theFileRanOut)

        var peak: Float = 0
        var frames = 0
        while let buffer = try source.read() {
            frames += Int(buffer.frameLength)
            guard let samples = buffer.floatChannelData?[0] else { continue }
            for at in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[at])) }
        }

        // A second and a half of a three second tone, give or take a packet.
        #expect(frames > 44100, "only \(frames) frames came back after the jump")
        #expect(peak > 0.2 && peak <= 1.0, "it decoded, but not to a tone: peak \(peak)")
    }

    /// Playback continues from the seek point, not from the start of the file.
    ///
    /// Fed by hand for the reason above: a `file://` URL does not answer range requests. This
    /// drives the engine the way the feed would if the store were the source. The store's own
    /// range support is checked against the live store.
    @Test func theNeedleCarriesOnFromWhereItWasSent() async throws {
        let bytes = try Data(contentsOf: try toneUrl())

        let first = StreamedPcm()
        try first.take(bytes)
        first.finish(.theFileRanOut)

        let landing = try #require(first.byteToHear(2.0))

        let after = StreamedPcm()
        try after.take(bytes.prefix(Int(landing.byte)))
        after.expectAJump(landingAt: landing.second)
        try after.take(bytes[Int(landing.byte)...])
        after.finish(.theFileRanOut)

        let engine = PcmEngine(normalize: NormalizeContext())
        try engine.play(after, from: landing.second, loudness: .unmeasured, because: .somebodyAskedForIt)

        #expect(engine.position >= landing.second)
        #expect(engine.position < landing.second + 0.5)

        try await Task.sleep(for: .milliseconds(400))
        #expect(engine.position > landing.second, "it did not carry on after the jump")

        engine.stop()
    }

    // ── a record encoded while it is sent ──

    /// The fixture is ADTS, as a live encode is, and is 2.13 seconds long.
    private func adts() throws -> Data {
        try Data(contentsOf: try #require(
            Bundle.module.url(forResource: "Fixtures/high-he", withExtension: "aac")))
    }

    /// Reads a live stream from the silent store until the connection has closed and everything
    /// that arrived is decoded, and returns how it ended.
    private func ending(of body: Data, stating length: String?) async throws -> Ending {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }

        store.serves(body, for: "live", headers: length.map { [TrackFeed.lengthHeader: $0] } ?? [:])

        let feed = TrackFeed()
        feed.start(store.address(of: "live"), kind: .live)
        for _ in 0..<100 where !feed.complete { try await Task.sleep(for: .milliseconds(50)) }
        try #require(feed.complete, "the stream did not close")

        while try feed.pcm.read() != nil {}
        #expect(feed.pcm.drained)
        return feed.pcm.ending
    }

    /// **The encoder can close the stream cleanly when it fails part way.** The connection then
    /// ends with no error, exactly as at the end of the record. Only the length the encoder
    /// stated beside the stream shows that the record is not over.
    @Test func aLiveStreamThatClosesShortOfItsStatedLengthDidNotReachItsEnd() async throws {
        let ended = try await ending(of: try adts(), stating: "10")

        #expect(ended.why == .theFileRanOut)
        #expect(ended.reachedItsEnd == false, "2 seconds of a 10 second record read as the whole of it")
        #expect(ended.worthAnotherGo)
    }

    @Test func aLiveStreamThatReachesItsStatedLengthReachedItsEnd() async throws {
        let ended = try await ending(of: try adts(), stating: "2.13")

        #expect(ended == .theRecordFinished)
    }

    /// The header is written with a decimal point by the server. A comma would not parse, and the
    /// stream is then taken at its word, as before there was a header.
    @Test func aLiveStreamWithNoLengthIsTakenAtItsWordWhenItClosesCleanly() async throws {
        let ended = try await ending(of: try adts(), stating: nil)

        #expect(ended == .theRecordFinished)
    }
}
