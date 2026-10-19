import Foundation
import CoreGraphics
import RPMKit
import RPMLibrary
import RPMDesign

/// A sleeve, decoded, and what colour it is.
///
/// The two are kept together because the code that decodes the picture is the only code that can
/// say what colour it is. Reading the colour is a downscale and a pass over the pixels. If each
/// card on a wall of six hundred worked it out for itself, it would be done six hundred times
/// for about ten possible answers.
public struct CoverArt: @unchecked Sendable {
    public let image: CGImage

    /// Everything the sleeve was read for, in one reading. See ``SleeveColours``.
    public let colours: SleeveColours

    /// The app's own accent nearest this sleeve, which is what the walls, the drawers
    /// and the pressed vinyl are painted from.
    public var accent: Accent? { colours.accent }

    public init(image: CGImage, colours: SleeveColours) {
        self.image = image
        self.colours = colours
    }

    /// A picture with only its accent known. A caller that builds one by hand has only this,
    /// and the room reads it as a sleeve with no colour of its own.
    public init(image: CGImage, accent: Accent?) {
        self.init(image: image,
                  colours: SleeveColours(accent: accent, dominant: nil, highlight: nil))
    }
}

/// The pictures.
///
/// One question, *what does this record look like*, is answered from four places, in order of
/// cost: the memory it is already in, this phone's disk, the store's own copy of the album's
/// cover, and last the art embedded in the user's own file.
///
/// **There is deliberately no lookup by name.** The desktop does the same. A cover guessed from
/// an artist and a title can be the wrong pressing, the wrong region, or another record entirely,
/// and it looks the same as a right one. Only backdrops are looked up by name.
///
/// Artwork is decoration. Offline, signed out, unknown record or undecodable file: every failure
/// here resolves to "no picture", never to an error on a screen.
///
/// Ordering rules that this actor relies on:
/// - The store's listing is read before the blank notes are checked (see `art(_:for:on:edge:)`).
/// - `forget()` bumps `era` before it clears anything, and every fetch checks `era` before it
///   stores a result.
/// - A cancelled or failed fetch is never noted as blank.
public actor ArtworkStore {
    private let source: any ArtSource
    private let disk: CoverDisk
    private let now: @Sendable () -> Date

    /// - Parameter mostBytes: how many bytes of decoded sleeves are held. The default is
    ///   ``mostBytesHeld``, the phone's limit. The TV passes more, because it draws more sleeves
    ///   at once.
    public init(source: any ArtSource,
                disk: CoverDisk = .inCaches(),
                now: @escaping @Sendable () -> Date = { Date() },
                mostBytes: Int = ArtworkStore.mostBytesHeld) {
        self.source = source
        self.disk = disk
        self.now = now
        held.totalCostLimit = mostBytes
        handed.totalCostLimit = mostBytes
    }

    // ── what is in memory ──

    private final class Entry {
        let art: CoverArt
        init(_ art: CoverArt) { self.art = art }
    }

    /// Decoded sleeves, at the size the wall is drawing them.
    ///
    /// `NSCache` is used rather than a dictionary with a size cap because the system **empties it
    /// when memory runs short**, before it ends the app. A hand-written cache can be given a
    /// budget, but it cannot be told that the budget has just changed.
    ///
    /// Entries are costed in pixels, which is what an entry really weighs. This balances the
    /// cache across a pinch gesture: at four sleeves across, an entry is a quarter of a megabyte
    /// and two hundred fit. At one across, it is four megabytes and sixteen fit, and only two
    /// are on the screen at that zoom.
    private let held = NSCache<NSString, Entry>()

    /// The sleeve last handed out for each record on each shelf at each size, keyed without the
    /// store's version so it can be read without the listing. See ``coverInMemory(for:on:edge:)``.
    /// `NSCache` is thread-safe, which is what the `unsafe` relies on.
    private nonisolated(unsafe) let handed = NSCache<NSString, Entry>()

    /// Sixty-four megabytes of decoded pictures. This holds several walls of sleeves at any zoom,
    /// and is small enough that it does not cause memory pressure on a phone.
    public static let mostBytesHeld = 64 * 1024 * 1024

    /// What colour each record is, once read. It is kept apart from the pictures and never
    /// evicted. It is one reading per album, and reading it again would need a decode of a
    /// picture that may already be gone from the cache.
    private var sleeves: [String: SleeveColours] = [:]

    /// Records that have been asked about and have nothing.
    ///
    /// Without this, a wall of records with no covers would make one signature request per
    /// tile per scroll. It is cleared whenever the index is read again, because a cover
    /// stored since then means the record no longer has nothing.
    private var blank: Set<String> = []

    // ── what the store says it has ──

    private var indexHeld: [String: [String: StoredCover]] = [:]
    private var indexReadAt: [String: Date] = [:]
    private var indexFailedAt: [String: Date] = [:]
    private var indexRunning: [String: Task<[String: StoredCover]?, Never>] = [:]

    /// How long the store's listing is trusted. A cover replaced on another machine
    /// shows up within this time. Asking more often would mean one listing per wall.
    public static let indexLife: TimeInterval = 10 * 60

    /// How long to wait before asking again when the store could not be reached at all.
    /// It is short, because the usual cause is a short loss of signal (for example a tunnel).
    /// It is not zero, or a wall of six hundred records would make six hundred failed listings.
    public static let indexRetry: TimeInterval = 20

    // ── who is waiting for what ──

    private final class Fetch {
        let task: Task<CoverArt?, Never>
        var waiting: Set<Int> = []
        init(_ task: Task<CoverArt?, Never>) { self.task = task }
    }

    private var inFlight: [String: Fetch] = [:]
    private var nextTicket = 0

    /// The discs being fetched before anybody asks for them, by address.
    ///
    /// A set, so a record whose tile is created four times in a fling is one fetch,
    /// and so the cap below counts what is really running.
    private var warming: Set<String> = []

    /// How many of those may run at once.
    ///
    /// **A prefetch over this limit is dropped, not queued.** A prefetch has no one waiting on
    /// it, so nothing cancels it when a cell is reused. A fling past six hundred records would
    /// otherwise leave six hundred downloads running for a wall that nobody is looking at.
    /// With four, the records that the user stops on are warmed and a fling costs almost nothing.
    /// A dropped prefetch is not a loss: the disc is fetched when the record plays.
    public static let warmingAtOnce = 4

    /// How many are running now. A test uses this to check that a fling cannot leave the whole
    /// wall downloading.
    var warmingNow: Int { warming.count }

    /// Bumped by `forget`. Work that started before the bump must not store anything after it.
    private var era = 0

    // ── the one question ──

    /// What this record looks like, at this size, or nothing.
    ///
    /// `edge` is in **pixels**, not points: the caller knows the screen it is
    /// drawing on and this store does not. The shelf is a parameter and has no default.
    /// A borrowed shelf has its own covers, and a default would risk drawing a friend's sleeve
    /// on the user's own record that has the same name.
    public func cover(for album: CloudAlbum, on shelf: CloudShelf, edge: Int) async -> CoverArt? {
        let era = self.era
        let sleeve = await art(.cover, for: album, on: shelf, edge: edge)

        // Kept for the next view's first frame. Not kept after a sign-out: the next account must
        // not be shown the last account's sleeves.
        if let sleeve, era == self.era {
            handed.setObject(Entry(sleeve), forKey: Self.handedKey(album, shelf, edge),
                             cost: sleeve.image.width * sleeve.image.height * 4)
        }

        // **Also fetch the record's own picture (its disc).** The desktop's sync pass handles a
        // record's cover and its disc in one loop, and this is the same pairing on the reading
        // side. A user who looked at this record is likely to play it. If the disc is already on
        // this phone, the record change does not wait for the network.
        warm(discOf: album, on: shelf)

        return sleeve
    }

    /// The sleeve ``cover(for:on:edge:)`` last answered for this record on this shelf at this size,
    /// else at the nearest size it answered (larger first), or nil. It is read at once, from any
    /// thread, so a view can draw the picture it already had on its first frame instead of its
    /// placeholder. A sleeve kept at another size is the same picture, drawn a little soft until
    /// the view's own ask answers with its size.
    ///
    /// **This is not the final answer.** The cover may have been replaced since. The view still
    /// asks ``cover(for:on:edge:)``, and the newer sleeve replaces this one when it arrives.
    public nonisolated func coverInMemory(for album: CloudAlbum, on shelf: CloudShelf, edge: Int) -> CoverArt? {
        let want = Self.bucket(holding: edge)
        let nearest = [want] + Self.buckets.filter { $0 > want } + Self.buckets.filter { $0 < want }.reversed()
        for size in nearest {
            if let kept = handed.object(forKey: Self.handedKey(album, shelf, size)) { return kept.art }
        }
        return nil
    }

    /// Whose shelf, which record and which size: the same record on a borrowed shelf has its own
    /// sleeve.
    private static func handedKey(_ album: CloudAlbum, _ shelf: CloudShelf, _ edge: Int) -> NSString {
        "\(shelf.ownerId)|\(album.key)|\(bucket(holding: edge))" as NSString
    }

    /// The picture of the record itself, where the store has one: the transparent disc
    /// image that the desktop cuts out of a photograph and puts in the album's folder. The
    /// turntable shows it in place of the record it draws. Nil is the ordinary answer:
    /// most albums have no disc art and the drawn record keeps turning.
    ///
    /// **No colour is returned, and this is deliberate.** The vinyl is pressed in the sleeve's
    /// accent. A second colour read from the label would make the record change colour when
    /// its disc arrives. The image is the whole answer.
    ///
    /// **The result is a ``ScannedDisc`` and not a plain picture**, because a picture alone is
    /// not enough to draw. A scan of a whole CD replaces the drawn record, and a scan of a
    /// label is placed on it. A caller that holds a bare image cannot tell them apart. The
    /// type works out its own kind, so the kind cannot be lost.
    ///
    /// `edge` is in pixels, like ``cover(for:on:edge:)``.
    public func disc(for album: CloudAlbum, on shelf: CloudShelf, edge: Int) async -> ScannedDisc? {
        guard let art = await art(.disc, for: album, on: shelf, edge: edge) else { return nil }
        return ScannedDisc(art.image)
    }

    private func art(_ picture: RecordPicture,
                     for album: CloudAlbum, on shelf: CloudShelf, edge: Int) async -> CoverArt? {
        let bucket = Self.bucket(holding: edge)
        let spellings = AlbumArtKey.spellings(picture, for: album.tracks)
        guard !spellings.isEmpty else { return nil }

        let index = await self.index(shelf)

        // **After the listing, not before it.** The note that a record has nothing is only true
        // for one reading of the store, and reading the listing again clears the notes. If the
        // notes were checked first, a record that gained a cover would show no cover for as long
        // as the app stayed open.
        guard !blank.contains(Self.note(picture, album)) else { return nil }

        // The store's own entry, under whichever spelling it knows. Its version matters: a cover
        // lives at an address derived from the record, so replacing the picture does not move it.
        // The stamp is the only thing that tells a cached copy of the old picture from the new.
        let stored = spellings.lazy.compactMap { index[$0] }.first
        let identity = stored?.albumKey ?? spellings[0]
        let stamp = stored?.updatedAt ?? 0

        let address = "\(identity)|\(stamp)|\(bucket)"

        if let entry = held.object(forKey: address as NSString) { return entry.art }

        let fetch = inFlight[address] ?? begin(address, picture: picture, album: album, shelf: shelf,
                                               spellings: spellings, stored: stored,
                                               identity: identity, stamp: stamp, bucket: bucket)

        let ticket = nextTicket
        nextTicket += 1
        fetch.waiting.insert(ticket)

        return await withTaskCancellationHandler {
            let art = await fetch.task.value
            leave(address, ticket)
            return art
        } onCancel: {
            // Always start a new task: a cancellation handler runs on whichever thread noticed
            // the cancellation. It may only hop back onto the actor, never touch state here.
            Task { await self.leave(address, ticket) }
        }
    }

    /// How much of the phone's storage the kept sleeves use. The screen that offers to clear
    /// them shows this.
    public func bytesOnDisk() async -> Int64 {
        await disk.bytesHeld()
    }

    /// The sleeves on the disk, and only those.
    ///
    /// This is not `forget()`, which is for signing out and also drops the listing and bumps
    /// the era. This method is for a user who reclaims space on a phone that they still use.
    /// What is in memory stays, because dropping it would redraw the wall the user is
    /// looking at.
    public func emptyTheDisk() async {
        await disk.empty()
    }

    /// Everything forgotten: memory, disk, and what the store was known to hold.
    ///
    /// The era is bumped **first**, before anything is cleared, so a fetch that is already
    /// running cannot put the last account's record collection back on this phone after it
    /// was removed.
    public func forget() async {
        era += 1

        for fetch in inFlight.values { fetch.task.cancel() }
        inFlight = [:]

        held.removeAllObjects()
        handed.removeAllObjects()
        sleeves = [:]
        blank = []

        // The addresses in here belong to the last account. The era check stops a warm that is
        // already running from writing its disc onto this phone. Clearing the set makes sure that
        // the next account's first four records are not turned away by names that belong to the
        // account that signed out.
        warming = []
        indexHeld = [:]
        indexReadAt = [:]
        indexFailedAt = [:]
        indexRunning = [:]

        await disk.empty()
    }

    // ── coalescing ──

    private func begin(
        _ address: String, picture: RecordPicture, album: CloudAlbum, shelf: CloudShelf,
        spellings: [String], stored: StoredCover?, identity: String, stamp: Int64, bucket: Int
    ) -> Fetch {
        let fetch = Fetch(Task { [weak self] in
            guard let self else { return nil }
            return await self.load(picture, album: album, shelf: shelf, spellings: spellings,
                                   stored: stored, identity: identity, stamp: stamp,
                                   bucket: bucket, address: address)
        })

        inFlight[address] = fetch
        return fetch
    }

    /// One waiter has gone. When the last one does, the work stops.
    ///
    /// A fling prepares and discards cells much faster than a network answers. A picture that
    /// nobody is looking at is not worth finishing. A picture that one caller still waits for
    /// is, however many other callers have scrolled past it.
    ///
    /// The waiters are a set and not a count, so leaving twice is the same as leaving once. A
    /// caller that is cancelled arrives here from the cancellation handler and again when it
    /// resumes.
    private func leave(_ address: String, _ ticket: Int) {
        guard let fetch = inFlight[address] else { return }

        fetch.waiting.remove(ticket)
        guard fetch.waiting.isEmpty else { return }

        fetch.task.cancel()
        inFlight[address] = nil
    }

    // ── the four places ──

    private func load(
        _ picture: RecordPicture,
        album: CloudAlbum, shelf: CloudShelf, spellings: [String], stored: StoredCover?,
        identity: String, stamp: Int64, bucket: Int, address: String
    ) async -> CoverArt? {
        let era = self.era

        // This phone's own copy first. It is asked for at the exact version when the store gave
        // one, and at any version when it did not. With no signal there is no index and so no
        // stamp, and an older cover is better than a grey square.
        if let onDisk = await fromDisk(spellings: spellings, identity: identity,
                                       stamp: stored == nil ? nil : stamp) {
            guard !Task.isCancelled else { return nil }
            return finish(picture, onDisk, big: nil, identity: identity, stamp: stamp,
                          bucket: bucket, address: address, era: era)
        }

        guard !Task.isCancelled else { return nil }

        let downloaded: Data

        switch await fetch(picture, album: album, shelf: shelf, stored: stored) {
        case .picture(let data):
            downloaded = data

        case .nothing:
            // Asked, and there is nothing. This is noted, so a wall of records with no covers
            // does not make a request per tile per scroll.
            note(blank: Self.note(picture, album), era: era)
            return nil

        case .unreachable:
            // **Nothing is noted.** The work was cancelled or the network was not available.
            // Neither means that the record has no cover. A note would leave the record blank
            // until the listing is read again, which is ten minutes (see `indexLife`).
            return nil
        }

        guard !Task.isCancelled else { return nil }

        // Decoded once at the size it is kept at, and that decode is what goes to the disk. The
        // original is never held. It can be three thousand pixels wide for a card a fifth of
        // that size.
        guard let big = Thumbnail.of(downloaded, edge: Thumbnail.stored),
              let keeping = Thumbnail.kept(downloaded, decoded: big, picture)
        else {
            // The bytes arrived but are not a picture that this phone can read. Asking again
            // will not change that, so it is noted like any other nothing.
            note(blank: Self.note(picture, album), era: era)
            return nil
        }

        guard era == self.era else { return nil }
        await disk.hold(albumKey: identity, stamp: stamp, keeping)

        return finish(picture, keeping, big: big, identity: identity, stamp: stamp,
                      bucket: bucket, address: address, era: era)
    }

    private func fromDisk(spellings: [String], identity: String, stamp: Int64?) async -> Data? {
        if let stamp {
            return await disk.picture(albumKey: identity, stamp: stamp)
        }

        // There is no index, so it is not known which spelling this phone filed the cover under.
        // Try every spelling.
        for key in spellings {
            if let data = await disk.picture(albumKey: key) { return data }
        }
        return nil
    }

    // ── the disc, fetched before anybody asks ──

    /// Puts a record's disc on this phone's disk, if the store has one and this phone
    /// does not have it already.
    ///
    /// **No request is made to find out whether a disc exists.** The listing that this store
    /// already holds names every picture on the shelf, discs included. A record with no disc
    /// art (most records) costs one dictionary lookup and no request. Only a record that has
    /// a disc is fetched.
    ///
    /// The disc is kept on the disk, not in memory. The memory cache is for the sleeves of a
    /// wall. Filling it with discs that nobody is looking at would evict the covers that are
    /// on the screen.
    private func warm(discOf album: CloudAlbum, on shelf: CloudShelf) {
        guard warming.count < Self.warmingAtOnce else { return }

        // The listing as it is now. It is never read here: this runs after a cover was asked
        // for, which has read it, and a prefetch is not worth a listing.
        guard let index = indexHeld[shelf.ownerId] else { return }

        let spellings = AlbumArtKey.spellings(.disc, for: album.tracks)
        guard let stored = spellings.lazy.compactMap({ index[$0] }).first else { return }

        let address = "\(stored.albumKey)|\(stored.updatedAt)"
        guard warming.insert(address).inserted else { return }

        let era = self.era
        Task { [weak self] in
            await self?.keep(disc: stored, of: album, on: shelf, address: address, era: era)
        }
    }

    private func keep(
        disc stored: StoredCover, of album: CloudAlbum, on shelf: CloudShelf,
        address: String, era: Int
    ) async {
        defer { warming.remove(address) }

        guard era == self.era else { return }

        // Already here, at this version. This is the ordinary case on every launch after the
        // first, and it is why the prefetch costs almost nothing.
        if await disk.picture(albumKey: stored.albumKey, stamp: stored.updatedAt) != nil {
            return
        }

        guard case .picture(let data) = await fetch(.disc, album: album, shelf: shelf,
                                                    stored: stored)
        else { return }

        // **Nothing is noted blank on this path.** A prefetch only runs for a record that the
        // listing says has a disc, so a failure here is a network failure and not an answer.
        // A note would stop the later read, when the record plays, from fetching the disc.
        guard era == self.era,
              let big = Thumbnail.of(data, edge: Thumbnail.stored),
              let keeping = Thumbnail.encoded(big, .disc)
        else { return }

        await disk.hold(albumKey: stored.albumKey, stamp: stored.updatedAt, keeping)
    }

    /// What "this record has nothing" is filed under.
    ///
    /// **The picture is part of it.** Covers and discs share one set. A record with a sleeve
    /// and no disc label is the ordinary case. If the note used the album alone, the first
    /// look for the disc would hide the record's cover for the ten minutes until the listing is
    /// read again.
    private static func note(_ picture: RecordPicture, _ album: CloudAlbum) -> String {
        "\(picture.rawValue)|\(album.key)"
    }

    /// A record is noted blank only from `load`, and never while the work that asked is being
    /// cancelled: a cancelled fetch says nothing about whether a cover exists.
    private func note(blank key: String, era: Int) {
        guard era == self.era, !Task.isCancelled else { return }
        blank.insert(key)
    }

    /// What came of asking.
    ///
    /// **"There is nothing" and "I could not ask" are different answers.** If they are mixed
    /// up, a wall empties. A fling cancels a fetch part way through, and a loss of signal fails
    /// one. If either were read as "this record has no cover", the record would stay blank
    /// until the listing is read again, and the faster the user scrolls, the more of the
    /// collection goes grey.
    private enum Asked {
        case picture(Data)

        /// Asked, and there is nothing: the store has no stored cover to serve, and
        /// there is no art in the file.
        case nothing

        /// Could not ask: cancelled, offline, or the store refused.
        case unreachable
    }

    private func fetch(_ picture: RecordPicture,
                       album: CloudAlbum, shelf: CloudShelf, stored: StoredCover?) async -> Asked {
        // The record's stored cover comes first. It is the picture that the library shows, and
        // for most ripped albums it is the image in the album folder, which is inside no file.
        // The embedded art is the fallback.
        if let stored {
            // The listing has a version but usually no address, so the usual path is a second
            // call to get a signed address. If a source gives an address, it is used as it is.
            var signed = stored.url
            if signed == nil {
                signed = await source.art(shelf, albumKey: stored.albumKey,
                                          size: Self.size(of: picture))?.url
            }

            if let signed, let url = URL(string: signed) {
                do {
                    let data = try await source.artwork(at: url)
                    if !data.isEmpty { return .picture(data) }
                } catch {
                    // The store said that it holds a cover for this record. A failure to reach
                    // it does not show that the record has no cover.
                    return .unreachable
                }
            }
        }

        if Task.isCancelled { return .unreachable }

        // **The sidecar is a fallback for covers only.** A sidecar holds the art embedded in the
        // user's file. A disc label is never in a tag: it is a picture in the album's folder, so
        // the store is the only place it can come from. Asking the sidecar for a disc would
        // return the sleeve, and it would be shown on the record as if it were a photograph of
        // the disc.
        guard picture == .cover else { return .nothing }

        // The art in the user's own file. Only for the user's own shelf: a sidecar is an object
        // under the account that uploaded it and the route takes no shelf, so asking about
        // another account's record would give a 404 and waste a round trip.
        guard shelf.isOwn, let first = album.tracks.first else { return .nothing }

        do {
            guard let art = try await source.sidecar(rpmId: first.rpmId)?.art, !art.isEmpty
            else { return .nothing }

            return .picture(art)
        } catch {
            return .unreachable
        }
    }

    /// Which picture of a stored cover the store is asked for.
    ///
    /// A sleeve is asked for at the size the phone keeps it (``Thumbnail/stored``). The API's
    /// copy at that edge is the picture that the phone would otherwise cut from the original, and
    /// it has a fraction of the bytes. A disc is asked for as the original, because the API's
    /// copies are JPEGs on a black background, and the transparent corners of a disc label are
    /// part of its shape.
    static func size(of picture: RecordPicture) -> CoverSize {
        switch picture {
        case .cover: return .edge(Thumbnail.stored)
        case .disc: return .original
        }
    }

    /// Decodes at the size asked for, works out the colour, and holds both.
    ///
    /// `big` is the thousand-pixel decode when there is one, so a fetch does not decode twice.
    /// A picture read from the disk has no `big`, and one decode at the wall's own size is
    /// the whole cost.
    private func finish(
        _ picture: RecordPicture, _ data: Data, big: CGImage?, identity: String, stamp: Int64,
        bucket: Int, address: String, era: Int
    ) -> CoverArt? {
        let image = (bucket >= Thumbnail.stored ? big : nil) ?? Thumbnail.of(data, edge: bucket)
        guard let image else { return nil }

        let read = "\(identity)|\(stamp)"
        let colours: SleeveColours

        // **No colour is read from a disc label.** Most of its square is transparent, so the
        // result would depend on what the corners are drawn against. The record is pressed in
        // the sleeve's colour anyway, and that colour must not change.
        if picture != .cover {
            colours = .none
        } else if let known = sleeves[read] {
            colours = known
        } else {
            // Read from the largest picture in hand. A 48 pixel square taken from 1000 pixels
            // and one taken from 250 pixels are not quite the same colour, and a record must not
            // change shade when the user pinches the wall.
            colours = Thumbnail.colours(of: big ?? image)
            if era == self.era { sleeves[read] = colours }
        }

        let art = CoverArt(image: image, colours: colours)

        guard era == self.era else { return art }
        held.setObject(Entry(art), forKey: address as NSString,
                       cost: image.width * image.height * 4)
        return art
    }

    // ── the store's listing ──

    private func index(_ shelf: CloudShelf) async -> [String: StoredCover] {
        let owner = shelf.ownerId
        let known = indexHeld[owner] ?? [:]

        if let read = indexReadAt[owner], now().timeIntervalSince(read) < Self.indexLife {
            return known
        }

        if let failed = indexFailedAt[owner], now().timeIntervalSince(failed) < Self.indexRetry {
            return known
        }

        if let running = indexRunning[owner] { return await running.value ?? known }

        let era = self.era
        let task = Task { [source] () -> [String: StoredCover]? in
            // Nil means "could not ask". That is a different answer from a collection
            // with no covers in it, which is an empty listing.
            guard let covers = try? await source.artCatalog(shelf) else { return nil }
            return Self.byKey(covers)
        }
        indexRunning[owner] = task

        let read = await task.value
        indexRunning[owner] = nil

        guard era == self.era else { return read ?? [:] }

        guard let read else {
            indexFailedAt[owner] = now()
            return known
        }

        indexHeld[owner] = read
        indexReadAt[owner] = now()
        indexFailedAt[owner] = nil

        // A cover stored since the last read means a record is no longer known to have nothing.
        blank = []

        return read
    }

    private static func byKey(_ covers: [StoredCover]) -> [String: StoredCover] {
        var map: [String: StoredCover] = [:]
        map.reserveCapacity(covers.count)

        // The last entry wins and a duplicate key is not an error. An error would hide the
        // user's covers for a small fault. The listing order is stable, so a record that is
        // listed twice always resolves to the same entry.
        for cover in covers { map[cover.albumKey] = cover }
        return map
    }

    // ── sizes ──

    /// The sizes a picture is kept at.
    ///
    /// Sizes are in buckets and not exact, because the wall's card has a different number of
    /// pixels at every step of a pinch. One decode per width would be a cache that never hits
    /// during the gesture that needs it most.
    public static let buckets = [256, 512, 1024]

    public static func bucket(holding edge: Int) -> Int {
        buckets.first { $0 >= edge } ?? buckets[buckets.count - 1]
    }
}
