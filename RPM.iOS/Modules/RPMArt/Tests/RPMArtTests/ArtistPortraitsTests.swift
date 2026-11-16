import Foundation
import Testing
import RPMKit
import RPMLibrary
import RPMDesign
@testable import RPMArt

/// Which picture a box on the artists wall shows.
///
/// **A backdrop, never the square.** The boxes are 16 by 9, the shape that backdrops come in. The
/// square pictures are used on pages about one artist (the home banner and the artist page). Those
/// pages call ``BackdropStore/portrait(artist:album:cutFor:)``.
struct ArtistPortraitsTests {
    actor Shelf: ArtSource {
        private let has: ArtistPictures
        private(set) var fetched: [URL] = []

        init(has: ArtistPictures) { self.has = has }

        func artistPictures(artist: String, album: String?) async throws -> ArtistPictures { has }

        func artwork(at url: URL) async throws -> Data {
            fetched.append(url)
            return Pictures.png(field: RGB(40, 120, 160), edge: 300)
        }

        func artCatalog(_ shelf: CloudShelf) async throws -> [StoredCover] { [] }
        func art(_ shelf: CloudShelf, albumKey: String, size: CoverSize) async -> StoredCover? { nil }
        func sidecar(rpmId: String) async throws -> TagSidecar? { nil }
    }

    private let square = URL(string: "https://assets.fanart.tv/fanart/music/x/artistthumb/sq.jpg")!
    private let backdrop = URL(string: "https://assets.fanart.tv/fanart/music/x/artistbackground/bg.jpg")!

    @Test func theWallWearsTheBackdropEvenWhereThereIsASquare() async {
        let shelf = Shelf(has: ArtistPictures(backdrops: [backdrop], squares: [square], logo: nil, partial: false))
        let portraits = ArtistPortraits(source: shelf, disk: nil)

        #expect(await portraits.portrait(of: "Enya", edge: 256) != nil)
        #expect(await shelf.fetched == [backdrop])
    }

    /// An artist with only a square has no box picture. The box then shows its plain ground, the
    /// same as an artist with no backdrop.
    @Test func aSquareAloneIsNoBoxPicture() async {
        let shelf = Shelf(has: ArtistPictures(backdrops: [], squares: [square], logo: nil, partial: false))
        let portraits = ArtistPortraits(source: shelf, disk: nil)

        #expect(await portraits.portrait(of: "Enya", edge: 256) == nil)
        #expect(await portraits.hasNothing(for: "Enya"))
        #expect(await shelf.fetched.isEmpty)
    }

    /// A portrait that is already fetched is drawn in a view's first frame. It is drawn at its own
    /// size, or at the nearest size held, with a larger size preferred.
    @Test func aPortraitHeldIsInMemoryAtItsSizeOrTheNearest() async {
        let shelf = Shelf(has: ArtistPictures(backdrops: [backdrop], squares: [], logo: nil, partial: false))
        let portraits = ArtistPortraits(source: shelf, disk: nil)

        #expect(portraits.portraitInMemory(of: "Enya", edge: 256) == nil)

        let small = try! #require(await portraits.portrait(of: "Enya", edge: 256))
        #expect(portraits.portraitInMemory(of: "Enya", edge: 200) === small)
        // No picture at 600 is held yet, so the 256 picture is the nearest size held.
        #expect(portraits.portraitInMemory(of: "Enya", edge: 600) === small)

        let large = try! #require(await portraits.portrait(of: "Enya", edge: 600))
        #expect(portraits.portraitInMemory(of: "Enya", edge: 600) === large)
        // A smaller view takes the next larger size held. A larger picture shrinks cleanly.
        #expect(portraits.portraitInMemory(of: "Enya", edge: 256) === small)
        #expect(portraits.portraitInMemory(of: "Kate Bush", edge: 256) == nil)
    }

    // ── the disk ──

    private func emptyDisk() -> CoverDisk {
        CoverDisk(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("portraits-\(UUID().uuidString)", isDirectory: true))
    }

    /// A photo fetched once is on the disk, so the next launch draws it without asking again.
    @Test func aPortraitFetchedOnceIsReadFromTheDiskAfterALaunch() async {
        let disk = emptyDisk()
        let first = Shelf(has: ArtistPictures(backdrops: [backdrop], squares: [], logo: nil, partial: false))
        _ = await ArtistPortraits(source: first, disk: disk).portrait(of: "Enya", edge: 256)
        #expect(await first.fetched == [backdrop])

        let next = Shelf(has: ArtistPictures(backdrops: [backdrop], squares: [], logo: nil, partial: false))
        let again = ArtistPortraits(source: next, disk: disk)
        #expect(await again.portrait(of: "Enya", edge: 256) != nil)
        #expect(await next.fetched.isEmpty)
        #expect(await again.bytesOnDisk() > 0)
    }

    /// An old photo is drawn at once, and the artist is asked again in the background.
    @Test func anOldPortraitIsDrawnAndAskedAgain() async throws {
        let disk = emptyDisk()
        let old = try #require(Thumbnail.of(Pictures.png(field: RGB(200, 40, 40), edge: 300), edge: 256))
        let bytes = try #require(Thumbnail.encoded(old, .cover))
        let lastPeriod = ArtistPortraits.period(Date()) - 1
        await disk.hold(albumKey: ArtistPortraits.diskKey("Enya", 256), stamp: lastPeriod, bytes)

        let shelf = Shelf(has: ArtistPictures(backdrops: [backdrop], squares: [], logo: nil, partial: false))
        let portraits = ArtistPortraits(source: shelf, disk: disk)
        #expect(await portraits.portrait(of: "Enya", edge: 256) != nil)

        // The ask runs in the background; it is given a moment to arrive.
        for _ in 0..<50 where await shelf.fetched.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        #expect(await shelf.fetched == [backdrop])
    }

    /// Signing out empties the disk: the artists a phone has photos of say what was in the collection.
    @Test func forgettingEmptiesTheDisk() async {
        let disk = emptyDisk()
        let shelf = Shelf(has: ArtistPictures(backdrops: [backdrop], squares: [], logo: nil, partial: false))
        let portraits = ArtistPortraits(source: shelf, disk: disk)
        _ = await portraits.portrait(of: "Enya", edge: 256)
        #expect(await portraits.bytesOnDisk() > 0)

        await portraits.forget()
        #expect(await portraits.bytesOnDisk() == 0)
    }
}
