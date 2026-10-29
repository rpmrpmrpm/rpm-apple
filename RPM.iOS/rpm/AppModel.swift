import Foundation
import os
import SwiftUI
import RPMKit
import RPMLibrary
import RPMArt
import RPMDesign
import RPMAudio
import RPMRadio
import RPMCast
import RPMUI
import RPMSession

/// Everything the app is made of, built once.
///
/// The composition root. Each of these parts does one thing and none of them
/// knows how to find the others. This keeps `RPMKit`, `RPMLibrary` and `RPMArt`
/// testable without a phone: the wiring is here, in the one file that cannot be
/// tested without a phone.
@MainActor
@Observable
final class AppModel {
    static let accounts = URL(string: "https://accounts.rpmrpmrpm.com/")!
    static let api = URL(string: "https://api.rpmrpmrpm.com")!

    let auth: AuthClient
    let cloud: RPMCloudClient

    /// Who other people are. This is the only part of the community side that the phone uses:
    /// a shared collection belongs to somebody, and a row that cannot name them says
    /// "Shared library".
    let community: RPMCommunityClient
    /// Send feedback and the crash reports: the scope, the outbox and the consent prompt.
    let diagnostics: Diagnostics

    /// What Wikipedia says about a record or an artist, for the text on the album and artist
    /// pages. It uses the same route as the desktop app: the API's papers, then Wikidata and
    /// Wikipedia in the phone's language.
    let articles: ArticleStore

    /// How many times all users have played each song on a record, for Popular tracks on the
    /// artist page. It asks the API's `metadata/plays`, the route that the desktop app's sweep uses.
    let worldPlays: WorldPlays
    let library: CloudLibrary
    let artwork: ArtworkStore

    /// The pictures of the playlists. The desktop app draws them and this head cannot.
    /// It is a separate store and not a part of `artwork`; see `PlaylistPictures`.
    let listPictures: PlaylistPictures

    /// Pictures of the artist, for the stage. It is a separate store, because it answers a different
    /// question from the sleeves and is the only part of the app that is looked up by
    /// name; see `BackdropStore`.
    let backdrops: BackdropStore

    /// The same photographs, at the size that the artists wall draws them. It is a second store
    /// and not a part of `backdrops`, because the two need different things from
    /// one catalogue; see `ArtistPortraits`.
    let portraits: ArtistPortraits

    let player: Player

    /// The albums downloaded to this phone, and the transfers that bring more. The player reads
    /// its book before it signs anything, so a downloaded record plays with no network.
    let downloads: AlbumDownloads

    /// The lock screen, the control centre and the headset button. It is held for the lifetime of
    /// the app, because it consists of the command targets and the session observers.
    private let remote: RemoteControl

    /// The account's library as the screens show it: the wall, home, the playlists, the shares,
    /// the marks and the quota. Shared with the TV; see `RPMSession`.
    let session: LibrarySession

    /// The words of what is playing.
    let words: LyricsLookup

    /// The station directory.
    let radio: StationSearch

    /// What is playing, with both of its pictures, and the lock screen kept in step with it.
    let record: NowPlayingRecord

    /// Whose shelf each record is on. The library holds it and the artwork reads it,
    /// because a borrowed collection has its own covers.
    var shelves: TrackShelves { session.shelves }

    // ── what the screen is ──

    typealias Standing = AccountStanding

    var standing: AccountStanding { session.standing }

    /// The browser sheet. It is held for the lifetime of the app so that it can be closed when the
    /// poll finishes, and not when the person notices that the poll is done.
    private let browser = SocialSignIn()
    var albums: [CloudAlbum] { session.albums }

    var wallStanding: LibraryPage.Standing { session.wallStanding }

    private(set) var trouble: String?

    /// A message for the sign-in screen that is not an error: the account has been deleted.
    /// The next sign-in attempt clears it.
    private(set) var notice: String?

    /// Which records are classical, filed by shelf. See ``ClassicalMarks``.
    var classical: ClassicalMarks { session.classical }

    /// Who is signed in, for the screen that says so.
    var who: Session? { session.who }

    /// What the account holds. It is read after the wall is shown.
    var quota: CloudQuota? { session.quota }

    /// The two rates, and which network the phone is on. They are held here because together
    /// they give one number, and the player uses that number.
    let prefs = Prefs()

    /// What this phone has played, and what the listener's other devices have played. It is held
    /// here because two parts use it: the player, which counts, and the home screen, which reads.
    let plays = PlayLog()

    /// What has been heard on the radio, on this phone and on the listener's other devices. It is
    /// held here for the same two users as the play log: the player, which counts, and the home
    /// screen.
    let radioListens = RadioListens(file: RadioListens.defaultFile)

    var homeStations: [String: RadioStation] { session.homeStations }
    var home: HomeScreen? { session.home }
    var played: [String: PlayLog.Played] { session.played }

    /// The one place where the app asks how far it can reach. It is held here and not made where
    /// it is needed: the gate inside every client uses it, and two of these would give two
    /// different answers.
    let reach = NetworkReach()

    /// The same reading, on the main actor, because a view cannot read a lock.
    ///
    /// **The state is `reach.now`; this is the copy that the screen draws.** Only
    /// ``watchTheLine()`` keeps the two the same. If this is set anywhere else, the banner and
    /// the gate disagree.
    private(set) var reading: Reach = .unknown

    /// How much space the kept sleeves use on the phone. It is read when the screen that
    /// offers to clear them is drawn, and not before, because it walks a directory.
    private(set) var cachedBytes: Int64 = 0

    /// The version of this build, for the About card.
    var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    /// Where a user goes to become a supporter.
    static let becomeSupporter = RpmSite.becomeSupporter

    /// What the account may choose between. It comes from the quota that the meter already
    /// fetches, because the phone has no supporter service to ask.
    var offer: AudioLadder.RateOffer {
        guard let quota else { return .unread }
        return .of(isSupporter: quota.supporter)
    }

    /// Tells the player what to ask for, based on the network the phone is on and what the
    /// account may have.
    ///
    /// It is called wherever either of those changes, and the player does not read it. The
    /// player signs an address on a background thread, and a preference read there would read
    /// main-actor state from another thread.
    func settleTheRate() {
        player.kilobits = prefs.kilobits(on: reading, offer: offer)
    }

    /// Whether records are levelled. The setting is changed only here, so
    /// what is stored and what the engine levels by cannot disagree. The engine reads it
    /// for every block, so a change reaches the record that is already playing.
    var levelling: NormalizeMode {
        get { prefs.levelling }
        set {
            prefs.levelling = newValue
            player.normalize.mode = newValue
        }
    }

    /// Whether records marked classical are levelled too. It is off by default, as on the
    /// desktop. As with ``levelling``, the setting is changed only here.
    var levelsClassical: Bool {
        get { prefs.levelsClassical }
        set {
            prefs.levelsClassical = newValue
            player.normalize.includeClassical = newValue
        }
    }

    // ── the line ──

    /// Starts watching the network, and keeps ``reading`` alongside it.
    ///
    /// **The stream is taken before the reading is read.** `changes` carries changes only.
    /// If the stream is registered first, a path change that arrives between the two lines is
    /// buffered and not lost. If the reading is read first and the stream is taken second, a
    /// change in that gap is lost.
    private func watchTheLine() {
        let changes = reach.changes

        // `path` and not `now`: this is what the person is told and what the rate is
        // chosen from, and it must be the system's own answer. `now` belongs to the gate, and it
        // also includes what the last request found out. That is right for a
        // socket and wrong for a banner.
        reading = reach.path
        reach.begin()

        Task { [weak self] in
            for await settled in changes {
                guard let self else { return }

                let was = self.reading
                self.reading = settled

                // The network came back, or the phone joined Wi-Fi. What to ask the store for
                // changes with it, and the next track that is signed uses the new answer.
                self.settleTheRate()

                if !was.isOnline, settled.isOnline { await self.theLineCameBack() }
                if was.isOnline, !settled.isOnline { self.theLineWentAway() }
            }
        }
    }

    /// Asks again when the network comes back.
    ///
    /// **It repeats whatever is in trouble now.** It reads the current standing and does not
    /// use a note made when something failed. A flag set at the failure could be wrong by the
    /// time the network returns, because the person may have switched shelves, opened a
    /// playlist or signed out in between, and each of those needs a different set of reads.
    ///
    /// Nothing here removes what is on the screen. Each read leaves the standing unchanged
    /// until it has an answer, so a second failure is not visible.
    private func theLineCameBack() async {
        if case .trouble = wallStanding { await refresh() }
        if case .trouble = playlistStanding { await rereadPlaylists() }

        // Never answered, which is different from answered with nothing. A quota that failed to
        // read limits the rate to the free level and greys out the user's own setting.
        if quota == nil { await readQuota(.nextLaunch) }

        // The user's own shelf is always a row, so an empty list means that the read failed.
        if shelfRows.isEmpty { await readShares() }

        player.theLineCameBack()

        // The session continues by itself when there is a network. It cannot sign the tracks
        // that were not asked for yet.
        await downloads.pump()
    }

    /// The network went away.
    ///
    /// **Only what is playing is decided here.** A streamed record stops, and the player holds
    /// the reason. A record read from the phone continues to play. The root view decides which
    /// screen to show, and it uses the same reading.
    private func theLineWentAway() {
        player.theLineWentAway()
    }

    /// The system woke the app to pass on finished downloads.
    ///
    /// The screen may not have been built when the app wakes like this, so nothing here waits
    /// for it. The account is read from the keychain, and the session, which is made with this
    /// model, delivers what finished and asks for the next tracks.
    func wokenForDownloads() async {
        await auth.load()
        guard await auth.isSignedIn else { return }
        await downloads.begin()
    }

    func readCacheSize() async {
        cachedBytes = await artwork.bytesOnDisk()
    }

    func clearCache() async {
        await artwork.emptyTheDisk()
        cachedBytes = 0
    }

    init() {
        auth = AuthClient(base: Self.accounts, keychain: Keychain(), reach: reach)

        let transport = Transport(base: Self.api, tokens: auth, reach: reach)
        cloud = RPMCloudClient(transport: transport)
        community = RPMCommunityClient(transport: transport)
        diagnostics = Diagnostics(transport: transport)
        articles = ArticleStore(
            client: PapersClient(transport: transport, reach: reach),
            languages: Encyclopedia.languages(preferred: Locale.preferredLanguages),
            directory: ArticleStore.inCaches())
        worldPlays = WorldPlays(client: cloud)

        library = CloudLibrary(source: cloud, marks: FavoriteMarks(), storeRoot: Self.storeRoot)
        artwork = ArtworkStore(source: cloud)
        listPictures = PlaylistPictures(source: cloud)
        backdrops = BackdropStore(source: cloud)
        portraits = ArtistPortraits(source: cloud)

        words = LyricsLookup(lrclib: LrcLibClient(reach: reach), cloud: cloud)
        radio = StationSearch(directory: RadioBrowserClient(reach: reach),
                              radioState: RadioState(record: RadioRepositoryClient(transport: transport)))

        // Made before the player, which asks its classical marks about every track it hands over.
        session = LibrarySession(auth: auth, cloud: cloud, community: community,
                                 library: library, plays: plays, radioListens: radioListens,
                                 playDevice: PlayDevice(store: .standard),
                                 additions: LibrarySession.nothingAdded)

        // **The cover that the other room shows is not the one on this screen.** A
        // television gets a JPEG small enough to travel as a message. The store is asked for
        // it and the player does not read a file, because a record played from somebody
        // else's shelf has no file on this phone. See `RoomCover`.
        //
        // The closure is built from the two values it needs and not from `self`, which does not
        // exist yet here and would make a reference cycle through the player.
        let covers = artwork
        let whoseShelf = library.shelves

        // **The download setting, and the store decides the rest.** The store limits a free
        // account whatever is asked, as it does for a stream. Low Data Mode is not
        // applied: a download is a choice to spend the data, and the setting is
        // what the user chose to spend it on. `settles` stops a stored value that is not on
        // the ladder from being sent.
        //
        // A rate that the store has not made is not downloaded live: `make` asks the store to
        // make it, and `AlbumDownloads` downloads the stored object when it exists.
        let prefs = self.prefs
        let book = DownloadBook(root: DownloadBook.standard)
        let signer = cloud
        downloads = AlbumDownloads(
            book: book, reach: reach,
            sign: { rpmId, kilobits in
                let said = try await signer.stream(.own, rpmId: rpmId, kilobits: kilobits)
                return (said.url, said.kilobits, said.kind)
            },
            make: { rpmIds, kilobits in
                try await signer.makeRenditions(rpmIds, kilobits: kilobits)
            },
            rate: { AudioLadder.RateOffer.unread.settles(on: prefs.rateForDownloads) })

        let classical = session.classical

        player = Player(source: cloud, shelves: whoseShelf,
                        copies: book, nearby: NothingNearby(), reach: reach,
                        levelling: prefs.levelling,
                        levelsClassical: prefs.levelsClassical,
                        classical: { classical.isClassical($0, on: whoseShelf.shelf(of: $0.rpmId)) },
                        cover: { await RoomCoverArt.jpeg(of: $0, from: covers, on: whoseShelf,
                                                         fitting: CastCover.limit) })
        remote = RemoteControl(player: player, reach: reach)
        speakerChoice = Speakers(player: player)
        record = NowPlayingRecord(session: session, artwork: artwork, player: player,
                                  remote: remote, edge: 600)

        watchTheLine()

        // The rate is read off the quota, so a quota read settles it again.
        session.onQuotaRead = { [weak self] in self?.settleTheRate() }

        // AVFoundation does not tell the lock screen what this app's player is
        // doing: the lock screen shows what it was last given. So a pause that it was not told
        // about leaves a pause key over a stopped track and a clock that still runs.
        player.onPlaybackChanged = { [weak remote] in remote?.showPosition() }

        // A play that counted. It is written down here and not by the counter, which stays
        // synchronous so that its readings cannot arrive out of order; see PlayCounter. The log
        // does not depend on the order, because a play is an increment and a stamp is a maximum.
        player.onPlayCounted = { [weak self] counted in
            guard let self else { return }
            Task { await self.plays.note(rpmId: counted.rpmId, at: counted.at) }
        }

        // Radio heard, in parts. The same rule applies: the counter stays synchronous, and the log
        // does not depend on the order, because the parts add up. See StationCounter.
        player.onStationHeard = { [weak self] heard in
            guard let self else { return }
            Task {
                await self.radioListens.note(heard.station, seconds: heard.seconds,
                                             newTune: heard.newTune, at: heard.at)
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

            record.show(station: station)
        }

        // **The volume keys follow the room, not the key that picked it.** If they were tied to
        // the cast call and the stop-casting call, they would stay on after every other way that
        // a cast can end (the room going away, stop, a failure). A hidden `MPVolumeView` stays on
        // with them, and it hides the system's own volume display. When nothing is cast, the
        // volume belongs to the phone and iOS shows its own bar for it.
        player.onCastChanged = { [weak self] room in
            guard let self else { return }

            guard room != nil else { keys.stop(); return }

            keys.start { [weak self] step in
                guard let self else { return }
                self.player.setRoomVolume(step: self.player.roomVolume + step)
            }
        }
    }

    /// Logs how old the running binary is, once, at launch.
    ///
    /// **This shows whether the running build contains the latest change.** Xcode
    /// compiles the file on disk, but its editor buffer can overwrite that file: a buffer
    /// with an unsaved keystroke in it is written over an edit made underneath it, and
    /// the compiler then compiles the old version. Xcode can also link a local
    /// package that it compiled before the sources changed. Neither case shows any warning,
    /// and both look like a fix that did not work.
    ///
    /// The date of the executable settles it in one log line. A build from four minutes ago
    /// is the one just made. A build from an hour ago is not, whatever the editor shows.
    private func sayWhichBuildThisIs() {
        let log = Logger(subsystem: "com.rpm.player", category: "launch")

        guard let path = Bundle.main.executablePath,
              let made = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate]
                       as? Date
        else { return }

        let ago = Date().timeIntervalSince(made)
        let clock = Date.FormatStyle(date: .omitted, time: .standard)

        let minutes = Int(ago / 60)
        log.notice("built \(made.formatted(clock), privacy: .public), \(minutes, privacy: .public) minutes ago, version \(self.version, privacy: .public)")
    }

    /// Where the catalogue is kept between launches. It is in application support and not in
    /// the caches: the system may remove the caches, and then the library would be fetched
    /// again on the next launch for no reason.
    private static var storeRoot: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true)
    }

    // ── the way in ──

    func start() async {
        sayWhichBuildThisIs()
        await auth.load()

        #if DEBUG
        // A way to open the app already signed in, so that a script can look at screens.
        // The simulator takes no synthetic taps, so otherwise a person is needed to get
        // past this gate.
        //
        // This is for debug builds only, and only when the environment sets it. A release
        // build does not read these variables, and no credential is stored here.
        if await !auth.isSignedIn,
           let email = ProcessInfo.processInfo.environment["RPM_SIGN_IN_EMAIL"],
           let password = ProcessInfo.processInfo.environment["RPM_SIGN_IN_PASSWORD"] {
            try? await auth.signIn(email: email, password: password)
        }
        #endif

        guard await auth.isSignedIn else { session.showSignedOut(); return }

        // What has been played, from the disk and then from the account. This happens before the
        // wall and not after it. The home screen's rows depend on listening, and a screen drawn
        // before the counts arrive would say that this listener has played nothing.
        await plays.load()
        Task { await self.syncPlays() }

        // Which stations are hidden and whether a logo changed. The first request skips the URL
        // cache, so a restart shows a change made in the admin. See RadioState.
        Task { await self.radio.radioState.refresh() }

        await show(ground: .nextLaunch)
    }

    /// Works out the home screen from the shelf and the play counts. See ``LibrarySession``.
    func settleHome() async { await session.settleHome() }

    /// One pass over the play counts and the saved stations, in both directions. It runs at launch
    /// and again when the app returns to the foreground.
    func syncPlays() async {
        await session.syncPlays()
        await syncSavedStations()
    }

    /// One pass over the saved stations, so that a heart pressed here reaches the other devices
    /// and the hearts from those devices reach this one. See ``FavoritesSync``.
    func syncSavedStations() async {
        guard let userId = who?.userId else { return }
        await FavoritesSync.run(favorites: saved, client: cloud, userId: userId)
    }

    /// A message for the person, shown where the sign-in errors are shown.
    func report(_ what: String) { trouble = what }

    func signIn(email: String, password: String) async {
        trouble = nil
        notice = nil
        do {
            try await auth.signIn(email: email, password: password)
            await show(ground: .adoptNow)
        } catch let error as RPMError {
            trouble = error.userMessage(refused: Loc.get("Rpm_SignIn_Failed"))
        } catch {
            trouble = Loc.get("Rpm_SignIn_Failed")
        }
    }

    /// Signs in with Apple or Google.
    ///
    /// The accounts service returns a URL and a one-time session id, the browser sheet takes the
    /// person through the provider, and the website sends the sheet back to `rpm://auth` with a
    /// one-time code. The app collects the tokens with that code and its poll secret, so a sign-in
    /// finished in someone else's browser never reaches this app.
    func signIn(with provider: String) async {
        trouble = nil
        notice = nil

        do {
            let started = try await auth.startSocialSignIn(provider: provider, returnTo: .app)
            let back = try await browser.authenticate(started.url)
            browser.dismiss()

            let query = URLComponents(url: back, resolvingAgainstBaseURL: false)?.queryItems ?? []
            guard query.first(where: { $0.name == "sessionId" })?.value == started.sessionId,
                  let code = query.first(where: { $0.name == "code" })?.value, !code.isEmpty
            else { throw RPMError.signInIncomplete }

            try await auth.finishSocialSignIn(sessionId: started.sessionId, code: code)
            await show(ground: .adoptNow)
        } catch is CancellationError {
            // The person closed the browser. This is not a failure and needs no message.
        } catch let error as RPMError {
            trouble = error.userMessage(refused: Loc.get("Login_Unable"))
        } catch {
            trouble = Loc.get("Login_Unable")
        }
    }

    /// Deletes the account: the accounts service deletes it and the cloud erases the library within
    /// two hours. On success this phone signs out as the Sign out key does, and the sign-in screen
    /// says what happened. It returns nil when done, and a sentence for the panel when not.
    func deleteAccount(confirmEmail: String) async -> String? {
        switch await auth.deleteAccount(confirmEmail: confirmEmail) {
        case .deleted:
            await signOut()
            notice = Loc.get("Account_DeletedBody")
            return nil
        case .emailRefused:
            return Loc.get("Account_DeleteEmailRefused")
        case .failed:
            return Loc.get("Account_DeleteFailed")
        }
    }

    func signOut() async {
        player.forget()
        record.forget()

        // The files are this account's music, and the next person who signs in on this phone
        // must not find them.
        downloads.forgetEverything()

        await auth.signOut()
        await artwork.forget()
        await listPictures.forget()
        await backdrops.forget()
        await portraits.forget()
        worldPlays.forget()
        sharedStations.forget()
        cachedBytes = 0
        pickingLibrary = false

        // This is last, because it shows the sign-in screen and removes the supporter ground.
        await session.forget()
    }

    // ── the library ──

    private func show(ground rule: GroundRule) async {
        await session.show(rule) {
            LaunchClock.mark("records on screen")

            // Behind the wall: the transfers that the system continued while the app was away,
            // and any albums that are still to come.
            Task { await self.downloads.begin() }
        }

        // This is after the quota, because what the account may ask for comes from the quota. It
        // also runs when the quota read failed, so that the rate then follows the network alone.
        settleTheRate()

        #if DEBUG
        // For looking at the screens that exist only while something is playing.
        // Debug builds only; see `start()`.
        if ProcessInfo.processInfo.environment["RPM_PLAY_FIRST"] != nil,
           let first = albums.first {
            await play(first, from: 0, tapped: .list)
        }

        if ProcessInfo.processInfo.environment["RPM_OPEN_FIRST_ALBUM"] != nil,
           let first = albums.first {
            openedByScript = first.key
        }

        // One record named by its title, for a screenshot of a chosen record and not the
        // first on the wall. It uses the title and not the key, because the key is built from the
        // record's folder, which a script cannot read.
        func titled(_ name: String) -> CloudAlbum? {
            albums.first { $0.album.caseInsensitiveCompare(name) == .orderedSame }
        }
        // RPM_PLAY_FROM picks the song, counted from 0 in the record's order.
        if let name = ProcessInfo.processInfo.environment["RPM_PLAY_ALBUM"],
           let album = titled(name) {
            let from = Int(ProcessInfo.processInfo.environment["RPM_PLAY_FROM"] ?? "") ?? 0
            await play(album, from: min(max(from, 0), album.tracks.count - 1), tapped: .list)
        }
        if let name = ProcessInfo.processInfo.environment["RPM_OPEN_ALBUM_TITLED"],
           let album = titled(name) {
            openedByScript = album.key
        }

        // A script cannot reach a station in any other way: the dial needs a
        // finger, and the simulator has none. Debug builds only; see `start()`.
        if ProcessInfo.processInfo.environment["RPM_TUNE_FIRST"] != nil {
            await searchStations("", genre: nil, country: nil)
            if let first = stations.first { tune(first) }
        }

        // A script cannot reach casting in any other way either: the picker is a
        // sheet and a speaker is a row in it. This plays the first record and sends it to
        // the first speaker that answers. Debug builds only; see `start()`.
        if ProcessInfo.processInfo.environment["RPM_CAST_FIRST"] != nil,
           let album = albums.first {
            await play(album, from: 0, tapped: .list)
            try? await Task.sleep(for: .seconds(3))

            await findSpeakers()
            let log = Logger(subsystem: "com.rpm.player", category: "cast")
            log.notice("found \(self.speakers.map(\.name).joined(separator: ", "), privacy: .public)")

            // A group is preferred to a single speaker, because half of a stereo pair refuses to
            // be cast to on its own, which is a real answer and not a fault. A name in
            // RPM_CAST_FIRST picks one, for testing with a particular room.
            let wanted = ProcessInfo.processInfo.environment["RPM_CAST_FIRST"] ?? ""

            if let speaker = speakers.first(where: { $0.name == wanted })
                          ?? speakers.first(where: { $0.isGroup }) ?? speakers.first {
                await cast(to: speaker)
                log.notice("cast to \(speaker.name, privacy: .public): \(self.castTrouble ?? "no trouble", privacy: .public)")
            }

            // Coming home needs its own check: the pump has to be released from the
            // room's pacing, and the needle has to be put back where the room was
            // and not where the decoder had advanced to.
            if ProcessInfo.processInfo.environment["RPM_COME_HOME"] != nil {
                try? await Task.sleep(for: .seconds(12))
                log.notice("coming home from \(self.player.position.seconds, format: .fixed(precision: 2), privacy: .public)s")

                let began = Date()
                await stopCasting()

                for _ in 0..<40 {
                    if self.player.isPlaying, !self.player.isBusy { break }
                    try? await Task.sleep(for: .milliseconds(250))
                }

                let took = Date().timeIntervalSince(began)
                log.notice("home after \(took, format: .fixed(precision: 2), privacy: .public)s at \(self.player.position.seconds, format: .fixed(precision: 2), privacy: .public)s")
            }
        }

        // A speaker named by address and not found on the network: the fake speaker that the
        // tests start (`HoldASpeaker`), so that a script can watch a cast without
        // any sound. With `RPM_REMOTE_KEYS`, keys are pressed at set times in the
        // way that the lock screen presses them, so they can be pressed while the app is in the
        // background. Debug builds only; see `start()`.
        if let host = ProcessInfo.processInfo.environment["RPM_CAST_HOST"],
           let colon = host.lastIndex(of: ":"), let port = Int(host[host.index(after: colon)...]),
           let album = albums.first {
            let log = Logger(subsystem: "com.rpm.player", category: "cast")
            await play(album, from: 0, tapped: .list)
            try? await Task.sleep(for: .seconds(3))

            await cast(to: CastDevice(id: "fake", name: "fake", model: "fake",
                                      host: String(host[..<colon]), port: port, isGroup: false))
            log.notice("debug: cast to \(host, privacy: .public): \(self.castTrouble ?? "no trouble", privacy: .public)")

            // `RPM_REMOTE_KEYS=30:pause,40:play,50:pause`: each pair is the seconds after the
            // cast, and the key.
            if let keys = ProcessInfo.processInfo.environment["RPM_REMOTE_KEYS"] {
                let player = self.player
                let began = ContinuousClock.now
                Task {
                    for pair in keys.split(separator: ",") {
                        let bits = pair.split(separator: ":")
                        guard bits.count == 2, let at = Double(bits[0]) else { continue }
                        try? await Task.sleep(until: began.advanced(by: .seconds(at)))

                        let state = UIApplication.shared.applicationState
                        log.notice("debug: remote \(String(bits[1]), privacy: .public); app state \(state == .background ? "background" : state == .inactive ? "inactive" : "active", privacy: .public); wantsToPlay \(player.wantsToPlay)")
                        switch bits[1] {
                        case "pause": Task { @MainActor in player.pause() }
                        case "play": Task { @MainActor in player.resume() }
                        default: Task { @MainActor in player.toggle() }
                        }
                    }
                }
            }
        }

        if ProcessInfo.processInfo.environment["RPM_PICK_LIBRARY"] != nil {
            await readShares()
            pickingLibrary = true
        }

        if ProcessInfo.processInfo.environment["RPM_FILE_FIRST"] != nil {
            await showPlaylists()
            filing = albums.first?.tracks.first
        }

        if let asked = ProcessInfo.processInfo.environment["RPM_TUNE"] {
            await searchStations(asked, genre: nil, country: nil)
            if let first = stations.first { tune(first) }
        }
        #endif
    }

    func refresh() async { await session.refresh() }

    private func readQuota(_ rule: GroundRule) async { await session.readQuota(rule) }

    /// Plays the record that a search result belongs to, starting on that song. A track on
    /// its own would be a queue of one, and a user who searches for a song does not want
    /// silence after it.
    func play(_ track: CloudTrack) async {
        let key = AlbumGrouping.key(for: track)

        guard let album = albums.first(where: { $0.key == key }),
              let at = album.tracks.firstIndex(where: { $0.rpmId == track.rpmId })
        else { return }

        await play(album, from: at, tapped: .song)
    }

    // ── playing ──

    /// What is playing, as the deck sees it: the record and both of its pictures, in one value
    /// that is replaced whole. See ``NowPlayingRecord``.
    var playing: PlayingRecord? { record.playing }

    /// Only the sleeve.
    var playingArt: CoverArt? { record.art }

    func play(_ album: CloudAlbum, from: Int, tapped: Tapped) async {
        await play(album.tracks, from: from, tapped: tapped)
    }

    func shuffle(_ album: CloudAlbum) async {
        await shuffle(album.tracks)
    }

    /// Any list of songs: a record, a playlist, the marked songs. It replaces the queue,
    /// or asks first if the user changed the songs that are still to come. See ``queueQuestion``.
    func play(_ tracks: [CloudTrack], from: Int, tapped: Tapped) async {
        songRadio = nil
        switch player.replacing(with: tracks, from: from, tapped: tapped) {
        case .clear(let start): await startPlaying(start)
        case .asks(let question): queueQuestion = question
        }
    }

    /// The song radio that is on, or nil. Dropped by every other way of starting a queue, so
    /// starting an album or a list ends the radio without saying so. See `SongRadioRun`.
    @ObservationIgnored private var songRadio: SongRadioRun?

    /// "Start radio" on a song: it plays now, and the queue keeps filling with songs like
    /// whichever one is playing. It replaces the queue without asking, as the computer does:
    /// a radio is a new thing to listen to, not a list to keep the old one beside.
    func startRadio(_ track: CloudTrack) {
        let start = switch player.replacing(with: [track], from: 0, tapped: .song) {
        case .clear(let clear): clear
        case .asks(let question): question.discard()
        }
        let run = session.startRadio(on: track)
        songRadio = run
        Task {
            await startPlaying(start)
            run.topUp(player)
        }
    }

    /// The question that is asked before a queue that the user changed is replaced. It is set
    /// while the question is on screen. Cancel sets it back to nil and nothing starts.
    var queueQuestion: QueueQuestion?

    /// Discard, or Play now and keep the queue: the start that the answer chose.
    func answer(_ start: QueueStart) async {
        queueQuestion = nil
        await startPlaying(start)
    }

    /// Marks the row, claims the audio session and starts. This happens after the question and
    /// not before it, because Cancel must not mark a row or stop the audio of another app.
    private func startPlaying(_ start: QueueStart) async {
        asked = start.firstTrack?.rpmId
        defer { asked = nil }

        await claim().value
        await player.start(start)
    }

    /// A row of the queue itself. It moves inside the queue, so it never asks.
    func jump(to at: Int) async {
        asked = player.queue.indices.contains(at) ? player.queue[at].rpmId : nil
        defer { asked = nil }

        await claim().value
        await player.jump(to: at)
    }

    /// The track that the user has just tapped, from the tap until the player has it.
    ///
    /// **The tap is a separate state**, and for most of a second it is the only state
    /// there is. A start goes through a claim on the audio session and a signature from the
    /// store before the player can say what is playing, and a list that waits for that
    /// answer shows nothing in the meantime. The tapped row would have no mark and no
    /// highlight (a finger is over it), and nothing to show that the tap was received.
    private(set) var asked: String?

    /// Which row has the playing mark: the one that was tapped, or the one under the
    /// needle. Every list reads this and not `player.current`, so all of them show the mark
    /// on the tap and none of them needs to know why.
    var nowPlaying: String? { asked ?? player.current?.rpmId }

    func shuffle(_ tracks: [CloudTrack]) async {
        guard !tracks.isEmpty else { return }
        await play(tracks.shuffled(), from: 0, tapped: .list)
    }

    /// The Shuffle key on the Now playing page: the queue in another order. It is a reorder
    /// and not a new list, so it never asks, and it counts as a change afterwards.
    func shuffleTheQueue() async {
        await claim().value
        await player.shuffleTheQueue()
    }

    /// Claims the audio session before anything reaches the engine, and not before
    /// there is something to play. An app that takes the session at launch stops
    /// whatever the person was already listening to.
    ///
    /// The caller must wait for it. Nothing may reach the engine before it
    /// finishes, because a stream that starts under the session the app was given, and not
    /// the one it asked for, is silenced by the ring switch and stops when the
    /// screen locks.
    ///
    /// **It is asked every time and not remembered here.** The session is given back at the
    /// end of a queue, which removes the card from the lock screen. A claim remembered here
    /// would then answer "already yours" for a session that this app no longer holds.
    /// `RemoteControl` knows whether the session is held, and only it can know, so the
    /// question goes there. It returns the claim that is in progress if there is one, so two
    /// taps close together wait for the same round trip.
    private func claim() -> Task<Void, Never> {
        Task { [remote] in await remote.begin() }
    }

    // ── the words ──

    /// The words of what is playing, or `.empty` if there are none.
    var lyrics: LyricSheet { words.sheet }

    /// Whether an answer is still to come.
    var lookingUpLyrics: Bool { words.looking }

    /// Reads the words for what is playing, once. The player screen asks for it while it is shown.
    func readLyrics() async {
        await words.read(player.current, on: shelves.shelf(of: player.current?.rpmId))
    }

    // ── the speaker in another room ──

    /// The speakers on the network and the picker's state (`Speakers`, shared with the TV app). The
    /// cover that a receiver's screen shows comes from `RoomCoverArt`, which is passed to the
    /// player above.
    let speakerChoice: Speakers

    /// What answered the last search. It is empty until the user opens the picker.
    var speakers: [CastDevice] { speakerChoice.found }
    var lookingForSpeakers: Bool { speakerChoice.looking }

    /// What went wrong with the last attempt, for the sheet to show.
    var castTrouble: String? { speakerChoice.trouble }

    func findSpeakers() async { await speakerChoice.look() }
    func cast(to speaker: CastDevice) async { await speakerChoice.cast(to: speaker) }
    func stopCasting() async { await speakerChoice.stop() }

    /// The phone's own volume keys. The app uses them for **exactly** as long as a speaker is
    /// connected. See `player.onCastChanged`, which switches them.
    private let keys = VolumeKeys()

    // ── the playlists ──

    var playlists: [PlaylistSet] { session.playlists }
    var playlistStanding: PlaylistsPage.Standing { session.playlistStanding }

    /// Every song that the listener has marked, newest first.
    var favoriteTracks: [CloudTrack] { session.favoriteTracks }

    func showPlaylists() async { await session.showPlaylists() }
    func loadPlaylists() async { await session.loadPlaylists() }
    func rereadPlaylists() async { await session.rereadPlaylists() }
    func hasAnotherList(_ set: PlaylistSet) -> Bool { session.hasAnotherList(set) }
    func newGeneratedList(_ set: PlaylistSet) { session.newGeneratedList(set) }

    func makePlaylist(name: String, in folder: [String], tracks: [CloudTrack]) async -> String? {
        await session.makePlaylist(name: name, in: folder, tracks: tracks)
    }

    func addToPlaylist(_ set: PlaylistSet, tracks: [CloudTrack],
                       whenAlreadyThere: PlaylistWriter.AlreadyThere) async -> String? {
        await session.addToPlaylist(set, tracks: tracks, whenAlreadyThere: whenAlreadyThere)
    }

    @discardableResult
    func reorderPlaylist(_ set: PlaylistSet, from: Int, to: Int) async -> String? {
        await session.reorderPlaylist(set, from: from, to: to)
    }

    // ── the queue, which is the one list this phone owns ──

    func removeFromQueue(_ rows: IndexSet) {
        player.remove(Array(rows))
    }

    /// Plays this song after the one that is playing.
    ///
    /// **Nothing starts.** A song sent up next is a song asked for later, as in the Uno
    /// head and in the desktop app's drawer. ``RPMAudio/Player/insertNext(_:)`` tells the
    /// engine, because the record that the engine already holds to play next was chosen for
    /// the order that this call has just changed.
    func playNext(_ track: CloudTrack) {
        player.insertNext([track])
    }

    // ── whose collection is on the wall ──

    /// The collection on screen, which is not always the user's own.
    var viewing: CloudShelf { session.viewing }

    var shelfRows: [ShelfRow] { session.shelfRows }

    /// Whether the picker is shown.
    var pickingLibrary = false

    /// Reads which users share with this account, and who they are.
    func readShares() async { await session.readShares() }

    /// Whether a collection is still arriving. See ``LibrarySession/shelfArriving``.
    var shelfArriving: Bool { session.shelfArriving }

    /// Opens a collection.
    func open(_ shelf: CloudShelf) async {
        pickingLibrary = false
        await session.open(shelf)
    }

    /// Whose collection is on the wall, or nil for the user's own.
    var lender: String? { session.lender }

    // ── the radio ──

    var directory: RadioBrowserClient { radio.directory }
    let saved = RadioFavorites()

    /// The saved stations of the shared libraries opened this session. See ``SharedStations``.
    let sharedStations = SharedStations()

    /// The saved stations that the radio shows: the listener's own, or the owner's while a shared
    /// library is open, which the hearts do not change.
    var savedStations: SavedStations {
        let rules = radio.radioState.rules
        // The admin's edits are applied, as for every station list.
        return sharedStations.saved(on: viewing, account: who?.userId ?? "", own: saved.stations)
            .edited(by: rules)
    }

    /// Reads the saved stations of the open shared library's owner again. It does nothing for the
    /// listener's own library. It runs each time the radio is shown.
    func readSharedStations() async {
        guard let userId = who?.userId else { return }
        let cloud = self.cloud
        await sharedStations.read(viewing, account: userId) { try await cloud.stationFavorites(of: $0) }
    }

    /// What rpm has decided about stations. Every station logo reads it through the environment.
    var radioState: RadioState { radio.radioState }

    var stations: [RadioStation] { radio.stations }
    var countries: [RadioFacet] { radio.countries }
    var radioStanding: RadioPage.Standing { radio.standing }

    func searchStations(_ asked: String, genre: String?, country: String?) async {
        await radio.search(asked, genre: genre, country: country)
    }

    func tune(_ station: RadioStation) {
        // This runs a step later than it reads, because the claim has to finish first and the
        // dial calls this from a plain button. A highlight that appears one frame late is
        // better than a station that plays under the wrong session.
        let claimed = claim()
        Task { await claimed.value; player.tune(station) }

        radio.reportTuned(station)
    }

    func save(_ station: RadioStation) {
        // The saved stations of a shared library belong to its owner, and the radio shows no heart
        // there.
        guard savedStations.mayChange else { return }
        saved.toggle(station)
        Task { await syncSavedStations() }
    }

    // ── the songs somebody loves ──

    func isTrackMine(_ track: CloudTrack) -> Bool { session.isTrackMine(track) }

    func isTrackMarked(_ track: CloudTrack?) -> Bool { session.isTrackMarked(track) }

    /// Marks the song that is playing, or clears the mark.
    func markTrack(_ on: Bool) async {
        guard let track = player.current else { return }
        await mark(track, on)
    }

    func mark(_ track: CloudTrack, _ on: Bool) async {
        await session.mark(track, on)
    }

    // ── filing a song ──

    /// The record that a script asked to open, set when the library has arrived and the
    /// key is known. Debug builds only; see `start()`.
    private(set) var openedByScript: String?

    /// The song that the picker is open for, or nil while the picker is closed.
    ///
    /// **It is the song and not a flag**, because the picker needs to know only which song it
    /// is filing.
    var filing: CloudTrack?

    // ── the records somebody loves ──

    func isMarked(_ album: CloudAlbum) -> Bool { session.isMarked(album) }

    func isClassical(_ album: CloudAlbum, on shelf: CloudShelf) -> Bool {
        session.isClassical(album, on: shelf)
    }

    func mark(_ album: CloudAlbum, _ on: Bool) async { await session.mark(album, on) }
}
