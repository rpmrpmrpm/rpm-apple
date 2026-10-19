import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// The Similar albums row under a record on the album page. It reads the shelf the way the
/// desktop's album page does, then ranks it with ``SimilarAlbums/pick(subject:library:count:)``.
struct SimilarAlbumRowTests {
    private func album(_ name: String, by artist: String, genre: String? = nil,
                       years: [Int] = []) -> CloudAlbum {
        let rows = years.isEmpty ? [0] : years
        let tracks = rows.enumerated().map { at, year in
            var tags = CloudTrackTags()
            tags.genre = genre
            tags.year = year
            return CloudTrack(rpmId: "\(name)-\(at)", relativePath: "\(artist)/\(name)/\(at).flac",
                              title: "\(at)", artist: artist, album: name, tags: tags)
        }
        return CloudAlbum(key: "\(artist)/\(name)", album: name, artist: artist, tracks: tracks)
    }

    /// "Deep House" and "House" are spellings of one app genre. Compared as raw tags they share
    /// nothing, so the techno record from the same year would win the tie, because its key sorts first.
    @Test func genresAreMatchedToTheAppsListBeforeTheyAreCompared() {
        let open = album("Atmosphere", by: "Kerri Chandler", genre: "Deep House", years: [1998])
        let house = album("Amnesia", by: "Larry Heard", genre: "House", years: [1998])
        let techno = album("Analord", by: "Aphex Twin", genre: "Techno", years: [1998])

        let row = SimilarAlbums.row(for: open, on: [techno, open, house])

        #expect(row.first?.key == house.key)
    }

    @Test func aTagThatIsNoneOfTheAppsGenresIsDropped() {
        let traits = SimilarAlbums.traits(of: album("A", by: "B", genre: "zzqx not a genre"))

        #expect(traits.genres.isEmpty)
    }

    @Test func theYearIsTheOneMostTracksAgreeOn() {
        let traits = SimilarAlbums.traits(of: album("A", by: "B", years: [1971, 1994, 1994]))

        #expect(traits.year == 1994)
    }

    /// Other records by this act are already on its own page, so the row leaves them out and shows
    /// records by other acts.
    @Test func theOpenRecordsOwnActIsLeftOut() {
        let open = album("Spirit of Eden", by: "Talk Talk", genre: "Rock", years: [1988])
        let same = album("Laughing Stock", by: "Talk Talk", genre: "Rock", years: [1991])
        let other = album("Hex", by: "Bark Psychosis", genre: "Rock", years: [1994])

        let row = SimilarAlbums.row(for: open, on: [open, same, other])

        #expect(row.map(\.key) == [other.key])
    }

    /// A record that is not on the shelf yet (for example, one opened while the shelf is being
    /// reloaded) still gets a row. It is scored on its own tracks.
    @Test func aRecordNotOnTheShelfStillGetsARow() {
        let open = album("Atmosphere", by: "Kerri Chandler", genre: "Deep House", years: [1998])
        let house = album("Amnesia", by: "Larry Heard", genre: "House", years: [1998])

        #expect(SimilarAlbums.row(for: open, on: [house]).map(\.key) == [house.key])
    }

    @Test func theRowIsNoLongerThanTheDesktops() {
        let open = album("Open", by: "Act", genre: "Rock")
        let shelf = (0..<30).map { album("R\($0)", by: "Act \($0)", genre: "Rock") }

        #expect(SimilarAlbums.row(for: open, on: shelf).count == SimilarAlbums.defaultCount)
    }
}
