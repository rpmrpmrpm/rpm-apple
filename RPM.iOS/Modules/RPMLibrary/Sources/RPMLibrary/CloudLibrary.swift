import Foundation
import RPMKit

/// Where a listing comes from.
///
/// A protocol so the orderings can be tested against a source that answers when
/// the test says so, rather than when a network does.
public protocol LibrarySource: Sendable {
    func list(_ shelf: CloudShelf) async throws -> [CloudTrack]
}

/// The library the phone draws, and everything that decides when to ask the cloud
/// again.
///
/// **Every `await` below is a suspension point.** An actor gives mutual exclusion of
/// statements, not of intentions: another task can run on this actor while one is
/// suspended. Read the notes on `era`, `inFlight` and `asked` before changing
/// anything here.
public actor CloudLibrary {
    private let source: any LibrarySource
    private let storeRoot: URL?
    private let now: @Sendable () -> Date

    /// Whose shelf each track came off. Held rather than owned: playback asks it
    /// about tracks this object has never heard of.
    public nonisolated let shelves: TrackShelves

    /// The listener's marks, read off every own-shelf listing that arrives.
    public nonisolated let marks: FavoriteMarks

    /// The shelves whose contents have changed since anybody last looked.
    ///
    /// A stream rather than a callback, and it says WHICH shelf rather than
    /// deciding for the reader whether they care. This object has no idea what is
    /// on screen and does not need one: whoever is drawing shelf X redraws when X
    /// comes down the stream, which is one less thing for the library layer to be
    /// wrong about.
    ///
    /// Nothing is sent when a refresh found the same library, because a phone
    /// opened twice in an evening must not rebuild a wall of a thousand covers to
    /// arrive at what was already on it.
    public nonisolated let changes: AsyncStream<CloudShelf>
    private nonisolated let announce: AsyncStream<CloudShelf>.Continuation

    private var held: [String: [CloudAlbum]] = [:]

    /// Which collections the cloud has been asked about since the app opened. What
    /// keeps a second look at the same shelf off the disk copy it has already
    /// replaced.
    private var asked: Set<String> = []

    /// **Which sign-in a read belongs to.** Increased by ``forget()``.
    ///
    /// Signing out can happen while a read is still in progress. A listing that
    /// arrives afterwards would put a catalogue back into memory and onto the disk
    /// that the sign-out had just cleared, and the listing names every record the
    /// user owns. So a read captures `era` before its first `await` and drops its
    /// answer if `era` has changed.
    private var era = 0

    /// The read already running for a shelf, if there is one.
    ///
    /// Two tabs asking at once (the wall, and the playlist tab's track lookup)
    /// would otherwise both fetch the whole catalogue. The second caller awaits the
    /// first caller's task rather than taking a lock: it is the shorter answer, it
    /// cannot deadlock, and a cancelled caller simply stops awaiting instead of
    /// stranding whoever is behind it.
    ///
    /// Per shelf, not one at a time overall, so reading a friend's records does not
    /// wait behind reading your own.
    private var inFlight: [String: Task<[CloudAlbum], Never>] = [:]

    private var lastRead: Date = .distantPast

    /// How long after a read the app coming forward is worth another one.
    public static let resumeInterval: TimeInterval = 5 * 60

    public init(
        source: any LibrarySource,
        shelves: TrackShelves = TrackShelves(),
        marks: FavoriteMarks,
        storeRoot: URL? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.source = source
        self.shelves = shelves
        self.marks = marks
        self.storeRoot = storeRoot
        self.now = now

        // Unbounded, and it drops nothing: a wall that missed the one message
        // saying its records changed is a wall that stays wrong until the app is
        // relaunched.
        (changes, announce) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    deinit { announce.finish() }

    // ── reading ──

    /// A shelf's records, grouped and in order.
    ///
    /// - Parameters:
    ///   - shelf: whose collection. Stated at every call site rather than
    ///     defaulted: the wall wants whatever is on screen, and the playlists and
    ///     the favourites want the user's own whatever is on screen, and a default
    ///     would silently make one of those two wrong.
    ///   - refresh: go to the cloud even when a library is already in hand. The
    ///     reload key, and nothing else.
    public func albums(_ shelf: CloudShelf, refresh: Bool = false) async -> [CloudAlbum] {
        if !refresh, let known = held[shelf.ownerId] { return known }

        // Somebody is already fetching this shelf: wait for their answer rather
        // than asking for a second copy of it.
        if !refresh, let running = inFlight[shelf.ownerId] { return await running.value }

        let task = Task { await self.load(shelf, refresh: refresh) }
        inFlight[shelf.ownerId] = task

        let answer = await task.value
        inFlight[shelf.ownerId] = nil
        return answer
    }

    private func load(_ shelf: CloudShelf, refresh: Bool) async -> [CloudAlbum] {
        // Captured BEFORE the first await: an era read after a suspension may
        // already have changed.
        let era = self.era

        let store = LibraryStore(shelf: shelf, root: storeRoot)

        // The copy from last time, off the disk. A catalogue is thousands of rows and
        // twenty round trips, and the library is written from the desktop, so the
        // app shows what it already knows and asks the cloud in the background
        // rather than making somebody wait for a spinner.
        if !refresh, !asked.contains(shelf.ownerId), let cached = store.load(), !cached.isEmpty {
            let grouped = AlbumWall.group(cached)
            guard era == self.era else { return [] }

            await hold(shelf, grouped, tracks: cached)
            Task { await self.refreshBehind(shelf) }
            return grouped
        }

        // Nothing on the disk: the whole library over the wire.
        guard let tracks = try? await source.list(shelf) else {
            // Offline, or signed out. What is held is what the phone has, and that
            // is a library rather than an error.
            return held[shelf.ownerId] ?? []
        }
        guard era == self.era else { return [] }

        asked.insert(shelf.ownerId)
        if shelf.isOwn { lastRead = now() }

        store.save(tracks)

        let grouped = AlbumWall.group(tracks)
        await hold(shelf, grouped, tracks: tracks)
        return grouped
    }

    /// Whether the store has ever answered for this shelf.
    ///
    /// **The difference between a collection that is empty and one that could not be
    /// read**, and there is no other way to tell them apart from outside: a failed
    /// read answers with what the phone holds, which for a shelf it has never reached
    /// is nothing at all. A wall drawn from that says "nothing here yet, upload your
    /// library" to somebody whose library is fine and whose train is in a tunnel.
    ///
    /// True from the first answer onwards, including an answer of no tracks, which is
    /// the point: that one IS an empty collection.
    public func reached(_ shelf: CloudShelf) -> Bool { asked.contains(shelf.ownerId) }

    /// The one read a launch does, behind a wall that is already drawn.
    ///
    /// It replaces what is held and says so only when the answer is different.
    public func refreshBehind(_ shelf: CloudShelf) async {
        let era = self.era

        guard let tracks = try? await source.list(shelf) else { return }
        guard era == self.era else { return }

        asked.insert(shelf.ownerId)
        if shelf.isOwn { lastRead = now() }

        let grouped = AlbumWall.group(tracks)
        let changed = held[shelf.ownerId].map { !AlbumWall.same($0, grouped) } ?? true

        LibraryStore(shelf: shelf, root: storeRoot).save(tracks)
        await hold(shelf, grouped, tracks: tracks)

        // Which shelf changed, said once. Whether that is news is the reader's
        // question, not this object's.
        if changed { announce.yield(shelf) }
    }

    /// Reads the library again if it has not been read for a while.
    ///
    /// A phone that has been in a pocket for a minute has not missed anything; one
    /// that has been shut for a day has.
    public func refreshOnResume() {
        guard now().timeIntervalSince(lastRead) >= Self.resumeInterval else { return }
        Task { await self.refreshBehind(.own) }
    }

    // ── forgetting ──

    /// Throws the library away, what is held and the copy on disk both.
    ///
    /// Signing out, and nothing else. The listing names every record somebody owns,
    /// and leaving it on a phone handed to the next person is a leak of the quiet
    /// kind.
    public func forget() {
        // FIRST, so that a read already in the air cannot write its answer back in
        // behind this.
        era += 1

        held.removeAll()
        asked.removeAll()
        lastRead = .distantPast

        LibraryStore.deleteAll(root: storeRoot)
        shelves.forget()

        // The marks are main-actor view state, so this hops. It is safe to hop
        // AFTER the era has moved: anything still in the air is already dead, and
        // a listing that hops in behind this one finds the era changed and clears
        // itself rather than repopulating.
        let marks = self.marks
        Task { @MainActor in marks.forget() }
    }

    /// Drops every borrowed shelf that is not in `live`. A share taken back.
    public func forgetShelvesOtherThan(_ live: Set<String>) {
        let gone = held.keys.filter { !$0.isEmpty && !live.contains($0) }
        guard !gone.isEmpty else { return }

        for owner in gone {
            // The disk copy goes too: a listing nobody may read any more must not
            // sit on the phone waiting for the next launch to draw it.
            LibraryStore(shelf: .of(owner), root: storeRoot).delete()
            held[owner] = nil
            asked.remove(owner)
        }

        // The rpmId map is deliberately left alone. A record still playing off a
        // shelf that has just been closed must not become unplayable half way
        // through: the server has the last word on whether it may go on, and it
        // says so by refusing the next signature.
    }

    // ── plumbing ──

    /// Files a listing under ITS OWN shelf, never under the one on screen, and
    /// reads the marks off it where it is the user's own.
    ///
    /// One door for both, because they are one fact: a screen that had the catalogue
    /// without the marks would draw a heart the library disagrees with.
    private func hold(_ shelf: CloudShelf, _ albums: [CloudAlbum], tracks: [CloudTrack]) async {
        held[shelf.ownerId] = albums

        guard shelf.isOwn else {
            shelves.hold(shelf, tracks: tracks)
            return
        }

        // The marks are main-actor view state, so this is a hop, and a hop is a
        // suspension: check the era on the far side of it too, or a sign-out that
        // lands in the gap is undone by the marks arriving after it.
        let era = self.era
        let marks = self.marks
        await MainActor.run { marks.read(tracks) }
        if era != self.era { await MainActor.run { marks.forget() } }
    }

    // Test seams. Internal rather than public: tests use them to check the
    // ordering rules described above.
    var heldShelves: Set<String> { Set(held.keys) }
    var currentEra: Int { era }
}
