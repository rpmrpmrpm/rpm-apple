import Testing
import Foundation
import ImageIO
import UniformTypeIdentifiers
import RPMKit
import RPMLibrary
import RPMDesign
@testable import RPMArt

// ── the fixtures ──

private func scratchDisk(files: Int = CoverDisk.mostFiles) -> (CoverDisk, URL) {
    let at = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("rpm-store-\(UUID().uuidString)", isDirectory: true)
    return (CoverDisk(directory: at, mostFiles: files), at)
}

private func record(_ name: String, artist: String = "Talk Talk",
                    albumArtist: String? = nil, tracks: Int = 3) -> CloudAlbum {
    let rows = (0..<tracks).map { i -> CloudTrack in
        var tags = CloudTrackTags()
        tags.albumArtist = albumArtist
        tags.trackNumber = i + 1
        return CloudTrack(rpmId: "\(name)-\(i)", relativePath: "\(artist)/\(name)/\(i).flac",
                          title: "Track \(i)", artist: artist, album: name, tags: tags)
    }
    return CloudAlbum(key: "\(artist)|\(name)", album: name, artist: artist, tracks: rows)
}

private func keyOf(_ album: CloudAlbum) -> String {
    AlbumArtKey.spellings(.cover, for: album.tracks)[0]
}

private let sleeve = Pictures.jpeg(field: RGB(50, 40, 40), splash: RGB(225, 30, 25),
                                   share: 0.3, edge: 600)

// ── the happy path ──

@Test func aRecordWithAStoredCoverGetsItsSleeve() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 100), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    let art = try! #require(await store.cover(for: album, on: .own, edge: 256))

    #expect(art.image.width == 256)
    #expect(["Vermilion", "Red", "Crimson", "Rust"].contains(art.accent?.name ?? "none"),
            "a red sleeve came out \(art.accent?.name ?? "none")")

    // The room's colour pair comes from the same square as the accent, and is cached with it.
    // This checks that the cache keeps both values.
    #expect(art.colours.dominant != nil, "the room got no colour off a red sleeve")
}

/// A wall is one listing, not one per tile. Otherwise a screen of many tiles would send
/// many requests.
@Test func theListingIsReadOnceForAWholeWall() async {
    let source = FakeArt()
    let albums = (0..<20).map { record("Album \($0)") }

    for album in albums {
        await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)
    }

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    await withTaskGroup(of: Void.self) { group in
        for album in albums {
            group.addTask { _ = await store.cover(for: album, on: .own, edge: 256) }
        }
    }

    #expect(await source.listings == 1)
}

/// A resize draws every visible cell again, so one record can be asked for twice in one frame. Two
/// asks must not become two downloads of the same picture.
@Test func twoTilesOfOneRecordAreOneDownload() async {
    let source = FakeArt()
    let album = record("Spirit of Eden")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)
    await source.slowDown(to: .milliseconds(80))

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    async let first = store.cover(for: album, on: .own, edge: 256)
    async let second = store.cover(for: album, on: .own, edge: 256)

    let both = await [first, second]

    #expect(both.allSatisfy { $0 != nil })
    #expect(await source.started == 1)
}

@Test func aSecondGlanceCostsNothing() async {
    let source = FakeArt()
    let album = record("Hex")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    _ = await store.cover(for: album, on: .own, edge: 256)
    _ = await store.cover(for: album, on: .own, edge: 256)

    #expect(await source.started == 1)
}

/// A second launch. Everything is on the disk, and nothing is fetched from the network.
@Test func aSleeveAlreadyOnTheDiskIsNotFetchedAgain() async {
    let source = FakeArt()
    let album = record("Watermark")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 42), picture: sleeve)

    let at = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("rpm-relaunch-\(UUID().uuidString)", isDirectory: true)

    _ = await ArtworkStore(source: source, disk: CoverDisk(directory: at))
        .cover(for: album, on: .own, edge: 256)

    let afterRelaunch = ArtworkStore(source: source, disk: CoverDisk(directory: at))
    #expect(await afterRelaunch.cover(for: album, on: .own, edge: 256) != nil)

    #expect(await source.started == 1)
}

/// **The version is the stamp.** A better scan uploaded from a desktop does not change the
/// picture's address. Only the version can tell the phone that its copy is out of date.
@Test func aReplacedSleeveIsFetchedAgain() async {
    let source = FakeArt()
    let album = record("Kid A")
    let key = keyOf(album)

    await source.hold(StoredCover(albumKey: key, updatedAt: 1), picture: sleeve)

    let at = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("rpm-replaced-\(UUID().uuidString)", isDirectory: true)

    _ = await ArtworkStore(source: source, disk: CoverDisk(directory: at))
        .cover(for: album, on: .own, edge: 256)

    let corrected = Pictures.jpeg(field: RGB(30, 60, 160), edge: 600)
    await source.hold(StoredCover(albumKey: key, updatedAt: 2), picture: corrected)

    let laterLaunch = ArtworkStore(source: source, disk: CoverDisk(directory: at))
    #expect(await laterLaunch.cover(for: album, on: .own, edge: 256) != nil)

    #expect(await source.started == 2)
}

// ── the size asked for ──

/// What the disk holds for a record: its format and its longer side.
private func kept(on disk: CoverDisk, _ key: String, stamp: Int64) async -> (data: Data, type: String, edge: Int)? {
    guard let data = await disk.picture(albumKey: key, stamp: stamp),
          let source = CGImageSourceCreateWithData(data as CFData, nil),
          let type = CGImageSourceGetType(source),
          let facts = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = facts[kCGImagePropertyPixelWidth] as? Int,
          let height = facts[kCGImagePropertyPixelHeight] as? Int
    else { return nil }
    return (data, type as String, max(width, height))
}

/// A sleeve is asked for at the size the phone keeps it, at every size it is drawn: the API's
/// copy at 1024 is the picture the phone would otherwise cut from the original itself.
@Test func aCoverIsAskedForAtTheSizeThePhoneKeeps() async {
    let source = FakeArt()
    let small = record("Spirit of Eden")
    let large = record("The Colour of Spring")
    await source.hold(StoredCover(albumKey: keyOf(small), updatedAt: 1), picture: sleeve)
    await source.hold(StoredCover(albumKey: keyOf(large), updatedAt: 1), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)
    _ = await store.cover(for: small, on: .own, edge: 200)
    _ = await store.cover(for: large, on: .own, edge: 1300)

    #expect(await source.sizes[keyOf(small)] == [.edge(Thumbnail.stored)])
    #expect(await source.sizes[keyOf(large)] == [.edge(Thumbnail.stored)])
}

/// The API's copy is already a JPEG no larger than what the phone keeps, so it goes to the
/// disk as it arrived rather than being compressed a second time.
@Test func aCopyThatArrivesAsASmallJPEGIsKeptAsItArrived() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    let copy = Pictures.jpeg(field: RGB(50, 40, 40), splash: RGB(225, 30, 25), share: 0.3,
                             edge: Thumbnail.stored)
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 5), picture: copy)

    let (disk, _) = scratchDisk()
    _ = await ArtworkStore(source: source, disk: disk).cover(for: album, on: .own, edge: 256)

    let held = try! #require(await kept(on: disk, keyOf(album), stamp: 5))
    #expect(held.data == copy)
}

/// An API that makes no copies, or one that could not cut this cover, sends the original. The
/// phone still cuts that down itself.
@Test func anOriginalLargerThanWhatIsKeptIsStillCutOnThePhone() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    let original = Pictures.jpeg(field: RGB(50, 40, 40), edge: 2000)
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 5), picture: original)

    let (disk, _) = scratchDisk()
    _ = await ArtworkStore(source: source, disk: disk).cover(for: album, on: .own, edge: 256)

    let held = try! #require(await kept(on: disk, keyOf(album), stamp: 5))
    #expect(held.edge == Thumbnail.stored)
    #expect(held.type == UTType.jpeg.identifier)
}

/// A small sleeve that is not a JPEG (an original the API served as it is) is kept as a JPEG,
/// as every sleeve on the disk is.
@Test func aSmallSleeveThatIsNotAJPEGIsKeptAsOne() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    let original = Pictures.png(field: RGB(50, 40, 40), edge: 600)
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 5), picture: original)

    let (disk, _) = scratchDisk()
    _ = await ArtworkStore(source: source, disk: disk).cover(for: album, on: .own, edge: 256)

    let held = try! #require(await kept(on: disk, keyOf(album), stamp: 5))
    #expect(held.type == UTType.jpeg.identifier)
    #expect(held.edge == 600)
}

// ── the records with no cover ──

/// Without remembering the miss, a wall of records with no cover would send one request per tile
/// on every scroll.
@Test func aRecordWithNothingIsAskedAboutOnce() async {
    let source = FakeArt()
    let album = record("Nothing Here")

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    for _ in 0..<10 {
        #expect(await store.cover(for: album, on: .own, edge: 256) == nil)
    }

    #expect(await source.sidecars == 1)
}

/// A sidecar is an object under the account that uploaded it. The route takes no shelf, so asking
/// about another person's row would be a 404 and a wasted round trip.
@Test func aBorrowedRecordDoesNotAskAboutSomebodyElsesFile() async {
    let source = FakeArt()
    let album = record("Borrowed")

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.cover(for: album, on: .of("someone-else"), edge: 256) == nil)
    #expect(await source.sidecars == 0)
}

/// The art embedded in the user's own audio file is the fallback. The stored cover is the picture
/// the library shows first. Most ripped albums have their cover as a folder image, not inside the
/// files.
@Test func theArtInTheFileIsTheFallback() async {
    let source = FakeArt()
    let album = record("Pink Moon")
    await source.embed(sleeve, in: album.tracks[0].rpmId)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.cover(for: album, on: .own, edge: 256) != nil)
    #expect(await source.signings == 0)
}

/// A compilation can be filed under "Various Artists" or under its track artist, depending on who
/// uploaded it. The phone tries both spellings.
@Test func aRecordIsFoundUnderEitherSpelling() async {
    let source = FakeArt()
    let album = record("Now 22", artist: "Snap!", albumArtist: "Various Artists")

    // The stored key uses the track artist, so the phone must try the other spelling.
    await source.hold(
        StoredCover(albumKey: AlbumArtKey.of(.cover, albumArtist: "Snap!", album: "Now 22"), updatedAt: 5),
        picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.cover(for: album, on: .own, edge: 256) != nil)
}

// ── the thumb ──

/// A download is kept going only while someone is waiting for it. Finishing downloads for a wall
/// that has already moved on wastes data, so the waiters are counted.
@Test func aPictureNobodyIsWaitingForIsNotFinished() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)
    await source.slowDown(to: .milliseconds(400))

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    let scrolledPast = Task { await store.cover(for: album, on: .own, edge: 256) }
    await source.waitUntilStarted(1)

    scrolledPast.cancel()
    _ = await scrolledPast.value

    try? await Task.sleep(for: .milliseconds(600))
    #expect(await source.finished == 0)
}

/// The other half of that rule: a download is kept while one waiter is still there, however many
/// have gone.
@Test func aPictureOnePersonIsStillWaitingForIsFinished() async {
    let source = FakeArt()
    let album = record("Spirit of Eden")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)
    await source.slowDown(to: .milliseconds(250))

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    let scrolledPast = Task { await store.cover(for: album, on: .own, edge: 256) }
    await source.waitUntilStarted(1)

    let stillLooking = Task { await store.cover(for: album, on: .own, edge: 256) }
    try? await Task.sleep(for: .milliseconds(40))

    scrolledPast.cancel()
    _ = await scrolledPast.value

    #expect(await stillLooking.value != nil)
    #expect(await source.started == 1)
}

// ── signing out ──

/// A download that finishes after sign-out would put the last person's record collection back on
/// this phone just after sign-out has removed it.
@Test func signingOutKeepsNothing() async {
    let source = FakeArt()
    let album = record("Blue")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)
    await source.slowDown(to: .milliseconds(200))

    let (disk, at) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    let inFlight = Task { await store.cover(for: album, on: .own, edge: 256) }
    await source.waitUntilStarted(1)

    await store.forget()
    _ = await inFlight.value

    try? await Task.sleep(for: .milliseconds(400))

    let files = (try? FileManager.default.contentsOfDirectory(atPath: at.path)) ?? []
    #expect(files.isEmpty, "left \(files) on the disk")
}

@Test func signingOutForgetsTheListingToo() async {
    let source = FakeArt()
    let album = record("Blue")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    _ = await store.cover(for: album, on: .own, edge: 256)
    await store.forget()
    _ = await store.cover(for: album, on: .own, edge: 256)

    #expect(await source.listings == 2)
}

// ── the listing ──

/// A listing that could not be read is not a valid reading. If it were kept for the full ten
/// minutes (`ArtworkStore.indexLife`), a phone that had lost signal would draw placeholders over a
/// disk full of covers.
@Test func aListingThatCouldNotBeReadIsNotAReading() async {
    let source = FakeArt()
    let album = record("Clandestino", artist: "Manu Chao")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)
    await source.unplug()

    let clock = Clock()
    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk, now: { clock.now })

    #expect(await store.cover(for: album, on: .own, edge: 256) == nil)

    await source.plugBackIn()
    clock.advance(ArtworkStore.indexRetry + 1)

    #expect(await store.cover(for: album, on: .own, edge: 256) != nil)
}

/// The other side of that rule. With no signal, a wall of six hundred records must make one failed
/// listing, not six hundred.
@Test func aWallUndergroundAsksOnce() async {
    let source = FakeArt()
    await source.unplug()

    let clock = Clock()
    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk, now: { clock.now })

    for i in 0..<20 {
        _ = await store.cover(for: record("Album \(i)"), on: .own, edge: 256)
    }

    #expect(await source.listings == 1)
}

/// An account with no covers stored is a valid reading. It is not asked about again until the
/// listing expires.
@Test func aCollectionWithNoCoversIsStillAnAnswer() async {
    let source = FakeArt()

    let clock = Clock()
    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk, now: { clock.now })

    for i in 0..<5 {
        _ = await store.cover(for: record("Album \(i)"), on: .own, edge: 256)
    }

    clock.advance(ArtworkStore.indexRetry + 1)
    _ = await store.cover(for: record("One More"), on: .own, edge: 256)

    #expect(await source.listings == 1)
}

@Test func theListingIsReadAgainAfterItsLife() async {
    let source = FakeArt()
    let album = record("Chorus", artist: "Erasure")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)

    let clock = Clock()
    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk, now: { clock.now })

    _ = await store.cover(for: album, on: .own, edge: 256)
    #expect(await source.listings == 1)

    clock.advance(ArtworkStore.indexLife + 1)
    _ = await store.cover(for: record("Something Else"), on: .own, edge: 256)

    #expect(await source.listings == 2)
}

/// A record that gained a cover after the last look must not stay in the no-cover notes. Those
/// notes are dropped whenever the listing is read again.
@Test func aRecordThatGainsACoverIsNoLongerNothing() async {
    let source = FakeArt()
    let album = record("Late Arrival")

    let clock = Clock()
    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk, now: { clock.now })

    #expect(await store.cover(for: album, on: .own, edge: 256) == nil)

    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 3), picture: sleeve)
    clock.advance(ArtworkStore.indexLife + 1)

    #expect(await store.cover(for: album, on: .own, edge: 256) != nil)
}

// ── the pinch ──

/// A pinch does not fetch anything. The picture is on this disk at a size that covers every width
/// the wall can have.
@Test func pinchingTheWallDoesNotFetchAnything() async {
    let source = FakeArt()
    let album = record("Sandinista", artist: "The Clash")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    for edge in [170, 256, 400, 512, 900, 1024] {
        #expect(await store.cover(for: album, on: .own, edge: edge) != nil)
    }

    #expect(await source.started == 1)
}

/// A record keeps the same colour when the wall is pinched.
@Test func aRecordIsTheSameColourAtEveryWidth() async {
    let source = FakeArt()
    let album = record("Amber")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    var names: Set<String> = []
    for edge in [170, 512, 1024] {
        names.insert(await store.cover(for: album, on: .own, edge: edge)?.accent?.name ?? "none")
    }

    #expect(names.count == 1, "read \(names)")
}

@Test func aWidthBiggerThanAnythingKeptStillDraws() async {
    let source = FakeArt()
    let album = record("Huge")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(await store.cover(for: album, on: .own, edge: 4000) != nil)
}

// ── a clock a test can move ──

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var at = Date(timeIntervalSince1970: 1_700_000_000)

    var now: Date { lock.withLock { at } }
    func advance(_ by: TimeInterval) { lock.withLock { at += by } }
}

// ── fetches that fail or are cancelled ──
//
// A cancelled or failed fetch says nothing about whether a record has a cover. Only the listing
// decides that. A record marked as having no cover stays marked until the listing is read again.

/// A scroll that cancels a fetch part way through says nothing about whether the record has a cover.
@Test func aCancelledFetchDoesNotLeaveTheRecordBlank() async {
    let source = FakeArt()
    let album = record("Laughing Stock")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)
    await source.slowDown(to: .milliseconds(300))

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    let scrolledPast = Task { await store.cover(for: album, on: .own, edge: 256) }
    await source.waitUntilStarted(1)
    scrolledPast.cancel()
    _ = await scrolledPast.value

    await source.slowDown(to: nil)

    // Scrolled back to. The cover is there and it must arrive.
    #expect(await store.cover(for: album, on: .own, edge: 256) != nil,
            "the record was written off because a scroll cancelled its download")
}

/// A failed fetch is not a record without a cover. The listing is already in hand, so the store
/// keeps answering from it. The picture arrives when the signal returns.
@Test func aFetchThatCouldNotBeMadeDoesNotLeaveTheRecordBlank() async {
    let source = FakeArt()
    let seen = record("Hex")
    let later = record("Codename Dustsucker")

    for album in [seen, later] {
        await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)
    }

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    // The listing arrives while there is a signal, and one record is drawn.
    #expect(await store.cover(for: seen, on: .own, edge: 256) != nil)

    // Then the signal is lost, and the next record down the wall is asked for. The listing is still
    // in hand, so the store knows this record has a cover. It cannot reach the cover yet.
    await source.unplug()
    #expect(await store.cover(for: later, on: .own, edge: 256) == nil)

    await source.plugBackIn()
    #expect(await store.cover(for: later, on: .own, edge: 256) != nil,
            "the record was written off because one fetch failed")
}

/// A record the store has nothing for is asked about once, not once per tile per scroll.
@Test func aRecordWithNothingAnywhereIsOnlyAskedAboutOnce() async {
    let source = FakeArt()
    let album = record("Nothing Here")

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    for _ in 0..<5 {
        #expect(await store.cover(for: album, on: .own, edge: 256) == nil)
    }

    let asked = await source.sidecars
    #expect(asked == 1, "asked \(asked) times for one nothing")
}

// ── what a view draws on its first frame ──

/// A card that is built again (a carousel step, or a row scrolled back) draws the cover it had on
/// its first frame. That is the last picture handed out for the record at that size, read without
/// waiting.
@Test func aSleeveHandedOutIsInMemoryForTheNextView() async {
    let source = FakeArt()
    let album = record("Spirit of Eden")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    #expect(store.coverInMemory(for: album, on: .own, edge: 256) == nil)

    let art = try! #require(await store.cover(for: album, on: .own, edge: 256))

    // Any size in the same bucket is the same picture. A larger view with no picture of its own
    // draws the nearest size held until its own request finishes. A record on another shelf is a
    // different record.
    #expect(store.coverInMemory(for: album, on: .own, edge: 200)?.image === art.image)
    #expect(store.coverInMemory(for: album, on: .own, edge: 600)?.image === art.image)
    #expect(store.coverInMemory(for: album, on: .of("someone-else"), edge: 256) == nil)

    let large = try! #require(await store.cover(for: album, on: .own, edge: 600))
    #expect(store.coverInMemory(for: album, on: .own, edge: 600)?.image === large.image)
    #expect(store.coverInMemory(for: album, on: .own, edge: 256)?.image === art.image)
}

/// After sign-out, the next account's first frames draw nothing from the last account.
@Test func signingOutEmptiesWhatAViewDrawsFirst() async {
    let source = FakeArt()
    let album = record("Hounds of Love")
    await source.hold(StoredCover(albumKey: keyOf(album), updatedAt: 1), picture: sleeve)

    let (disk, _) = scratchDisk()
    let store = ArtworkStore(source: source, disk: disk)

    _ = await store.cover(for: album, on: .own, edge: 256)
    await store.forget()

    #expect(store.coverInMemory(for: album, on: .own, edge: 256) == nil)
}
