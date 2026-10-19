import Foundation
import CoreGraphics
import RPMKit

/// Small pictures of artists, for the wall of boxes and the band at the top of an artist's page.
///
/// This is a separate store from ``BackdropStore``. Both answer the same catalogue, but they need
/// different things from it, and one shared cache would serve neither well:
///
/// - A backdrop is one photograph at a time, decoded at two thousand pixels and cut for the frame
///   it is shown in. Eight are held, which is enough for one artist's backdrops.
/// - A wall shows a hundred artists at once, each a few hundred points wide. Asked of the backdrop
///   store, one screen would push out the held backdrops several times over. It would also decode
///   about a megabyte per box to draw a small picture.
///
/// So this store holds thumbnails, keyed by artist and size, in a cache that the system may empty
/// when memory runs low. It does not hold the list of pictures for each artist. That list is small,
/// and both stores ask the source for it. If the phone has already opened an artist's page, the list
/// is usually fetched already.
///
/// **Backdrops only, never the square pictures.** The wall's boxes are 16 by 9, the shape that
/// backdrops arrive in. The square pictures are used on the pages about one artist, which ask
/// ``BackdropStore/portrait(artist:album:cutFor:)``.
///
/// Every failure becomes "no picture". The box is then drawn on its plain background.
public actor ArtistPortraits {
    private let source: any ArtSource

    /// Which pictures an artist has, best first. An empty answer is cached, and a failure is not.
    /// An artist with no photograph is common, so remembering that saves lookups. A failed lookup,
    /// for example one made before sign-in finished, must not be remembered as "no pictures".
    private var found: [String: [URL]] = [:]

    private final class Entry {
        let picture: CGImage
        init(_ picture: CGImage) { self.picture = picture }
    }

    /// `NSCache` is thread-safe. That is why `nonisolated(unsafe)` is allowed here. The cache is read
    /// from outside the actor, by ``portraitInMemory(of:edge:)``.
    private nonisolated(unsafe) let held = NSCache<NSString, Entry>()

    /// Sixteen megabytes of decoded thumbnails. That is enough for a wall of boxes several times over,
    /// at any box size.
    public static let mostBytesHeld = 16 * 1024 * 1024

    /// The sizes a portrait is decoded at, in pixels along the long edge.
    ///
    /// This is a fixed ladder, not the exact size asked for. Two boxes a few points apart then share
    /// one decode and one cache entry. ``ArtworkStore/bucket(holding:)`` works the same way. The widest
    /// rung covers the band at the top of an artist's page on the largest phone at three times scale.
    private static let rungs = [256, 512, 1024, 1600]

    /// - Parameter mostBytes: how many bytes of decoded portraits to hold. The default,
    ///   ``mostBytesHeld``, suits a phone. The TV draws more portraits at once, so it passes a larger value.
    public init(source: any ArtSource, mostBytes: Int = ArtistPortraits.mostBytesHeld) {
        self.source = source
        held.totalCostLimit = mostBytes
    }

    /// A picture of this artist, or nil where there is none.
    ///
    /// - Parameter edge: the width it will be drawn at, in pixels. Rounded up to the next rung, so a
    ///   pinch gesture does not cause a decode on every frame.
    public func portrait(of artist: String?, edge: Int) async -> CGImage? {
        guard let artist, !artist.isEmpty else { return nil }

        let key = Self.key(artist, edge)

        if let entry = held.object(forKey: key) { return entry.picture }

        let urls = await pictures(of: artist)
        guard let first = urls.first,
              let data = try? await source.artwork(at: first),
              let picture = Thumbnail.of(data, edge: Self.bucket(holding: edge))
        else { return nil }

        held.setObject(Entry(picture), forKey: key,
                       cost: picture.width * picture.height * 4)
        return picture
    }

    /// The picture that ``portrait(of:edge:)`` holds for this artist at this size. If there is none,
    /// it uses the nearest size held, larger sizes first, or returns nil. It reads the cache at once,
    /// from any thread, so a view can draw on its first frame. A picture held at another size is the
    /// same photograph. It may look a little soft until the view asks for its own size.
    public nonisolated func portraitInMemory(of artist: String?, edge: Int) -> CGImage? {
        guard let artist, !artist.isEmpty else { return nil }
        let want = Self.bucket(holding: edge)
        let nearest = [want] + Self.rungs.filter { $0 > want } + Self.rungs.filter { $0 < want }.reversed()
        for rung in nearest {
            if let held = held.object(forKey: Self.key(artist, rung)) { return held.picture }
        }
        return nil
    }

    private static func key(_ artist: String, _ edge: Int) -> NSString {
        "\(artist.lowercased())@\(bucket(holding: edge))" as NSString
    }

    /// Whether this artist is known to have no picture at all.
    ///
    /// A box checks this before it shows a spinner. The answer is already known once the artist's
    /// page has been opened. For an artist with no pictures, the box does not wait for a fetch that
    /// will never return one.
    public func hasNothing(for artist: String?) -> Bool {
        guard let artist, !artist.isEmpty else { return true }
        return found[artist.lowercased()]?.isEmpty ?? false
    }

    /// Clears everything. Used on sign-out, and on sign-in as a different user.
    public func forget() {
        found = [:]
        held.removeAllObjects()
    }

    /// Which rung a request at this size uses. The widest rung is the ceiling. A request larger than
    /// that is served from the largest picture held, and the ladder does not grow.
    public static func bucket(holding edge: Int) -> Int {
        rungs.first { $0 >= edge } ?? rungs[rungs.count - 1]
    }

    private func pictures(of artist: String) async -> [URL] {
        let key = artist.lowercased()
        if let known = found[key] { return known }

        guard let said = try? await source.artistPictures(artist: artist, album: nil) else {
            return []
        }

        // A partial answer is used but not kept. The next box that asks about this artist gets the rest.
        if !said.partial {
            found[key] = said.backdrops
        }
        return said.backdrops
    }
}
