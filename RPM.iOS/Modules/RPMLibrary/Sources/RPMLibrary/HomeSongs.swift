import Foundation
import RPMKit

/// The songs that the quick selection is dealt from: what this listener plays most, track by track.
///
/// The desktop asks its mirror, which keeps a play count on every row (`QueryMostPlayedTracks`).
/// This platform keeps its counts in the ``PlayLog``, and its songs in the listing. So the same
/// question is asked of both together.
public enum HomeSongs {
    /// The most played first. Only songs that this library actually holds are included.
    ///
    /// A count for a track that is not in the listing is kept in the log, but it is not
    /// offered here. The play rows name every one of the listener's devices. A key that
    /// nothing can be drawn from would be a row in the selection with no title, no artist and
    /// nowhere to go.
    ///
    /// - Parameter played: everything anybody has played, by cloud id. See
    ///   ``PlayLog/everythingPlayed()``.
    /// - Parameter count: how many to choose, at most.
    public static func mostPlayed(_ albums: [CloudAlbum], played: [String: PlayLog.Played],
                                  count: Int) -> [String] {
        guard count > 0, !played.isEmpty else { return [] }

        var heard: [(id: String, plays: Int, at: Int64)] = []

        for album in albums {
            for track in album.tracks {
                guard let played = played[track.rpmId], played.plays > 0 else { continue }
                heard.append((track.rpmId, played.plays, played.lastPlayedAt))
            }
        }

        // Most played, then most recently played, then by id. The last two make the selection
        // the same on two launches with nothing played in between. A dictionary has no order of
        // its own. A block that rearranged itself on every launch would look like a fault.
        heard.sort {
            if $0.plays != $1.plays { return $0.plays > $1.plays }
            if $0.at != $1.at { return $0.at > $1.at }
            return $0.id < $1.id
        }

        return heard.prefix(count).map(\.id)
    }
}

/// The generated lists as the home screen meets them.
///
/// **A row on that screen carries a name and nothing else.** The desktop's own cards carry only
/// a name too. There is one lookup, not one per caller. The screen needs the list to draw its
/// picture, and the shell needs it to open the list. Two ways of saying "which list is this"
/// would let a card open something other than what it drew.
public enum HomeLists {
    /// The stored list that a home row's name stands for, or nil where this phone does not hold it.
    ///
    /// If two lists share a name, the first one is used. The computer files them in different
    /// folders, but the home screen shows only the name. So it cannot be asked which one is
    /// meant. Taking the first gives one answer, not two.
    public static func set(named name: String, in sets: [PlaylistSet]) -> PlaylistSet? {
        sets.first { $0.name == name }
    }

    /// How many of the computer's lists the home screen offers.
    public static let generatedCount = 8

    /// The names that the home screen's lists row offers, in order.
    ///
    /// These are the computer's generated lists. **On a borrowed shelf, the lender's own
    /// playlists come after them.** The desktop's home does the same. On the reader's own shelf,
    /// their playlists are one tab away. On somebody else's shelf, they are most of what that
    /// person arranged. The generated lists come first, so the banner can still pick one of the
    /// computer's lists where there is one.
    ///
    /// - Parameter shelf: the collection on screen. This has no default, because the shelf
    ///   decides whether the stored lists are offered at all.
    public static func offered(_ sets: [PlaylistSet], on shelf: CloudShelf) -> [String] {
        let generated = sets.filter { $0.origin == .generated }.prefix(generatedCount).map(\.name)
        let lent = shelf.isOwn ? [] : sets.filter { $0.origin == .stored }.map(\.name)
        return Array(generated) + lent
    }
}
