import Foundation
import RPMKit

/// The song the welcome plays on its last step, while the hints show the player round.
///
/// One the person already knows: the song they have played most, else one they marked as a
/// favourite, else any song in the collection. Only a song that can be played now, that has a title
/// to show, and that is long enough to look round the player while it plays. The Android app picks
/// the same way (`sampleOf`).
///
/// A collection that is only the starter tracks (``StarterTracks``), shown while the person has no
/// music of their own, has no plays and no marks to go by. Its song is the first of
/// ``StarterTracks/welcomeOrder`` that fits. Without them a new account would have no song, and the
/// welcome would leave out its last step and the player's tour.
public enum WelcomeSong {
    /// A song shorter than this ends before the player has been shown round, in seconds.
    public static let shortest: Double = 90

    /// The song, with its record and its place on the record, or nil where the collection has no
    /// song that fits. With nil, the welcome leaves out its last step.
    ///
    /// Among songs played the same number of times, a marked one comes first. Among songs that are
    /// still equal, the one with the smallest id, so the same collection always gives the same song.
    ///
    /// - Parameters:
    ///   - played: everything played, by cloud id. See ``PlayLog/everythingPlayed()``.
    ///   - isMarked: whether a song is one of the person's favourites.
    ///   - canPlay: whether a record can be played now (offline, only what is on the phone).
    public static func pick(_ albums: [CloudAlbum],
                            played: [String: PlayLog.Played],
                            isMarked: (CloudTrack) -> Bool,
                            canPlay: (CloudAlbum) -> Bool) -> (album: CloudAlbum, at: Int)? {
        var best: (album: CloudAlbum, at: Int, plays: Int, marked: Bool, id: String)?

        // The starter tracks that fit, and whether every song that fits is one.
        var starters: [String: (album: CloudAlbum, at: Int)] = [:]
        var onlyStarters = true

        for album in albums where canPlay(album) {
            for (at, track) in album.tracks.enumerated() {
                guard let title = track.title, !title.trimmingCharacters(in: .whitespaces).isEmpty,
                      (track.tags?.durationSeconds ?? 0) >= shortest
                else { continue }

                if StarterTracks.isStarter(track.rpmId) {
                    starters[track.rpmId] = (album, at)
                } else {
                    onlyStarters = false
                }

                let plays = played[track.rpmId]?.plays ?? 0
                let marked = isMarked(track)

                if let held = best {
                    if plays != held.plays {
                        guard plays > held.plays else { continue }
                    } else if marked != held.marked {
                        guard marked else { continue }
                    } else {
                        guard track.rpmId < held.id else { continue }
                    }
                }
                best = (album, at, plays, marked, track.rpmId)
            }
        }

        if onlyStarters,
           let first = StarterTracks.welcomeOrder.lazy.compactMap({ starters[$0] }).first {
            return first
        }

        return best.map { (album: $0.album, at: $0.at) }
    }
}
