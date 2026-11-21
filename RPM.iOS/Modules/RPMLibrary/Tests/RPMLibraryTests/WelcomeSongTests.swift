import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// The song the welcome plays: the most played, then a favourite, long enough and playable.
struct WelcomeSongTests {
    private func track(_ id: String, seconds: Double = 240, title: String? = nil) -> CloudTrack {
        var tags = CloudTrackTags()
        tags.durationSeconds = seconds
        return CloudTrack(rpmId: id, relativePath: "Talk Talk/Laughing Stock/\(id).flac",
                          title: title ?? id, artist: "Talk Talk", album: "Laughing Stock", tags: tags)
    }

    private func album(_ key: String, _ tracks: [CloudTrack]) -> CloudAlbum {
        CloudAlbum(key: key, album: key, artist: "Talk Talk", tracks: tracks)
    }

    private func played(_ counts: [String: Int]) -> [String: PlayLog.Played] {
        counts.mapValues { PlayLog.Played(plays: $0, lastPlayedAt: 0) }
    }

    private func pick(_ albums: [CloudAlbum], played: [String: PlayLog.Played] = [:],
                      marked: Set<String> = [], playable: Set<String>? = nil) -> String? {
        WelcomeSong.pick(albums, played: played,
                         isMarked: { marked.contains($0.rpmId) },
                         canPlay: { playable?.contains($0.key) ?? true })
            .map { $0.album.tracks[$0.at].rpmId }
    }

    @Test func theMostPlayedSongIsChosen() {
        let shelf = [album("k1", [track("a"), track("b")]), album("k2", [track("c")])]

        #expect(pick(shelf, played: played(["a": 2, "b": 1, "c": 9])) == "c")
    }

    @Test func aFavouriteComesBeforeAnUnmarkedSongPlayedAsOften() {
        let shelf = [album("k1", [track("a"), track("b")])]

        #expect(pick(shelf, played: played(["a": 3, "b": 3]), marked: ["b"]) == "b")
    }

    @Test func playsComeBeforeTheMark() {
        let shelf = [album("k1", [track("a"), track("b")])]

        #expect(pick(shelf, played: played(["a": 4, "b": 1]), marked: ["b"]) == "a")
    }

    @Test func withNothingPlayedAFavouriteIsChosen() {
        let shelf = [album("k1", [track("a"), track("b"), track("c")])]

        #expect(pick(shelf, marked: ["c"]) == "c")
    }

    @Test func withNothingPlayedOrMarkedTheSameSongIsChosenEveryTime() {
        #expect(pick([album("k1", [track("m"), track("d"), track("x")])]) == "d")
        #expect(pick([album("k1", [track("x"), track("d"), track("m")])]) == "d")
    }

    @Test func aShortSongIsPassedOver() {
        let shelf = [album("k1", [track("short", seconds: 60), track("long")])]

        #expect(pick(shelf, played: played(["short": 50, "long": 1])) == "long")
    }

    @Test func aSongWithNoKnownLengthIsPassedOver() {
        let shelf = [album("k1", [track("unknown", seconds: 0)])]

        #expect(pick(shelf) == nil)
    }

    @Test func aSongWithNoTitleIsPassedOver() {
        let shelf = [album("k1", [track("blank", title: "  "), track("named")])]

        #expect(pick(shelf, played: played(["blank": 9])) == "named")
    }

    /// Offline, only a record on the phone can play.
    @Test func aRecordThatCannotPlayNowIsPassedOver() {
        let shelf = [album("k1", [track("a")]), album("k2", [track("b")])]

        #expect(pick(shelf, played: played(["a": 9, "b": 1]), playable: ["k2"]) == "b")
    }

    @Test func theSongsPlaceOnItsRecordIsGiven() throws {
        let shelf = [album("k1", [track("a"), track("b"), track("c")])]

        let chosen = try #require(WelcomeSong.pick(shelf, played: played(["c": 1]),
                                                   isMarked: { _ in false }, canPlay: { _ in true }))

        #expect(chosen.album.key == "k1")
        #expect(chosen.at == 2)
    }

    @Test func anEmptyCollectionHasNoSong() {
        #expect(pick([]) == nil)
    }
}
