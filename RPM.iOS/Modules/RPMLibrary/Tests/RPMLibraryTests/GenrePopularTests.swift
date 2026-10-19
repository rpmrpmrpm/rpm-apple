import Testing
import RPMKit
@testable import RPMLibrary

/// A genre's popular songs. The Android `GenrePopularTest`, case for case.
struct GenrePopularTests {
    private func album(_ key: String, artist: String, songs: Int) -> CloudAlbum {
        let tracks = (1...songs).map { at -> CloudTrack in
            var tags = CloudTrackTags()
            tags.trackNumber = at
            return CloudTrack(rpmId: "\(key)-\(at)", title: "\(key) song \(at)", artist: artist, tags: tags)
        }
        return CloudAlbum(key: key, album: key, artist: artist, tracks: tracks)
    }

    private func plays(_ albums: CloudAlbum...) -> [String: [TrackPlace: Int64]] {
        Dictionary(uniqueKeysWithValues: albums.map { album in
            (album.key, Dictionary(uniqueKeysWithValues: album.tracks.map { track in
                let at = track.tags?.trackNumber ?? 0
                return (TrackPlace(disc: 1, position: at), Int64(1000 - at))
            }))
        })
    }

    @Test func noActHasMoreThanItsShare() {
        let big = album("big", artist: "Big Act", songs: 10)
        let other = album("other", artist: "Other Act", songs: 10)
        let ranked = GenrePopular.ranked(GenrePopular.songs([big, other]), plays: plays(big, other))
        #expect(ranked.filter { $0.album.artist == "Big Act" }.count == GenrePopular.perAct)
        #expect(ranked.filter { $0.album.artist == "Other Act" }.count == GenrePopular.perAct)
    }

    @Test func theRecordsPlayedMostHereAreAskedFirst() {
        let a = album("a", artist: "A", songs: 1)
        let b = album("b", artist: "B", songs: 1)
        let c = album("c", artist: "C", songs: 1)
        let played = ["a": 1, "b": 9, "c": 5]
        #expect(GenrePopular.records([a, b, c]) { played[$0.key] ?? 0 }.map(\.key) == ["b", "c", "a"])
    }

    @Test func tooFewIsNone() {
        let one = album("one", artist: "Solo", songs: 10)
        #expect(GenrePopular.ranked(GenrePopular.songs([one]), plays: plays(one)).isEmpty)
    }
}
