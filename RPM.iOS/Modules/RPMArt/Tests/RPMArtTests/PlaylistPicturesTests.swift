import Foundation
import Testing
import RPMKit
import RPMLibrary
import RPMDesign
@testable import RPMArt

/// What a list's card draws on its first frame.
struct PlaylistPicturesTests {
    actor Drawn: ArtSource {
        func playlistArt(_ shelf: CloudShelf, playlistId: String) async -> URL? {
            URL(string: "https://example.invalid/\(shelf.ownerId)/\(playlistId).png")
        }

        func artwork(at url: URL) async throws -> Data {
            Pictures.png(field: RGB(30, 90, 150), edge: 300)
        }

        func artistPictures(artist: String, album: String?) async throws -> ArtistPictures {
            ArtistPictures(backdrops: [], squares: [], logo: nil, partial: false)
        }

        func artCatalog(_ shelf: CloudShelf) async throws -> [StoredCover] { [] }
        func art(_ shelf: CloudShelf, albumKey: String, size: CoverSize) async -> StoredCover? { nil }
        func sidecar(rpmId: String) async throws -> TagSidecar? { nil }
    }

    /// A list's picture, once fetched, is in memory for the next card at that size, on that shelf.
    @Test func aPictureFetchedIsInMemoryAtItsSizeOnItsShelf() async {
        let pictures = PlaylistPictures(source: Drawn())

        #expect(pictures.pictureInMemory(playlistId: "evening", on: .own, edge: 200) == nil)

        let art = try! #require(await pictures.picture(playlistId: "evening", on: .own, edge: 200))
        #expect(pictures.pictureInMemory(playlistId: "evening", on: .own, edge: 200)?.image === art.image)
        #expect(pictures.pictureInMemory(playlistId: "evening", on: .own, edge: 400) == nil)
        #expect(pictures.pictureInMemory(playlistId: "evening", on: .of("someone-else"), edge: 200) == nil)

        await pictures.forget()
        #expect(pictures.pictureInMemory(playlistId: "evening", on: .own, edge: 200) == nil)
    }
}
