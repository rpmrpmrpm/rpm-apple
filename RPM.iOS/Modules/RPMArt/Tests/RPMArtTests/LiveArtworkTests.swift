import Testing
import Foundation
import RPMKit
import RPMLibrary
@testable import RPMArt

/// The fakes prove that the store follows its rules. Only this test proves that the rules
/// match the real service.
///
/// Off unless credentials are in the environment:
///
///     RPM_TEST_EMAIL=… RPM_TEST_PASSWORD=… swift test --filter LiveArtwork
///
/// **Read-only.** It signs in, reads a listing, fetches one picture and decodes it.
/// It writes nothing to the account itself. The API stores a cut copy of a cover the
/// first time one is asked for at a size, as it does for every client. The only thing
/// the test writes is a cache in its own temporary directory.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RPM_TEST_EMAIL"] != nil))
struct LiveArtworkTests {
    private actor Nowhere: SecretStore {
        private var held: [String: Data] = [:]
        func read(_ key: String) async -> Data? { held[key] }
        func write(_ key: String, _ value: Data) async { held[key] = value }
        func delete(_ key: String) async { held[key] = nil }
    }

    private func signedIn() async throws -> (RPMCloudClient, CloudLibrary) {
        let env = ProcessInfo.processInfo.environment
        let auth = AuthClient(base: URL(string: "https://accounts.rpmrpmrpm.com/")!,
                              keychain: Nowhere(), reach: NetworkReach())
        try await auth.signIn(email: env["RPM_TEST_EMAIL"]!, password: env["RPM_TEST_PASSWORD"]!)

        let cloud = RPMCloudClient(
            transport: Transport(base: URL(string: "https://api.rpmrpmrpm.com")!, tokens: auth,
                                 reach: NetworkReach()))

        // The marks live on the main actor, because a row reads them while it is drawn.
        let marks = await MainActor.run { FavoriteMarks() }
        return (cloud, CloudLibrary(source: cloud, marks: marks))
    }

    private func scratch() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rpm-live-art-\(UUID().uuidString)", isDirectory: true)
    }

    /// The whole path, end to end: a listing, a signature, a download with no
    /// credential on it, a decode, and a colour. The contract can change in any of
    /// these steps, and none of them reports it: the wall just stays grey.
    @Test func aRealSleeveComesDownAndDecodes() async throws {
        let (cloud, library) = try await signedIn()

        let albums = await library.albums(.own)
        #expect(!albums.isEmpty, "the smoke account has no music in it, so this proves nothing")

        let store = ArtworkStore(source: cloud, disk: CoverDisk(directory: scratch()))

        var found = 0
        for album in albums.prefix(4) {
            guard let art = await store.cover(for: album, on: .own, edge: 512) else { continue }
            found += 1

            #expect(art.image.width > 64, "\(album.album) decoded to \(art.image.width) across")
            #expect(art.accent != nil, "\(album.album) came back with no colour")
        }

        #expect(found > 0, "not one record on the smoke account answered with a cover")
    }

    /// The second launch costs only a file read. The test uses two stores over one
    /// directory, because that is what a relaunch looks like.
    @Test func theSecondLaunchDoesNotGoToTheNetwork() async throws {
        let (cloud, library) = try await signedIn()

        let album = try #require(await library.albums(.own).first)
        let at = scratch()

        let first = ArtworkStore(source: cloud, disk: CoverDisk(directory: at))
        try #require(await first.cover(for: album, on: .own, edge: 512))

        // A source that cannot answer anything. If the picture still arrives, it
        // came from the disk.
        let second = ArtworkStore(source: Silence(), disk: CoverDisk(directory: at))
        #expect(await second.cover(for: album, on: .own, edge: 512) != nil)
    }

    /// A sized ask is served the API's cut copy: a signed address under `artcut/{edge}/`, a
    /// picture no larger than the edge, and the original's stamp.
    @Test func aSizedAskIsServedTheAPIsCutCopy() async throws {
        let (cloud, _) = try await signedIn()
        let key = try #require(try await cloud.artCatalog(.own).first).albumKey

        let original = try #require(await cloud.art(.own, albumKey: key, size: .original))
        let copy = try #require(await cloud.art(.own, albumKey: key, size: .edge(256)))
        #expect(copy.updatedAt == original.updatedAt)

        let address = try #require(copy.url.flatMap(URL.init(string:)))
        #expect(address.path.contains("/artcut/256/"), "a sized ask was signed \(address.path)")

        let image = try #require(Thumbnail.of(try await cloud.artwork(at: address), edge: 4096))
        #expect(max(image.width, image.height) <= 256)
    }

    /// A source that never answers, so a disk hit is the only way an answer can
    /// arrive.
    private struct Silence: ArtSource {
        struct Nothing: Error {}
        func artCatalog(_ shelf: CloudShelf) async throws -> [StoredCover] { throw Nothing() }
        func art(_ shelf: CloudShelf, albumKey: String, size: CoverSize) async -> StoredCover? { nil }
        func artwork(at url: URL) async throws -> Data { throw Nothing() }
        func sidecar(rpmId: String) async throws -> TagSidecar? { throw Nothing() }

        func artistPictures(artist: String, album: String?) async throws -> ArtistPictures { .none }
    }
}
