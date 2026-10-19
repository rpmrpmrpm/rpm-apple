import Testing
import Foundation
@testable import RPMKit

/// The routes that WRITE, against the real service.
///
/// Separate from `LiveSmokeTests` and behind a second switch, because that suite
/// promises to be read-only and a write smoke test in it would quietly break that
/// promise. Run it deliberately:
///
///     RPM_TEST_EMAIL=… RPM_TEST_PASSWORD=… RPM_TEST_WRITES=1 \
///       swift test --filter LiveWriteSmoke
///
/// **Everything it makes, it deletes.** The ids are fresh UUIDs, which is what the
/// store will accept: it refuses anything that is not one with "Bad playlist id",
/// so a marker in the id is not available and the names carry it instead.
///
/// This suite exists for one fault: a write sent to `cloud/playlists/{id}` (the
/// listing's route with an id on the end) gets a 404 every time, because the store's
/// route is `cloud/playlist/{id}`. A decode test cannot see that, because it never
/// sends anything.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RPM_TEST_EMAIL"] != nil
                 && ProcessInfo.processInfo.environment["RPM_TEST_WRITES"] != nil),
       .serialized)
struct LiveWriteSmokeTests {
    private func signedIn() async throws -> RPMCloudClient {
        let env = ProcessInfo.processInfo.environment
        let auth = AuthClient(base: URL(string: "https://accounts.rpmrpmrpm.com/")!,
                              keychain: MemoryStore(), reach: NetworkReach())
        try await auth.signIn(email: env["RPM_TEST_EMAIL"]!,
                              password: env["RPM_TEST_PASSWORD"]!)

        return RPMCloudClient(transport: Transport(
            base: URL(string: "https://api.rpmrpmrpm.com")!, tokens: auth,
            reach: NetworkReach()))
    }

    private func made(_ id: String, name: String, tracks: [String] = [],
                      folder: [String] = []) -> CloudPlaylist {
        CloudPlaylist(playlistId: id, name: name, trackIds: tracks,
                      folder: folder, updatedAt: 0)
    }

    /// The whole round trip: write it, find it in the listing as written, take it
    /// away, and find it gone.
    @Test func aPlaylistCanBeWrittenReadBackAndRemoved() async throws {
        let cloud = try await signedIn()
        let id = UUID().uuidString.lowercased()

        let tracks = try await cloud.list(.own).prefix(3).map(\.rpmId)

        // Zero, not nil: this id was made up a line ago and nothing should be
        // stored under it. A store that says otherwise has met a UUID twice, which
        // is worth failing on rather than overwriting somebody's playlist.
        let stamped = try await cloud.putPlaylist(
            made(id, name: "Swift smoke", tracks: Array(tracks), folder: ["Smoke"]),
            ifUnchangedSince: 0)

        do {
            let held = try await cloud.playlists(.own)
            let mine = try #require(held.first { $0.playlistId == id },
                                    "the write did not land in the listing")

            #expect(mine.name == "Swift smoke")
            #expect(mine.trackIds == Array(tracks))
            #expect(mine.folderChain == ["Smoke"], "the folder chain did not survive the trip")
            #expect(mine.updatedAt > 0, "the store stamped nothing")

            // The stamp the write reported is the one the listing carries, which is
            // what makes the next conditional write possible.
            if stamped > 0 { #expect(mine.updatedAt == stamped) }
        }

        try await cloud.deletePlaylist(id: id)

        let after = try await cloud.playlists(.own)
        #expect(!after.contains { $0.playlistId == id }, "it is still there")
    }

    /// Asking for something to be gone that is already gone is not a failure.
    @Test func removingSomethingThatIsNotThereIsNotAnError() async throws {
        let cloud = try await signedIn()
        try await cloud.deletePlaylist(id: UUID().uuidString.lowercased())
    }

    /// The conditional write, which is the whole of what keeps two phones from
    /// writing over each other. A stamp from before the last change is refused, and
    /// the refusal carries the copy that is actually stored.
    @Test func aWriteAgainstAStaleStampIsRefusedWithWhatIsStored() async throws {
        let cloud = try await signedIn()
        let id = UUID().uuidString.lowercased()

        _ = try await cloud.putPlaylist(made(id, name: "First"), ifUnchangedSince: 0)
        defer { Task { try? await cloud.deletePlaylist(id: id) } }

        _ = try await cloud.putPlaylist(made(id, name: "Second"), ifUnchangedSince: nil)

        do {
            _ = try await cloud.putPlaylist(made(id, name: "Third"), ifUnchangedSince: 1)
            Issue.record("a write against a stamp of 1 was accepted")
        } catch let clash as PlaylistConflict {
            #expect(clash.name == "Third")
            #expect(clash.stored?.name == "Second",
                    "the refusal did not carry the copy that is stored")
        }
    }
}
