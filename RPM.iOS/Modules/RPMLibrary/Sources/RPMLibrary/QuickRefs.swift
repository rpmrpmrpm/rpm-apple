import Foundation
import RPMKit

/// What the person put on home's Quick selection themselves, as it is stored: a song by its cloud
/// id, a record by its album key, or a list by its id, each with its kind in front ("song:...",
/// "album:...", "list:..."). The Android app stores the same refs.
///
/// Something the collection no longer holds is skipped when home is drawn, and kept in the store,
/// so it comes back when the collection has it again.
public enum QuickRefs {
    /// How many refs are kept. Adding one more lets the oldest go.
    public static let most = 16

    private static let song = "song:"
    private static let album = "album:"
    private static let list = "list:"

    public static func of(song rpmId: String) -> String { song + rpmId }
    public static func of(album key: String) -> String { album + key }
    public static func of(list id: String) -> String { list + id }

    /// The song's cloud id in a song's ref, or nil for any other ref.
    public static func songId(_ ref: String) -> String? {
        ref.hasPrefix(song) ? String(ref.dropFirst(song.count)) : nil
    }

    /// `added` with `ref` at its front, newest first, each ref once, at most ``most``.
    public static func adding(_ ref: String, to added: [String]) -> [String] {
        Array(([ref] + added.filter { $0 != ref }).prefix(most))
    }

    /// `added` without `ref`.
    public static func removing(_ ref: String, from added: [String]) -> [String] {
        added.filter { $0 != ref }
    }

    /// The pick a ref names, or nil where the collection does not hold it (any more).
    ///
    /// A list is keyed by its name on home (``QuickPick``), so a list's ref is turned into the
    /// name of the list with that id.
    ///
    /// - Parameter hasSong: whether the collection holds the song with this cloud id.
    /// - Parameter hasAlbum: whether it holds the record with this key.
    /// - Parameter listName: the name of the list with this id, or nil where there is none.
    public static func pick(_ ref: String, hasSong: (String) -> Bool, hasAlbum: (String) -> Bool,
                            listName: (String) -> String?) -> QuickPick? {
        if ref.hasPrefix(song) {
            let id = String(ref.dropFirst(song.count))
            return hasSong(id) ? QuickPick(kind: .song, key: id) : nil
        }
        if ref.hasPrefix(album) {
            let key = String(ref.dropFirst(album.count))
            return hasAlbum(key) ? QuickPick(kind: .album, key: key) : nil
        }
        if ref.hasPrefix(list) {
            return listName(String(ref.dropFirst(list.count))).map { QuickPick(kind: .playlist, key: $0) }
        }
        return nil
    }

    /// The ref of a pick on Quick selection, or nil for a station or a mixtape, which the person
    /// cannot add.
    ///
    /// - Parameter listId: the id of the list with this name, or nil where there is none.
    public static func ref(of pick: QuickPick, listId: (String) -> String?) -> String? {
        switch pick.kind {
        case .song: return of(song: pick.key)
        case .album: return of(album: pick.key)
        case .playlist: return listId(pick.key).map { of(list: $0) }
        case .station, .radio: return nil
        }
    }

    /// Quick selection as home shows it: the suggested mixtapes first, then what the person added,
    /// newest first, then the rest of the suggestions, at most `most` lines. A suggestion the
    /// person also added is shown once, where they put it.
    ///
    /// - Parameter resolve: the pick a ref names, or nil (``pick(_:hasSong:hasAlbum:listName:)``).
    /// - Parameter refOf: the ref of a suggested pick (``ref(of:listId:)``).
    public static func merged(_ suggested: [QuickPick], added: [String], most: Int,
                              resolve: (String) -> QuickPick?,
                              refOf: (QuickPick) -> String?) -> [QuickPick] {
        let theirs = added.compactMap(resolve)
        guard !theirs.isEmpty else { return Array(suggested.prefix(most)) }

        let refs = Set(added)
        let mixtapes = suggested.prefix(while: { $0.kind == .radio })
        let rest = suggested.dropFirst(mixtapes.count).filter { pick in
            guard let ref = refOf(pick) else { return true }
            return !refs.contains(ref)
        }
        return Array((Array(mixtapes) + theirs + rest).prefix(most))
    }
}

/// The songs played lately, newest first: the history at the top of the playlists tab. Each song
/// once, at the last time it was played on any of the listener's devices, as the desktop's
/// Recently played list orders them.
///
/// The play log already lays this phone's own listens over what the other devices reported, so a
/// song heard a minute ago is first at once. Only for the person's own shelf: a collection
/// another account shares holds none of this person's plays, and the caller passes nothing for it.
public enum PlayedLately {
    /// How many songs the history holds. Older plays fall off the end.
    public static let most = 100

    /// - Parameter played: everything played, by cloud id (``PlayLog/everythingPlayed()``).
    public static func of(_ albums: [CloudAlbum], played: [String: PlayLog.Played]) -> [CloudTrack] {
        guard !played.isEmpty else { return [] }

        var heard: [(track: CloudTrack, at: Int64)] = []
        var seen: Set<String> = []
        for album in albums {
            for track in album.tracks {
                guard let at = played[track.rpmId]?.lastPlayedAt, at > 0,
                      seen.insert(track.rpmId).inserted else { continue }
                heard.append((track, at))
            }
        }

        heard.sort { $0.at != $1.at ? $0.at > $1.at : $0.track.rpmId < $1.track.rpmId }
        return heard.prefix(most).map(\.track)
    }
}
