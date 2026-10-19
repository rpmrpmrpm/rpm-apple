import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// The songs the quick selection is drawn from: the tracks this listener plays most, one by one.
///
/// The desktop asks its mirror for `QueryMostPlayedTracks`. This app has no mirror, so the same
/// question is asked of the play log and the library listing together.
struct HomeSongsTests {
    private func track(_ id: String, album: String = "Spirit of Eden") -> CloudTrack {
        CloudTrack(rpmId: id, relativePath: "Talk Talk/\(album)/\(id).flac", title: id,
                   artist: "Talk Talk", album: album)
    }

    private func album(_ key: String, _ ids: [String]) -> CloudAlbum {
        CloudAlbum(key: key, album: key, artist: "Talk Talk", tracks: ids.map { track($0) })
    }

    private func played(_ counts: [String: Int], at: Int64 = 0) -> [String: PlayLog.Played] {
        counts.mapValues { PlayLog.Played(plays: $0, lastPlayedAt: at) }
    }

    @Test func theMostPlayedComesFirst() {
        let songs = HomeSongs.mostPlayed([album("k1", ["t1", "t2", "t3"])],
                                         played: played(["t1": 2, "t2": 9, "t3": 5]), count: 16)

        #expect(songs == ["t2", "t3", "t1"])
    }

    @Test func aSongNobodyHasPlayedIsNotOffered() {
        let songs = HomeSongs.mostPlayed([album("k1", ["t1", "t2"])],
                                         played: played(["t1": 3]), count: 16)

        #expect(songs == ["t1"])
    }

    /// A play count for a track this library does not hold is ignored, because there is no song to
    /// draw. On a cold launch the play rows can arrive before the listing, and they cover every device's
    /// music, not only this library's.
    @Test func aCountForATrackThisLibraryLacksIsNotOffered() {
        let songs = HomeSongs.mostPlayed([album("k1", ["t1"])],
                                         played: played(["t1": 1, "elsewhere": 40]), count: 16)

        #expect(songs == ["t1"])
    }

    /// The same input always gives the same order. Tracks with equal play counts are sorted by when
    /// they were last played, then by id. A dictionary has no order of its own, and a selection that
    /// changed between launches would look like a bug.
    @Test func theOrderIsTheSameEveryTimeItIsAsked() {
        let shelf = [album("k1", ["t1", "t2", "t3"])]
        let counts = ["t1": PlayLog.Played(plays: 4, lastPlayedAt: 10),
                      "t2": PlayLog.Played(plays: 4, lastPlayedAt: 90),
                      "t3": PlayLog.Played(plays: 4, lastPlayedAt: 90)]

        #expect(HomeSongs.mostPlayed(shelf, played: counts, count: 16) == ["t2", "t3", "t1"])
        #expect(HomeSongs.mostPlayed(shelf, played: counts, count: 16)
                == HomeSongs.mostPlayed(shelf, played: counts, count: 16))
    }

    @Test func noMoreThanWasAskedFor() {
        let songs = HomeSongs.mostPlayed([album("k1", ["t1", "t2", "t3"])],
                                         played: played(["t1": 1, "t2": 2, "t3": 3]), count: 2)

        #expect(songs == ["t3", "t2"])
    }

    @Test func aShelfNobodyHasPlayedOffersNothing() {
        #expect(HomeSongs.mostPlayed([album("k1", ["t1"])], played: [:], count: 16).isEmpty)
    }
}
