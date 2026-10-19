import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// Uses real files in a temporary folder. What matters here is what survives when the app process ends.

private func scratch() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("rpm-store-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func rows(_ n: Int) -> [CloudTrack] {
    (0..<n).map { i in
        var tags = CloudTrackTags()
        tags.trackNumber = i + 1
        tags.durationSeconds = Double(i) + 0.5
        return CloudTrack(rpmId: "id-\(i)", sha256: "sha-\(i)",
                          relativePath: "Artist/Album/\(i).flac",
                          title: "Track \(i)", artist: "Artist", album: "Album",
                          addedAt: 1_700_000_000, tags: tags, updatedAt: 1_700_000_001)
    }
}

@Test func aListingSurvivesBeingWrittenAndReadBack() {
    let root = scratch()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = LibraryStore(shelf: .own, root: root)
    store.save(rows(50))

    let back = try! #require(store.load())
    #expect(back.count == 50)
    #expect(back[7].title == "Track 7")
    #expect(back[7].tags?.trackNumber == 8)
    #expect(back[7].tags?.durationSeconds == 7.5)
}

/// A cache that cannot be read counts as no cache. A read error must not throw when the user opens
/// their music.
@Test func aStoreThatWasNeverWrittenReadsAsNothing() {
    let root = scratch()
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(LibraryStore(shelf: .own, root: root).load() == nil)
}

@Test func aTruncatedFileReadsAsNothingRatherThanThrowing() {
    let root = scratch()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = LibraryStore(shelf: .own, root: root)
    store.save(rows(20))

    // Half a file, as an interrupted write would leave it if the move were not atomic.
    let file = root.appendingPathComponent("listing.json.z")
    let whole = try! Data(contentsOf: file)
    try! whole.prefix(whole.count / 2).write(to: file)

    #expect(store.load() == nil)
}

/// One file per shelf. Going into a friend's records and back out means two reads from disk, and
/// the two files can never be mixed up.
@Test func aBorrowedShelfIsADifferentFileFromTheUsersOwn() {
    let root = scratch()
    defer { try? FileManager.default.removeItem(at: root) }

    LibraryStore(shelf: .own, root: root).save(rows(3))
    LibraryStore(shelf: .of("friend"), root: root).save(rows(9))

    #expect(LibraryStore(shelf: .own, root: root).load()?.count == 3)
    #expect(LibraryStore(shelf: .of("friend"), root: root).load()?.count == 9)
}

/// An account id identifies a person. File names can be read on the phone without opening any file, so the
/// name uses a hash of the id.
@Test func aBorrowedShelfIsNamedAfterAHashRatherThanTheAccountId() {
    let name = LibraryStore.name(for: .of("us-east-1:9f3c-real-account-id"))

    #expect(name.hasPrefix("shelf-"))
    #expect(!name.contains("9f3c"))
    #expect(name.count == "shelf-".count + 16, "eight bytes of hex")
}

/// The user's own shelf keeps a fixed name, so an app update does not delete the listing already on
/// the phone.
@Test func theUsersOwnShelfKeepsAStableName() {
    #expect(LibraryStore.name(for: .own) == "listing")
}

@Test func theSameOwnerAlwaysNamesTheSameFile() {
    #expect(LibraryStore.name(for: .of("friend")) == LibraryStore.name(for: .of("friend")))
    #expect(LibraryStore.name(for: .of("friend")) != LibraryStore.name(for: .of("other")))
}

/// When a share is taken back, its listing must be deleted. Nobody may read it any more, so it must
/// not stay on the phone.
@Test func deletingOneShelfLeavesTheOthers() {
    let root = scratch()
    defer { try? FileManager.default.removeItem(at: root) }

    LibraryStore(shelf: .own, root: root).save(rows(3))
    let borrowed = LibraryStore(shelf: .of("friend"), root: root)
    borrowed.save(rows(9))

    borrowed.delete()

    #expect(borrowed.load() == nil)
    #expect(LibraryStore(shelf: .own, root: root).load()?.count == 3)
}

@Test func signingOutLeavesNoListingAtAll() {
    let root = scratch()
    defer { try? FileManager.default.removeItem(at: root) }

    LibraryStore(shelf: .own, root: root).save(rows(3))
    LibraryStore(shelf: .of("one"), root: root).save(rows(4))
    LibraryStore(shelf: .of("two"), root: root).save(rows(5))

    LibraryStore.deleteAll(root: root)

    #expect(LibraryStore(shelf: .own, root: root).load() == nil)
    #expect(LibraryStore(shelf: .of("one"), root: root).load() == nil)
    #expect(LibraryStore(shelf: .of("two"), root: root).load() == nil)
}

@Test func savingTwiceLeavesTheSecondListing() {
    let root = scratch()
    defer { try? FileManager.default.removeItem(at: root) }

    let store = LibraryStore(shelf: .own, root: root)
    store.save(rows(30))
    store.save(rows(4))

    #expect(store.load()?.count == 4)
}

/// No `.part` file may be left after a save. A leftover file would grow with a copy of the library on every
/// launch.
@Test func noTemporaryFileIsLeftBehind() {
    let root = scratch()
    defer { try? FileManager.default.removeItem(at: root) }

    LibraryStore(shelf: .own, root: root).save(rows(10))

    let left = try! FileManager.default.contentsOfDirectory(atPath: root.path)
    #expect(left == ["listing.json.z"], "left behind: \(left)")
}

/// The listing is compressed because it has thousands of rows that look almost the same.
@Test func aListingCompressesWorthwhile() {
    let root = scratch()
    defer { try? FileManager.default.removeItem(at: root) }

    let tracks = rows(2000)
    LibraryStore(shelf: .own, root: root).save(tracks)

    let raw = try! RPMJSON.encoder.encode(tracks).count
    let onDisk = try! Data(contentsOf: root.appendingPathComponent("listing.json.z")).count

    #expect(onDisk < raw / 5, "\(onDisk) of \(raw) is not worth compressing for")
}
