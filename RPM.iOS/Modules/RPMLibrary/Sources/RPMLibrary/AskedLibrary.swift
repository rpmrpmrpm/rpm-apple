import Foundation
import RPMKit

/// The library that a cache last answered for, and the check whether a new question is about the
/// same library. ``SortedWall``, ``ReadArtists`` and ``ReadGenres`` use it.
///
/// **The check is cheap only while the two arrays share storage.** Two Swift arrays that share
/// storage compare in constant time. Two equal arrays in different storage are compared album by
/// album and track by track, and a track has about fifty fields. A refresh that reads the same
/// library again places an equal array in new storage. If a cache kept its old array, every later
/// question would pay the full comparison, several times on every pass of a body, and a body runs
/// on every change of track and on every play and pause.
///
/// So an equal library is kept as well: the cache takes the caller's array in place of its own,
/// and from then on the same question is answered in constant time again.
struct AskedLibrary {
    private(set) var albums: [CloudAlbum] = []

    /// Whether `albums` is the library last asked about. When it is equal but held in other
    /// storage, it is kept in place of the old array, so the next check is cheap.
    mutating func isStill(_ albums: [CloudAlbum]) -> Bool {
        guard self.albums == albums else { return false }
        self.albums = albums
        return true
    }

    /// Remembers a library that is not the one last asked about.
    mutating func replace(with albums: [CloudAlbum]) {
        self.albums = albums
    }

    /// Whether `other` is held in the same storage as the library last asked about. Tests use
    /// this to check that the next question costs no comparison.
    func sharesStorage(with other: [CloudAlbum]) -> Bool {
        albums.withUnsafeBufferPointer { mine in
            other.withUnsafeBufferPointer { theirs in
                mine.baseAddress == theirs.baseAddress && mine.count == theirs.count
            }
        }
    }
}
