import Foundation
import RPMKit

/// The album wall in the requested order. **The sort runs once** for each library and
/// order. It does not run again on every redraw.
///
/// Sorting the wall takes more time than it appears to. Each album's year and date added
/// are read from its tracks. Then the whole list is compared by name, using the reader's
/// language rules. This takes tens of milliseconds for three thousand albums on a desktop
/// and much longer on a phone. A SwiftUI body runs whenever anything on the screen
/// changes: a key press, playback progress, or the keyboard appearing. If the sort ran
/// inside a body, its full cost would be paid on every pass. That made the search key
/// slow to respond and the wall stutter under a finger.
///
/// So the result is kept, and it is returned again whenever the question is the same.
/// The question is the library and the order. Comparing two libraries is fast because two
/// Swift arrays that share storage compare in constant time. A view receives the same
/// array on each pass while nothing has changed.
///
/// **Held by the app shell and passed to the page. It is not a global.** A tab is created
/// when the user opens it and discarded when they leave. A cache owned by the page would
/// be empty on every visit. A cache owned by the app survives the trip. Two screens that
/// show two libraries in two orders each use their own instance, so neither can return
/// the other's wall.
public final class SortedWall {
    /// The number of times the wall has actually been sorted. **This value is used in
    /// tests to check that the cache works.** The gap between how often `wall` is called
    /// and how often `sorts` increases shows the cache is working. Without this check, a
    /// cache could stop working and no test would notice.
    public private(set) var sorts = 0

    private var asked: [CloudAlbum] = []
    private var ordering: AlbumOrdering?
    private var answer: [CloudAlbum] = []

    public init() {}

    /// The albums in `ordering`, sorted from whatever order they arrive in.
    public func wall(_ albums: [CloudAlbum], in ordering: AlbumOrdering) -> [CloudAlbum] {
        if self.ordering == ordering, asked == albums { return answer }

        asked = albums
        self.ordering = ordering
        sorts += 1

        answer = AlbumSort.by(albums, ordering) {
            AlbumFacts(album: $0.album, artist: $0.artist,
                       addedAt: AlbumSort.addedOf($0.tracks),
                       year: AlbumSort.yearOf($0.tracks))
        }

        return answer
    }
}
