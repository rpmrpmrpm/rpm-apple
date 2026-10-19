import Foundation
import RPMKit

/// One row on the playlists tab: a stored playlist, a folder to step into, or one of the two
/// lists that nobody made.
public struct PlaylistRow: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// What is playing. This is not stored anywhere, and it belongs to this phone alone.
        case queue

        /// Every song the listener has marked, in the order they were marked. **This is read
        /// from the catalogue and not filled by anybody.** So it is not a `PlaylistSet`. There is
        /// nothing in the cloud to open.
        case favorites

        case folder(PlaylistFolderRow)
        case playlist(PlaylistSet)
    }

    public let kind: Kind

    public let name: String

    /// What the row holds. It is empty for a folder: a folder is a place, and what is in it is
    /// a count, not a running order.
    public let tracks: [CloudTrack]

    /// How many of a stored playlist's tracks are not in this library. This is always zero for
    /// the kinds that are made from the library, rather than named against it.
    public let missing: Int

    /// How many playlists a folder holds, including everything beneath it. This is zero on every
    /// row that is a list rather than a place.
    public let playlists: Int


    public var id: String {
        switch kind {
        case .queue: return "\u{1}queue"
        case .favorites: return "\u{1}favorites"
        case .folder(let folder): return "\u{1}folder/" + folder.path.joined(separator: "/")
        case .playlist(let set): return set.id
        }
    }

    /// Whether tapping the row goes somewhere, rather than opening a list of songs. Only these
    /// rows show a chevron. A chevron repeated down a list of rows that all behave the same way
    /// adds no information.
    public var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }

    /// The record that the row takes its picture from, when the list has no picture of its own.
    /// This is the first track. It is nil for a folder. A picture that stands for a place says
    /// something about one of the things inside it, and nothing about the place itself.
    public var artSource: CloudTrack? { isFolder ? nil : tracks.first }

    /// The list's OWN picture, where it has one. See ``ListPicture``.
    ///
    /// A playlist has a cover that somebody chose. A list that the app built uses its shipped
    /// photograph where it has one. Otherwise it uses the figure that the computer drew for it.
    /// This is nil for rows that are not stored lists. The queue and the marked songs are made
    /// here, out of what is playing and what has been marked. A folder is a place.
    public var picture: ListPicture? {
        guard case .playlist(let set) = kind else { return nil }
        return set.picture
    }

    /// The list itself, if this row is one. This is nil for the queue, the marked songs and a
    /// folder. None of them is a running order that the cloud holds.
    ///
    /// The square tiles read this, because they need more of a list than its picture. A
    /// generated list's frame is coloured from what the list IS. See `GeneratedListLook`.
    public var set: PlaylistSet? {
        guard case .playlist(let set) = kind else { return nil }
        return set
    }

    public var duration: Duration {
        .seconds(tracks.reduce(0.0) { $0 + ($1.tags?.durationSeconds ?? 0) })
    }
}

/// The playlists tab as it stands at one place in the tree.
///
/// **Where you are and what is on screen are one answer.** So they are worked out together and
/// handed over together. The open folder is the surface's state, and the tree is not the
/// surface's to own. A playlist deleted on a computer can empty the folder that somebody is
/// standing in. A path kept as it was would leave them in a place that no longer exists.
/// ``PlaylistFolderTree/stillOpen(_:folders:)`` is folded in here, rather than left for the
/// caller to remember. A caller that forgets it does not fail. It draws an empty list that will
/// never fill.
public struct PlaylistBrowse: Sendable, Equatable {
    /// Where the reader actually is, which is not always where they were standing.
    public let at: [String]

    /// The folders inside it, then the playlists in it. Folders come above playlists, as on the
    /// desktop's own grid and in every file browser. The folders are the frame, and the lists
    /// are what is in it. Both are sorted alphabetically. A flat screen is not the tree. The
    /// order that siblings happen to have on a computer means nothing once they are off that
    /// computer.
    public let rows: [PlaylistRow]

    /// - Parameters:
    ///   - at: the folder being looked at. Empty means the top of the tree.
    ///   - playlists: what the cloud holds for this shelf, resolved against it.
    ///   - queue: what is playing. **A row at the top of the tree even when it is empty.** It
    ///     is where the music actually is. A row that comes and goes is a row that nobody
    ///     learns the position of.
    ///   - favorites: every song the listener has marked, or nil on a borrowed shelf. Nil and
    ///     empty are different answers. A borrowed row cannot be marked from a phone at all. The
    ///     mark is a tag on a catalogue row under the account that holds the file. So the list
    ///     would be empty by construction, and a row that is always empty is worse than no row.
    public static func of(
        at: [String], playlists: [PlaylistSet],
        queue: [CloudTrack], favorites: [CloudTrack]?
    ) -> PlaylistBrowse {
        let folders = playlists.map(\.folder)
        let here = PlaylistFolderTree.stillOpen(at, folders: folders)

        var rows: [PlaylistRow] = []

        // The queue and the marked songs belong to the top of the tree, and only there. They are
        // not filed anywhere. Drawing them inside every folder would say that they are.
        if here.isEmpty {
            rows.append(PlaylistRow(kind: .queue, name: "", tracks: queue,
                                    missing: 0, playlists: 0))

            if let favorites {
                rows.append(PlaylistRow(kind: .favorites, name: "", tracks: favorites,
                                        missing: 0, playlists: 0))
            }
        }

        for folder in PlaylistFolderTree.foldersIn(folders, at: here) {
            rows.append(PlaylistRow(kind: .folder(folder), name: folder.name,
                                    tracks: [], missing: 0, playlists: folder.playlists))
        }

        // Sorted here, and not assumed to arrive sorted. The caller resolves these against a
        // listing, and the listing's order belongs to the store, not to the reader.
        //
        // **A mood's own list comes first, above the cuts of it.** When standing in Adrenaline,
        // the row somebody came for is Adrenaline, the whole of it. Alphabetical order would put
        // it among Amplified and Hustle, by the accident of its letters. It is the only row this
        // rule can move, because it is the only row whose name is the name of the place it is in.
        let inside = playlists
            .filter { PlaylistFolderTree.isIn($0.folder, here) }
            .sorted { a, b in
                let (first, second) = (GeneratedLists.isPooled(a), GeneratedLists.isPooled(b))
                if first != second { return first }

                return a.name.compare(b.name, options: .caseInsensitive,
                                      range: nil, locale: .current) == .orderedAscending
            }

        for set in inside {
            rows.append(PlaylistRow(kind: .playlist(set), name: set.name,
                                    tracks: set.tracks, missing: set.missing, playlists: 0))
        }

        return PlaylistBrowse(at: here, rows: rows)
    }

    /// The tree alone: the folders and the stored playlists, without the two lists that nobody made.
    ///
    /// This is what a picker walks through. A song cannot be filed into the queue or into the
    /// marked songs. One is what is playing, and the other is a question asked of the rows. A
    /// picker that drew them would be offering two places that refuse.
    ///
    /// **Nor into a generated list.** The computer cuts those from the collection and replaces
    /// them whole on its next run. A song put into one would be gone by the next morning.
    /// Generated lists are removed before the tree is walked, not filtered out of the rows
    /// afterwards. This also removes the folders that held nothing else. A Moods folder that
    /// opens on nothing is a place that refuses, and it would be drawn one step later.
    public static func places(at: [String], playlists: [PlaylistSet]) -> PlaylistBrowse {
        let whole = of(at: at, playlists: playlists.filter { $0.origin == .stored },
                       queue: [], favorites: nil)

        return PlaylistBrowse(at: whole.at,
                              rows: whole.rows.filter { $0.kind != .queue })
    }

    /// Where the open folder sits, for the line above its name. Two folders called "90s" are two
    /// places. The name alone would not say which one is open. There is nothing to show at the
    /// top of the tree, or one step into it.
    public var path: [String] { at.count > 1 ? Array(at.dropLast()) : [] }

    /// The way back out, or nil at the top of the tree, where there is nowhere to go. A key
    /// that does nothing is worse than no key.
    public var back: [String]? { at.isEmpty ? nil : Array(at.dropLast()) }
}
