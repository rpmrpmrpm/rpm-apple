import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

private func album(_ name: String, by artist: String, year: Int = 0) -> CloudAlbum {
    var tags = CloudTrackTags()
    tags.year = year

    return CloudAlbum(key: "\(artist)/\(name)", album: name, artist: artist,
                      tracks: [CloudTrack(rpmId: "\(name)-1", relativePath: "x.flac",
                                          title: "One", artist: artist, album: name,
                                          tags: tags)])
}

private let shelf = [
    album("Hex", by: "Bark Psychosis", year: 1994),
    album("Spirit of Eden", by: "Talk Talk", year: 1988),
    album("Laughing Stock", by: "Talk Talk", year: 1991),
]

/// The cache the wall is drawn from. Its value is that it sorts less often than it is asked,
/// so these tests check how often it sorts.
@Suite("The wall, put in order once")
struct SortedWallTests {

    @Test func theWallComesBackInTheOrderAskedFor() {
        let wall = SortedWall()

        #expect(wall.wall(shelf, in: .artist).map(\.album)
                == ["Hex", "Laughing Stock", "Spirit of Eden"])
        #expect(wall.wall(shelf, in: .album).map(\.album)
                == ["Hex", "Laughing Stock", "Spirit of Eden"])
        #expect(wall.wall(shelf, in: .year).map(\.album)
                == ["Hex", "Laughing Stock", "Spirit of Eden"])
    }

    /// The cache exists because a screen asks for the wall on every pass of its body, and a body
    /// runs whenever anything on the screen moves.
    @Test func askingAgainDoesNotSortAgain() {
        let wall = SortedWall()

        for _ in 0..<50 { _ = wall.wall(shelf, in: .artist) }

        #expect(wall.sorts == 1)
    }

    @Test func anotherOrderIsAnotherQuestion() {
        let wall = SortedWall()

        _ = wall.wall(shelf, in: .artist)
        _ = wall.wall(shelf, in: .year)
        _ = wall.wall(shelf, in: .year)

        #expect(wall.sorts == 2)
    }

    /// A library that has been read again needs a new sort, even when it has the same number of
    /// records.
    @Test func aLibraryThatChangedIsAnotherQuestion() {
        let wall = SortedWall()
        var changed = shelf
        changed[0] = album("Codename: Dustsucker", by: "Bark Psychosis", year: 2004)

        _ = wall.wall(shelf, in: .artist)
        let after = wall.wall(changed, in: .artist)

        #expect(wall.sorts == 2)
        #expect(after.map(\.album) == ["Codename: Dustsucker", "Laughing Stock", "Spirit of Eden"])
    }

    /// It is only a cache, not a second sort rule. Its result must match what `AlbumSort` returns.
    @Test func itAnswersWhatTheSortWouldHave() {
        for ordering in AlbumOrdering.allCases {
            let mine = SortedWall().wall(shelf, in: ordering)
            let theirs = AlbumSort.by(shelf, ordering) {
                AlbumFacts(album: $0.album, artist: $0.artist,
                           addedAt: AlbumSort.addedOf($0.tracks),
                           year: AlbumSort.yearOf($0.tracks))
            }

            #expect(mine.map(\.key) == theirs.map(\.key), "\(ordering)")
        }
    }

    @Test func anEmptyShelfIsAnEmptyWall() {
        #expect(SortedWall().wall([], in: .artist).isEmpty)
    }
}
