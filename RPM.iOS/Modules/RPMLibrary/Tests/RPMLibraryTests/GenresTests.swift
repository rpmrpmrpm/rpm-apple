import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// The tag cases mirror `RPM.Core.Tests/GenresTests.cs`, case for case. Both apps file a record under one
/// genre, so they use the same answers.
@Suite struct GenresTests {
    static let matches: [(tag: String, genre: String)] = [
        ("Rock", "Rock"),
        ("rock", "Rock"),
        ("Hip Hop", "Hip-Hop / Rap"),
        ("hip-hop", "Hip-Hop / Rap"),
        ("Rap", "Rap"),
        ("R&B", "R&B"),
        ("RnB", "R&B"),
        ("Funk / Soul", "Funk"),
        ("Soul", "Soul"),
        ("Electronic", "Electronic / Dance"),
        ("House", "House"),
        ("Deep House", "House"),
        ("Techno", "Techno"),
        ("Indie Rock", "Indie"),
        ("Game", "Video Game"),
        ("Neo-Soul", "Soul"),
        ("neo soul", "Soul"),
        ("singer-songwriter, lo-fi, folk, bedroom pop, indie pop, indie rock", "Indie"),
        ("singer-songwriter, pop, pop rock, baroque pop, soft rock, rock", "Pop"),
        ("Stage & Screen", "Soundtrack"),
        ("Folk, World, & Country", "Folk"),
        ("Gospel", "Religious"),
        ("Religious", "Religious"),
        ("Score", "Soundtrack"),
        ("International", "World"),
        ("Video Game Soundtrack", "Video Game"),
        ("Video Game", "Video Game"),
        ("R&B / Soul", "R&B"),
        ("World / International", "World"),
        ("Gospel / Religious", "Religious"),
        ("Soundtrack / Score", "Soundtrack"),
        ("Post-Punk", "Punk"),
        ("Hard Rock", "Rock"),
        ("Synth-pop", "Pop"),
        ("Death Metal", "Metal"),
        ("Contemporary Jazz", "Jazz"),
        ("electro house", "House"),
        ("trap latino", "Latin"),
        ("pop rap", "Rap"),
        ("jazz rap", "Rap"),
        ("ambient techno", "Techno"),
        ("electro-disco", "Disco"),
        ("pop metal", "Metal"),
        ("reggaeton", "Latin"),
        ("Funk / Soul", "Funk"),
        ("Folk, World, & Country", "Folk"),
        ("Rock | Pop | Folk Rock | Art Rock", "Rock"),
        ("Progressive House, Trance, Speed Garage", "House"),
        ("cloud rap, hip hop, trap", "Rap"),
        ("Punk Rock", "Punk"),
        ("Lovers Rock", "Reggae"),
        ("Christian Rock", "Religious"),
        ("Gospel Soul", "Religious"),
        ("Gospel Blues", "Religious"),
        ("Latin Rock", "Latin"),
        ("Latin Pop", "Latin"),
        ("Country Pop", "Country"),
        ("Folk Pop", "Folk"),
        ("Jazz Pop", "Jazz"),
        ("Dream Pop", "Indie"),
        ("Bedroom Pop", "Indie"),
        ("Jangle Pop", "Indie"),
        ("Chamber Pop", "Indie"),
        ("Post-Punk Revival", "Indie"),
        ("Power Pop", "Rock"),
        ("Dance-Pop", "Pop"),
        ("Trap Soul", "R&B"),
        ("G-Funk", "Hip-Hop / Rap"),
        ("Witch House", "Electronic / Dance"),
        ("Future Funk", "Electronic / Dance"),
        ("Ambient Classical", "Neo-Classical"),
        ("Video Game Score", "Video Game"),
        ("Desert Blues", "World"),
        ("Ethio-Jazz", "World"),
        ("Progressive Punk Rock", "Punk"),
        ("Experimental Hip Hop", "Hip-Hop / Rap"),
        ("Experimental Rock", "Rock"),
        ("Cloud Rap", "Rap"),
    ]

    @Test(arguments: matches)
    func aTagMatchesTheDesktopsGenre(_ tag: String, _ genre: String) {
        #expect(Genres.match(tag) == genre)
    }

    @Test(arguments: ["R", "B", "Non-Music", "Shellac", "Test Pressing", ""])
    func anythingElseMatchesNothing(_ tag: String) {
        #expect(Genres.match(tag) == nil)
    }

    /// The "Other" shelf, for music that fits no genre, is not a genre on the wall. Its words are not
    /// genres either.
    @Test func theUnknownShelfMatchesNothing() {
        #expect(Genres.match("Unknown") == nil)
        #expect(Genres.match("Other") == nil)
        #expect(Genres.match("Other / Unknown") == nil)
        #expect(Genres.match(nil) == nil)
    }
}

private func track(_ id: String, genre: String?) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.genre = genre
    return CloudTrack(rpmId: id, tags: tags)
}

private func album(_ key: String, _ genres: [String?]) -> CloudAlbum {
    CloudAlbum(key: key, album: key, artist: "",
               tracks: genres.enumerated().map { track("\(key)-\($0.offset)", genre: $0.element) })
}

@Suite struct GenreWallTests {
    @Test func anAlbumIsOnTheGenreItsTracksAreTagged() {
        let wall = GenreWall.build([album("a", ["Hip Hop", "Hip Hop"])])
        #expect(wall == [GenreWallItem(name: "Hip-Hop / Rap", albums: ["a"])])
    }

    /// "Hip Hop", "hip-hop" and "Hip-Hop / Rap" are one card, not three.
    @Test func theCataloguesSpellingsLandOnOneCard() {
        let wall = GenreWall.build([album("a", ["Hip Hop"]), album("b", ["hip-hop"]),
                                    album("c", ["Hip-Hop / Rap"])])
        #expect(wall == [GenreWallItem(name: "Hip-Hop / Rap", albums: ["a", "b", "c"])])
    }

    @Test func anUntaggedOrUnknownAlbumIsOnOtherAndOtherIsLast() {
        let wall = GenreWall.build([album("a", [nil]), album("b", ["Shellac"]),
                                    album("c", ["Rock"])])
        #expect(wall.map(\.name) == ["Rock", GenreWall.unclassified])
        #expect(wall.last?.albums == ["a", "b"])
    }

    /// The cards are in the app's order, not the library's.
    @Test func theCardsAreInTheAppsOrder() {
        let wall = GenreWall.build([album("a", ["Jazz"]), album("b", ["Rock"])])
        #expect(wall.map(\.name) == ["Rock", "Jazz"])
    }

    /// The most common tag decides the genre. On an even split, the tag that comes first on the record wins.
    @Test func theMostCommonTagDecidesAndATieGoesToTheFirst() {
        #expect(GenreWall.genre(of: album("a", ["Jazz", "Rock", "Rock"])) == "Rock")
        #expect(GenreWall.genre(of: album("b", ["Jazz", "Rock"])) == "Jazz")
        #expect(GenreWall.genre(of: album("c", [nil, "", "Soul"])) == "Soul")
    }

    @Test func theWallIsBuiltOncePerLibrary() {
        let read = ReadGenres()
        let albums = [album("a", ["Rock"])]
        _ = read.genres(albums)
        _ = read.genres(albums)
        #expect(read.builds == 1)
        _ = read.genres(albums + [album("b", ["Jazz"])])
        #expect(read.builds == 2)
    }
}

/// Mirrors the `Related` cases in `RPM.Core.Tests/GenresTests.cs`.
@Suite struct GenreRelationsTests {
    @Test func aHeadListsItsKinds() {
        #expect(Genres.related("Rock") == ["Indie", "Punk", "Metal", "Noise"])
    }

    @Test func aKindListsTheHeadFirstAndThenItsSiblings() {
        #expect(Genres.related("Punk") == ["Rock", "Indie", "Metal", "Noise"])
    }

    @Test func aGenreInTwoFamiliesNamesBothHeadsFirst() {
        #expect(Genres.related("Disco") == ["Pop", "R&B", "Indie", "Club", "Soul", "Funk"])
    }

    @Test(arguments: ["Reggae", "Latin", "Spoken Word", Genres.unknown, "Something nobody files under", ""])
    func aGenreInNoFamilyHasNoRelations(_ genre: String) {
        #expect(Genres.related(genre).isEmpty)
    }

    @Test func everyRelationIsOneOfTheAppsGenresAndMutual() {
        for genre in Genres.all {
            for other in Genres.related(genre) {
                #expect(Genres.all.contains(other))
                #expect(Genres.related(other).contains(genre), "\(genre) and \(other)")
            }
        }
    }

    @Test func aGenreIsSpokenByItsFirstWord() {
        #expect(Genres.spoken("Hip-Hop / Rap") == "hip-hop")
        #expect(Genres.spoken("Electronic / Dance") == "electronic")
        #expect(Genres.spoken("R&B") == "R&B")
        #expect(Genres.spoken("Rock") == "rock")
    }
}

private func dated(_ key: String, genre: String, year: Int, added: Int64) -> CloudAlbum {
    var tags = CloudTrackTags()
    tags.genre = genre
    tags.year = year
    return CloudAlbum(key: key, album: key, artist: "",
                      tracks: [CloudTrack(rpmId: key, addedAt: added, tags: tags)])
}

private func act(_ name: String, _ albums: [String], tracks: Int = 1) -> ArtistWallItem {
    ArtistWall.build(albums.map {
        ArtistCreditRow(album: $0, albumArtist: name, artist: name, tracks: tracks)
    })[0]
}

@Suite struct GenreShelvesTests {
    let records = [dated("a", genre: "Punk", year: 1977, added: 30),
                   dated("b", genre: "Punk", year: 1979, added: 10),
                   dated("c", genre: "Punk", year: 1994, added: 20),
                   dated("d", genre: "Punk", year: 0, added: 0),
                   dated("r", genre: "Rock", year: 1970, added: 5)]

    var shelves: GenreShelves {
        let wall = GenreWall.build(records)
        let punk = wall.first { $0.name == "Punk" }!
        return GenreShelves.of(punk, wall: wall,
                               albums: Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0) }),
                               artists: [act("One", ["a"]), act("Two", ["b", "c"]), act("Rocker", ["r"])])
    }

    @Test func recentlyAddedIsNewestFirstAndSkipsTheUndated() {
        #expect(shelves.added == ["a", "c", "b"])
    }

    @Test func theActsAreThoseWithMostAlbumsOnTheGenre() {
        #expect(shelves.acts.map(\.name) == ["Two", "One"])
        #expect(shelves.actCount == 2)
    }

    @Test func theErasAreOldestDecadeFirstAndNewestAlbumFirst() {
        #expect(shelves.eras == [GenreShelves.Era(decade: 1970, albums: ["b", "a"]),
                                 GenreShelves.Era(decade: 1990, albums: ["c"])])
    }

    @Test func onlyRelatedGenresTheCollectionHoldsAreListed() {
        #expect(shelves.related == [GenreShelves.Relation(genre: "Rock", albums: 1)])
    }
}
