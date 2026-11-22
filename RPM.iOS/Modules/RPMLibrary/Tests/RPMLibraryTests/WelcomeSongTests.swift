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

    // ── the starter tracks ──

    /// A new account has only the starter tracks, and the welcome still has a song to spin:
    /// Connect first, whatever order the wall is in and whatever was played.
    @Test func theStarterShelfSpinsConnect() {
        let shelf = Array(StarterTracks.albums.reversed())
        let gymnopedie = StarterTracks.prefix + "gymnopedie"

        #expect(pick(shelf) == StarterTracks.prefix + "connect")
        #expect(pick(shelf, played: played([gymnopedie: 9]), marked: [gymnopedie])
                == StarterTracks.prefix + "connect")
    }

    @Test func aStarterRecordThatCannotPlayIsPassedOver() {
        let playable = Set(StarterTracks.albums.filter {
            $0.tracks[0].rpmId != StarterTracks.prefix + "connect"
        }.map(\.key))

        #expect(pick(StarterTracks.albums, playable: playable) == StarterTracks.prefix + "gymnopedie")
    }

    /// A wall with a song of the person's own beside the starter tracks is not the starter shelf,
    /// so the usual rule chooses.
    @Test func aSongOfTheirOwnBesideTheStarterTracksIsChosenByTheUsualRule() {
        let shelf = StarterTracks.albums + [album("k1", [track("a")])]

        #expect(pick(shelf, played: played(["a": 1])) == "a")
    }

    @Test func nothingPlayableIsNoSong() {
        #expect(pick(StarterTracks.albums, playable: []) == nil)
    }
}
