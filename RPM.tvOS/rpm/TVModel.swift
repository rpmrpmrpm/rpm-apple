import Foundation
import os
import SwiftUI
import UIKit
import RPMKit
import RPMLibrary
import RPMArt
import RPMAudio
import RPMCast
import RPMRadio
import RPMSession
import RPMSharing
import RPMSharedUI

/// Everything the TV app consists of, built once: the shared modules connected together, and the
/// few things that only the TV does (sign-in with a QR code, the home network and the rules for
/// the remote).
///
/// The library, home, playlists, shares, marks, plays and lyrics belong to `RPMSession`, which is
/// the same code that the phone runs. This class contains what the TV adds or does differently.
@MainActor
@Observable
final class TVModel {
    static let accounts = URL(string: "https://accounts.rpmrpmrpm.com/")!
    static let api = URL(string: "https://api.rpmrpmrpm.com")!

    let reach = NetworkReach()

    /// The network state that the screen shows. It is a copy of `reach.path` on the main actor,
    /// and only ``watchTheLine()`` changes it, as on the phone.
    private(set) var reading: Reach = .unknown
    let auth: AuthClient
    let cloud: RPMCloudClient
    let community: RPMCommunityClient
    let articles: ArticleStore
    /// How often the world has played each song, used for an artist's popular tracks.
    let worldPlays: WorldPlays
    let library: CloudLibrary
    let artwork: ArtworkStore
    let listPictures: PlaylistPictures
    let portraits: ArtistPortraits
    let backdrops: BackdropStore
    let player: Player
    /// The speakers on the network that the player can play on, as on the phone.
    let speakers: Speakers
    let remote: RemoteControl
    let session: LibrarySession
    let words: LyricsLookup
    let stations: StationSearch
    let record: NowPlayingRecord
    let homeNetwork: HomeNetwork
    let radio: TVRadio
    /// What each card of home's banner shows, prepared before the card is on the screen.
    let bannerLooks = BannerLooks()
    let settings = TVSettings(store: .standard)
    /// The star ratings that were given to records on this TV. They are stored on this TV only.
    /// Matches `AlbumRatings` in the Android TV app.
    let ratings = AlbumRatings()
    let plays = PlayLog()
    /// The last queue. It is stored between runs and restored at the next launch.
    let keptQueue = KeptQueueFile(folder: KeptFiles.folder)
    let radioListens = RadioListens(file: RadioListens.defaultFile)

    /// The tracks on the computers, for the player, reached through `homeNetwork`.
    private let nearby: HomeNearby

    init() {
        auth = AuthClient(base: Self.accounts, keychain: Keychain(), reach: reach)
        let transport = Transport(base: Self.api, tokens: auth, reach: reach)
        cloud = RPMCloudClient(transport: transport)
        community = RPMCommunityClient(transport: transport)
        worldPlays = WorldPlays(client: cloud)
        articles = ArticleStore(
            client: PapersClient(transport: transport, reach: reach),
            languages: Encyclopedia.languages(preferred: Locale.preferredLanguages),
            directory: ArticleStore.inCaches())

        // The catalogue copy is in the Caches folder, because an Apple TV app has no other folder
        // where it may keep files.
        library = CloudLibrary(source: cloud, marks: FavoriteMarks(), storeRoot: KeptFiles.folder)
        // The caches are larger than on the phone. A TV screen shows two or three times as many
        // cards, and the 4K Apple TV draws a card at 512 pixels (one megabyte when decoded).
        // 192 MB of sleeves hold home, one screen of the wall and the pages opened from them.
        // 64 MB of portraits hold the artists a few screens deep. A portrait that is removed from
        // the cache is loaded from the network again, not from the disk.
        artwork = ArtworkStore(source: cloud, mostBytes: 192 * 1024 * 1024)
        listPictures = PlaylistPictures(source: cloud)
        portraits = ArtistPortraits(source: cloud, mostBytes: 64 * 1024 * 1024)
        backdrops = BackdropStore(source: cloud)

        words = LyricsLookup(lrclib: LrcLibClient(reach: reach), cloud: cloud)
        stations = StationSearch(directory: RadioBrowserClient(reach: reach, agent: "RPM/1.0 (tvOS)"),
                                 radioState: RadioState(record: RadioRepositoryClient(transport: transport)))

        // The home network is created before the session, because the session adds the tracks of
        // the computers to the account's own shelf.
        let auth = self.auth
        let home = HomeNetwork(store: .standard, keys: Keychain(service: "com.rpm.player.peer"),
                               deviceName: UIDevice.current.name,
                               account: { await auth.current?.userId ?? "" })
        homeNetwork = home
        session = LibrarySession(
            auth: auth, cloud: cloud, community: community, library: library,
            plays: plays, radioListens: radioListens, playDevice: PlayDevice(store: .standard),
            additions: { read in
                let catalogs = Array(home.here.values)
                guard !catalogs.isEmpty else { return read }
                return AlbumWall.group(HomeMerge.merge(read.flatMap(\.tracks), catalogs))
            })

        nearby = HomeNearby(home: home)
        let classical = session.classical
        let whoseShelf = library.shelves
        let covers = artwork
        player = Player(source: cloud, shelves: whoseShelf, copies: NothingDownloaded(),
                        nearby: nearby, reach: reach,
                        levelling: settings.levelling, levelsClassical: settings.levelsClassical,
                        classical: { classical.isClassical($0, on: whoseShelf.shelf(of: $0.rpmId)) },
                        // The cover that a speaker's own screen shows while the TV casts to it.
                        cover: { await RoomCoverArt.jpeg(of: $0, from: covers, on: whoseShelf,
                                                         fitting: CastCover.limit) })
        remote = RemoteControl(player: player, reach: reach)
        speakers = Speakers(player: player)
        record = NowPlayingRecord(session: session, artwork: artwork, player: player,
                                  remote: remote, edge: 800)
        radio = TVRadio(search: stations, listens: radioListens, reach: reach)

        wire()
    }

    /// Connects the callbacks between the parts, after all of them exist.
    private func wire() {
        RemoteKeys.wire(self)
        // The streaming rate that the account may use is known after its quota is read.
        session.onQuotaRead = { [weak self] in self?.settleTheRate() }
        homeNetwork.onCatalogsChanged = { [weak self] in
            guard let self else { return }
            Task { await self.session.additionsChanged() }
        }

        player.onPlaybackChanged = { [weak remote] in remote?.showPosition() }

        player.onPlayCounted = { [weak self] counted in
            guard let self else { return }
            Task {
                await self.plays.note(rpmId: counted.rpmId, at: counted.at)
                self.syncPlaysSoon()
            }
        }

        player.onStationHeard = { [weak self] heard in
            guard let self else { return }
            Task {
                await self.radioListens.note(heard.station, seconds: heard.seconds,
                                             newTune: heard.newTune, at: heard.at)
                self.syncPlaysSoon()
            }
        }

        player.onTrackChanged = { [weak self] track in
            guard let self else { return }
            Task { await self.record.show(track) }
            // A song the radio queued is playing: the radio queues the songs after it.
            Task { @MainActor in self.songRadio?.topUp(self.player) }
        }

        player.onStationChanged = { [weak self] station in
            guard let self else { return }
            if let station { lastStation = station }
            record.show(station: station)
        }
    }

    // MARK: Signing in

    var standing: AccountStanding { session.standing }

    /// The state of the QR sign-in.
    private(set) var signIn: SignInState = .starting
    private var signingIn: Task<Void, Never>?

    func start() async {
        // Compile the room shader programs before the first screen with a room needs them.
        Task { await RoomView.compileAhead() }
        // The single reading of the network state that the gate of every client uses.
        watchTheLine()
        settleTheRate()
        await auth.load()

        #if DEBUG
        // Lets a script open the app already signed in, because the simulator's remote cannot be
        // scripted past a QR code. Debug only: a release build does not read these values.
        if await !auth.isSignedIn,
           let email = ProcessInfo.processInfo.environment["RPM_SIGN_IN_EMAIL"],
           let password = ProcessInfo.processInfo.environment["RPM_SIGN_IN_PASSWORD"] {
            try? await auth.signIn(email: email, password: password)
        }
        #endif

        homeNetwork.start()

        guard await auth.isSignedIn else {
            session.showSignedOut()
            beginSignIn()
            return
        }

        await plays.load()
        Task { await self.syncPlays() }
        Task { await self.stations.radioState.refresh() }

        await show(.nextLaunch)
    }

    private func show(_ rule: GroundRule) async {
        // The names and photos of this account and of the people who share with it, for the
        // sidebar and the collections. They are read when the session starts, as in the Android TV
        // app, and not when the collections are first opened.
        Task { await session.readShares() }
        await session.show(rule) {}
        radio.refresh()
    }

    /// Starts the QR sign-in. There is one code for each provider, and both are checked
    /// repeatedly until one finishes.
    func beginSignIn() {
        signingIn?.cancel()
        signingIn = Task { [weak self] in
            guard let self else { return }
            let flow = SignInFlow(auth: auth)
            let done = await flow.run { [weak self] said in self?.signIn = said }
            guard done, !Task.isCancelled else { return }
            await self.show(.adoptNow)
        }
    }

    func signOut() async {
        // This must come first. After this line the queue is not stored (the stop below triggers a
        // store) until the next account's own queue has been restored. This also allows that
        // account's queue to be restored in this run. A restore that is still reading the previous
        // account's file restores nothing and marks nothing.
        queueEra += 1
        queuePutBack = false
        playsWaiting?.cancel()
        playsWaiting = nil
        player.stop()
        lastStation = nil
        // Written through the same chain as every other store, after any write that is still
        // running.
        write(nil)
        await writing?.value
        record.forget()
        await auth.signOut()
        await artwork.forget()
        worldPlays.forget()
        await listPictures.forget()
        await portraits.forget()
        await backdrops.forget()
        bannerLooks.forget()
        radio.shared.forget()
        homeNetwork.forgetSessions()
        await session.forget()
        beginSignIn()
    }

    /// Called when the app returns to the foreground. The plays from other devices are downloaded,
    /// this device's plays are uploaded, and the playlists are read again. The library is also read
    /// again if it was last read a long time ago, because records may have been imported on the
    /// computer. A library that changed is redrawn through the session.
    func cameToTheFront() {
        guard standing == .showing else { return }
        Task { await syncPlays() }
        Task { await session.rereadPlaylists() }
        Task { await library.refreshOnResume() }
    }

    // MARK: Playing

    /// Plays `tracks` from the index `from`. The TV replaces the queue without asking, as the
    /// Android TV app does, because a remote control cannot show the phone's question.
    func play(_ tracks: [CloudTrack], from: Int) {
        guard tracks.indices.contains(from) else { return }
        songRadio = nil
        let start: QueueStart
        switch player.replacing(with: tracks, from: from, tapped: .list) {
        case .clear(let clear): start = clear
        case .asks(let question): start = question.discard()
        }
        Task {
            await remote.begin()
            await player.start(start)
        }
    }

    /// The song radio that is on, or nil. Dropped by every other way of starting a queue, so
    /// starting an album or a list ends the radio without saying so. See `SongRadioRun`.
    @ObservationIgnored private var songRadio: SongRadioRun?

    /// "Start radio" on a song: it plays now, and the queue keeps filling with songs like
    /// whichever one is playing.
    func startRadio(_ track: CloudTrack) {
        play([track], from: 0)
        let run = session.startRadio(on: track)
        songRadio = run
        // The first top-up waits for the song to be the one playing; the change of track asks
        // again in any case.
        Task {
            try? await Task.sleep(for: .seconds(1))
            run.topUp(player)
        }
    }

    func shuffle(_ tracks: [CloudTrack]) {
        guard !tracks.isEmpty else { return }
        play(tracks.shuffled(), from: 0)
    }

    func playNext(_ track: CloudTrack) {
        if player.queue.isEmpty { return play([track], from: 0) }
        player.insertNext([track])
        flash(Loc.get("Viz_QueueMovedNext", track.title ?? ""))
    }

    func addToQueue(_ track: CloudTrack) {
        if player.queue.isEmpty { return play([track], from: 0) }
        player.append([track])
        flash(Loc.get("Atv_AddedToQueue", track.title ?? ""))
    }

    /// Adds a whole record or list after the current song, in its own order, under its `name`.
    func playNext(_ tracks: [CloudTrack], named name: String) {
        guard !tracks.isEmpty else { return }
        if player.queue.isEmpty { return play(tracks, from: 0) }
        player.insertNext(tracks)
        flash(Loc.get("Viz_QueueMovedNext", name))
    }

    /// Adds a whole record or list at the end of the queue, in its own order, under its `name`.
    func addToQueue(_ tracks: [CloudTrack], named name: String) {
        guard !tracks.isEmpty else { return }
        if player.queue.isEmpty { return play(tracks, from: 0) }
        player.append(tracks)
        flash(Loc.get("Atv_AddedToQueue", name))
    }

    /// Plays a row of the queue.
    func jump(to at: Int) {
        Task {
            await remote.begin()
            await player.jump(to: at)
        }
    }

    // MARK: The network and the rate

    /// Starts watching the network and keeps ``reading`` up to date. The change stream is taken
    /// before the current state is read, so a change between the two is buffered and not lost.
    /// Matches `watchTheLine` on the phone.
    private func watchTheLine() {
        let changes = reach.changes
        reading = reach.path
        reach.begin()

        Task { [weak self] in
            for await settled in changes {
                guard let self else { return }
                let was = self.reading
                self.reading = settled
                if !was.isOnline, settled.isOnline { await self.theLineCameBack() }
                if was.isOnline, !settled.isOnline { self.player.theLineWentAway() }
            }
        }
    }

    /// Called when the network comes back. It repeats every request that is failing now. The
    /// check uses the current standing and not a note that was made when the request failed.
    /// Nothing on the screen is removed while the requests run.
    private func theLineCameBack() async {
        if case .trouble = session.wallStanding { await session.refresh() }
        if case .trouble = session.playlistStanding { await session.rereadPlaylists() }
        if session.quota == nil { await session.readQuota(.nextLaunch) }
        // The account's own collection is always a row, so an empty list means that the read
        // failed.
        if session.shelfRows.isEmpty { await session.readShares() }
        player.theLineCameBack()
    }

    /// Whether the account is a supporter of rpm. It is nil until the quota is read.
    var isSupporter: Bool? { session.quota.map(\.unlimited) }

    /// Whether the sung lyric line is highlighted word by word. It needs the setting and a
    /// supporter account, as on the desktop and in the Android TV app.
    var karaokeOn: Bool { settings.karaoke && isSupporter == true }

    /// The rates that the account may stream at: every rung for a supporter, one rung for a free
    /// account, and every rung before the quota is read (the store limits a free account to its
    /// rung in any case).
    var offer: AudioLadder.RateOffer {
        guard let quota = session.quota else { return .unread }
        return .of(isSupporter: quota.unlimited)
    }

    /// Sets the rate that the player requests, from the setting and the offer. It is called
    /// wherever either of them changes. A TV has a fixed network connection, so there is one
    /// setting and not the two settings of the phone.
    func settleTheRate() {
        player.kilobits = offer.settles(on: settings.kilobits)
    }

    /// Moves to the next rate that the account may use, in the offer's order (the original first).
    func nextQuality() {
        let rungs = offer.rungs
        guard rungs.count > 1 else { return }
        let at = rungs.firstIndex(of: offer.settles(on: settings.kilobits)) ?? 0
        settings.kilobits = rungs[(at + 1) % rungs.count]
        settleTheRate()
    }

    // MARK: Volume levelling

    /// Moves to the next levelling choice, in the desktop app's order (off, albums, tracks). This
    /// is the only place that changes the setting, so the stored value and the value that the
    /// engine uses cannot differ. The engine reads the value for every block, so the change
    /// applies at once to the record that is playing.
    func nextLevelling() {
        let all = NormalizeMode.allCases
        settings.levelling = all[((all.firstIndex(of: settings.levelling) ?? 0) + 1) % all.count]
        player.normalize.mode = settings.levelling
    }

    func switchLevelsClassical() {
        settings.levelsClassical.toggle()
        player.normalize.includeClassical = settings.levelsClassical
    }

    // MARK: Plays

    /// When plays were last sent.
    private var playsSent: ContinuousClock.Instant?
    /// The send that ``syncPlaysSoon()`` has scheduled.
    private var playsWaiting: Task<Void, Never>?

    /// The saved stations that the radio shows: the listener's own, or the owner's while a
    /// collection that another account shares is open. The heart buttons do not change the
    /// owner's stations (as in the Android TV app).
    var savedStations: SavedStations {
        radio.shared.saved(on: session.viewing, account: session.who?.userId ?? "", own: radio.saved.stations)
    }

    /// Reads the saved stations of the open shared collection's owner again. It does nothing for
    /// the listener's own collection. It runs each time the radio screen is shown.
    func readSharedStations() async {
        guard let userId = session.who?.userId else { return }
        let cloud = self.cloud
        await radio.shared.read(session.viewing, account: userId) { try await cloud.stationFavorites(of: $0) }
    }

    /// Downloads the plays of every device and uploads the plays of this one. It runs at launch,
    /// when the app returns to the foreground, and within five minutes of a play.
    func syncPlays() async {
        playsSent = .now
        await session.syncPlays()

        // Also synchronise the saved stations with the listener's other devices. See
        // `FavoritesSync`.
        if let userId = session.who?.userId {
            await FavoritesSync.run(favorites: radio.saved, client: cloud, userId: userId)
        }
    }

    /// Sends plays at most five minutes after a play is counted. Matches `TrackPlaysSync.soon` in
    /// the Android TV app. A TV can play for hours without leaving the foreground, and the phone
    /// sends its plays when it returns to the foreground. It is safe for two sends to overlap,
    /// because what is sent is a total that is written again.
    private func syncPlaysSoon() {
        guard playsWaiting == nil else { return }
        let wait = playsSent.map { max(.zero, $0 + .seconds(300) - .now) } ?? .zero
        playsWaiting = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard let self, !Task.isCancelled else { return }
            self.playsWaiting = nil
            await self.syncPlays()
        }
    }

    // MARK: The last queue

    /// Whether the signed-in account's queue has been restored. Until it has, nothing is stored:
    /// the player is empty at launch, and storing that would overwrite the queue that is about
    /// to be restored. It is false again from the start of a sign-out.
    private var queuePutBack = false

    /// Identifies the account session that a restore belongs to. Every sign-out increases it. A
    /// restore that began before a sign-out neither cues the previous account's queue nor marks
    /// the next account's queue as restored when its read returns.
    private var queueEra = 0

    /// The value of `queueEra` that a restore is running for, if one is running. It is separate
    /// from ``queuePutBack``, which must stay false until the restore has finished. The opening
    /// requests a restore on every change of home, and two requests during the file read would
    /// both pass a check of `queuePutBack`.
    private var puttingBack: Int?

    /// Restores the queue that the last run stored, once per run, when the library is ready. The
    /// tracks are paused at the stored position (``Player/cue(_:at:position:)``), so the player
    /// shows them and Play resumes them. A stored station becomes the station that the play key
    /// tunes. Only tracks that are still in the collection are restored. Nothing is restored if
    /// the track at the stored position has been removed.
    func putBackTheQueue() async {
        let era = queueEra
        guard !queuePutBack, puttingBack != era else { return }
        puttingBack = era
        defer { if puttingBack == era { puttingBack = nil } }

        // The account comes from the keychain's session and not from `session.who`, because the
        // session reads `who` after the screens are shown. If the account were empty, the restore
        // would mark itself as done with nothing restored, and the next store would write the
        // empty player over the stored queue. When nobody is signed in, the restore is not done:
        // the next change of home requests it again.
        guard let account = await auth.current?.userId else { return }
        let kept = await keptQueue.read(for: account)

        // A sign-out during the read ended this account's session: nothing is restored or marked.
        guard era == queueEra else { return }
        defer { if era == queueEra { queuePutBack = true } }

        // This check is after the read and not before it, because the user may have started
        // playback while the file was read, and the restore must not replace it.
        guard let kept, player.current == nil, player.station == nil else { return }

        switch kept {
        case .tracks(let tracks, let at, let seconds):
            let here = Dictionary(session.albums.flatMap(\.tracks).map { ($0.rpmId, $0) },
                                  uniquingKeysWith: { first, _ in first })
            guard here[tracks[at].rpmId] != nil else { return }
            let still = tracks.compactMap { here[$0.rpmId] }
            guard let needle = still.firstIndex(where: { $0.rpmId == tracks[at].rpmId }) else { return }
            await player.cue(still, at: needle, position: .seconds(seconds))
        case .station(let station):
            lastStation = station
        }
    }

    /// Stores what is playing now, or deletes the stored queue when nothing is playing. It is
    /// called when the queue changes, on pause, at intervals while playing, and when the app
    /// leaves the foreground.
    func keepTheQueue() {
        guard queuePutBack, let account = session.who?.userId else { return }

        let what: KeptQueue.What?
        if let station = player.station ?? (player.queue.isEmpty ? lastStation : nil) {
            what = .station(station)
        } else if let at = player.index, player.queue.indices.contains(at) {
            what = .tracks(player.queue, at: at, seconds: player.position.seconds)
        } else {
            what = nil
        }

        write(what.map { KeptQueue(account: account, what: $0) })
    }

    /// The write that is running. The next write waits for it.
    private var writing: Task<Void, Never>?

    /// Writes in the order in which they were requested. Separate tasks reach the file's actor in
    /// no guaranteed order, and an older queue that is written last would be the one that is
    /// restored.
    private func write(_ queue: KeptQueue?) {
        let before = writing
        writing = Task { [keptQueue] in
            await before?.value
            await keptQueue.write(queue)
        }
    }

    /// The station that was tuned last. The play key tunes it again after a stop, because a
    /// stopped station leaves nothing in the player to resume.
    private(set) var lastStation: RadioStation?

    /// The play key, on the remote or on a screen. It pauses and resumes playback, and tunes the
    /// last station again after a station was stopped.
    func togglePlay() {
        if player.current == nil, player.station == nil, let lastStation {
            tune(lastStation)
            return
        }
        Task {
            await remote.begin()
            player.toggle()
        }
    }

    /// Stops the station that is playing. It remains the last station, so the play key tunes it
    /// again.
    func stopStation() {
        player.stop()
    }

    /// The Stop key on the remote, handled as in the Android TV app. A station stops. A track
    /// pauses at its start, and the queue is kept.
    func stopKey() {
        if player.station != nil { return stopStation() }
        guard player.current != nil else { return }
        player.pause()
        _ = player.seek(to: .zero)
    }

    /// Moves the playback position by `seconds`, within the track.
    func skip(by seconds: Double) {
        guard player.current != nil, player.duration > .zero else { return }
        let to = min(max(player.position.seconds + seconds, 0), player.duration.seconds)
        _ = player.seek(to: .seconds(to))
    }

    func tune(_ station: RadioStation) {
        Task {
            await remote.begin()
            player.tune(station)
        }
        stations.reportTuned(station)
    }

    // MARK: The user's own collection

    func mark(_ track: CloudTrack, _ on: Bool) {
        Task {
            let title = track.title ?? ""
            let saved = await session.mark(track, on)
            switch (saved, on) {
            case (true, true): flash(Loc.get("Viz_FavoriteAdded", title))
            case (true, false): flash(Loc.get("Viz_FavoriteRemoved", title))
            case (false, true): flash(Loc.get("Tv_FavoriteFailed"))
            case (false, false): flash(Loc.get("Tv_UnfavoriteFailed"))
            }
        }
    }

    /// - Parameter again: what to do when the list already contains the song. It has no default
    ///   value: the menu asks the user first (``Screens/fileAgain``) and passes the answer.
    func file(_ track: CloudTrack, in set: PlaylistSet, whenAlreadyThere again: PlaylistWriter.AlreadyThere) {
        Task {
            if let trouble = await session.addToPlaylist(set, tracks: [track], whenAlreadyThere: again) {
                flash(trouble)
            } else {
                flash(Loc.get("Viz_PlaylistAdded", track.title ?? "", set.name))
            }
        }
    }

    func file(_ track: CloudTrack, inNew name: String) {
        let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !named.isEmpty else { return }
        Task {
            if let trouble = await session.makePlaylist(name: named, in: [], tracks: [track]) {
                flash(trouble)
            } else {
                flash(Loc.get("Viz_PlaylistAdded", track.title ?? "", named))
            }
        }
    }

    // MARK: The message line

    /// The result of the last write, shown along the bottom of the screen for a short time.
    private(set) var flashText: String?

    /// Counts the messages, so the same text shown twice is displayed twice.
    private(set) var flashCount = 0

    /// Fetches what home shows first, before the opening screen hands over, so that home appears
    /// complete and does not fill in after the opening has gone. Matches `fetchHomePictures` in
    /// the Android TV app. It fetches the banner's front card and both neighbour cards, complete
    /// (``BannerLooks``), and the pictures of the first twelve items of Quick selection, at the
    /// sizes that home draws them, because the stores use the size as part of the key. A picture
    /// that fails is skipped. All of this work is network and store time, off the main thread.
    /// The opening sets the limit for how long it waits (`TVRoot.handOver`). What has not arrived
    /// by then continues to load and fades in on home.
    func warmHome(scale: CGFloat) async {
        guard let home = session.home else { return }
        let strip = home.strip
        var onShow: [HomeFeature] = []
        if let plate = strip.first { onShow.append(plate) }
        if strip.count > 1 { onShow.append(strip[strip.count - 1]) }
        if strip.count > 2 { onShow.append(strip[1]) }

        let albums = Dictionary(session.albums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let quick = home.quickPicks.prefix(12)
        let songs = Set(quick.filter { $0.kind == .song || $0.kind == .radio }.map(\.key))
        let tracks = songs.isEmpty ? [:] : Dictionary(
            session.albums.lazy.flatMap(\.tracks).filter { songs.contains($0.rpmId) }.map { ($0.rpmId, $0) },
            uniquingKeysWith: { first, _ in first })

        let edge = PictureSize.pixels(96, scale: scale)
        var sleeves: [CloudAlbum] = []
        var lists: [PlaylistSet] = []
        var logos: [RadioStation] = []
        for pick in quick {
            switch pick.kind {
            case .album:
                if let album = albums[pick.key] { sleeves.append(album) }
            case .song, .radio:
                if let track = tracks[pick.key], let album = albums[AlbumGrouping.key(for: track)] { sleeves.append(album) }
            case .playlist:
                if let set = HomeLists.set(named: pick.key, in: session.playlists) { lists.append(set) }
            case .station:
                if let station = session.homeStations[pick.key] { logos.append(station) }
            }
        }

        // Each job is a separate task, and all start at once. The opening waits for all of them or
        // for the limit.
        let shelves = session.shelves
        let artwork = artwork
        let state = stations.radioState
        let reach = reading
        var jobs = [Task { await self.bannerLooks.prepare(onShow, model: self, scale: scale) }]
        for album in sleeves {
            let shelf = shelves.shelf(ofAlbum: album)
            jobs.append(Task { _ = await artwork.cover(for: album, on: shelf, edge: edge) })
        }
        for set in lists {
            jobs.append(Task { _ = await ListArt.load(set, edge: edge, model: self) })
        }
        for station in logos {
            jobs.append(Task { _ = await StationDress.dress(station, edge: 96, state: state, reach: reach) })
        }
        for job in jobs { await job.value }
    }

    /// Fetches the first cards of each of home's rows (its lists, then its records) after the
    /// opening has gone. The cards are fetched one at a time, in the background, so that scrolling
    /// down shows them already drawn. A row shows six cards and the edge of a seventh.
    func warmRows(scale: CGFloat) async {
        guard let home = session.home else { return }
        let albums = Dictionary(session.albums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let edge = PictureSize.pixels(Card.edge, scale: scale)
        for set in home.lists.compactMap({ HomeLists.set(named: $0, in: session.playlists) }).prefix(7) {
            _ = await ListArt.load(set, edge: edge, model: self)
        }
        for row in home.rows {
            for album in row.keys.prefix(7).compactMap({ albums[$0] }) {
                _ = await artwork.cover(for: album, on: session.shelves.shelf(ofAlbum: album), edge: edge)
            }
        }
    }

    /// Fetches an artist page's photograph and text while a screen that leads to the page is
    /// shown (the artist's record page or the player), so the page opens with them and not with
    /// the initial letter. If a credit names several artists, the first artist is also fetched,
    /// because the page opens for that artist.
    func warmArtist(_ credit: String, scale: CGFloat) async {
        guard !credit.isEmpty else { return }
        var names = [credit]
        if let first = ArtistCredit.first(credit), first != credit { names.append(first) }
        for name in names {
            _ = await portraits.portrait(of: name, edge: PictureSize.pixels(ArtistPage.photoEdge, scale: scale))
            _ = await articles.article(.artist(name))
        }
    }

    func flash(_ text: String) {
        flashText = text
        flashCount += 1
    }
}

/// The TV stores no downloads: every track comes from the cloud or from a computer on the
/// network.
struct NothingDownloaded: PhoneCopies {
    func copy(of rpmId: String) -> PhoneCopy? { nil }
}

/// The player's access to the computers on the home network.
///
/// A track on the account's own shelf that a paired computer holds, in a format that this device
/// can decode, is streamed from that computer while it is available. A failure marks the computer
/// as away for two minutes and drops its token, so the player's next request goes to the cloud.
@MainActor
final class HomeNearby: NearbyCopies {
    private let home: HomeNetwork

    init(home: HomeNetwork) {
        self.home = home
    }

    func address(of track: CloudTrack, on shelf: CloudShelf) async -> URL? {
        // A borrowed shelf belongs to another owner's cloud. The computers on this network hold
        // this account's music.
        guard shelf.isOwn, let computer = home.computer(holding: track.rpmId) else { return nil }
        do {
            return try await home.address(of: track.rpmId, on: computer)
        } catch {
            home.markAway(computer.key, at: computer.base)
            return nil
        }
    }

    func failed(_ address: URL) {
        guard let host = address.host, let port = address.port,
              let computer = home.found.values.first(where: { $0.address == host && $0.port == port })
        else { return }
        home.forgetToken(computer.key)
        home.markAway(computer.key, at: computer.base)
    }
}
