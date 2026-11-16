import Foundation
import CryptoKit
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
///
/// **The thumbnails are also kept on this phone's disk** (``CoverDisk``), so a wall opened after a
/// launch draws its photos without asking the catalogue again. A thumbnail younger than
/// ``freshFor`` is used as it is. An older one is still drawn at once, and the artist is asked
/// again in the background, so a new photo is found. The Android app keeps its answers for the
/// same time.
public actor ArtistPortraits {
    private let source: any ArtSource

    /// Where the thumbnails are kept between launches; nil keeps them in memory only, as the
    /// tests do.
    private let disk: CoverDisk?

    /// How long a thumbnail on the disk is used without asking again.
    public static let freshFor: TimeInterval = 14 * 24 * 60 * 60

    /// The artists being asked again in the background, by disk key, so one stale box does not
    /// start a second ask while the first runs.
    private var refreshing: Set<String> = []

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
    /// - Parameter disk: where the thumbnails are kept between launches, or nil for memory only. **No
    ///   default**: each caller states whether the pictures stay on the phone.
    public init(source: any ArtSource, mostBytes: Int = ArtistPortraits.mostBytesHeld, disk: CoverDisk?) {
        self.source = source
        self.disk = disk
        held.totalCostLimit = mostBytes
    }

    /// The usual disk: its own folder in the caches, apart from the sleeves, so clearing one does
    /// not count against the other's limits.
    public static func diskInCaches() -> CoverDisk { .inCaches(named: "portraits") }

    /// A picture of this artist, or nil where there is none.
    ///
    /// - Parameter edge: the width it will be drawn at, in pixels. Rounded up to the next rung, so a
    ///   pinch gesture does not cause a decode on every frame.
    public func portrait(of artist: String?, edge: Int) async -> CGImage? {
        guard let artist, !artist.isEmpty else { return nil }

        let key = Self.key(artist, edge)

        if let entry = held.object(forKey: key) { return entry.picture }

        let rung = Self.bucket(holding: edge)
        let named = Self.diskKey(artist, rung)
        let now = Self.period(Date())

        // Kept on the disk in this period: used as it is.
        if let disk, let data = await disk.picture(albumKey: named, stamp: now),
           let picture = Thumbnail.of(data, edge: rung) {
            hold(picture, key)
            return picture
        }

        // Kept from an earlier period: drawn now, and asked again in the background.
        if let disk, let data = await disk.picture(albumKey: named),
           let picture = Thumbnail.of(data, edge: rung) {
            hold(picture, key)
            refresh(artist, rung: rung, named: named)
            return picture
        }

        guard let picture = await fetch(artist, rung: rung, named: named) else { return nil }
        hold(picture, key)
        return picture
    }

    /// The picture of this artist kept in memory or on the disk, at any age, without asking the
    /// catalogue. For reading ahead of a wall: an artist whose photo this phone has never had is
    /// asked about when their box appears, not before.
    public func portraitKept(of artist: String?, edge: Int) async -> CGImage? {
        guard let artist, !artist.isEmpty else { return nil }
        let key = Self.key(artist, edge)
        if let entry = held.object(forKey: key) { return entry.picture }

        let rung = Self.bucket(holding: edge)
        guard let disk, let data = await disk.picture(albumKey: Self.diskKey(artist, rung)),
              let picture = Thumbnail.of(data, edge: rung)
        else { return nil }
        hold(picture, key)
        return picture
    }

    /// Asks the catalogue for the artist's first backdrop, decodes it at this rung, and keeps it on
    /// the disk under the current period.
    private func fetch(_ artist: String, rung: Int, named: String) async -> CGImage? {
        let urls = await pictures(of: artist)
        guard let first = urls.first,
              let data = try? await source.artwork(at: first),
              let picture = Thumbnail.of(data, edge: rung)
        else { return nil }

        if let disk, let keeping = Thumbnail.encoded(picture, .cover) {
            await disk.hold(albumKey: named, stamp: Self.period(Date()), keeping)
        }
        return picture
    }

    /// Asks again for an artist whose kept thumbnail is old. The memory is updated only when a
    /// picture arrives: a failed ask keeps the old photo.
    private func refresh(_ artist: String, rung: Int, named: String) {
        guard !refreshing.contains(named) else { return }
        refreshing.insert(named)
        Task {
            let fresh = await fetch(artist, rung: rung, named: named)
            refreshing.remove(named)
            if let fresh { hold(fresh, Self.key(artist, rung)) }
        }
    }

    private func hold(_ picture: CGImage, _ key: NSString) {
        held.setObject(Entry(picture), forKey: key, cost: picture.width * picture.height * 4)
    }

    /// The disk's name for an artist at a rung. ``CoverDisk`` takes a key of hex characters only, so
    /// no artist's name can make a path of its own.
    static func diskKey(_ artist: String, _ rung: Int) -> String {
        let text = "\(artist.lowercased())@\(rung)"
        return SHA256.hash(data: Data(text.utf8)).prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    /// The period a thumbnail is written in, as its version on the disk: one step every
    /// ``freshFor``. A thumbnail of an earlier period is old.
    static func period(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 / freshFor)
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

    /// How much of the phone the kept thumbnails use.
    public func bytesOnDisk() async -> Int64 { await disk?.bytesHeld() ?? 0 }

    /// Empties the disk. What is held in memory stays until the app quits.
    public func emptyTheDisk() async { await disk?.empty() }

    /// Clears everything, the disk too. Used on sign-out, and on sign-in as a different user: the
    /// artists a phone has pictures of say what the last person's collection held.
    public func forget() async {
        found = [:]
        held.removeAllObjects()
        await disk?.empty()
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
