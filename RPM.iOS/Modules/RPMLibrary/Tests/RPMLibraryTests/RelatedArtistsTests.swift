import Testing
import RPMKit
@testable import RPMLibrary

/// The acts closest to one act, read from the collection. The Android `RelatedArtistsTest`, case
/// for case.
struct RelatedArtistsTests {
    private func act(_ name: String, _ albums: [String], together: [String] = [],
                     appearances: [String] = [], tracks: Int = 10) -> ArtistWallItem {
        ArtistWallItem(name: name, albums: albums, together: together, appearances: appearances,
                       tracks: tracks)
    }

    private let genres = [
        GenreWallItem(name: "Rock", albums: ["r1", "r2", "r3", "r4", "r5"]),
        GenreWallItem(name: "Jazz", albums: ["j1", "j2", "j3"]),
        GenreWallItem(name: GenreWall.unclassified, albums: ["u1", "u2"]),
    ]

    private func record(_ key: String, genre: String? = nil) -> CloudAlbum {
        var tags = CloudTrackTags()
        tags.genre = genre
        return CloudAlbum(key: key, album: key, artist: "x",
                          tracks: [CloudTrack(rpmId: key + "1", tags: tags)])
    }

    private func related(_ me: ArtistWallItem, _ others: [ArtistWallItem],
                         albums: [String: CloudAlbum] = [:], lists: [[CloudTrack]] = []) -> [String] {
        RelatedArtists.of(me, in: RelatedArtists.Collection(artists: [me] + others, genres: genres,
                                                            albums: albums, lists: lists))
            .map(\.name)
    }

    @Test func aRecordMadeTogetherCountsBeforeAGenreInCommon() {
        let me = act("Me", ["r1"], together: ["j3"])
        let partner = act("Partner", ["j2"], together: ["j3"])
        let rocker = act("Rocker", ["r2", "r3"])
        #expect(related(me, [partner, rocker]) == ["Partner", "Rocker"])
    }

    @Test func anActOfOtherGenresAndNoRecordInCommonIsNotRelated() {
        let me = act("Me", ["r1", "r2"])
        #expect(related(me, [act("Jazz act", ["j1"])]).isEmpty)
    }

    @Test func theActItselfAndVariousArtistsAreNeverRelated() {
        let me = act("Me", ["r1"])
        #expect(related(me, [act("Various Artists", ["r2"]), act("me", ["r3"])]).isEmpty)
    }

    @Test func unshelvedRecordsDoNotMakeActsAlike() {
        #expect(related(act("Me", ["u1"]), [act("Other", ["u2"])]).isEmpty)
    }

    @Test func tiesGoToTheActWithMoreSongs() {
        let me = act("Me", ["r1"])
        #expect(related(me, [act("Small", ["r2"], tracks: 3), act("Big", ["r3"], tracks: 40)])
                == ["Big", "Small"])
    }

    @Test func unshelvedRecordsWithTheSameTagAreAlike() {
        let albums = [record("u1", genre: "Singer-Songwriter"),
                      record("u2", genre: " singer-songwriter "),
                      record("r5", genre: "Rock")]
        let byKey = Dictionary(uniqueKeysWithValues: albums.map { ($0.key, $0) })
        let me = act("Me", ["u1"])
        #expect(related(me, [act("Alike", ["u2"]), act("Rocker", ["r5"])], albums: byKey) == ["Alike"])
    }

    @Test func actsOnTheSameSmallListsAreRelated() {
        let albums = [record("u1"), record("u2"), record("j1")]
        let byKey = Dictionary(uniqueKeysWithValues: albums.map { ($0.key, $0) })
        func list(_ keys: String...) -> [CloudTrack] { keys.map { byKey[$0]!.tracks[0] } }

        let me = act("Me", ["u1"])
        #expect(related(me, [act("Company", ["u2"]), act("Stranger", ["j1"])], albums: byKey,
                        lists: [list("u1", "u2"), list("j1", "u2")]) == ["Company"])
    }

    @Test func atMostTwelve() {
        let me = act("Me", ["r1"])
        let many = (1...20).map { act("Act \($0)", ["r2"]) }
        #expect(related(me, many).count == RelatedArtists.most)
    }
}
