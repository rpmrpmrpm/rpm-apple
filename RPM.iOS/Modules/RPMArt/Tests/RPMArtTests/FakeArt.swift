import Foundation
import RPMKit
import RPMLibrary
@testable import RPMArt

/// A store that answers questions about pictures, and counts what it was asked.
///
/// Every test here is about how often something is asked for, so the counts are the assertions. A
/// wall of six hundred records must be one listing, and a record viewed twice must be one download.
actor FakeArt: ArtSource {
    /// **Each shelf is kept apart by its owner.** With one list, every test about a borrowed
    /// collection would pass even when the owner was never sent in the request. That is the one
    /// thing those tests check. A route that drops `?owner=` returns the caller's own rows with a
    /// 200 response, and every later step then runs on the wrong library.
    var shelves: [String: [StoredCover]] = [:]
    var pictures: [String: Data] = [:]
    var embedded: [String: Data] = [:]

    /// The caller's own shelf, which nearly every test here uses.
    var covers: [StoredCover] {
        get { shelves[""] ?? [] }
        set { shelves[""] = newValue }
    }

    /// How long a download takes. The cancellation tests need a download that lasts long enough to
    /// be interrupted.
    var takes: Duration?

    /// Whether the store can be reached at all.
    var reachable = true

    private(set) var listings = 0
    private(set) var signings = 0
    private(set) var started = 0
    private(set) var finished = 0
    private(set) var sidecars = 0

    /// The size each key's signed address was asked for at, in order.
    private(set) var sizes: [String: [CoverSize]] = [:]

    struct Unreachable: Error {}

    func artCatalog(_ shelf: CloudShelf) async throws -> [StoredCover] {
        listings += 1
        guard reachable else { throw Unreachable() }
        return shelves[shelf.ownerId] ?? []
    }

    func art(_ shelf: CloudShelf, albumKey: String, size: CoverSize) async -> StoredCover? {
        signings += 1
        sizes[albumKey, default: []].append(size)
        guard reachable,
              let cover = (shelves[shelf.ownerId] ?? []).first(where: { $0.albumKey == albumKey })
        else { return nil }

        // The owner is part of the address, as in the real service. A picture is an object under
        // the owner's prefix, so two people can have a record under the same key.
        return StoredCover(albumKey: albumKey, updatedAt: cover.updatedAt,
                           url: "https://example.invalid/" + Self.address(shelf, albumKey))
    }

    func artwork(at url: URL) async throws -> Data {
        started += 1
        if let takes { try await Task.sleep(for: takes) }
        guard reachable, let data = pictures[url.lastPathComponent] else { throw Unreachable() }
        finished += 1
        return data
    }

    /// No artist has a photograph here. The backdrop store has its own tests, and every test in
    /// this file is about covers.
    func artistPictures(artist: String, album: String?) async throws -> ArtistPictures { .none }

    func sidecar(rpmId: String) async throws -> TagSidecar? {
        sidecars += 1
        guard reachable else { throw Unreachable() }

        var json: [String: Any] = ["RelativePath": "x/\(rpmId).flac", "Extension": ".flac",
                                   "RpmId": rpmId]
        if let art = embedded[rpmId] { json["Art"] = art.base64EncodedString() }

        return try JSONDecoder().decode(
            TagSidecar.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // ── what a test sets up ──

    func hold(_ cover: StoredCover, picture: Data, on shelf: CloudShelf = .own) {
        var held = shelves[shelf.ownerId] ?? []
        held.removeAll { $0.albumKey == cover.albumKey }
        held.append(cover)
        shelves[shelf.ownerId] = held

        pictures[Self.address(shelf, cover.albumKey)] = picture
    }

    /// One path component. The empty owner of an own shelf must not make the address a different
    /// shape from the address of a borrowed shelf.
    static func address(_ shelf: CloudShelf, _ albumKey: String) -> String {
        shelf.isOwn ? albumKey : "\(shelf.ownerId)~\(albumKey)"
    }

    func embed(_ art: Data, in rpmId: String) { embedded[rpmId] = art }
    func slowDown(to takes: Duration?) { self.takes = takes }
    func unplug() { reachable = false }
    func plugBackIn() { reachable = true }

    /// Waits until the store has been asked for this many downloads. A test does not have to guess
    /// how long a task takes to start.
    func waitUntilStarted(_ many: Int) async {
        while started < many { try? await Task.sleep(for: .milliseconds(1)) }
    }
}
