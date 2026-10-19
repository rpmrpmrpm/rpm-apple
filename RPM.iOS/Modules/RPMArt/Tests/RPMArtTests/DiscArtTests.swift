import Testing
import Foundation
import CoreGraphics
import RPMKit
import RPMLibrary
import RPMDesign
@testable import RPMArt

// ── the fixtures ──

private func scratchDisk() -> (CoverDisk, URL) {
    let at = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("rpm-disc-\(UUID().uuidString)", isDirectory: true)
    return (CoverDisk(directory: at), at)
}

private func record(_ name: String, artist: String = "Talk Talk", tracks: Int = 3) -> CloudAlbum {
    let rows = (0..<tracks).map { i -> CloudTrack in
        var tags = CloudTrackTags()
        tags.trackNumber = i + 1
        return CloudTrack(rpmId: "\(name)-\(i)", relativePath: "\(artist)/\(name)/\(i).flac",
                          title: "Track \(i)", artist: artist, album: name, tags: tags)
    }
    return CloudAlbum(key: "\(artist)|\(name)", album: name, artist: artist, tracks: rows)
}

private func coverKey(_ album: CloudAlbum) -> String {
    AlbumArtKey.spellings(.cover, for: album.tracks)[0]
}

private func discKey(_ album: CloudAlbum) -> String {
    AlbumArtKey.spellings(.disc, for: album.tracks)[0]
}

private let sleeve = Pictures.jpeg(field: RGB(50, 40, 40), splash: RGB(225, 30, 25),
                                   share: 0.3, edge: 600)
private let pressing = Pictures.disc(RGB(20, 20, 20), edge: 600)

// ── the record the store has a photograph of ──

/// A record whose folder holds a disc.png on the desktop turns on the phone's deck
/// wearing that picture.
@Test func aRecordWithAStoredDiscWearsIt() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 100), picture: pressing)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    let disc = try! #require(await store.disc(for: album, on: .own, edge: 256))
    #expect(disc.image.width == 256)

    // A whole disc, so it replaces the drawn record rather than sitting on it.
    #expect(disc.coversRecord)
}

/// **A disc is asked for as the original.** The API's sized copies are JPEGs on a black
/// background, so a copy of a disc label would come back as a square with black corners turning
/// on the deck.
@Test func aDiscIsAskedForAsTheOriginal() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 100), picture: pressing)

    let (disk, _) = scratchDisk()
    _ = await ArtworkStore(source: source, disk: disk).disc(for: album, on: .own, edge: 256)

    #expect(await source.sizes[discKey(album)] == [.original])
}

/// The same rule applies to a disc that is fetched beside its sleeve before anybody asks for it.
@Test func aWarmedDiscIsAskedForAsTheOriginal() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: coverKey(album), updatedAt: 100), picture: sleeve)
    await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 100), picture: pressing)

    let (disk, _) = scratchDisk()
    let wall = ArtworkStore(source: source, disk: disk)
    _ = await wall.cover(for: album, on: .own, edge: 256)
    #expect(await landed(on: disk, key: discKey(album), stamp: 100))

    #expect(await source.sizes[discKey(album)] == [.original])
    #expect(await source.sizes[coverKey(album)] == [.edge(Thumbnail.stored)])

    withExtendedLifetime(wall) {}
}

/// **A disc is filed under its own key and read from nowhere else.** The two pictures
/// of one record live in one prefix. If the store fell back to the cover's key, the sleeve
/// would appear on the turntable: a square photograph of a cardboard sleeve turning where the
/// record should be, and nothing would report it.
@Test func aDiscIsNeverTheCoverUnderAnotherName() async {
    let source = FakeArt()
    let album = record("Spirit of Eden")
    await source.hold(StoredCover(albumKey: coverKey(album), updatedAt: 100), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.disc(for: album, on: .own, edge: 256) == nil)
}

/// A sidecar holds the art embedded in the user's own file, and a disc label is never
/// in a tag. Falling back to the sidecar would fetch the sleeve and return it as if it
/// were a photograph of the record. It would also cost one round trip per album.
@Test func aDiscIsNeverTakenOutOfASidecar() async {
    let source = FakeArt()
    let album = record("Colour of Spring")
    await source.embed(sleeve, in: album.tracks[0].rpmId)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.disc(for: album, on: .own, edge: 256) == nil)
    #expect(await source.sidecars == 0, "the disc went looking in a file's tags")
}

/// **The ordinary record.** Most albums have a cover and no disc. The note that says "asked,
/// and there is nothing" is kept in one set. If a disc were noted under the album alone, the
/// album's sleeve would disappear from the lock screen for the ten minutes until the listing is
/// read again.
@Test func aRecordWithNoDiscStillHasItsCover() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: coverKey(album), updatedAt: 100), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.disc(for: album, on: .own, edge: 256) == nil)
    #expect(await store.cover(for: album, on: .own, edge: 256) != nil,
            "asking for the disc took the sleeve away")
}

/// The other way round: the same set, read from the other end.
@Test func aRecordWithNoCoverStillHasItsDisc() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 100), picture: pressing)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.cover(for: album, on: .own, edge: 256) == nil)
    #expect(await store.disc(for: album, on: .own, edge: 256) != nil,
            "asking for the sleeve took the record away")
}

// ── the transparency, which is the shape ──

/// A disc arrives round: a circle with the corners of the photograph cut away. The
/// turntable clips to this shape, and it makes the picture look like a record.
@Test func aDiscArrivesWithItsCornersCutAway() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 100), picture: pressing)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    let disc = try! #require(await store.disc(for: album, on: .own, edge: 256))

    #expect(Pictures.opacity(of: disc.image, atX: 1, y: 1) == 0, "the corner came back opaque")
    #expect(Pictures.opacity(of: disc.image, atX: disc.image.width / 2, y: disc.image.height / 2) == 255,
            "the middle of the record came back see-through")
}

/// **A JPEG would fail this test.** The store keeps its own downscale and not the bytes
/// that arrived. A sleeve is kept as a JPEG, which cannot carry an alpha channel. If a disc
/// were kept that way, it would come back from this phone's disk as a full square, and the
/// background of the photograph would turn on the deck.
@Test func aKeptDiscComesBackOffTheDiskStillRound() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 100), picture: pressing)

    let (disk, _) = scratchDisk()

    // The disc is fetched once and kept. Then a second store is asked for it. That store has
    // nothing in memory and its source cannot be reached, so the only place the answer can
    // come from is what the first store wrote to the disk.
    _ = await ArtworkStore(source: source, disk: disk).disc(for: album, on: .own, edge: 256)
    await source.unplug()

    let again = ArtworkStore(source: source, disk: disk)
    let disc = try! #require(await again.disc(for: album, on: .own, edge: 256))

    #expect(Pictures.opacity(of: disc.image, atX: 1, y: 1) == 0,
            "the disc was kept as a square and came back as one")
}

// ── somebody else's shelf ──

private let borrowed = CloudShelf.of("a-friend")

/// A borrowed record's disc is an object under the owner's prefix, not the reader's.
/// A borrowed album has no folder on this machine, so the disc cannot be read from a folder.
/// This test checks that the phone asks the owner's shelf.
@Test func aBorrowedRecordsDiscComesOffTheOwnersShelf() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 100),
                      picture: pressing, on: borrowed)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    let disc = try! #require(await store.disc(for: album, on: borrowed, edge: 256))
    #expect(disc.coversRecord)
}

/// **A borrowed shelf is not the reader's own.** Two people can hold a record under one key.
/// A read that dropped the owner would answer with whichever copy this account has, silently
/// and with a 200 status.
@Test func aBorrowedShelfIsNotTheReadersOwn() async {
    let source = FakeArt()
    let album = record("Laughing Stock")

    // Only the reader has a disc for this record. When a friend's shelf is asked, the
    // answer is nothing, not the reader's own copy.
    await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 100), picture: pressing)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.disc(for: album, on: borrowed, edge: 256) == nil)
    #expect(await store.disc(for: album, on: .own, edge: 256) != nil)
}

/// A borrowed shelf has no sidecar to fall back on either. The route takes no owner,
/// so asking would give a 404 and waste a round trip. The cover code already follows this
/// rule, and the disc code must follow it too.
@Test func aBorrowedDiscNeverAsksForASidecar() async {
    let source = FakeArt()
    let album = record("Spirit of Eden")
    await source.embed(sleeve, in: album.tracks[0].rpmId)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.disc(for: album, on: borrowed, edge: 256) == nil)
    #expect(await source.sidecars == 0)
}

// ── fetched with the cover, not when the record plays ──

/// Waits, with a ceiling, for a picture to appear on the disk.
///
/// A warm has nobody waiting on it by design, so a test cannot await one. A loop with no
/// limit would turn a failure into a hung test run instead of a failed test.
private func landed(on disk: CoverDisk, key: String, stamp: Int64) async -> Bool {
    for _ in 0..<400 {
        if await disk.picture(albumKey: key, stamp: stamp) != nil { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

/// **The pairing that the desktop does, seen from the reading side.** A user who looked at a
/// record is likely to play it, so its disc is put on this phone while its sleeve is: when the
/// deck asks, the record change does not wait for the network.
@Test func askingForACoverPutsTheRecordsDiscOnThePhoneToo() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: coverKey(album), updatedAt: 100), picture: sleeve)
    await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 100), picture: pressing)

    let (disk, _) = scratchDisk()

    // **The store must be held in a variable.** A warm keeps only a weak reference to the
    // store, because a picture that nobody has asked for is not worth keeping a whole artwork
    // store alive. A store that goes out of scope takes its prefetch with it.
    let wall = ArtworkStore(source: source, disk: disk)

    // The wall asks for a sleeve. Nobody asks for a disc.
    _ = await wall.cover(for: album, on: .own, edge: 256)
    #expect(await landed(on: disk, key: discKey(album), stamp: 100),
            "the disc never reached this phone")

    // Now the store cannot be reached, as for a phone in a lift. The disc must come from
    // this phone or not at all.
    await source.unplug()

    let store = ArtworkStore(source: source, disk: disk)
    #expect(await store.disc(for: album, on: .own, edge: 256) != nil,
            "the disc was on the phone and the deck did not find it")

    withExtendedLifetime(wall) {}
}

/// **A record with no disc costs nothing**, and most records have none. The listing that the
/// store already holds names every picture on the shelf, so the question is answered
/// without a request, and without a note that would hide the sleeve.
@Test func aRecordWithNoDiscIsNotAskedAbout() async {
    let source = FakeArt()
    let album = record("Spirit of Eden")
    await source.hold(StoredCover(albumKey: coverKey(album), updatedAt: 100), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.cover(for: album, on: .own, edge: 256) != nil)

    // Long enough for a warm to start, if one were going to start.
    try? await Task.sleep(for: .milliseconds(60))

    #expect(await source.started == 1, "a record with no disc art was still asked about")
    #expect(await store.cover(for: album, on: .own, edge: 256) != nil,
            "warming the disc took the sleeve away")
}

/// A borrowed record's disc is warmed from its owner's shelf, like everything else about
/// it. This matters most for a shared collection, because its pictures have never been on
/// this phone before.
@Test func aBorrowedRecordsDiscIsWarmedFromItsOwnersShelf() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: coverKey(album), updatedAt: 100),
                      picture: sleeve, on: borrowed)
    await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 100),
                      picture: pressing, on: borrowed)

    let (disk, _) = scratchDisk()
    let wall = ArtworkStore(source: source, disk: disk)

    _ = await wall.cover(for: album, on: borrowed, edge: 256)
    #expect(await landed(on: disk, key: discKey(album), stamp: 100))

    await source.unplug()

    #expect(await ArtworkStore(source: source, disk: disk)
        .disc(for: album, on: borrowed, edge: 256) != nil)

    withExtendedLifetime(wall) {}
}

/// A fling prepares and discards cells much faster than a network answers, and a warm
/// has nobody waiting on it who could cancel it. So there is a limit, and past the limit a
/// record's disc is left to be fetched when the record plays.
@Test func aFlingCannotLeaveTheWholeWallDownloading() async {
    let source = FakeArt()
    await source.slowDown(to: .seconds(10))

    let albums = (0..<40).map { record("Album \($0)") }
    for album in albums {
        await source.hold(StoredCover(albumKey: coverKey(album), updatedAt: 1), picture: sleeve)
        await source.hold(StoredCover(albumKey: discKey(album), updatedAt: 1), picture: pressing)
    }

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    // Forty tiles are created and thrown away, as in a fling.
    await withTaskGroup(of: Void.self) { group in
        for album in albums {
            group.addTask {
                let asked = Task { _ = await store.cover(for: album, on: .own, edge: 256) }
                try? await Task.sleep(for: .milliseconds(5))
                asked.cancel()
            }
        }
    }

    try? await Task.sleep(for: .milliseconds(80))

    let running = await store.warmingNow
    #expect(running <= ArtworkStore.warmingAtOnce,
            "a fling left \(running) discs downloading")
}
