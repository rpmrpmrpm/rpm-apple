import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// Two helpers that have no desktop counterpart: turning the phone's albums into credit rows, and turning
/// one artist's rows into the shelves for their page.

private func track(_ id: String, artist: String? = nil, year: Int = 0) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.year = year
    return CloudTrack(rpmId: id, title: id, artist: artist, tags: tags)
}

private func album(_ key: String, _ name: String, _ artist: String,
                   year: Int = 0, credits: [String?] = [nil]) -> CloudAlbum {
    CloudAlbum(key: key, album: name, artist: artist,
               tracks: credits.enumerated().map { at, credit in
                   track("\(key)#\(at)", artist: credit, year: year)
               })
}

private func shelves(_ artist: String, over albums: [CloudAlbum]) throws -> ArtistShelves {
    let wall = ArtistWall.build(ArtistWall.rows(albums))
    let who = try #require(wall.first { $0.name == artist })
    return ArtistShelves.of(who, in: Dictionary(uniqueKeysWithValues: albums.map { ($0.key, $0) }))
}

@Suite struct ArtistCreditRowsTests {
    /// One row per (album, track artist) pair. The desktop's mirror builds its own wall from the same rows.
    @Test func anAlbumMakesOneRowPerDistinctTrackCredit() {
        let rows = ArtistWall.rows([
            album("k", "Arrival", "ABBA", credits: ["ABBA", "ABBA", "ABBA feat. Somebody"]),
        ])

        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.albumArtist == "ABBA" })
        #expect(rows.map(\.artist) == ["ABBA", "ABBA feat. Somebody"])
        // Two tracks have the first credit and one has the second, so the wall counts three songs, not six.
        #expect(rows.map(\.tracks) == [2, 1])
    }

    /// A record whose tracks have no artist tag is filed under the album artist, so it is still on that
    /// artist's page.
    @Test func anAlbumWithNoTrackCreditsStillNamesItsOwner() throws {
        let rows = ArtistWall.rows([album("k", "Untagged", "Boards of Canada",
                                          credits: [nil, nil, nil])])

        try #require(rows.count == 1)
        #expect(rows[0].albumArtist == "Boards of Canada")
        #expect(rows[0].artist == nil)
        #expect(rows[0].tracks == 3)

        let wall = ArtistWall.build(rows)
        #expect(wall.map(\.name) == ["Boards of Canada"])
    }
}

@Suite struct ArtistShelvesTests {
    /// Four kinds of title move a record to its own shelf. A plain title stays on the records shelf.
    @Test func aRecordLandsOnTheShelfItsNameNames() throws {
        let page = try shelves("Prince", over: [
            album("a", "Purple Rain", "Prince"),
            album("b", "Live at the Apollo", "Prince"),
            album("c", "Runaway - Single", "Prince"),
            album("d", "Music from the Motion Picture Batman", "Prince"),
            album("e", "The Very Best of Prince", "Prince"),
        ])

        #expect(page.records.map(\.album) == ["Purple Rain"])
        #expect(page.live.map(\.album) == ["Live at the Apollo"])
        #expect(page.singles.map(\.album) == ["Runaway - Single"])
        #expect(page.soundtracks.map(\.album) == ["Music from the Motion Picture Batman"])
        #expect(page.compilations.map(\.album) == ["The Very Best of Prince"])
    }

    /// Each record is on one shelf. When a title matches more than one kind, the first match wins, in this
    /// order: single, live, soundtrack, compilation.
    @Test func aTitleThatAnswersTwiceIsListedOnce() throws {
        let page = try shelves("Prince", over: [
            album("a", "Live at Abbey Road - Single", "Prince"),
            album("b", "Greatest Hits Live", "Prince"),
        ])

        #expect(page.singles.map(\.album) == ["Live at Abbey Road - Single"])
        #expect(page.live.map(\.album) == ["Greatest Hits Live"])
        #expect(page.compilations.isEmpty)
        #expect(page.records.isEmpty)
    }

    /// Shelves are sorted newest first. A record with no year goes last, not to whichever end a zero
    /// year sorts to.
    @Test func aShelfReadsNewestFirstAndUndatedLast() throws {
        let page = try shelves("Portishead", over: [
            album("a", "Dummy", "Portishead", year: 1994),
            album("b", "Third", "Portishead", year: 2008),
            album("c", "Unknown", "Portishead", year: 0),
        ])

        #expect(page.records.map(\.album) == ["Third", "Dummy", "Unknown"])
    }

    /// A record by two artists is on its own shelf, and it appears on the shelf of each artist.
    @Test func aJointRecordIsOnItsOwnShelf() throws {
        let albums = [
            album("a", "Graduation", "Kanye West", credits: ["Kanye West"]),
            album("b", "Be", "Common", credits: ["Common"]),
            album("c", "Both", "Kanye West & Common", credits: ["Kanye West & Common"]),
        ]

        #expect(try shelves("Kanye West", over: albums).together.map(\.album) == ["Both"])
        #expect(try shelves("Common", over: albums).together.map(\.album) == ["Both"])
        #expect(try shelves("Kanye West", over: albums).records.map(\.album) == ["Graduation"])
    }

    /// An artist's own records give every track. Another artist's record gives only the tracks that name the
    /// artist, which is why that record is on the page.
    @Test func songsTakeTheirOwnRecordsWholeAndFilterTheRest() throws {
        let page = try shelves("Blur", over: [
            album("a", "Parklife", "Blur", credits: ["Blur", nil]),
            album("b", "Now 40", "Various Artists", credits: ["Blur", "Pulp", "Oasis"]),
        ])

        // Both tracks from Parklife, including the one with no credit, and one track from the compilation.
        #expect(page.songs.count == 3)
        #expect(page.songs.filter { $0.album.key == "a" }.count == 2)
        #expect(page.songs.filter { $0.album.key == "b" }.map(\.track.artist) == ["Blur"])
        #expect(page.appearances.map(\.album) == ["Now 40"])
    }

    /// A joint record's tracks are credited to the pair, not to either artist. They are taken whole, the same
    /// way as an artist's own records.
    @Test func aJointRecordsSongsAreOnBothPages() throws {
        let albums = [
            album("a", "Graduation", "Kanye West", credits: ["Kanye West"]),
            album("b", "Be", "Common", credits: ["Common"]),
            album("c", "Both", "Kanye West & Common",
                  credits: ["Kanye West & Common", "Kanye West & Common"]),
        ]

        #expect(try shelves("Common", over: albums).songs.filter { $0.album.key == "c" }.count == 2)
        #expect(try shelves("Kanye West", over: albums).songs.filter { $0.album.key == "c" }.count == 2)
    }

    @Test func anArtistWithNothingOnAnyShelfSaysSo() throws {
        let page = try shelves("ABBA", over: [album("a", "Arrival", "ABBA")])

        #expect(!page.isEmpty)
        #expect(page.records.map(\.album) == ["Arrival"])
    }
}

/// What a record's release type does to its shelf: the type the listener set wins over the name.
@Suite struct ReleaseTypeShelfTests {
    private func typed(_ key: String, _ name: String, _ types: [String?]) -> CloudAlbum {
        CloudAlbum(key: key, album: name, artist: "Queen", tracks: types.enumerated().map { at, type in
            var tags = CloudTrackTags()
            tags.releaseType = type
            return CloudTrack(rpmId: "\(key)#\(at)", title: key, artist: "Queen", tags: tags)
        })
    }

    @Test func aSetTypeWinsOverTheNameAndEpsAndMixtapesHaveShelves() throws {
        let page = try shelves("Queen", over: [
            typed("through", "Live Through This", ["Album"]),
            typed("ep", "Five Live", ["Ep"]),
            typed("tape", "Street Sounds", ["Mixtape"]),
            typed("guess", "Live at Wembley", [nil]),
        ])

        #expect(page.records.map(\.key) == ["through"])
        #expect(page.eps.map(\.key) == ["ep"])
        #expect(page.mixtapes.map(\.key) == ["tape"])
        #expect(page.live.map(\.key) == ["guess"])
    }

    @Test func mostOfARecordsTracksDecideItsType() {
        #expect(ReleaseType.shelf(of: typed("a", "A", ["Ep", "Ep", "single"])) == .ep)
        #expect(ReleaseType.shelf(of: typed("b", "B - Single", [nil, "nonsense"])) == .single)
        #expect(ReleaseType.shelf(of: typed("c", "C", [nil])) == .album)
    }
}
