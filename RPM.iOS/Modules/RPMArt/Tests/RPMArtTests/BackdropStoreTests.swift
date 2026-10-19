import Foundation
import Testing
import RPMKit
import RPMLibrary
import RPMDesign
@testable import RPMArt

/// Pictures of the artist.
///
/// **What costs here is asking.** A lookup is one small answer per artist, and a picture is about a
/// megabyte. A track change inside an album must not fetch either again. Twelve tracks would be
/// twelve identical questions and twelve identical downloads of the same photograph.
/// **Serialised.** `VNImageRequestHandler.perform` is synchronous and holds the thread it runs on for
/// close to a second. If several of these run alongside the rest of the suite, every thread in the
/// cooperative pool can be inside Vision at once. The actor hops that the other tests wait for then
/// have no thread to run on, and the suite hangs instead of failing.
@Suite("Pictures of the artist", .serialized)
struct BackdropStoreTests {

    /// A fake catalogue that counts its requests.
    actor Catalogue: ArtSource {
        var lookups = 0
        var downloads = 0

        /// Whether the store can be reached at all, as on a phone that is not yet signed in.
        var reachable = true
        struct Unreachable: Error {}
        func unplug() { reachable = false }
        func plugBackIn() { reachable = true }

        /// Which artists have pictures, and how many.
        private let has: [String: Int]

        /// Whether the API marks its answers as only part of the full list.
        var partial = false
        func answerInPart() { partial = true }

        init(has: [String: Int]) { self.has = has }

        func artistPictures(artist: String, album: String?) async throws -> ArtistPictures {
            guard reachable else { throw Unreachable() }

            lookups += 1

            return ArtistPictures(backdrops: (0..<(has[artist] ?? 0)).map {
                URL(string: "https://pictures.example/\(artist)/\($0).jpg")!
            }, squares: [], logo: nil, partial: partial)
        }

        func artwork(at url: URL) async throws -> Data {
            downloads += 1

            return Pictures.png(field: RGB(120, 40, 160), edge: 300)
        }

        func artCatalog(_ shelf: CloudShelf) async throws -> [StoredCover] { [] }
        func art(_ shelf: CloudShelf, albumKey: String, size: CoverSize) async -> StoredCover? { nil }
        func sidecar(rpmId: String) async throws -> TagSidecar? { nil }

        func asked() -> (lookups: Int, downloads: Int) { (lookups, downloads) }
    }

    /// The stage, as the crop sees it: a landscape frame with the record covering the right from half
    /// its diameter in, and the words along the bottom.
    static let stage = ArtScene.forClearLeft(width: 852, height: 393, clearTop: 0,
                                             clearRight: 0.75, clearBottom: 0.62)
    var stage: ArtScene { Self.stage }

    // ── what it does ──

    /// A photograph comes back in the frame's shape, whatever shape it was read in. A square picture
    /// filled into a banner three times as wide as tall would be cut from its middle. On a person,
    /// that middle is the chest. So the cut is made to the frame's shape.
    @Test func aBackdropComesBackInTheFramesShape() async throws {
        let banner = ArtScene.forClearLeft(width: 1480, height: 480, clearTop: 0,
                                           clearRight: 1, clearBottom: 1)
        let store = BackdropStore(source: Catalogue(has: ["Loreena McKennitt": 1]))

        let picture = try #require(await store.backdrop(artist: "Loreena McKennitt", album: nil,
                                                        cutFor: banner))

        let shape = Double(picture.width) / Double(picture.height)
        #expect(abs(shape - 1480.0 / 480.0) < 0.05)
    }

    @Test func anArtistWithAPictureGetsOne() async {
        let store = BackdropStore(source: Catalogue(has: ["Enya": 3]))

        #expect(await store.backdrop(artist: "Enya", album: "Watermark", cutFor: stage) != nil)
        #expect(await store.count(artist: "Enya", album: nil) == 3)
    }

    /// The ordinary answer. Most artists in most libraries have no photograph anywhere. The stage then
    /// shows the record on its own ground, which is not a failure.
    @Test func anArtistWithNoPictureIsNotAFailure() async {
        let store = BackdropStore(source: Catalogue(has: [:]))

        #expect(await store.backdrop(artist: "Nobody", album: nil, cutFor: stage) == nil)
        #expect(await store.count(artist: "Nobody", album: nil) == 0)
    }

    @Test func nothingIsAskedAboutNobody() async {
        let catalogue = Catalogue(has: ["Enya": 1])
        let store = BackdropStore(source: catalogue)

        #expect(await store.backdrop(artist: nil, album: nil, cutFor: stage) == nil)
        #expect(await store.backdrop(artist: "", album: nil, cutFor: stage) == nil)
        #expect(await catalogue.asked().lookups == 0)
    }

    /// **A deck does not wrap.** A wrapping deck would page forever through one photograph, and
    /// there would be no sign that the end had been reached.
    @Test func askingPastTheLastPictureComesBackWithNothing() async {
        let store = BackdropStore(source: Catalogue(has: ["Enya": 2]))

        #expect(await store.backdrop(artist: "Enya", album: nil, at: 1, cutFor: stage) != nil)
        #expect(await store.backdrop(artist: "Enya", album: nil, at: 2, cutFor: stage) == nil)
        #expect(await store.backdrop(artist: "Enya", album: nil, at: -1, cutFor: stage) == nil)
    }

    // ── what it costs ──

    /// **One lookup per artist, not per track.** Every record by an artist shows the same photograph,
    /// so a lookup per album would repeat the same question for each record.
    @Test func anArtistIsLookedUpOnce() async {
        let catalogue = Catalogue(has: ["Enya": 2])
        let store = BackdropStore(source: catalogue)

        for album in ["Watermark", "Shepherd Moons", "The Very Best Of Enya"] {
            _ = await store.backdrop(artist: "Enya", album: album, cutFor: stage)
        }

        #expect(await catalogue.asked().lookups == 1)
    }

    /// ...and an artist with no pictures is looked up once too. An empty answer is the common case.
    /// Without this cache, every track change would ask the catalogue about them again.
    @Test func anArtistWithNothingIsAlsoAskedAboutOnce() async {
        let catalogue = Catalogue(has: [:])
        let store = BackdropStore(source: catalogue)

        for _ in 0..<5 { _ = await store.backdrop(artist: "Nobody", album: nil, cutFor: stage) }

        #expect(await catalogue.asked().lookups == 1)
    }

    /// A partial answer is not kept. The API is still finishing the list, so the next request for
    /// this artist asks again and gets the rest.
    @Test func partOfAnAnswerIsAskedAgain() async {
        let catalogue = Catalogue(has: ["Enya": 2])
        await catalogue.answerInPart()
        let store = BackdropStore(source: catalogue)

        _ = await store.backdrop(artist: "Enya", album: nil, cutFor: stage)
        _ = await store.backdrop(artist: "Enya", album: nil, cutFor: stage)

        #expect(await catalogue.asked().lookups == 2)
    }

    @Test func aPictureIsDownloadedOnce() async {
        let catalogue = Catalogue(has: ["Enya": 2])
        let store = BackdropStore(source: catalogue)

        for _ in 0..<4 { _ = await store.backdrop(artist: "Enya", album: nil, cutFor: stage) }

        #expect(await catalogue.asked().downloads == 1)
    }

    /// **An artist's whole deck is held**, because the stage lays out the whole deck. Swiping back to
    /// the far end must not download that end again.
    @Test func theWholeDeckIsHeld() async {
        let catalogue = Catalogue(has: ["Enya": 8])
        let store = BackdropStore(source: catalogue, picking: temporaryPicks())

        for at in 0..<8 { _ = await store.backdrop(artist: "Enya", album: nil, at: at, cutFor: stage) }
        _ = await store.backdrop(artist: "Enya", album: nil, at: 0, cutFor: stage)

        #expect(await catalogue.asked().downloads == 8)
    }

    /// ...and no more than that. These are full-frame photographs. A phone has better uses for its
    /// memory than a gallery nobody asked for.
    @Test func andNoMoreThanTheDeck() async {
        let catalogue = Catalogue(has: ["Enya": 10])
        let store = BackdropStore(source: catalogue, picking: temporaryPicks())

        for at in 0..<10 { _ = await store.backdrop(artist: "Enya", album: nil, at: at, cutFor: stage) }
        // The first two have been dropped from memory by now, so asking again is a second download.
        _ = await store.backdrop(artist: "Enya", album: nil, at: 0, cutFor: stage)

        #expect(await catalogue.asked().downloads == 11)
    }

    /// **Turning the phone cuts again. It does not ask again.** A window cut for a landscape frame is
    /// wrong for a portrait one. So the picture is measured against the new shape. The photograph
    /// itself is already held, and fetching it again would spend mobile data on bytes the phone has.
    @Test func turningThePhoneCutsAgainWithoutAskingAgain() async {
        let catalogue = Catalogue(has: ["Enya": 1])
        let store = BackdropStore(source: catalogue)

        let turned = ArtScene.forClearLeft(width: 393, height: 852, clearTop: 0,
                                           clearRight: 1, clearBottom: 1)

        _ = await store.backdrop(artist: "Enya", album: nil, cutFor: stage)
        _ = await store.backdrop(artist: "Enya", album: nil, cutFor: turned)
        _ = await store.backdrop(artist: "Enya", album: nil, cutFor: stage)

        #expect(await catalogue.asked().downloads == 1)
    }

    /// The picture arrives already in the shape of the screen it goes on. The view then has nothing
    /// left to decide, and the crop is the only step that made a decision.
    @Test func aPictureArrivesTheShapeOfTheFrame() async throws {
        let store = BackdropStore(source: Catalogue(has: ["Enya": 1]))

        let picture = try #require(await store.backdrop(artist: "Enya", album: nil,
                                                        cutFor: stage))

        let aspect = Double(picture.width) / Double(picture.height)
        #expect(abs(aspect - stage.aspect) / stage.aspect < 0.05)
    }

    /// **The chooser runs once.** The first time an artist appears, their first few photographs are
    /// read and the best one is kept. After that, the choice is stored on disk, and nothing is judged
    /// again.
    @Test func theBestOfTheFirstFewIsChosenAndThenRemembered() async {
        let file = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("picks-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }

        let catalogue = Catalogue(has: ["Enya": 4])
        let store = BackdropStore(source: catalogue, picking: file)

        let at = await store.opening(artist: "Enya", album: nil, cutFor: stage).at

        // Three candidates, not the artist's whole gallery. Every photograph examined is downloaded,
        // and downloads use the user's data.
        #expect(await catalogue.asked().downloads == 3)
        #expect(at >= 0 && at < 3)
        #expect(BackdropPicks(file: file).pick("Enya") != nil)

        // A second store reads the same file. The answer is there, and nothing is judged.
        let again = BackdropStore(source: Catalogue(has: ["Enya": 4]), picking: file)
        #expect(await again.opening(artist: "Enya", album: nil, cutFor: stage).at == at)
    }

    /// An artist with one photograph has nothing to choose between. Judging it would spend a
    /// download for no reason.
    @Test func onephotographIsNotAChoice() async {
        let catalogue = Catalogue(has: ["Enya": 1])
        let store = BackdropStore(source: catalogue, picking: temporaryPicks())

        #expect(await store.opening(artist: "Enya", album: nil, cutFor: stage).at == 0)
        #expect(await catalogue.asked().downloads == 0)
    }

    /// A frame measured before layout cannot judge anything. The crop it would score is a rectangle
    /// cut from nothing.
    @Test func nothingIsJudgedBeforeThereIsAFrame() async {
        let catalogue = Catalogue(has: ["Enya": 4])
        let store = BackdropStore(source: catalogue, picking: temporaryPicks())
        let unmeasured = ArtScene.forClearLeft(width: 0, height: 0, clearTop: 0,
                                               clearRight: 0.75, clearBottom: 0.6)

        #expect(await store.opening(artist: "Enya", album: nil, cutFor: unmeasured).at == 0)
        #expect(await catalogue.asked().downloads == 0)
    }

    private func temporaryPicks() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("picks-\(UUID().uuidString).json")
    }

    /// Signing out gives everything back. A phone that is handed on must not keep the last person's
    /// pictures.
    @Test func signingOutKeepsNothing() async {
        let catalogue = Catalogue(has: ["Enya": 1])
        let store = BackdropStore(source: catalogue)

        _ = await store.backdrop(artist: "Enya", album: nil, cutFor: stage)
        await store.forget()
        _ = await store.backdrop(artist: "Enya", album: nil, cutFor: stage)

        #expect(await catalogue.asked() == (lookups: 2, downloads: 2))
    }

    // ── the square, for the pages about one artist ──

    /// A catalogue whose artists can have square pictures as well as backdrops. It records which
    /// pictures were fetched. `refused` lists picture addresses that answer the lookup but then
    /// fail to download.
    actor Shelf: ArtSource {
        private let has: [String: ArtistPictures]
        private let refused: Set<URL>
        private let picture: Data
        private(set) var fetched: [URL] = []

        init(has: [String: ArtistPictures], refused: Set<URL> = [],
             picture: Data = Pictures.png(field: RGB(120, 40, 160), edge: 300)) {
            self.has = has
            self.refused = refused
            self.picture = picture
        }

        struct Refused: Error {}

        func artistPictures(artist: String, album: String?) async throws -> ArtistPictures {
            has[artist] ?? .none
        }

        func artwork(at url: URL) async throws -> Data {
            fetched.append(url)
            guard !refused.contains(url) else { throw Refused() }
            return picture
        }

        func artCatalog(_ shelf: CloudShelf) async throws -> [StoredCover] { [] }
        func art(_ shelf: CloudShelf, albumKey: String, size: CoverSize) async -> StoredCover? { nil }
        func sidecar(rpmId: String) async throws -> TagSidecar? { nil }
    }

    // ── the logo, for the title of the artist page ──

    static let logo = URL(string: "https://assets.fanart.tv/fanart/music/x/hdmusiclogo/logo.png")!

    /// The catalogue's canvas: 800 by 310, with the lettering 400 by 100 in the middle.
    static let canvas = LetteringTests.png(LetteringTests.canvas(width: 800, height: 310,
                                                                 block: (200, 105, 400, 100)))

    @Test func aLogoComesBackCutToItsLetteringAndTheHeightAsked() async throws {
        let shelf = Shelf(has: ["Enya": ArtistPictures(backdrops: [], squares: [], logo: Self.logo, partial: false)],
                          picture: Self.canvas)
        let store = BackdropStore(source: shelf)

        let mark = try #require(await store.logo(artist: "Enya", album: nil,
                                                 box: LetteringBox(tall: 50, wide: 1000)))

        #expect(mark.height == 50)
        #expect(mark.width == 200)
    }

    @Test func aLogoIsFetchedOnceAndReducedAgainForANewBox() async throws {
        let shelf = Shelf(has: ["Enya": ArtistPictures(backdrops: [], squares: [], logo: Self.logo, partial: false)],
                          picture: Self.canvas)
        let store = BackdropStore(source: shelf)

        _ = await store.logo(artist: "Enya", album: nil, box: LetteringBox(tall: 50, wide: 1000))
        let narrow = try #require(await store.logo(artist: "Enya", album: nil,
                                                   box: LetteringBox(tall: 50, wide: 120)))

        #expect(narrow.width == 120)
        #expect(narrow.height == 30)
        #expect(await shelf.fetched == [Self.logo])
    }

    @Test func anArtistWithNoLogoGetsNone() async {
        let shelf = Shelf(has: ["Enya": ArtistPictures(backdrops: [Self.first], squares: [], logo: nil, partial: false)])
        let store = BackdropStore(source: shelf)

        #expect(await store.logo(artist: "Enya", album: nil, box: LetteringBox(tall: 50, wide: 1000)) == nil)
        #expect(await shelf.fetched.isEmpty)
    }

    /// A logo that could not be downloaded is not the same as no logo. The next request fetches it
    /// again.
    @Test func aLogoThatWouldNotFetchIsAskedForAgain() async {
        let shelf = Shelf(has: ["Enya": ArtistPictures(backdrops: [], squares: [], logo: Self.logo, partial: false)],
                          refused: [Self.logo], picture: Self.canvas)
        let store = BackdropStore(source: shelf)

        _ = await store.logo(artist: "Enya", album: nil, box: LetteringBox(tall: 50, wide: 1000))
        _ = await store.logo(artist: "Enya", album: nil, box: LetteringBox(tall: 50, wide: 1000))

        #expect(await shelf.fetched == [Self.logo, Self.logo])
    }

    static let square = URL(string: "https://assets.fanart.tv/fanart/music/x/artistthumb/sq.jpg")!
    static let first = URL(string: "https://assets.fanart.tv/fanart/music/x/artistbackground/1.jpg")!
    static let second = URL(string: "https://assets.fanart.tv/fanart/music/x/artistbackground/2.jpg")!

    /// The home banner's card on a phone. It is nearly upright, which is why the square is used there.
    static let card = ArtScene.forClearLeft(width: 390, height: 450, clearTop: 0, clearRight: 0.94, clearBottom: 0.62)

    /// The artist page's band: a 16 by 9 picture plus the status bar, so wider than a square.
    static let band = ArtScene.forClearLeft(width: 393, height: 280, clearTop: 0, clearRight: 0.94, clearBottom: 0.66)

    @Test func aPageAboutTheArtistWearsTheirSquare() async {
        let shelf = Shelf(has: ["Enya": ArtistPictures(backdrops: [Self.first], squares: [Self.square], logo: nil, partial: false)])
        let store = BackdropStore(source: shelf)

        #expect(await store.portrait(artist: "Enya", album: nil, cutFor: Self.card) != nil)
        #expect(await shelf.fetched == [Self.square])
    }

    /// **A square is filled, not read.** The person is already framed in the square. So the square is
    /// cut to the band's shape and kept from the top. The coloured strip along the bottom edge of the
    /// square is cut away.
    @Test func aSquareIsKeptFromTheTop() async throws {
        let square = Pictures.png(field: RGB(120, 40, 160), splash: RGB(230, 40, 40),
                                  share: 0.25, edge: 300)
        let shelf = Shelf(has: ["Enya": ArtistPictures(backdrops: [Self.first], squares: [Self.square], logo: nil, partial: false)],
                          picture: square)
        let store = BackdropStore(source: shelf)

        let picture = try #require(await store.portrait(artist: "Enya", album: nil, cutFor: Self.band))

        let aspect = Double(picture.width) / Double(picture.height)
        #expect(abs(aspect - Self.band.aspect) / Self.band.aspect < 0.02)
        #expect(Pictures.rgb(of: picture, atX: picture.width / 2, fromTop: picture.height - 1).r < 180)
    }

    /// Most artists have no square. Those pages show the first backdrop instead.
    @Test func withNoSquareThePageWearsTheFirstBackdrop() async {
        let shelf = Shelf(has: ["Enya": ArtistPictures(backdrops: [Self.first, Self.second], squares: [], logo: nil, partial: false)])
        let store = BackdropStore(source: shelf)

        #expect(await store.portrait(artist: "Enya", album: nil, cutFor: Self.card) != nil)
        #expect(await shelf.fetched == [Self.first])
    }

    /// A square that is listed but will not download is not the same as a page with no picture. The
    /// page falls back to the backdrop.
    @Test func aSquareThatWillNotFetchFallsBackToTheBackdrop() async {
        let shelf = Shelf(has: ["Enya": ArtistPictures(backdrops: [Self.first], squares: [Self.square], logo: nil, partial: false)],
                          refused: [Self.square])
        let store = BackdropStore(source: shelf)

        #expect(await store.portrait(artist: "Enya", album: nil, cutFor: Self.card) != nil)
        #expect(await shelf.fetched == [Self.square, Self.first])
    }

    /// **The deck behind the record never holds a square.** It uses a landscape frame and pages by
    /// index. The position it stops on is saved as the artist's pick. A square in the deck would be
    /// paged to and then saved.
    @Test func theDeckPagesThroughBackdropsOnly() async {
        let shelf = Shelf(has: ["Enya": ArtistPictures(backdrops: [Self.first, Self.second], squares: [Self.square], logo: nil, partial: false)])
        let store = BackdropStore(source: shelf)

        _ = await store.backdrop(artist: "Enya", album: nil, at: 0, cutFor: stage)
        _ = await store.backdrop(artist: "Enya", album: nil, at: 1, cutFor: stage)

        #expect(await store.backdrop(artist: "Enya", album: nil, at: 2, cutFor: stage) == nil)
        #expect(await store.count(artist: "Enya", album: nil) == 2)
        #expect(await shelf.fetched == [Self.first, Self.second])
    }
}
