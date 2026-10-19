import Foundation
import Testing
import RPMKit
import RPMCast
@testable import RPMAudio

/// A record from the store, through the engine, into a real speaker.
///
/// **The end of the chain.** This is the only test that covers the whole path. The other tests
/// check each part separately. This one checks that the parts fit together. It runs only when
/// `RPM_TEST_EMAIL` and `RPM_TEST_CAST=1` are set:
/// `RPM_TEST_EMAIL=… RPM_TEST_PASSWORD=… RPM_TEST_CAST=1 swift test --filter LiveCast`
///
/// It does not change the speaker's volume. See below.
@Suite("A record plays in the kitchen",
       .enabled(if: ProcessInfo.processInfo.environment["RPM_TEST_EMAIL"] != nil
                 && ProcessInfo.processInfo.environment["RPM_TEST_CAST"] == "1"),
       .serialized)
struct LiveCastTests {

    private actor Held: SecretStore {
        private var items: [String: Data] = [:]
        func read(_ key: String) async -> Data? { items[key] }
        func write(_ key: String, _ value: Data) async { items[key] = value }
        func delete(_ key: String) async { items[key] = nil }
    }

    @Test func theStoresMusicComesOutOfARealSpeaker() async throws {
        // ── the track ──
        let env = ProcessInfo.processInfo.environment
        let auth = AuthClient(base: URL(string: "https://accounts.rpmrpmrpm.com/")!, keychain: Held(),
                              reach: NetworkReach())
        try await auth.signIn(email: env["RPM_TEST_EMAIL"]!, password: env["RPM_TEST_PASSWORD"]!)

        let cloud = RPMCloudClient(
            transport: Transport(base: URL(string: "https://api.rpmrpmrpm.com")!, tokens: auth,
                                 reach: NetworkReach()))

        let track = try #require(try await cloud.list(.own).first)
        let signed = try await cloud.stream(.own, rpmId: track.rpmId, kilobits: 128)
        print("  \(track.artist ?? "?") — \(track.title ?? "?")")

        // ── the engine ──
        let feed = TrackFeed()
        feed.start(signed.url, kind: signed.kind)
        for _ in 0..<200 where !feed.pcm.ready { try await Task.sleep(for: .milliseconds(50)) }
        #expect(feed.trouble == nil)

        let engine = PcmEngine(normalize: NormalizeContext())
        let sink = CastSink(engine: engine)
        let url = try await sink.begin(from: 0, named: "a test")
        print("  serving \(url)")

        try engine.play(feed.pcm, loudness: .unmeasured, because: .somebodyAskedForIt)
        try await Task.sleep(for: .seconds(1))

        // ── the speaker ──
        let speakers = await CastDiscovery().speakers(for: .seconds(5))
        let speaker = try #require(speakers.first { $0.isGroup } ?? speakers.first)
        print("  \(speaker.name)")

        let link = CastLink(to: speaker)
        _ = try await link.open()

        // **The speaker's volume is not changed.** A speaker plays a sound each time its volume
        // is set. Connecting should not make a noise in another room. The app uses the same rule:
        // it keeps the speaker's current volume.
        let app = try await link.launch()
        let loaded = try await link.load(
            CastMedia(url: url.absoluteString, contentType: "audio/wav",
                      title: track.title ?? "", artist: track.artist, album: track.album),
            on: app.transportId)

        #expect(!loaded.failed, "the speaker could not fetch it")

        // Wait long enough for the speaker to fetch the stream, start it, and keep playing.
        try await Task.sleep(for: .seconds(6))
        let playing = try await link.mediaStatus(on: app.transportId)
        print("  \(playing?.playerState ?? "nothing") at \(playing?.currentTime ?? -1)s, "
              + "\(sink.dropped) bytes dropped")

        #expect(playing?.isPlaying == true, "it is not playing: \(playing?.idleReason ?? "no reason")")
        #expect((playing?.currentTime ?? 0) > 1, "the speaker's own clock never moved")

        // ── hand everything back ──
        try? await link.stop(app.sessionId)
        await link.close()

        engine.stop()
        await sink.end()
        feed.stop()
    }
}
