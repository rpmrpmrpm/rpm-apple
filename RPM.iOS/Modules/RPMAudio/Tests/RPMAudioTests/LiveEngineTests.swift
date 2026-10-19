import Foundation
import Testing
import RPMKit
@testable import RPMAudio

/// A real track from the store, through the engine.
///
/// The fixture next to this suite is three seconds, encoded on a development machine. It proves
/// that the decoder works, but not what the store serves. This suite checks the store. Run it with
/// `RPM_TEST_EMAIL=… RPM_TEST_PASSWORD=… swift test --filter LiveEngine`.
@Suite("A real track plays through the new engine",
       .enabled(if: ProcessInfo.processInfo.environment["RPM_TEST_EMAIL"] != nil),
       .serialized)
struct LiveEngineTests {

    /// In memory, so no test writes to the real Keychain.
    private actor Held: SecretStore {
        private var items: [String: Data] = [:]
        func read(_ key: String) async -> Data? { items[key] }
        func write(_ key: String, _ value: Data) async { items[key] = value }
        func delete(_ key: String) async { items[key] = nil }
    }

    private func aTrack() async throws -> (URL, CloudTrack) {
        let env = ProcessInfo.processInfo.environment
        let auth = AuthClient(base: URL(string: "https://accounts.rpmrpmrpm.com/")!, keychain: Held(),
                              reach: NetworkReach())
        try await auth.signIn(email: env["RPM_TEST_EMAIL"]!, password: env["RPM_TEST_PASSWORD"]!)

        let cloud = RPMCloudClient(
            transport: Transport(base: URL(string: "https://api.rpmrpmrpm.com")!, tokens: auth,
                                 reach: NetworkReach()))

        let tracks = try await cloud.list(.own)
        let track = try #require(tracks.first, "the account has no music in it")

        let signed = try await cloud.stream(.own, rpmId: track.rpmId, kilobits: 128)
        return (signed.url, track)
    }

    @Test func theStoresOwnBytesDecodeAndPlay() async throws {
        let (url, track) = try await aTrack()
        print("  \(track.artist ?? "?") — \(track.title ?? "?")")

        let feed = TrackFeed()
        feed.start(url, kind: .stored)

        for _ in 0..<200 where !feed.pcm.ready {
            try await Task.sleep(for: .milliseconds(50))
        }

        #expect(feed.trouble == nil, "the store refused: \(String(describing: feed.trouble))")
        let format = try #require(feed.pcm.format, "nothing here could read what the store sent")
        print("  \(format)")

        let engine = PcmEngine(normalize: NormalizeContext())
        try engine.play(feed.pcm, loudness: .unmeasured, because: .somebodyAskedForIt)

        for _ in 0..<100 where engine.position <= 0.2 {
            try await Task.sleep(for: .milliseconds(50))
        }
        let early = engine.position

        try await Task.sleep(for: .seconds(1))
        let later = engine.position
        print("  played \(early) then \(later), \(feed.received) bytes in")

        engine.stop()
        feed.stop()

        #expect(early > 0, "nothing rendered")
        #expect(later > early, "the clock stopped")
    }

    /// **Checks what a `file://` URL cannot.** A seek sends a Range request. Whether the store
    /// supports Range requests is a question for the store.
    @Test func theStoreAnswersARangeAndTheJumpDecodes() async throws {
        let (url, _) = try await aTrack()

        let feed = TrackFeed()
        feed.start(url, kind: .stored)

        for _ in 0..<200 where !feed.pcm.ready {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(feed.trouble == nil)

        let landed = try #require(feed.moveTo(60), "the track could not be moved through")
        print("  asked for 60s, landed at \(landed)")

        var peak: Float = 0
        var frames = 0
        for _ in 0..<200 where frames < 44_100 {
            while let buffer = try feed.pcm.read() {
                frames += Int(buffer.frameLength)
                guard let samples = buffer.floatChannelData?[0] else { continue }
                for at in stride(from: 0, to: Int(buffer.frameLength), by: 16) {
                    peak = max(peak, abs(samples[at]))
                }
            }
            try await Task.sleep(for: .milliseconds(25))
        }

        feed.stop()
        print("  \(frames) frames after the jump, peak \(peak)")

        #expect(feed.trouble == nil, "the store refused the range")
        #expect(frames > 44_100, "nothing decoded from a minute in")
        #expect(peak > 0.001, "it decoded to silence, which is a jump that landed wrong")
    }

}
