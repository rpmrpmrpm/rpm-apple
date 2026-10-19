import Foundation

/// One folder as a row in a list that shows a single level of the tree.
public struct PlaylistFolderRow: Sendable, Equatable {
    /// The folder's own name: the last step of its path.
    public let name: String

    /// The full path to the folder, outermost first. Opening the row makes this
    /// path the open folder. A playlist created inside it is filed under this path.
    public let path: [String]

    /// The number of rows shown when the folder is opened: the folders directly
    /// in it, plus the playlists directly in it.
    ///
    /// **This counts only the rows one level down, not every item beneath.** A
    /// total of all nested playlists would be misleading, because the reader sees
    /// only the rows that open. A folder always has at least one row, because it
    /// exists only when something is filed in it or beneath it.
    public let playlists: Int
}

/// The playlist tree as a phone walks it: one folder at a time, going in and
/// back out.
///
/// This is not the desktop's tree. The cloud stores each playlist together with
/// the folders it sits in. It stores no folders of its own. So a folder exists
/// here only when a playlist is filed in it or beneath it. An empty folder made on
/// a computer is not shown, because there is nothing to draw and nothing to open.
///
/// Every value is worked out from the folder chains passed in, each time it is
/// asked. Nothing is kept between calls. This keeps the open folder safe: it is
/// not a stored pointer that may point at something removed. See `stillOpen`. It
/// moves a reader who is in a folder whose last playlist was deleted elsewhere to
/// the nearest folder that still has content, instead of leaving them in front of
/// an empty list.
public enum PlaylistFolderTree {
    /// Whether a playlist filed at `folder` sits directly in `at`. That is, the
    /// playlist is one of the rows a list showing `at` draws.
    public static func isIn(_ folder: [String], _ at: [String]) -> Bool {
        folder.count == at.count && beneath(folder, at)
    }

    /// Whether `folder` is `at` or anywhere below it. A folder counts as beneath
    /// itself, because everything in it is also part of the folder's contents.
    public static func isUnder(_ folder: [String], _ at: [String]) -> Bool {
        folder.count >= at.count && beneath(folder, at)
    }

    /// The folders directly inside `at`, sorted by name. Each row carries the
    /// number of rows that opening it would show.
    ///
    /// - Parameters:
    ///   - folders: The folder chain of every playlist, with repeats. There is one
    ///     entry per playlist, not per folder, because the counting depends on it.
    ///   - at: The folder being viewed. An empty array means the top of the tree.
    public static func foldersIn(
        _ folders: [[String]], at: [String]
    ) -> [PlaylistFolderRow] {
        // Folders are keyed on the lowercased name only. Inside one folder, the name
        // is the identity, so the tree needs no other way to tell folders apart. Two
        // folders with the same name are never on screen together, because the user
        // stands in one folder at a time.
        var spelling: [String: String] = [:]

        for folder in folders {
            // Skip anything that is not a direct child of `at`, or is not beneath it.
            guard folder.count > at.count, beneath(folder, at) else { continue }

            let name = folder[at.count]

            // The first spelling seen is kept. This stops a folder whose playlists
            // use different capitals from being drawn as two rows, or from changing
            // its spelling when the list order changes.
            if spelling[fold(name)] == nil { spelling[fold(name)] = name }
        }

        return spelling.values.map { name in
            let path = at + [name]
            return PlaylistFolderRow(name: name, path: path, playlists: rowsIn(folders, at: path))
        }
        .sorted { compare($0.name, $1.name) }
    }

    /// The number of rows shown when standing in `at`: the folders directly in
    /// it, plus the playlists directly in it.
    ///
    /// This is the same count the browser uses when it draws that level. The count
    /// on a folder row and the rows behind it always match, because both come from
    /// this one function.
    public static func rowsIn(_ folders: [[String]], at: [String]) -> Int {
        var children: Set<String> = []
        var here = 0

        for folder in folders {
            // The length check comes first. `beneath` reads `at.count` items from
            // `folder`, so a chain shorter than `at` would index past its end.
            guard folder.count >= at.count, beneath(folder, at) else { continue }

            if folder.count == at.count { here += 1 }
            else { children.insert(fold(folder[at.count])) }
        }

        return children.count + here
    }

    /// The folder to show for a reader at `at`, given the playlists available now.
    /// This is the deepest part of `at` that still holds at least one playlist.
    ///
    /// The open folder is state owned by the screen, not by the tree. A playlist
    /// deleted on another device, a changed shelf, or a list that comes back
    /// different can each empty the open folder. If the path were kept as it was,
    /// the reader would be left at a folder that no longer exists, and the back
    /// button would be the only way out. So the result is computed again on each
    /// rebuild, and is never trusted from the last call.
    public static func stillOpen(_ at: [String], folders: [[String]]) -> [String] {
        guard !at.isEmpty else { return at }

        for depth in stride(from: at.count, through: 1, by: -1) {
            let here = Array(at.prefix(depth))
            if folders.contains(where: { isUnder($0, here) }) { return here }
        }

        return []
    }

    // ── plumbing ──

    private static func beneath(_ folder: [String], _ at: [String]) -> Bool {
        for i in 0..<at.count where fold(folder[i]) != fold(at[i]) { return false }
        return true
    }

    /// Two folder names are the same when they differ only by case. The desktop
    /// tree matches names the same way. A phone that compared case-sensitively
    /// would show one folder as two.
    private static func fold(_ name: String) -> String {
        name.lowercased(with: .current)
    }

    /// Compares names case-insensitively and by locale. This matches the
    /// `CurrentCultureIgnoreCase` order that the desktop app uses for these rows.
    private static func compare(_ a: String, _ b: String) -> Bool {
        a.compare(b, options: .caseInsensitive, range: nil, locale: .current) == .orderedAscending
    }
}
