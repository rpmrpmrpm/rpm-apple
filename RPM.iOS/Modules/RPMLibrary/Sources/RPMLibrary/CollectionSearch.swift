import Foundation

/// The library search's answers that are not records or songs (``SongSearch``): the artists, the
/// playlists and the genres whose names hold the words. The library's search finds every kind of
/// thing the collection is made of, so a name typed is found whichever view it lives in.
///
/// **Names are compared folded, as the artists view's own filter compares them**
/// (``ArtistWall/searchKey(_:)``): case, accents, spaces and punctuation are left out, so
/// "beyonce" finds Beyoncé and "acdc" finds AC/DC. Each answer keeps the order it is given in.
///
/// The Android phone's `CollectionSearch` is the same; change both together.
public enum CollectionSearch {
    /// The artists whose name holds `asked`.
    public static func artists(_ artists: [ArtistWallItem], for asked: String) -> [ArtistWallItem] {
        named(artists, asked) { $0.name }
    }

    /// The genres whose name holds `asked`.
    public static func genres(_ genres: [GenreWallItem], for asked: String) -> [GenreWallItem] {
        named(genres, asked) { $0.name }
    }

    /// The playlists whose name holds `asked`, by the name they are shown by.
    public static func playlists(_ lists: [PlaylistSet], for asked: String) -> [PlaylistSet] {
        named(lists, asked) { $0.name }
    }

    /// What holds the words. A search that was cancelled stops where it is, and its answer is
    /// thrown away by the caller.
    private static func named<T>(_ things: [T], _ asked: String, _ name: (T) -> String) -> [T] {
        let wanted = ArtistWall.searchKey(asked)
        guard !wanted.isEmpty else { return [] }

        var found: [T] = []
        for thing in things {
            if Task.isCancelled { break }
            if ArtistWall.searchKey(name(thing)).contains(wanted) { found.append(thing) }
        }
        return found
    }
}
