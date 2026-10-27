import Foundation
import RPMKit
import RPMLibrary
import RPMRadio

/// The signed-in account's library as the screens show it: whose collection is on the wall, its
/// records, home, the playlists, the shares, the marks and the quota.
///
/// Shared by the phone and the TV. Each head builds one, owns the screens that read it, and
/// adds what only it does (downloads and casting on the phone, the home network on the TV).
///
/// Every read that finishes after an `await` checks that its result still matches the screen: the
/// shelf it was asked for (``viewing``), the account (``standing``, ``marksEra``), or the switch
/// that started it (``switching``). A new read added here needs the same check. Without it, a slow
/// answer for an old shelf or account could overwrite the current one.
@MainActor
@Observable
public final class LibrarySession {
    public let auth: AuthClient
    public let cloud: RPMCloudClient
    public let community: RPMCommunityClient
    public let library: CloudLibrary

    /// What this device has played, and what the listener's other devices have.
    public let plays: PlayLog

    /// What has been heard on the radio, on this device and the listener's other devices.
    public let radioListens: RadioListens

    /// Which records are classical, filed by shelf.
    public let classical = ClassicalMarks()

    /// The id this install reports its plays under. See ``PlayDevice``.
    public let playDevice: PlayDevice

    /// Whose shelf each record is on.
    public var shelves: TrackShelves { library.shelves }

    /// Told after every quota read that answered, so the head can settle the stream rate on it.
    /// Set once by the head after it is built.
    public var onQuotaRead: @MainActor () -> Void = {}

    /// What is added to the account's own shelf before it is shown: on the TV, the tracks that
    /// only a computer on the home network holds. Applied to the own shelf alone. A borrowed shelf
    /// is only the owner's cloud, so nothing is added to it.
    public typealias Additions = @MainActor ([CloudAlbum]) -> [CloudAlbum]

    /// The own shelf as the cloud has it. The phone uses this, and it adds nothing.
    public static let nothingAdded: Additions = { $0 }

    private let additions: Additions

    /// The own shelf as the library last read it, before ``additions``, so a change on the home
    /// network can be laid over it again without another read.
    private var ownAsRead: [CloudAlbum] = []

    /// - Parameter additions: what is added to the own shelf. There is no default. A head with
    ///   tracks beyond the cloud's must pass its own function. A head with none passes
    ///   ``nothingAdded``.
    public init(auth: AuthClient, cloud: RPMCloudClient, community: RPMCommunityClient,
                library: CloudLibrary, plays: PlayLog, radioListens: RadioListens,
                playDevice: PlayDevice, additions: @escaping Additions) {
        self.additions = additions
        self.auth = auth
        self.cloud = cloud
        self.community = community
        self.library = library
        self.plays = plays
        self.radioListens = radioListens
        self.playDevice = playDevice
    }

    // ── where the app is ──

    public private(set) var standing: AccountStanding = .starting

    /// Who is signed in. Stored here because `AuthClient` is an actor, and a view cannot await it.
    public private(set) var who: Session?

    /// The account's storage use and plan. Read after the wall is up, or before it at sign-in
    /// (see ``GroundRule``).
    public private(set) var quota: CloudQuota?

    /// The records on the wall, for the shelf in ``viewing``.
    public private(set) var albums: [CloudAlbum] = []

    /// The state of the wall. Switching to another person's shelf empties the wall while it loads.
    /// An empty array would look like an empty library, so the state is kept separately.
    public private(set) var wallStanding: ReadStanding = .reading

    /// Which records are marked. Loaded with one call for the whole library, not one call per tile.
    public private(set) var marks: Set<String> = []

    /// Changed on sign-out. A marks read compares it after its `await`, so the marks of one account
    /// are never stored in the session of the next account.
    private var marksEra = 0

    /// The home screen. Worked out once per launch, and nil until the shelf and the play counts
    /// are both available.
    public private(set) var home: HomeScreen?

    /// What has been played, on every device, as of the last time home was worked out.
    public private(set) var played: [String: PlayLog.Played] = [:]

    /// The stations named on home, keyed by uuid, as the log had them when home was worked out.
    public private(set) var homeStations: [String: RadioStation] = [:]

    /// The seed for the home draw. It is set once per launch, so home changes between launches
    /// and stays the same during a session.
    private let homeDraw = Int(Date().timeIntervalSince1970)

    /// Called after the keychain has been read and no one is signed in.
    public func showSignedOut() {
        standing = .signedOut
    }

    /// Reads the account's own collection and puts it on screen.
    ///
    /// - Parameters:
    ///   - rule: what the quota read may do with the supporter ground. At sign-in the quota
    ///     is read before the wall, because it decides which ground the wall is drawn on.
    ///   - whenUp: run once the wall and home are shown, before the marks and quota are read.
    ///     The phone starts its downloads here.
    public func show(_ rule: GroundRule, whenUp: @MainActor () -> Void) async {
        listenForChanges()
        standing = .loading
        wallStanding = .reading

        if rule == .adoptNow { await readQuota(rule) }

        let read = await library.albums(.own)

        place(read, of: .own)
        wallStanding = await settled(albums, of: .own)

        // Settled before the screens appear, not after the marks and quota. The launch screen stays
        // up until home's banner has its first pictures. Home does not need the marks or the quota.
        await settleHome()

        standing = .showing
        whenUp()

        who = await auth.current
        Task { await self.readShares() }

        // Read after the wall is up, not before it.
        await readMarks()
        if rule == .nextLaunch { await readQuota(rule) }

        // The playlists fill the lists row on home. This runs after home is settled, so the first
        // screen does not wait for another request.
        Task { await self.settleHomeLists() }
    }

    /// Whether the library's change stream has a reader. It has one reader for the app's life.
    private var listening = false

    /// Follows the library's own refreshes. The library can read a shelf again in the background,
    /// for example at launch when the copy on disk was shown first, or after the app returns to the
    /// front. When the new read differs, the shelf on screen is laid out again, and home and the
    /// playlists follow.
    private func listenForChanges() {
        guard !listening else { return }
        listening = true
        let changes = library.changes
        Task { [weak self] in
            for await shelf in changes {
                guard let self else { return }
                await self.shelfChanged(shelf)
            }
        }
    }

    private func shelfChanged(_ shelf: CloudShelf) async {
        guard standing == .showing, shelf.ownerId == viewing.ownerId else { return }
        let read = await library.albums(shelf)
        // Checked again after the await, because a switch to another shelf may have happened
        // during it.
        guard standing == .showing, shelf.ownerId == viewing.ownerId else { return }

        place(read, of: shelf)
        wallStanding = await settled(albums, of: shelf)
        await settleHome()

        // The playlists are resolved against the tracks, so a new listing is a new answer.
        await rereadPlaylists()
    }

    /// Reads the shelf on the wall again, skipping the copy in memory.
    public func refresh() async {
        let shelf = viewing
        let read = await library.albums(shelf, refresh: true)

        guard shelf.ownerId == viewing.ownerId else { return }

        place(read, of: shelf)
        wallStanding = await settled(albums, of: shelf)

        guard viewing.isOwn else { return }
        await readQuota(.nextLaunch)
    }

    /// The storage use, and whether the account is a supporter.
    ///
    /// A failed read changes nothing. Without a network, a device must not show the account as
    /// having stopped supporting.
    public func readQuota(_ rule: GroundRule) async {
        quota = try? await cloud.quota()

        guard let quota else { return }

        switch rule {
        case .adoptNow: SupporterGround.adopt(isSupporter: quota.supporter, in: .standard)
        case .nextLaunch: SupporterGround.remember(isSupporter: quota.supporter, in: .standard)
        }
        onQuotaRead()
    }

    /// Forgets everything this session holds about the account, for signing out. The head
    /// signs out of `auth` and clears what it owns itself.
    public func forget() async {
        await library.forget()
        await radioListens.forget()
        // The plays are cleared with the account, and so is the id they were sent under. If the id
        // were kept, the next account would send the previous account's unsent plays as its own.
        await plays.forget()
        playDevice.forget()

        albums = []
        ownAsRead = []
        marks = []
        classical.forget()
        marksEra += 1
        viewing = .own
        shelfRows = []
        faces = [:]
        ownFace = .nobody
        received = []
        sharesKnown = false
        playlists = []
        playlistsRead = false
        playlistStanding = .reading
        home = nil
        played = [:]
        homeStations = [:]
        who = nil
        quota = nil
        standing = .signedOut

        // Signing out is a known answer, unlike a quota read that failed. The app returns to its
        // own ground now.
        SupporterGround.adopt(isSupporter: false, in: .standard)
    }

    /// Puts a shelf's records on the wall: the own shelf with ``additions`` laid over it.
    private func place(_ read: [CloudAlbum], of shelf: CloudShelf) {
        if shelf.isOwn {
            ownAsRead = read
            albums = additions(read)
        } else {
            albums = read
        }
    }

    /// The result of ``additions`` changed, for example because a computer joined, left, or changed
    /// its catalogue. The own shelf is laid out again from the last read, and home with it. A
    /// borrowed shelf is not changed.
    public func additionsChanged() async {
        guard viewing.isOwn, standing == .showing else { return }
        albums = additions(ownAsRead)
        // If the cloud read failed but a computer adds tracks, the wall shows them, so the failure
        // message is cleared.
        if !albums.isEmpty { wallStanding = .showing }
        await settleHome()
    }

    // ── home ──

    /// Works out the home screen from the shelf and the play counts.
    ///
    /// Run again when the counts arrive from the account. Before that, the device only knows about
    /// what it has played itself.
    public func settleHome() async {
        // One reading of the log for the whole screen, so the rows and the quick selection
        // cannot disagree about which record was played most.
        let played = await plays.everythingPlayed()
        self.played = played

        // Read here, before the records are looked at. Everything after this line runs after the
        // last `await`, so the records, the playlists and the shelf come from the same moment.
        let listened = await radioListens.top(QuickPicks.count)

        // A collection being opened has no records yet. The open step settles home itself once they
        // arrive. This state is read after the `await` above, because a switch can start during it.
        if case .reading = wallStanding { return }

        let shelf = HomeAlbums.of(albums, played: played)
        let songs = HomeSongs.mostPlayed(albums, played: played, count: QuickPicks.count)

        // The stations heard most, on every device. Not shown on a borrowed shelf: the listening
        // belongs to the borrower, and the collection belongs to someone else.
        let heard = viewing == .own ? listened : []
        homeStations = Dictionary(heard.map { ($0.station.uuid, $0.station) },
                                  uniquingKeysWith: { first, _ in first })

        // A radio on the song played most, and on the next one by somebody else.
        let byId = Dictionary(albums.flatMap(\.tracks).map { ($0.rpmId, $0) }, uniquingKeysWith: { first, _ in first })
        let radios = QuickPicks.radioSeeds(songs.compactMap { id in
            byId[id].map { track in
                let albumArtist = track.tags?.albumArtist ?? ""
                return (id: id, act: albumArtist.isEmpty ? (track.artist ?? "") : albumArtist)
            }
        })

        home = HomeScreen.build(shelf: shelf, songs: songs,
                                lists: HomeLists.offered(playlists, on: viewing),
                                stations: heard.map(\.station.uuid), draw: homeDraw, radios: radios)
    }

    /// Reads the collection's playlists if they have not been read, and works home out again with
    /// them. Safe after a switch: ``readPlaylists(sayingWhyItFailed:)`` drops an answer for a
    /// collection no longer on screen.
    private func settleHomeLists() async {
        await showPlaylists()
        guard !albums.isEmpty else { return }
        await settleHome()
    }

    /// Syncs the play counts and the station log in both directions. Runs at launch and when the
    /// app returns to the front.
    public func syncPlays() async {
        guard await auth.isSignedIn else { return }
        await PlaysSync.run(log: plays, client: cloud, mine: playDevice.id)
        await StationListensSync.run(log: radioListens, client: cloud)

        // Counts that arrive after home is settled change the answer for every row, so home is
        // worked out again.
        if !albums.isEmpty { await settleHome() }
    }

    // ── the playlists ──

    public private(set) var playlists: [PlaylistSet] = []
    public private(set) var playlistStanding: ReadStanding = .reading

    /// Whether the playlist tree has been read in this session.
    private var playlistsRead = false

    /// The cut of generated lists last sent by the computer (`CloudMoodLists`). It is kept so that
    /// stepping to the next slice is local arithmetic, not a network round trip.
    private var moodCut: CloudMoodLists?

    /// Which slice of each generated list this device is on.
    private var moodReadings = GeneratedListReadings()

    /// The shelf the kept cut belongs to.
    private var moodCutShelf: CloudShelf?

    /// The kept cut when it belongs to the shelf on screen, for a song radio to read which
    /// moods each song is in. See ``startRadio(on:)``.
    var radioMoods: CloudMoodLists? { moodCutShelf == viewing ? moodCut : nil }

    /// Every song the listener has marked, newest first. Read each time it is used, so a song
    /// marked a moment ago is included.
    public var favoriteTracks: [CloudTrack] { library.marks.marked(in: albums) }

    /// Reads the playlist tree once per session.
    public func showPlaylists() async {
        guard !playlistsRead else { return }
        await loadPlaylists()
    }

    /// The first read of the tree, and the read behind the Try again button.
    public func loadPlaylists() async {
        playlistStanding = .reading
        await readPlaylists(sayingWhyItFailed: true)
    }

    /// Reads the tree again without clearing what is on screen. If the read fails, the current
    /// lists stay.
    public func rereadPlaylists() async {
        guard playlistsRead else { return await loadPlaylists() }
        await readPlaylists(sayingWhyItFailed: false)
    }

    /// Whether this generated list has another slice to step to.
    public func hasAnotherList(_ set: PlaylistSet) -> Bool {
        guard set.origin == .generated, let cut = moodCut else { return false }

        let id = GeneratedLists.storeId(of: set)
        guard let list = cut.lists.first(where: { $0.id == id }) else { return false }

        return list.shows > 0 && list.trackIds.count > list.shows
    }

    /// Shows the next slice of one generated list. Nothing is fetched: the cut is already held in
    /// memory.
    public func newGeneratedList(_ set: PlaylistSet) {
        guard set.origin == .generated,
              let cut = moodCut,
              let shelf = moodCutShelf,
              shelf.ownerId == viewing.ownerId
        else { return }

        moodReadings.step(GeneratedLists.storeId(of: set))

        let tracks = albums.flatMap(\.tracks)
        let generated = GeneratedLists.sets(
            cut, against: tracks, shelf: shelf, readings: moodReadings.all)

        playlists = playlists.filter { $0.origin != .generated } + generated
    }

    private func readPlaylists(sayingWhyItFailed: Bool) async {
        // Read once, so the rows and the heading describe the same collection.
        let shelf = viewing

        do {
            // Both are requested at once. A failure of the cut must not fail the read: `moodLists`
            // returns nil for a 404, and any other error is dropped so the stored lists still load.
            async let stored = cloud.playlists(shelf)
            async let cut: CloudMoodLists? = try? await cloud.moodLists(shelf)

            let held = try await stored
            let generated = await cut
            guard shelf.ownerId == viewing.ownerId else { return }

            // Resolved against the tracks in memory. The shelf is the same for both reads: a
            // borrowed collection's lists name that owner's tracks.
            let tracks = albums.flatMap(\.tracks)

            moodCut = generated
            moodCutShelf = shelf

            playlists = PlaylistSet.resolve(held, against: tracks, shelf: shelf)
                + (generated.map {
                    GeneratedLists.sets($0, against: tracks, shelf: shelf,
                                        readings: moodReadings.all)
                } ?? [])

            playlistsRead = true
            playlistStanding = .showing
        } catch RPMError.notServed {
            // An older API that does not support shared collections returns the reader's own tree
            // instead. The message says so.
            guard sayingWhyItFailed else { return }
            playlistStanding = .trouble(Loc.get("Rpm_Share_NotServed"))
        } catch let error as RPMError {
            guard sayingWhyItFailed else { return }
            playlistStanding = .trouble(error.userMessage(refused: Loc.get("Rpm_Playlists_Error")))
        } catch {
            guard sayingWhyItFailed else { return }
            playlistStanding = .trouble(Loc.get("Rpm_Playlists_Error"))
        }
    }

    // ── writing a playlist ──

    /// Built on each call, because it captures the current shelf lookup.
    private var writer: PlaylistWriter {
        let shelves = library.shelves
        return PlaylistWriter(store: cloud, shelfOf: { shelves.shelf(of: $0) })
    }

    /// Makes a playlist. Answers a sentence when it failed, nil when it is done.
    public func makePlaylist(name: String, in folder: [String], tracks: [CloudTrack]) async -> String? {
        do {
            let made = try await writer.create(name: name, folder: folder, tracks: tracks)

            // The new list is added locally instead of being read back from the store.
            playlists.append(made)
            return nil
        } catch let refused as PlaylistWriteError {
            return refused.userMessage
        } catch let error as RPMError {
            return error.userMessage(refused: Loc.get("Rpm_Playlists_CreateFailed"))
        } catch {
            return Loc.get("Rpm_Playlists_CreateFailed")
        }
    }

    /// Puts songs into a playlist that exists.
    /// - Parameter whenAlreadyThere: what happens to a song the list already holds. The caller
    ///   decides. See ``PlaylistWriter/AlreadyThere``.
    public func addToPlaylist(_ set: PlaylistSet, tracks: [CloudTrack],
                              whenAlreadyThere: PlaylistWriter.AlreadyThere) async -> String? {
        do {
            let added = try await writer.add(to: set, tracks: tracks,
                                             whenAlreadyThere: whenAlreadyThere)

            // Nothing was added. The song was already in this playlist.
            guard !added.isEmpty else { return Loc.get("Rpm_PlaylistPick_AlreadyIn", set.name) }

            // Appended to the copy held in memory. The stamp is not changed, because the next write
            // reads the listing again.
            if let at = playlists.firstIndex(where: { $0.id == set.id }) {
                playlists[at] = PlaylistSet(
                    id: set.id, name: set.name, tracks: set.tracks + added,
                    missing: set.missing, folder: set.folder, stamp: set.stamp,
                    shelf: set.shelf, origin: set.origin)
            }
            return nil
        } catch let refused as PlaylistWriteError {
            return refused.userMessage
        } catch let error as RPMError {
            return error.userMessage(refused: Loc.get("Rpm_PlaylistPick_Failed"))
        } catch {
            return Loc.get("Rpm_PlaylistPick_Failed")
        }
    }

    /// Changes the order of a playlist. The copy in memory is changed first, and put back if the
    /// store refuses. `to` is the index where the moved track is inserted, after it is removed
    /// from `from`.
    @discardableResult
    public func reorderPlaylist(_ set: PlaylistSet, from: Int, to: Int) async -> String? {
        guard let at = playlists.firstIndex(where: { $0.id == set.id }), from != to
        else { return nil }

        var tracks = set.tracks
        guard tracks.indices.contains(from), tracks.indices.contains(to) else { return nil }

        let carried = tracks.remove(at: from)
        tracks.insert(carried, at: to)

        let was = playlists[at]
        playlists[at] = set.with(tracks: tracks)

        do {
            let stamp = try await writer.reorder(set, tracks: tracks)

            if let now = playlists.firstIndex(where: { $0.id == set.id }) {
                playlists[now] = set.with(tracks: tracks, stamp: stamp)
            }
            return nil
        } catch let refused as PlaylistWriteError {
            playlists[at] = was
            return refused.userMessage
        } catch {
            playlists[at] = was
            return Loc.get("Rpm_Playlists_OrderFailed")
        }
    }

    // ── whose collection is on the wall ──

    /// The collection on screen, which is not always the account's own. Every read of a collection
    /// names which one. No default is used.
    public private(set) var viewing: CloudShelf = .own

    public private(set) var shelfRows: [ShelfRow] = []

    /// Who each owner is, read once. An owner whose profile could not be read is not stored, so the
    /// next read asks again.
    private var faces: [String: PeerFace] = [:]

    private var received: [CloudShare] = []

    /// Whether the shares have been read in this session. Until then, ``received`` is not a
    /// real answer.
    private var sharesKnown = false

    /// Whether `shelf` is still shared with this account, according to the last shares read. The
    /// account's own shelf is always shared, and so is every shelf before the first read has
    /// answered. A failed read never reports a share as removed.
    public func isShared(_ shelf: CloudShelf) -> Bool {
        shelf.isOwn || !sharesKnown || received.contains { $0.ownerId == shelf.ownerId }
    }

    /// Reads who shares with this account, and their profiles. Each update is checked against the
    /// app still being signed in, so profile names from a previous account are not kept after
    /// sign-out.
    public func readShares() async {
        await readOwnFace()

        let answered = try? await cloud.shares()
        guard standing == .showing else { return }

        // A failed read changes nothing. An outage is not an empty list. Treated as empty, it would
        // remove every shared collection until the next read.
        if let answered {
            received = answered.received
            sharesKnown = true
        }
        let held = received

        for share in held where faces[share.ownerId] == nil && !share.ownerId.isEmpty {
            // Not `try?`: a failed read must not be stored as a profile with no name. The owner is
            // asked again next time.
            let answered: RPMProfile?
            do { answered = try await community.publicProfile(userId: share.ownerId) }
            catch { continue }

            guard standing == .showing else { return }

            var face = PeerFace.nobody
            if let profile = answered, !profile.displayName.isEmpty {
                face = PeerFace(displayName: profile.displayName,
                                avatar: community.avatar(for: profile),
                                supporter: profile.supporter)
            }

            faces[share.ownerId] = face
        }

        drawShelves()
    }

    /// The picture and name of the signed-in account. `.nobody` until read.
    private var ownFace: PeerFace = .nobody

    private func readOwnFace() async {
        guard let mine = try? await community.profile(), standing == .showing else { return }

        ownFace = PeerFace(displayName: mine.displayName,
                           avatar: community.avatar(for: mine),
                           supporter: mine.supporter)
        drawShelves()
    }

    private func drawShelves() {
        shelfRows = SharedShelves.rows(received: received, faces: faces, viewing: viewing,
                                       ownName: Loc.get("Rpm_Share_OwnLibrary"),
                                       unknownName: Loc.get("Rpm_Share_Unknown"),
                                       ownFace: ownFace)
    }

    /// The number of the latest switch. A second pick can arrive while the first is still loading,
    /// so only the latest one is applied.
    private var switching = 0

    /// Whether a collection is still arriving: from the pick until home is settled with its
    /// playlists row. Only the switch that set it may clear it.
    public private(set) var shelfArriving = false

    /// The longest time the cover stays up for the playlists row after the rest of home is settled.
    private static let listsWait = Duration.milliseconds(2500)

    /// Opens a collection. The wall, the playlists and the artwork then load, because each one
    /// reads which shelf is being viewed.
    public func open(_ shelf: CloudShelf) async {
        guard shelf.ownerId != viewing.ownerId else { return }

        switching += 1
        let mine = switching

        viewing = shelf
        drawShelves()
        shelfArriving = true

        albums = []
        playlists = []
        playlistsRead = false
        playlistStanding = .reading
        wallStanding = .reading

        let read = await library.albums(shelf)
        guard mine == switching else { return }

        place(read, of: shelf)
        wallStanding = await settled(albums, of: shelf)

        await settleHome()
        guard mine == switching else { return }

        // The cover is removed when the playlists row is ready, or after `listsWait`, whichever
        // comes first. Both check that their switch is still the current one.
        let arrived = { [weak self] in
            guard let self, mine == self.switching else { return }
            self.shelfArriving = false
        }
        Task {
            await self.settleHomeLists()
            arrived()
        }
        Task {
            try? await Task.sleep(for: Self.listsWait)
            arrived()
        }

        // A borrowed shelf's classical marks belong to its owner. Its hearts are not read.
        // A heart on a borrowed record belongs to this account.
        guard shelf.isOwn else {
            await readClassical(shelf)
            return
        }

        await readMarks()
    }

    /// Decides what an empty result means. An empty array can mean the shelf is empty or that it
    /// could not be reached. Only the library knows which, so it is asked. See
    /// ``CloudLibrary/reached(_:)``.
    private func settled(_ read: [CloudAlbum], of shelf: CloudShelf) async -> ReadStanding {
        guard read.isEmpty, await !library.reached(shelf) else { return .showing }
        return .trouble(Loc.get("Rpm_Library_Error"))
    }

    /// Whose collection is on the wall, or nil for the account's own.
    public var lender: String? {
        guard !viewing.isOwn else { return nil }
        return shelfRows.first { $0.shelf.ownerId == viewing.ownerId }?.name ?? Loc.get("Rpm_Share_Unknown")
    }

    // ── the marked songs ──

    /// Whether a song belongs to this account. A song on a borrowed shelf cannot be marked or
    /// filed.
    /// The check is made on the song itself, because the queue can still hold a borrowed record
    /// after the reader returns to their own wall.
    public func isTrackMine(_ track: CloudTrack) -> Bool {
        shelves.shelf(of: track.rpmId).isOwn
    }

    public func isTrackMarked(_ track: CloudTrack?) -> Bool {
        guard let track else { return false }
        return library.marks.isMarked(track.rpmId)
    }

    /// Marks a song, or clears the mark. The change is shown before the network call and undone if
    /// the call fails. Returns whether the store accepted it.
    @discardableResult
    public func mark(_ track: CloudTrack, _ on: Bool) async -> Bool {
        let at = UtcTicks.now
        library.marks.note(track.rpmId, favorite: on, at: at)

        do {
            try await cloud.setFavorite(rpmId: track.rpmId, favorite: on, favoritedUtcTicks: at)
            return true
        } catch {
            library.marks.note(track.rpmId, favorite: !on, at: at)
            return false
        }
    }

    // ── the marked records ──

    public func isMarked(_ album: CloudAlbum) -> Bool { markKeys(of: album).contains(where: marks.contains) }

    /// Whether a record on a shelf is shown as works and movements. There is no default shelf,
    /// because on a borrowed shelf the answer comes from the owner.
    public func isClassical(_ album: CloudAlbum, on shelf: CloudShelf) -> Bool {
        classical.isClassical(album.tracks, on: shelf)
    }

    /// The keys a record's mark can be stored under, best first: the album hash that the desktop
    /// app writes, in each spelling.
    private func markKeys(of album: CloudAlbum) -> [String] {
        AlbumArtKey.spellings(.cover, for: album.tracks)
    }

    /// Marks a record, or clears the mark. The change is shown before the network call and undone
    /// if the call fails. A mark is stored under the best key. A clear removes it from every key it
    /// is stored under.
    public func mark(_ album: CloudAlbum, _ on: Bool) async {
        let spellings = markKeys(of: album)
        let keys = on ? Array(spellings.prefix(1)) : spellings.filter(marks.contains)

        for key in keys {
            set(key, on)

            do {
                try await cloud.putAlbumMark(albumKey: key, favorite: on,
                                             favoritedUtcTicks: UtcTicks.now)
            } catch {
                set(key, !on)
            }
        }
    }

    private func set(_ key: String, _ on: Bool) {
        if on { marks.insert(key) } else { marks.remove(key) }
    }

    /// This account's marks: the hearts, and the classical records on its own shelf. If the read
    /// fails, the marks already held are kept.
    private func readMarks() async {
        let era = marksEra
        guard let held = try? await cloud.albumMarks(.own), era == marksEra else { return }

        marks = Set(held.filter(\.favorite).map(\.albumKey))
        classical.file(held, for: .own)
    }

    /// A borrowed shelf's classical records, as its owner marked them.
    private func readClassical(_ shelf: CloudShelf) async {
        let era = marksEra
        guard let held = try? await cloud.albumMarks(shelf), era == marksEra else { return }

        classical.file(held, for: shelf)
    }
}
