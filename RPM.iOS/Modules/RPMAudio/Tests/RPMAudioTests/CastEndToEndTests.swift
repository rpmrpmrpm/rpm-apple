import Foundation
import Testing
import RPMCast
@testable import RPMAudio

/// **A record cast to a speaker, with the playback controls pressed.**
///
/// Everything runs for real except the speaker: the engine, `CastSink`, `CastServer`,
/// `CastLink`, the TLS handshake, the framing, and an HTTP fetch of the stream. The speaker is
/// `FakeSpeaker`. It runs in this process and makes no sound. The records are silence, so a
/// whole queue can play through without making any noise.
///
/// The tests use the same path as a real cast, so a fault shows up without a physical speaker.
@Suite("A record in the woonkamer", .serialized)
struct CastEndToEndTests {

    /// Builds the engine, a sink and a speaker on this machine, wired the same way as `Player`.
    /// `Player` needs a store and a signer, so these tests cover the layers below it: the engine
    /// and the cast path.
    private func castingToAFakeSpeaker(seconds: Double = 30)
    async throws -> (PcmEngine, CastSink, CastLink, FakeSpeaker, ReceiverStatus.Application) {
        let speaker = FakeSpeaker()
        try await speaker.start()

        let engine = PcmEngine(normalize: NormalizeContext())
        try engine.play(try SilentRecord.source(seconds: seconds), loudness: .unmeasured, because: .somebodyAskedForIt)

        let sink = CastSink(engine: engine)
        let url = try await sink.begin(from: 0, named: "woonkamer")

        let link = CastLink(to: speaker.device)
        _ = try await link.open()
        let app = try await link.launch()

        _ = try await link.load(
            CastMedia(url: url.absoluteString, contentType: "audio/wav",
                      title: "silence", artist: nil, album: nil),
            on: app.transportId)

        return (engine, sink, link, speaker, app)
    }

    /// Waits until `done` returns true. If that does not happen within `within`, the test
    /// records an issue. Tests name the condition they wait for, not a fixed delay.
    private func until(_ what: String, within: Duration = .seconds(10),
                       _ done: () -> Bool) async throws {
        let end = ContinuousClock.now.advanced(by: within)
        while ContinuousClock.now < end {
            if done() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        Issue.record("timed out waiting for \(what)")
    }

    // ── the connection itself ──

    @Test func aSpeakerTakesTheStreamAndPlaysIt() async throws {
        let (engine, sink, link, speaker, _) = try await castingToAFakeSpeaker()
        defer { speaker.stop(); Task { await link.close() } }

        try await until("the speaker to fetch the stream") { speaker.what { $0.fetched > 0 } }

        #expect(engine.casting, "the engine's destination is the room")
        #expect(speaker.what { $0.heard } == ["LOAD"])
        #expect(speaker.what { $0.playerState } == "PLAYING")

        try await until("its clock to move") { speaker.what { $0.currentTime > 0.2 } }

        await sink.end()
    }

    // ── the keys, pressed from the phone ──

    @Test func pauseFromThePhoneReachesTheSpeaker() async throws {
        let (engine, sink, link, speaker, app) = try await castingToAFakeSpeaker()
        defer { speaker.stop(); Task { await link.close() } }

        try await until("it to be playing") { speaker.what { $0.playerState } == "PLAYING" }

        // The same steps as `Player.apply(.pause)`: pause the engine, then pause the speaker.
        engine.pause()
        try await link.pause(session: speaker.what { $0.session }, on: app.transportId)

        try await until("the speaker to pause") { speaker.what { $0.playerState } == "PAUSED" }

        #expect(engine.isPaused)
        #expect(speaker.what { $0.heard }.contains("PAUSE"))

        // **The speaker stays paused.** Only a play command may start it again.
        let at = speaker.what { $0.currentTime }
        try await Task.sleep(for: .seconds(2))

        #expect(speaker.what { $0.playerState } == "PAUSED", "it started itself again")
        #expect(abs(speaker.what { $0.currentTime } - at) < 0.3, "the needle moved under a pause")
        #expect(engine.isPaused, "the engine let its own pause go")

        await sink.end()
    }

    @Test func playAfterAPauseStartsItAgain() async throws {
        let (engine, sink, link, speaker, app) = try await castingToAFakeSpeaker()
        defer { speaker.stop(); Task { await link.close() } }

        try await until("it to be playing") { speaker.what { $0.playerState } == "PLAYING" }

        engine.pause()
        try await link.pause(session: speaker.what { $0.session }, on: app.transportId)
        try await until("it to pause") { speaker.what { $0.playerState } == "PAUSED" }

        try engine.resume()
        try await link.play(session: speaker.what { $0.session }, on: app.transportId)

        try await until("it to play again") { speaker.what { $0.playerState } == "PLAYING" }
        #expect(engine.isPaused == false)

        await sink.end()
    }

    // ── the ring, which is where an underrun is ──

    @Test func aRoomPlayingSteadilyNeverRunsTheRingDry() async throws {
        let (engine, sink, link, speaker, _) = try await castingToAFakeSpeaker()
        defer { speaker.stop(); Task { await link.close() } }

        try await until("it to be playing") { speaker.what { $0.playerState } == "PLAYING" }
        try await Task.sleep(for: .seconds(4))

        #expect(speaker.what { $0.starved } == 0, "the speaker ran out of audio")
        #expect(engine.casting)

        await sink.end()
    }
}
