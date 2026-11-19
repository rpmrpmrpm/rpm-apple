import Foundation
import RPMKit

/// One row on the playlists tab: a stored playlist, a generated list, the marked songs, or a
/// folder to step into.
public struct PlaylistRow: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        /// Every song the listener has marked, in the order they were marked. **The songs are read
        /// from the catalogue on this phone, not from the cloud.** The set gives the id and the
        /// frame of the computer's Favourite tracks list. See
        /// ``GeneratedLists/marked(_:among:)``.
        case favorites(PlaylistSet)

        /// A folder, and what its square shows. See ``FolderFace``.
        case folder(PlaylistFolderRow, FolderFace)

        case playlist(PlaylistSet)
    }

    public let kind: Kind

    public let name: String

    /// What the row holds. It is empty for a folder: a folder has a count of rows, not a
    /// running order.
    public let tracks: [CloudTrack]

    /// How many of a stored playlist's tracks are not in this library. This is always zero for
    /// the marked songs, which are made from the library.
    public let missing: Int

    /// How many rows a folder shows when it is opened. This is zero on every row that is a list.
    public let playlists: Int


    public var id: String {
        switch kind {
        case .favorites: return GeneratedLists.markedId
        case .folder(let folder, _): return "\u{1}folder/" + folder.path.joined(separator: "/")
        case .playlist(let set): return set.id
        }
    }

    /// Whether tapping the row steps into a folder, rather than opening a list of songs. Only
    /// these rows show a chevron.
    public var isFolder: Bool {
        if case .folder = kind { return true }
        return false
    }

    /// What a folder's square shows, or nil for a row that is a list.
    public var face: FolderFace? {
        if case .folder(_, let face) = kind { return face }
        return nil
    }

    /// The record that the row takes its picture from, when the list has no picture of its own.
    /// This is the first track. It is nil for a folder, which shows a mark and not a record.
    public var artSource: CloudTrack? { isFolder ? nil : tracks.first }

    /// The list's own picture, where it has one. See ``ListPicture``. This is nil for a folder.
    ///
    /// The marked songs have a picture only under the id of the computer's copy. Without a copy
    /// their id names nothing in the store, and asking for it would be a request that always
    /// fails.
    public var picture: ListPicture? {
        if case .favorites(let set) = kind, set.id == GeneratedLists.markedId { return nil }
        return self.set?.picture
    }

    /// The list itself, or nil for a folder.
    ///
    /// The square tiles read this, because they need more of a list than its picture. A
    /// generated list's frame is coloured from what the list is. See `GeneratedListLook`.
    public var set: PlaylistSet? {
        switch kind {
        case .favorites(let set), .playlist(let set): return set
        case .folder: return nil
        }
    }

    public var duration: Duration {
        .seconds(tracks.reduce(0.0) { $0 + ($1.tags?.durationSeconds ?? 0) })
    }
}

/// What a folder's square shows in place of the plain folder mark.
///
/// It is worked out from the lists under the folder, not from the folder's name. The name is in
/// the language of the computer that filed the lists, which can be different from the phone's.
/// The desktop draws the same marks in its playlist tree (`PlaylistTreeItem.Glyph`).
public enum FolderFace: Sendable, Equatable {
    /// A folder somebody made, a folder that holds at least one list somebody made, or a folder
    /// of generated lists of more than one kind.
    case plain

    /// The folder of the moods: the moods picture.
    case moods

    /// The folder of the decades: a clock.
    case decades

    /// One mood and its cuts by genre. `kind` is the mood, as the desktop's `SmartPlaylistKind`
    /// spells it, for example "Calm".
    case mood(String)
}

/// The playlists tab as it stands at one place in the tree.
///
/// **Where you are and what is on screen are one answer.** So they are worked out together and
/// returned together. The open folder is state of the screen, and the tree is not. A playlist
/// deleted on a computer can empty the folder that somebody is in. A path kept as it was would
/// leave them in a folder that no longer exists. So
/// ``PlaylistFolderTree/stillOpen(_:folders:)`` is applied here, and not left for the caller to
/// remember. A caller that forgot it would not fail. It would draw an empty list that never fills.
public struct PlaylistBrowse: Sendable, Equatable {
    /// Where the reader actually is, which is not always where they were.
    public let at: [String]

    /// The folders inside it, then the lists in it.
    ///
    /// The app's own folders come first: Moods, then Decades. Then the other folders by name.
    /// Then the lists: a mood's own list first in the folder named after it, then the app's
    /// lists, then the person's own, each by name. The Android app uses the same order.
    public let rows: [PlaylistRow]

    /// - Parameters:
    ///   - at: the folder being looked at. Empty means the top of the tree.
    ///   - playlists: what the cloud holds for this shelf, resolved against it.
    ///   - favorites: every song the listener has marked, or nil on a borrowed shelf. **Nil and
    ///     empty are different answers.** Nil leaves the cut as the computer sent it. Empty is
    ///     this phone saying that nothing is marked now, so the computer's older copy of
    ///     Favourite tracks is not shown either.
    ///
    /// There is no row for the queue. The queue key on the player shows it, and the desktop
    /// leaves it out of its tree for the same reason.
    ///
    /// **The listening lists stand at the top of the tree** (Your mix, On repeat, Favourite
    /// tracks and the others, ``GeneratedLists/ownerOnly``). The computer files them in its Smart
    /// playlists folder. The phone apps have no such folder and show them as lists of their own.
    public static func of(
        at: [String], playlists: [PlaylistSet], favorites: [CloudTrack]?
    ) -> PlaylistBrowse {
        // The marked songs as this phone has them now, in the place of the computer's copy.
        // The copy is removed whenever this phone has an answer, so the two are never shown
        // together.
        let marked = favorites.flatMap { GeneratedLists.marked($0, among: playlists) }
        let shown = (favorites == nil ? playlists : playlists.filter { !GeneratedLists.isMarkedCopy($0) })
            .map(atTheTopIfListening)
            + (marked.map { [$0] } ?? [])

        let folders = shown.map(\.folder)
        let here = PlaylistFolderTree.stillOpen(at, folders: folders)
        let moods = moodsFolder(shown)

        var rows: [PlaylistRow] = []

        let places = PlaylistFolderTree.foldersIn(folders, at: here).map { folder in
            (folder, face(of: folder, holding: shown.filter {
                PlaylistFolderTree.isUnder($0.folder, folder.path)
            }, moods: moods))
        }

        // The index breaks ties, so folders of the same rank keep their order by name. Swift's
        // sort is not stable.
        for (folder, face) in places.enumerated()
            .sorted(by: { (rank($0.element.1), $0.offset) < (rank($1.element.1), $1.offset) })
            .map(\.element) {
            rows.append(PlaylistRow(kind: .folder(folder, face), name: folder.name,
                                    tracks: [], missing: 0, playlists: folder.playlists))
        }

        // Sorted here, and not assumed to arrive sorted. The caller resolves these against a
        // listing, and the listing's order belongs to the store, not to the reader.
        //
        // **A mood's own list comes first, above the cuts of it.** In the Adrenaline folder, the
        // row somebody came for is the whole Adrenaline list. Alphabetical order would put it
        // among Amplified and Hustle because of its letters. It is the only row this rule moves,
        // because it is the only row whose name is the name of the folder it is in.
        let inside = shown
            .filter { PlaylistFolderTree.isIn($0.folder, here) }
            .sorted { a, b in
                let (first, second) = (GeneratedLists.isPooled(a), GeneratedLists.isPooled(b))
                if first != second { return first }

                // The app's lists above the person's own.
                let (madeA, madeB) = (a.origin == .generated, b.origin == .generated)
                if madeA != madeB { return madeA }

                return a.name.compare(b.name, options: .caseInsensitive,
                                      range: nil, locale: .current) == .orderedAscending
            }

        for set in inside {
            let kind: PlaylistRow.Kind = set.id == marked?.id ? .favorites(set) : .playlist(set)
            rows.append(PlaylistRow(kind: kind, name: set.name,
                                    tracks: set.tracks, missing: set.missing, playlists: 0))
        }

        return PlaylistBrowse(at: here, rows: rows)
    }

    /// The tree alone: the folders and the stored playlists.
    ///
    /// This is what a picker walks through. A song cannot be filed into the marked songs, which
    /// are a question asked of the catalogue, not a list.
    ///
    /// **Nor into a generated list.** The computer cuts those from the collection and replaces
    /// them whole on its next run. A song put into one would be gone the next day. Generated
    /// lists are removed before the tree is walked, not filtered out of the rows afterwards. This
    /// also removes the folders that held nothing else. A Moods folder that opens on nothing
    /// would be a place that refuses songs, one step later.
    public static func places(at: [String], playlists: [PlaylistSet]) -> PlaylistBrowse {
        of(at: at, playlists: playlists.filter { $0.origin == .stored }, favorites: nil)
    }

    /// Where the open folder sits, for the line above its name. Two folders called "90s" are two
    /// places, and the name alone would not say which one is open. There is nothing to show at
    /// the top of the tree, or one step into it.
    public var path: [String] { at.count > 1 ? Array(at.dropLast()) : [] }

    /// The way back out, or nil at the top of the tree, where there is nowhere to go. A key
    /// that does nothing is worse than no key.
    public var back: [String]? { at.isEmpty ? nil : Array(at.dropLast()) }

    // ── where a list stands ──

    /// A listening list moved to the top of the tree, out of the folder the computer filed it
    /// in. Every other set is returned as it is. See ``of(at:playlists:favorites:)``.
    private static func atTheTopIfListening(_ set: PlaylistSet) -> PlaylistSet {
        guard set.origin == .generated, !set.folder.isEmpty,
              GeneratedLists.ownerOnly.contains(set.cut?.kind ?? "")
        else { return set }

        return PlaylistSet(id: set.id, name: set.name, tracks: set.tracks, missing: set.missing,
                           folder: [], stamp: set.stamp, shelf: set.shelf, origin: set.origin,
                           cut: set.cut)
    }

    // ── what a folder shows ──

    /// The name of the folder the computer filed its moods in: the outermost folder of a
    /// generated list that is neither a listening list nor a decade. Nil when there is none, or
    /// when the computer sent no folders.
    private static func moodsFolder(_ sets: [PlaylistSet]) -> String? {
        sets.first {
            $0.origin == .generated && ($0.cut?.decade ?? 0) == 0
                && !GeneratedLists.ownerOnly.contains($0.cut?.kind ?? "") && !$0.folder.isEmpty
        }?.folder.first
    }

    /// What a folder's square shows, from `inside`, the lists anywhere under it.
    ///
    /// A folder that holds a list somebody made is plain, so a person's own folder never shows
    /// the app's marks, whatever it is called.
    private static func face(of folder: PlaylistFolderRow, holding inside: [PlaylistSet],
                             moods: String?) -> FolderFace {
        guard !inside.isEmpty, inside.allSatisfy({ $0.origin == .generated }) else { return .plain }

        if let moods, folder.path.count == 1,
           folder.path[0].lowercased(with: .current) == moods.lowercased(with: .current) {
            return .moods
        }

        if inside.allSatisfy({ ($0.cut?.decade ?? 0) > 0 }) { return .decades }

        // One mood and its cuts. A listening list is never a mood.
        if let kind = inside.first?.cut?.kind, !GeneratedLists.ownerOnly.contains(kind),
           inside.allSatisfy({ $0.cut?.kind == kind && $0.cut?.decade == 0 }) {
            return .mood(kind)
        }

        return .plain
    }

    /// The order of folders in one place: Moods, then Decades, then every other folder.
    private static func rank(_ face: FolderFace) -> Int {
        switch face {
        case .moods: return 0
        case .decades: return 1
        case .mood, .plain: return 2
        }
    }
}
