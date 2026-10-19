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
        let portraits = ArtistPortraits(source: shelf)

        #expect(await portraits.portrait(of: "Enya", edge: 256) != nil)
        #expect(await shelf.fetched == [backdrop])
    }

    /// An artist with only a square has no box picture. The box then shows its plain ground, the
    /// same as an artist with no backdrop.
    @Test func aSquareAloneIsNoBoxPicture() async {
        let shelf = Shelf(has: ArtistPictures(backdrops: [], squares: [square], logo: nil, partial: false))
        let portraits = ArtistPortraits(source: shelf)

        #expect(await portraits.portrait(of: "Enya", edge: 256) == nil)
        #expect(await portraits.hasNothing(for: "Enya"))
        #expect(await shelf.fetched.isEmpty)
    }

    /// A portrait that is already fetched is drawn in a view's first frame. It is drawn at its own
    /// size, or at the nearest size held, with a larger size preferred.
    @Test func aPortraitHeldIsInMemoryAtItsSizeOrTheNearest() async {
        let shelf = Shelf(has: ArtistPictures(backdrops: [backdrop], squares: [], logo: nil, partial: false))
        let portraits = ArtistPortraits(source: shelf)

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
}
