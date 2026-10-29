import SwiftUI
import RPMSharedUI
import RPMUI
import RPMDesign
import RPMLibrary
import RPMArt
import RPMAudio
import RPMKit

/// What the app opens on.
struct RootView: View {
    /// Created by the app delegate, not here. See `RPMDelegate`.
    @State private var model: AppModel

    init(model: AppModel) { _model = State(initialValue: model) }
    @Environment(\.displayScale) private var displayScale

    /// Whether the app is in the foreground.
    ///
    /// **It is read for one reason**: a playlist can be changed on the computer as well as on
    /// the phone, so a phone that was in the background holds an old copy. Returning to the
    /// foreground is the moment to read the playlists again. See `AppModel.rereadPlaylists`,
    /// which does this without removing what is already on the screen.
    @Environment(\.scenePhase) private var phase

    /// What is open on the albums view of the library: records, and artists opened from a
    /// record's artist line. The steps hold names, not copies of the data. See ``LibraryStep``.
    @State private var opened: [LibraryStep] = []

    /// Whether the player is shown over everything, and its position while the user drags it
    /// down.
    ///
    /// **One value, held here and not in the sheet.** Whether the screen is up and where it is
    /// are one fact. If the sheet kept the position, the position would outlive the showing it
    /// belongs to, and a player that was put away at the bottom would come back invisible.
    /// ``ScreenPull/raise()`` is the only way to show the player and it sets the position, so
    /// that state cannot occur.
    @State private var playing = ScreenPull()

    /// The height of the bottom bar of the app, reported by the chrome itself. Every page
    /// receives it. See `footRoom` and ``PageFoot``.
    @State private var chrome: CGFloat = 0

    /// The tab that is shown. The app opens on Home because it is the one screen that is about
    /// this listener and not about the way the collection is organised.
    @State private var tab: RPMTab = .home

    /// What is open on top of the home screen: records and lists that were tapped there. This is
    /// home's own stack, so a record opened from home slides in over it and slides back out to
    /// it, and the library's stacks are not changed.
    @State private var homePath: [HomeStep] = []

    enum HomeStep: Hashable {
        case album(String)
        case artist(String)
        case list(OpenList)
    }

    /// Whether the stage is shown, and the value that decides it.
    ///
    /// Turning the phone is not a navigation step: the stage appears over the current screen,
    /// and turning back leaves that screen as it was. `verticalSizeClass` is used and not the
    /// device orientation, because every iPhone gives the same value for it and it stays correct
    /// when the phone lies flat.
    @Environment(\.verticalSizeClass) private var vertical
    @State private var staged = false

    /// Which lists are open on the playlists tab. This stack is separate, so that a playlist
    /// pushed here is not still on screen after the user goes to the records.
    @State private var lists: [OpenList] = []

    /// A list, identified by name and not by a copy of its data. The queue changes while its
    /// page is open, and a stored playlist can be read again under an open page. The page is
    /// therefore drawn from the model each time, and this value only says which list to draw.
    enum OpenList: Hashable {
        case queue
        case favorites
        case playlist(String)
    }

    /// The reviews of each open record, by album key, and the key of the record whose review
    /// sheet is shown. They are held here and not in the page, because a page pushed onto a
    /// stack is rebuilt when the library under it changes, and its state would be lost.
    ///
    /// **There is one wall per key, not one wall for the page opened last.** Several album pages
    /// exist at the same time: one under another in a stack (Similar albums opens a record from
    /// a record), and one on home, which stays built under the other tabs. With a single wall,
    /// the page underneath would show the reviews of the page above it, because its own task
    /// does not run again when it becomes visible. Each page reads the wall of its own record.
    @State private var walls: [String: ReviewWall] = [:]
    @State private var writing: String?

    /// Whether the list of downloaded albums is up, over the profile tab.
    @State private var showingDownloads = false

    /// The open Send feedback sheet, with the screenshot taken just before it opened.
    @State private var feedback: FeedbackShot?

    /// Whether the wait mark is still shown over the wall. See the overlay below.
    @State private var covering = false

    /// Whether the home screen has drawn what it opens on: the banner's front card, with its
    /// sleeve drawn and its photograph requested. The page sets it and the launch hold reads it.
    /// It is cleared when the shell goes away, because a new shell is a new home screen.
    @State private var homeReady = false

    /// The longest time that the launch keeps the wait mark for the home screen, after the wall's
    /// own 400 ms. A photograph is a network request, and a slow one must not block the app. After
    /// this time the page is shown, and the card fades its photograph in when it arrives.
    private static let homeWaitsAtMost: Duration = .milliseconds(2100)

    /// The wall, kept in the order in which it is shown.
    ///
    /// **It is held here and not on the page**, because a tab is built when the user opens it
    /// and discarded when the user leaves it. If the page held it, every return to the library
    /// would sort the whole collection again. See `SortedWall`.
    @State private var inOrder = SortedWall()

    /// The same library grouped by artist. It is held here for the same reason as `inOrder`: it
    /// needs a pass over every credit in the collection, and a tab is discarded each time the user
    /// leaves it. See `ReadArtists`.
    @State private var readArtists = ReadArtists()

    /// The genres wall, built once for each library. See ``ReadGenres``.
    @State private var readGenres = ReadGenres()

    /// What is open on the genres view of the library: a genre, and records opened from it.
    @State private var genrePath: [GenreStep] = []

    enum GenreStep: Hashable {
        case genre(String)
        case artist(String)
        case album(String)
        case list(OpenList)
    }

    /// The view of the library tab. It is stored between launches, as the wall's order is,
    /// because it is a way to view a collection and the user should not have to choose it again
    /// each time the app opens.
    @AppStorage("library.mode") private var mode: LibraryMode = .albums

    /// What is open on the artists side of the library tab.
    ///
    /// This stack is separate, so that a page pushed under the artists is not still on screen
    /// after the user switches back to the records. It is one path and not two, because an
    /// artist opens a record, and going back from that record must return to the artist.
    @State private var browsing: [LibraryStep] = []

    /// A step on the albums or the artists stack: a record or an artist. Each step holds a name
    /// and not a copy of the data, so a library that refreshes under an open page redraws the page
    /// with the new rows and not with the copy that was pushed.
    enum LibraryStep: Hashable {
        case artist(String)
        case album(String)
    }

    var body: some View {
        Group {
            switch model.standing {
            case .starting:
                waiting(nil)

            case .signedOut:
                SignInView(model: model)

            case .loading:
                waiting(Loc.get("Rpm_Library_Reading"))

            case .showing:
                shell
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Start radio, on every song menu and home's radio entries. See `StartRadio`.
        .environment(\.startRadio, { [model] track in model.startRadio(track) })
        // Asked before a tap replaces a queue that the user changed. It is on the root and not on
        // each page, because a tap on every page reaches `AppModel.play`, and the player is an
        // overlay here and not a system sheet that would hide a dialog presented under it.
        .confirmationDialog(Loc.get("Rpm_Queue_DiscardTitle"),
                            isPresented: Binding(get: { model.queueQuestion != nil },
                                                 set: { if !$0 { model.queueQuestion = nil } }),
                            titleVisibility: .visible,
                            presenting: model.queueQuestion) { question in
            Button(Loc.get("Rpm_Queue_Discard"), role: .destructive) {
                Task { await model.answer(question.discard()) }
            }
            Button(Loc.get("Rpm_Queue_PlayNowKeep")) {
                Task { await model.answer(question.keepQueue()) }
            }
            Button(Loc.get("Common_Cancel"), role: .cancel) {}
        } message: { _ in
            Text(Loc.get("Rpm_Queue_DiscardMessage"))
        }
        // The wait mark fades out while the wall fades in, as in the Uno app
        // (`LibraryPage.ShowMark`), and the records do not replace the mark in one frame. The
        // library data arrives before the wall is on the screen, because the grid still has to
        // lay out and the first sleeves still have to be drawn. If the wait mark were removed in
        // between, the screen would be blank.
        .overlay {
            if covering {
                ZStack {
                    VinylGround().ignoresSafeArea()
                    // The words are shown only over the user's own collection. The text says
                    // "your library", which is wrong for another user's collection. The record
                    // image alone shows that the app is waiting.
                    waiting(model.viewing.isOwn ? Loc.get("Rpm_Library_Reading") : nil)
                }
                .transition(.opacity)
                // Taps are blocked while the mark is shown. The screen under it is the collection
                // that is being replaced, and a tap would open one of its records.
                .allowsHitTesting(model.shelfArriving)
            }
        }
        // This background is for the two screens that are not a page: starting, and reading the
        // library. Every page has its own background, because a navigation stack paints over
        // anything placed under the app.
        .background { VinylGround() }
        // Shown over every screen, including the sign-in form and the wait mark. The missing
        // connection is the reason why all three can fail, and a notice that exists only on the
        // library would never be seen by a user who is signing in.
        .overlay(alignment: .top) {
            OfflineBar(showing: !model.reading.isOnline,
                       detail: model.standing == .showing ? Loc.get("Rpm_Net_OfflineDownloads") : nil)
        }
        // **The player is an overlay on the app, not a separate presentation.** The Uno app puts
        // the player over the shell with `Grid.RowSpan="2"`, which covers the tab bar and the mini
        // player that opened it. This overlay does the same: it is on the same screen, and the app
        // is still drawn underneath. A system `fullScreenCover` also covers the tab bar, but it
        // removes the app from the screen, so dragging the grip would show the window's black
        // background and not the library. The part that moves with the finger needs something
        // behind it. The stage is declared after this overlay, so it draws over the player.
        // `onStage` relies on this order when it puts the player away.
        .overlay {
            if playing.up {
                NowPlayingSheet(player: model.player, art: model.playingArt,
                                marked: model.isTrackMarked(model.player.current),
                                lyrics: model.lyrics,
                                lookingUpLyrics: model.lookingUpLyrics,
                                onNeedLyrics: { await model.readLyrics() },
                                onMark: { on in Task { await model.markTrack(on) } },
                                pull: $playing,
                                onFile: model.player.current.map { track in { model.filing = track } },
                                onAlbum: model.player.current.flatMap { track in
                                    let key = AlbumGrouping.key(for: track)
                                    guard model.albums.contains(where: { $0.key == key }) else { return nil }
                                    // The mode is set as well as the tab: the record is pushed
                                    // onto the albums stack, and the library has two other views
                                    // whose stacks would not show it.
                                    return { tab = .library; mode = .albums; opened = [.album(key)] }
                                },
                                // The artists view of the library, with the artist's page
                                // pushed on its own stack, as `RPM_OPEN_ARTIST` does.
                                onArtist: model.player.current.flatMap { track in
                                    guard let who = readArtists.artist(of: track, in: model.albums)
                                    else { return nil }
                                    return { tab = .library; mode = .artists; browsing = [.artist(who.name)] }
                                },
                                playingOn: model.player.castingTo?.name,
                                onSpeakers: { close in
                                    AnyView(SpeakerSheet(
                                        speakers: model.speakers,
                                        playingOn: model.player.castingTo,
                                        looking: model.lookingForSpeakers,
                                        trouble: model.castTrouble,
                                        onPick: { speaker in
                                            Task { await model.cast(to: speaker); close() }
                                        },
                                        onHandset: { Task { await model.stopCasting(); close() } },
                                        onAgain: { Task { await model.findSpeakers() } },
                                        onClose: close)
                                        // The search for speakers starts when the sheet opens
                                        // and not when the app starts. It takes a few seconds, and
                                        // there is no reason to spend them for a user who never
                                        // opens the sheet.
                                        .task { await model.findSpeakers() })
                                })
                    // **This transition makes the whole movement of the player, in both
                    // directions.** The sheet moves itself only while a finger is on it
                    // (`NowPlayingSheet.putting`). When the finger lifts, the sheet hands over at
                    // its current position (`NowPlayingSheet.putAway`) and does not move again.
                    // This transition then continues downwards from that position, or from the
                    // top when a tap on the grip put the player away. Only one animation moves
                    // the player, so two animations never take it to different places with
                    // different timing, and no sheet animation has to finish before it closes.
                    .transition(.belowWindow)
            }
        }
        .animation(.spring(duration: 0.35), value: playing.up)
        // Shown over everything, including the tab bar and the mini player. The stage is the whole
        // screen while the phone is turned.
        .overlay {
            if staged {
                StageView(player: model.player, playing: model.playing,
                          playingOn: model.player.castingTo?.name,
                          backdrops: model.backdrops,
                          onSpeakers: { close in
                              AnyView(SpeakerSheet(
                                  speakers: model.speakers,
                                  playingOn: model.player.castingTo,
                                  looking: model.lookingForSpeakers,
                                  trouble: model.castTrouble,
                                  onPick: { speaker in
                                      Task { await model.cast(to: speaker); close() }
                                  },
                                  onHandset: { Task { await model.stopCasting(); close() } },
                                  onAgain: { Task { await model.findSpeakers() } },
                                  onClose: close)
                                  .task { await model.findSpeakers() })
                          })
                    .transition(.opacity)
            }
        }
        .onChange(of: onStage) { _, now in
            // The stage is declared after the player and so draws over it, but the player is also
            // put away and is not left under the stage. Turning the phone back therefore shows the
            // tab that the player was opened from. The Uno app differs: it returns to the player.
            if now { playing.putAway() }

            withAnimation(.easeOut(duration: 0.25)) { staged = now }
        }
        // **The app rotates only while there is something to rotate to.** The other screens are
        // designed for an upright phone, so landscape is allowed only while a record is loaded.
        // When the music stops, a phone held sideways is asked to turn back, so it is not left on
        // a screen that was not designed for landscape. The Uno app has the same rule. See
        // `StageOrientation`.
        .onChange(of: loaded, initial: true) { _, now in
            StageOrientation.allow(landscape: now)
        }
        // **When playback ends**, the player is put away and the tab shown is the one that the
        // music came from: the library for a record, the radio for a station.
        //
        // The value is read from the player and not set by the code that handles the stop key.
        // Playback can end in two ways, and only one of them is a key press. A queue that plays
        // to its end ends in the same way as the key, and a screen that reacted only to the key
        // would leave the mini player at the bottom of the app over a record that has finished.
        // See `Player.isOver`.
        .onChange(of: model.player.isOver) { _, over in
            guard over else { return }

            playing.putAway()

            // The tab that the music came from. Home is never the result: the record has finished
            // playing, and the place to see what played is the collection it came from.
            tab = model.player.wasTheRadio ? .radio : .library
        }
        .preferredColorScheme(.dark)
        // Passed to the views that fetch a picture from an address that the app does not own. They
        // read it to decide whether to make the request. They do not draw anything with it.
        //
        // **It is set below the overlays, not above them.** An overlay is outside the modifiers
        // that come before it, so a value set above the player's overlay does not reach the
        // player's station tile.
        .environment(\.rpmReach, model.reading)
        // What rpm has decided about stations, for every station logo. It is set below the overlays
        // for the same reason. A `StationFace` without it stops the app.
        .environment(model.radioState)
        .task {
            LaunchClock.mark("root appeared")
            MainActorWatch.start()
            openWhereTheScriptAsked()
            await model.start()
        }
        // Decides the report scope, then sends or asks about the crashes that are waiting.
        .task { await model.diagnostics.start() }
        // A shake of the phone opens Send feedback over whatever is on screen.
        .onReceive(NotificationCenter.default.publisher(for: .rpmShake)) { _ in openFeedback() }
        .sheet(item: $feedback) { shot in
            FeedbackSheet(screenshot: shot.png, email: model.who?.email,
                          send: { await model.diagnostics.sendFeedback($0) },
                          onClose: { feedback = nil })
        }
        .alert(Loc.get("Crash_PromptTitle"),
               isPresented: Binding(get: { model.diagnostics.asksAboutCrashes }, set: { _ in })) {
            Button(Loc.get("Crash_PromptSend")) { Task { await model.diagnostics.answer(send: true) } }
            Button(Loc.get("Crash_PromptDontSend"), role: .cancel) {
                Task { await model.diagnostics.answer(send: false) }
            }
        } message: {
            Text(Loc.get("Crash_PromptBody"))
        }
        // **Returning to the foreground reads the playlists again.** Only the playlists are read:
        // the wall has its own key, and reading a whole library is expensive, while reading the
        // playlists when nothing changed is one request. The read does not change the screen
        // while it runs, and does not change it if it fails.
        .onChange(of: phase) { _, now in
            if now == .active {
                CrashWatch.sceneBecameActive()
            } else {
                model.diagnostics.sceneLeftActive()
            }
            if now == .background { CrashWatch.sceneWentToBackground() }

            // When the app leaves the foreground, the current record is settled, so the last
            // thing that the user listened to is counted and is not lost with the session.
            guard now == .active else {
                if now == .background {
                    // The record on the deck is counted before the app is suspended, and the log
                    // is saved before iOS can end the process. Otherwise everything counted in
                    // this session would exist only in memory.
                    model.player.settlePlay()
                    Task { await model.plays.save() }
                }
                return
            }

            Task { await model.rereadPlaylists() }

            // Start the downloads that could not start while the app was in the background, such
            // as tracks that were not yet signed when the last batch finished.
            Task { await model.downloads.pump() }

            // Also read the play history, for the same reason as the playlists: it can change on
            // the computer as well as on the phone.
            Task { await model.syncPlays() }
        }
        // **The wait mark is also shown over a switch to another collection**, for as long as the
        // model reports that the collection is arriving, plus half a second for the banner's first
        // pictures. Without it the new collection would appear in pieces: titles, then sleeves,
        // then the photo.
        .onChange(of: model.shelfArriving) { _, arriving in
            guard !arriving else {
                withAnimation(.easeIn(duration: 0.15)) { covering = true }
                return
            }

            Task {
                try? await Task.sleep(for: .milliseconds(500))

                // Another switch started during the hold, and that switch controls the cover now.
                guard !model.shelfArriving else { return }
                withAnimation(.easeOut(duration: 0.35)) { covering = false }
            }
        }
        // The wait mark is kept over the wall for its first frames, and then until the home screen
        // has drawn what it opens on, so the app shows a finished page and not one that is still
        // filling in. The home screen is worked out before the shell appears (see
        // `AppModel.show`), and the banner's front card fetches its sleeve and photograph under
        // this mark. The page reports when it has them. The wait is limited by `homeWaitsAtMost`.
        //
        // **The flag is polled and not awaited**, so it does not matter whether the page reports
        // that it is ready before or after the 400 ms: `homeReady` is a state that is read when
        // it is needed.
        .onChange(of: model.standing) { _, now in
            guard now == .showing else {
                homeReady = false
                return
            }

            covering = true
            Task {
                try? await Task.sleep(for: .milliseconds(400))

                let cap = ContinuousClock.now.advanced(by: Self.homeWaitsAtMost)
                while !homeReady, ContinuousClock.now < cap {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                withAnimation(.easeOut(duration: 0.35)) { covering = false }
            }
        }
        // **When offline, show all of the user's own records, with the ones that are not on the
        // phone greyed.** A borrowed collection cannot be read without a network, so the app
        // switches to the user's own. The value is the settled reading, the same one that the
        // offline bar draws, so a short Wi-Fi handover does not change the screen.
        .onChange(of: model.reading.isOnline) { _, online in
            guard !online, model.standing == .showing else { return }
            showWhatPlaysOffline()
        }
        // Debug only. See `AppModel.start()`. The key is not known until the library has loaded,
        // so it cannot be read with the other script values.
        .onChange(of: model.openedByScript) { if let key = $1 { opened = [.album(key)] } }
    }

    /// Called when the connection is lost. It shows the library tab, on the records, on the
    /// user's own shelf.
    ///
    /// The stacks are cleared only when the shelf changes. An open page of the user's own shelf
    /// stays open, because its record is still there and may be on the phone.
    private func showWhatPlaysOffline() {
        if !model.viewing.isOwn {
            opened = []
            lists = []
            browsing = []
            homePath = []
            genrePath = []
            Task { await model.open(.own) }
        }

        tab = .library
        mode = .albums
    }

    /// Whether the stage should be shown: the phone is turned and a record is loaded. A stage
    /// with nothing loaded is a black screen with a wordmark, so a turned phone with nothing
    /// loaded keeps the tab it was on.
    private var onStage: Bool { vertical == .compact && loaded }

    /// Whether a record or a station is loaded. This is the second condition for the stage, and
    /// the only reason for the app to be in landscape.
    ///
    /// One property serves both uses, so the rule that lets the phone rotate and the screen it
    /// rotates to cannot disagree. An app that is allowed into landscape with nothing to show
    /// there would show a black screen with a wordmark.
    private var loaded: Bool {
        model.player.current != nil || model.player.station != nil
    }

    /// Opens a named screen, so that a script can show a page.
    ///
    /// The simulator accepts no synthetic taps, so a screen that is three steps deep can
    /// otherwise only be reached by hand. Debug only: a release build does not read this.
    /// Takes the screenshot first, while the screen the tester is reporting is still showing, then
    /// opens the sheet over it. Only a TestFlight build offers this (`ReportScope`).
    private func openFeedback() {
        guard model.diagnostics.offersFeedback, feedback == nil else { return }
        feedback = FeedbackShot(png: WindowShot.capture())
    }

    private func openWhereTheScriptAsked() {
        #if DEBUG
        let asked = ProcessInfo.processInfo.environment

        if let name = asked["RPM_OPEN_TAB"], let want = RPMTab(rawValue: name) { tab = want }

        if asked["RPM_OPEN_PLAYER"] != nil { playing.raise() }
        if let key = asked["RPM_OPEN_ALBUM"], !key.isEmpty { opened = [.album(key)] }

        // The view of the library tab, and one artist's page on it. A script can ask for every
        // view and not only the artists, because the choice is stored between launches, and a
        // script that could only ask for the artists could not return to the records. The
        // artist is given by name and not by key, because the wall is built on names.
        if let want = asked["RPM_LIBRARY_MODE"], let picked = LibraryMode(rawValue: want) {
            mode = picked
        }

        if let name = asked["RPM_OPEN_ARTIST"], !name.isEmpty {
            mode = .artists
            browsing = [.artist(name)]
        }

        switch asked["RPM_OPEN_LIST"] {
        case "queue": lists = [.queue]
        case "favorites": lists = [.favorites]
        case .some(let id) where !id.isEmpty: lists = [.playlist(id)]
        default: break
        }

        // Every vertical scroll view on the screen is scrolled by this amount after twelve seconds,
        // for a screenshot of a scrolled page. The simulator accepts no scroll gestures.
        if let asked = asked["RPM_SCROLL_BY"], let by = Double(asked) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { Self.scrollEverything(by: by) }
        }
        #endif
    }

    #if DEBUG
    private static func scrollEverything(by: Double) {
        func visit(_ view: UIView) {
            if let scroller = view as? UIScrollView,
               scroller.contentSize.height + scroller.adjustedContentInset.top
                   + scroller.adjustedContentInset.bottom > scroller.bounds.height,
               scroller.contentSize.width <= scroller.bounds.width + 1 {
                scroller.setContentOffset(
                    CGPoint(x: scroller.contentOffset.x, y: by - scroller.adjustedContentInset.top),
                    animated: false)
            }
            view.subviews.forEach(visit)
        }
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            scene.windows.forEach(visit)
        }
    }
    #endif

    // MARK: The app once there is something to show

    /// A screen, the player and the tab bar. The player and the tab bar below the screen are one
    /// stack, because they move together.
    private var shell: some View {
        ZStack {
            // **Home is built once and kept, under whichever tab is shown.** If it were rebuilt
            // each time, opening a record from it and returning would reset it: scrolled to the
            // top, on the first card, every row at its start. Kept, it stays where the user left
            // it. While hidden, it receives no touches, is not read by VoiceOver, and its
            // animated rooms stop (`onScreen`), so it costs no frames while another tab is shown.
            home
                .opacity(tab == .home ? 1 : 0)
                .allowsHitTesting(tab == .home)
                .accessibilityHidden(tab != .home)

            switch tab {
            case .home:
                EmptyView()

            case .library where mode == .artists:
                // This view has its own stack and its own path. Switching back to the records must
                // not leave an artist's page on the screen, and returning to the artists must not
                // show the place where the user was in the records.
                NavigationStack(path: $browsing) {
                    ArtistsPage(
                        inOrder: { readArtists.artists(model.albums, in: $0) },
                        albums: readArtists.albums(model.albums),
                        standing: model.wallStanding, covers: covers,
                        mode: $mode, lender: model.lender,
                        onOpen: { browsing.append(.artist($0.name)) },
                        onRefresh: { await model.refresh() })
                        .footRoom(chrome, .insideAStack)
                        .navigationDestination(for: LibraryStep.self) { step in
                            page(step, on: $browsing).footRoom(chrome, .insideAStack)
                        }
                }

            case .library where mode == .genres:
                // This view has its own stack and path, as the artists view does. A genre opened
                // here must not be on screen after the user goes to the records.
                NavigationStack(path: $genrePath) {
                    GenresPage(genres: readGenres.genres(model.albums),
                               standing: model.wallStanding,
                               mode: $mode, lender: model.lender,
                               onOpen: { genrePath.append(.genre($0.name)) },
                               onRefresh: { await model.refresh() })
                        .toolbar(.hidden, for: .navigationBar)
                        .footRoom(chrome, .insideAStack)
                        .navigationDestination(for: GenreStep.self) { step in
                            genrePage(step).footRoom(chrome, .insideAStack)
                        }
                }

            case .library where mode == .playlists:
                // The lists have their own stack, so that a playlist pushed here is not still on
                // screen after the user goes to the records. Both views are on the library tab.
                NavigationStack(path: $lists) {
                    PlaylistsPage(
                        playlists: model.playlists,
                        mode: $mode,
                        queue: model.player.queue,
                        // Nil and not empty on a borrowed shelf. A track on a borrowed shelf
                        // cannot be marked from a phone, so the list would always be empty.
                        favorites: model.viewing.isOwn ? model.favoriteTracks : nil,
                        covers: covers, lender: model.lender,
                        standing: model.playlistStanding,
                        albums: model.albums,
                        onOpen: { row in lists.append(named(row)) },
                        onReread: { await model.rereadPlaylists() },
                        onMake: { name, folder, tracks in
                            await model.makePlaylist(name: name, in: folder, tracks: tracks)
                        })
                        .footRoom(chrome, .insideAStack)
                        .navigationDestination(for: OpenList.self) { open in
                            page(open, back: { lists.removeLast() })
                                .toolbar(.hidden, for: .navigationBar)
                                .footRoom(chrome, .insideAStack)
                        }
                }
                .task { await model.showPlaylists() }

            case .library:
                // The stack belongs to the library and not to the app. A record pushed here must
                // not still be on screen after the user goes to the account.
                NavigationStack(path: $opened) {
                    LibraryPage(
                        albums: model.albums, standing: model.wallStanding, covers: covers,
                        playing: model.nowPlaying,
                        inOrder: inOrder, mode: $mode,
                        lender: model.lender,
                        onOpen: { opened.append(.album($0.key)) },
                        onPlay: { track in Task { await model.play(track) } },
                        onRefresh: { await model.refresh() },
                        isTrackMarked: { model.isTrackMarked($0) },
                        isTrackMine: { model.isTrackMine($0) },
                        onMarkTrack: { track, on in Task { await model.mark(track, on) } },
                        onFile: { model.filing = $0 },
                        upNext: .send { model.playNext($0) })
                        .footRoom(chrome, .insideAStack)
                        .navigationDestination(for: LibraryStep.self) { step in
                            page(step, on: $opened).footRoom(chrome, .insideAStack)
                        }
                }

            case .radio:
                RadioPage(stations: model.stations, saved: model.savedStations,
                          countries: model.countries,
                          tuned: model.player.station?.uuid,
                          announced: model.player.announced,
                          standing: model.radioStanding,
                          onSearch: { asked, genre, country in
                              await model.searchStations(asked, genre: genre, country: country)
                          },
                          onTune: { model.tune($0) },
                          onSave: { model.save($0) })
                    .footRoom(chrome, .underTheChrome)
                    // Run each time the radio is shown and when another library is opened, so that
                    // a shared library's saved stations are its owner's current stations.
                    .task(id: [model.who?.userId ?? "", model.viewing.ownerId]) {
                        await model.readSharedStations()
                    }

            case .profile:
                ProfilePage(name: model.who?.displayName ?? "",
                            email: model.who?.email ?? "",
                            quota: model.quota,
                            onWifi: Binding(get: { model.prefs.rateOnWifi },
                                            set: { model.prefs.rateOnWifi = $0
                                                   model.settleTheRate() }),
                            onCellular: Binding(get: { model.prefs.rateOnCellular },
                                                set: { model.prefs.rateOnCellular = $0
                                                       model.settleTheRate() }),
                            // The queue is pumped at once, so that tracks that are still to be
                            // downloaded are signed at the new rate now and not at the next wake.
                            onDownload: Binding(get: { model.prefs.rateForDownloads },
                                                set: { model.prefs.rateForDownloads = $0
                                                       Task { await model.downloads.pump() } }),
                            levelling: Binding(get: { model.levelling },
                                               set: { model.levelling = $0 }),
                            levelsClassical: Binding(get: { model.levelsClassical },
                                                     set: { model.levelsClassical = $0 }),
                            reach: model.reading,
                            cached: model.cachedBytes,
                            downloaded: (model.downloads.list.count, model.downloads.bytes),
                            onDownloads: { showingDownloads = true },
                            version: model.version,
                            onClearCache: { Task { await model.clearCache() } },
                            onSignOut: { Task { await model.signOut() } },
                            onDeleteAccount: { await model.deleteAccount(confirmEmail: model.who?.email ?? "") },
                            onSupport: { openUrl(AppModel.becomeSupporter) },
                            crashReports: Binding(get: { model.diagnostics.sendsCrashReports },
                                                  set: { model.diagnostics.sendsCrashReports = $0 }),
                            onFeedback: model.diagnostics.offersFeedback ? { openFeedback() } : nil)
                    .task { await model.readCacheSize() }
                    .footRoom(chrome, .underTheChrome)
                    .sheet(isPresented: $showingDownloads) {
                        DownloadsPage(
                            rows: model.downloads.list.map {
                                DownloadsPage.Row(album: $0.album, bytes: $0.bytes,
                                                  standing: $0.standing)
                            },
                            covers: covers,
                            onRemove: { model.downloads.remove($0) },
                            onClose: { showingDownloads = false })
                    }
            }
        }
        // `spacing: 0`, because the default spacing is eight points. With it, the content of the
        // pages that the shell's inset reaches would end eight points above the bar. That shows a
        // band of background over the bar on every screen outside a navigation stack.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RPMChrome(player: model.player, art: model.playingArt,
                      showing: $tab) { playing.raise() }
        }
        .onPreferenceChange(ChromeHeight.self) { chrome = $0 }
        // Which records can be played now, for every tile and row that is greyed. See
        // ``PlayableHere``.
        .environment(\.rpmPlayable, PlayableHere(isOnline: model.reading.isOnline,
                                                  onPhone: model.downloads.onPhone))
        // **The app does not move when the keyboard opens.** By default SwiftUI treats the
        // keyboard as a safe area and lifts everything that is inset at the bottom above it. Then
        // opening the library's search box would move the tab bar, the mini player and the whole
        // page up the screen. Other iOS apps do not do this: the keyboard appears over the bottom
        // of the app. A list is responsible for keeping its own last rows visible. See
        // ``PageFoot``.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Shown over everything in the app, as the Uno app attaches it to the shell. A song can be
        // filed from any list, and the picker stays after the row that opened it is gone.
        .overlay {
            if model.pickingLibrary {
                LibraryPicker(rows: model.shelfRows,
                              onOpen: { shelf in
                                  opened = []
                                  browsing = []
                                  lists = []
                                  homePath = []
                                  genrePath = []
                                  Task { await model.open(shelf) }
                              },
                              onClose: { model.pickingLibrary = false })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.pickingLibrary)
        .overlay {
            if let track = model.filing {
                PlaylistPickSheet(
                    track: track, playlists: model.playlists,
                    onAdd: { set, song, already in
                        await model.addToPlaylist(set, tracks: [song], whenAlreadyThere: already)
                    },
                    onClose: { model.filing = nil })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.filing?.rpmId)
        .task(id: model.filing?.rpmId) {
            // The picker shows the playlist tree, and the tab that reads the playlists may not have
            // been opened. They are read once, when they are first needed.
            guard model.filing != nil else { return }
            await model.showPlaylists()
        }
    }

    /// The long-press menu on a song outside the queue. It is passed to pages that show songs
    /// among other content: home's quick selection and a genre's most played songs. See
    /// `TrackMenu`.
    private var songMenu: TrackMenu {
        TrackMenu(isMarked: { model.isTrackMarked($0) },
                  isMine: { model.isTrackMine($0) },
                  upNext: .send { model.playNext($0) },
                  onMark: { track, on in Task { await model.mark(track, on) } },
                  onFile: { model.filing = $0 })
    }

    /// The home screen. See `shell`, which keeps it built under the other tabs.
    private var home: some View {
        // Home's own stack. What is opened here is pushed here, so it slides in over home and
        // back out to it, in the same way as a record opens on the library.
        NavigationStack(path: $homePath) {
            HomePage(screen: model.home, albums: model.albums, lists: model.playlists,
                     stations: model.homeStations,
                     covers: covers, backdrops: model.backdrops,
                     canSwitch: model.shelfRows.count > 1,
                     onSwitch: { model.pickingLibrary = true },
                     onScreen: tab == .home && homePath.isEmpty,
                     onOpen: { homePath.append(.album($0.key)) },
                     onOpenList: { name in
                         // The same lookup that the screen used for the card's picture, so the
                         // list that opens is the list that was pressed. See `HomeLists`.
                         if let set = HomeLists.set(named: name, in: model.playlists) {
                             homePath.append(.list(.playlist(set.id)))
                         }
                     },
                     onPlay: { tracks in Task { await model.play(tracks, from: 0, tapped: .list) } },
                     onTune: { model.tune($0) },
                     onAddMusic: { tab = .library; mode = .albums },
                     songMenu: songMenu,
                     onReady: {
                         if !homeReady { LaunchClock.mark("home drawn") }
                         homeReady = true
                     })
                .toolbar(.hidden, for: .navigationBar)
                .footRoom(chrome, .insideAStack)
                .navigationDestination(for: HomeStep.self) { step in
                    homePage(step).footRoom(chrome, .insideAStack)
                }
        }
    }

    /// A genre, or a record opened from one.
    @ViewBuilder
    private func genrePage(_ step: GenreStep) -> some View {
        switch step {
        case .genre(let name):
            let byKey = readArtists.albums(model.albums)
            if let shelves = readGenres.shelves(of: name, in: model.albums, byKey: byKey,
                                                artists: readArtists.artists(model.albums)) {
                let records = shelves.albums.compactMap { byKey[$0] }
                let heard = HomeSongs.mostPlayed(records, played: model.played, count: 10)
                let songs = Dictionary(records.flatMap(\.tracks).map { ($0.rpmId, $0) },
                                       uniquingKeysWith: { first, _ in first })
                // The mood lists from the computer that are cut for this genre. Lists that are also
                // cut by a decade are excluded: a list is cut by a genre or by a decade, never both.
                let moods = model.playlists.filter {
                    $0.origin == .generated && $0.cut?.genre == name && $0.cut?.decade == 0
                }
                GenrePage(genre: name, shelves: shelves, albums: byKey,
                          mostPlayed: heard.compactMap { songs[$0] }, moods: moods,
                          covers: covers,
                          onOpen: { genrePath.append(.album($0.key)) },
                          onPlay: { tracks in Task { await model.play(tracks, from: 0, tapped: .list) } },
                          onArtist: { genrePath.append(.artist($0.name)) },
                          onList: { genrePath.append(.list(.playlist($0.id))) },
                          onGenre: { genrePath.append(.genre($0)) },
                          onBack: { genrePath.removeLast() },
                          songMenu: songMenu)
                    .toolbar(.hidden, for: .navigationBar)
            } else {
                // The genre was removed while the page was open. There is nothing to draw.
                RPMInk.ground.ignoresSafeArea()
            }

        case .artist(let name):
            artistPage(named: name, open: { genrePath.append(.album($0.key)) },
                       openArtist: { genrePath.append(.artist($0.name)) },
                       back: { genrePath.removeLast() })

        case .list(let open):
            page(open, back: { genrePath.removeLast() })
                .toolbar(.hidden, for: .navigationBar)

        case .album(let key):
            if let album = model.albums.first(where: { $0.key == key }) {
                page(album, back: { genrePath.removeLast() },
                     open: { genrePath.append(.album($0.key)) },
                     openArtist: { genrePath.append(.artist($0.name)) })
            } else {
                // The record went while the page was open. Nothing to draw.
                RPMInk.ground.ignoresSafeArea()
            }
        }
    }

    /// A record or a list opened from the home screen, or an artist opened from a record.
    @ViewBuilder
    private func homePage(_ step: HomeStep) -> some View {
        switch step {
        case .album(let key):
            if let album = model.albums.first(where: { $0.key == key }) {
                page(album, back: { homePath.removeLast() },
                     open: { homePath.append(.album($0.key)) },
                     openArtist: { homePath.append(.artist($0.name)) })
            } else {
                // The record went while the page was open. Nothing to draw.
                RPMInk.ground.ignoresSafeArea()
            }

        case .artist(let name):
            artistPage(named: name, open: { homePath.append(.album($0.key)) },
                       openArtist: { homePath.append(.artist($0.name)) },
                       back: { homePath.removeLast() })

        case .list(let open):
            page(open, back: { homePath.removeLast() })
                .toolbar(.hidden, for: .navigationBar)
        }
    }

    @Environment(\.openURL) private var openUrl

    private func named(_ row: PlaylistRow) -> OpenList {
        switch row.kind {
        case .queue: return .queue
        case .favorites: return .favorites
        case .playlist(let set): return .playlist(set.id)
        // A folder is opened on the tab itself. It never opens a page.
        case .folder: return .queue
        }
    }

    /// One list, drawn from the model and not from the data that the row held when it was
    /// tapped.
    @ViewBuilder
    private func page(_ open: OpenList, back: @escaping () -> Void) -> some View {
        switch open {
        case .queue:
            PlaylistPage(title: Loc.get("AlbumMenu_PlaylistNowPlaying"), tracks: model.player.queue, missing: 0,
                         covers: covers, isQueue: true,
                         // The queue as this listening session has it. A record that was started
                         // at track ten has nine earlier tracks in the queue that were never
                         // played, and they are not shown or rearranged in this session.
                         look: .sitting(from: model.player.earliest,
                                        playing: model.player.index),
                         canReorder: true,
                         playing: model.nowPlaying,
                         onPlay: { at, _ in Task { await model.jump(to: at) } },
                         onShuffle: { Task { await model.shuffleTheQueue() } },
                         onRemove: { model.removeFromQueue($0) },
                         onMove: { from, to in model.player.move(from: from, to: to) },
                         onBack: back,
                         isTrackMarked: { model.isTrackMarked($0) },
                         isTrackMine: { model.isTrackMine($0) },
                         onMarkTrack: { track, on in Task { await model.mark(track, on) } },
                         onFile: { model.filing = $0 },
                         // This list is the play order itself. A row here is already in the
                         // queue, so there is nothing to send to play next. The row is moved
                         // with the grip.
                         upNext: .itIsTheQueue)

        case .favorites:
            list(Loc.get("Playlists_FavoriteTracks"), model.favoriteTracks, missing: 0, back: back)

        case .playlist(let id):
            if let set = model.playlists.first(where: { $0.id == id }) {
                // **Nothing can be added to a list that the computer generated.** Its id does not
                // exist in the store, and the computer replaces the whole list at its next run, so
                // a song added to it would be lost. Nil here removes the plus button and the
                // grips. See `PlaylistSet.isWritable`.
                list(set.name, set.tracks, missing: set.missing,
                     adding: set.origin == .stored ? set : nil,
                     picture: set.picture,
                     // The list itself, for the frame on the cover of a generated list. It is not
                     // the same as `adding`, which is nil for exactly the lists that have a frame.
                     showing: set,
                     // Another selection of the same list, only where the computer sent enough
                     // tracks to make one. A stored playlist has no such selection, because it
                     // holds exactly the tracks that the user added.
                     newList: model.hasAnotherList(set)
                         ? { model.newGeneratedList(set) }
                         : nil,
                     back: back)
            } else {
                // The playlist was removed while the page was open. There is nothing to draw
                // and nothing to report.
                RPMInk.ground.ignoresSafeArea()
            }
        }
    }

    /// A list whose order this phone does not control: a stored playlist, or the marked songs.
    /// Songs can still be added to a stored playlist, which is what `adding` is for.
    private func list(_ title: String, _ tracks: [CloudTrack], missing: Int,
                      adding: PlaylistSet? = nil,
                      picture: ListPicture? = nil,
                      showing: PlaylistSet? = nil,
                      newList: (() -> Void)? = nil,
                      back: @escaping () -> Void) -> some View {
        PlaylistPage(title: title, tracks: tracks, missing: missing,
                     covers: covers, isQueue: false, look: .whole,
                     // A write sends the whole order, so a playlist that holds songs this phone
                     // cannot see must not be rearranged here. A list that no user made must not
                     // be rearranged either. See `PlaylistSet.isWritable`, which checks both
                     // conditions: the list belongs to this account and a user made it.
                     canReorder: adding.map { $0.isWritable && $0.missing == 0 } ?? false,
                     playing: model.nowPlaying,
                     adding: adding, albums: model.albums,
                     onPlay: { at, tapped in Task { await model.play(tracks, from: at, tapped: tapped) } },
                     onShuffle: { Task { await model.shuffle(tracks) } },
                     onRemove: { _ in },
                     onMove: { from, to in
                         guard let set = adding else { return }
                         Task { await model.reorderPlaylist(set, from: from, to: to) }
                     },
                     onBack: back,
                     onNewList: newList,
                     // A batch chosen from the albums, so tracks that are already in the list
                     // are left as they are. A user who chooses twelve tracks does not want a
                     // second copy of the three that are already there. A second copy is offered
                     // only in the picker for a single song, where the user can answer the
                     // question.
                     onAdd: { set, songs in
                         await model.addToPlaylist(set, tracks: songs, whenAlreadyThere: .leaveIt)
                     },
                     picture: picture,
                     showing: showing,
                     isTrackMarked: { model.isTrackMarked($0) },
                     isTrackMine: { model.isTrackMine($0) },
                     onMarkTrack: { track, on in Task { await model.mark(track, on) } },
                     onFile: { model.filing = $0 },
                     upNext: .send { model.playNext($0) })
    }

    /// One step on the albums or the artists stack: a record or an artist. What either page opens
    /// is pushed onto `path`, the stack that the page is on.
    ///
    /// Both pages are drawn from the model and not from the data that was pushed, so a library
    /// that refreshes under an open page redraws it with the new rows.
    @ViewBuilder
    private func page(_ step: LibraryStep, on path: Binding<[LibraryStep]>) -> some View {
        switch step {
        case .artist(let name):
            artistPage(named: name, open: { path.wrappedValue.append(.album($0.key)) },
                       openArtist: { path.wrappedValue.append(.artist($0.name)) },
                       back: { path.wrappedValue.removeLast() })

        case .album(let key):
            if let album = model.albums.first(where: { $0.key == key }) {
                page(album, back: { path.wrappedValue.removeLast() },
                     open: { path.wrappedValue.append(.album($0.key)) },
                     openArtist: { path.wrappedValue.append(.artist($0.name)) })
            } else {
                // The record was removed while the page was open. There is nothing to draw and
                // nothing to report.
                RPMInk.ground.ignoresSafeArea()
            }
        }
    }

    /// One artist's page, looked up by name each time it is drawn.
    @ViewBuilder
    private func artistPage(named name: String,
                            open: @escaping (CloudAlbum) -> Void,
                            openArtist: @escaping (ArtistWallItem) -> Void,
                            back: @escaping () -> Void) -> some View {
        if let who = readArtists.artists(model.albums).first(where: { $0.name == name }) {
            artistPage(who, open: open, openArtist: openArtist, back: back)
                .toolbar(.hidden, for: .navigationBar)
        } else {
            // The artist's last record was removed while the page was open, so the artist no
            // longer exists. There is nothing to draw and nothing to report.
            RPMInk.ground.ignoresSafeArea()
        }
    }

    private func artistPage(_ artist: ArtistWallItem,
                            open: @escaping (CloudAlbum) -> Void,
                            openArtist: @escaping (ArtistWallItem) -> Void,
                            back: @escaping () -> Void) -> some View {
        // The artist's songs, so that the songs after the current one are the artist's other
        // work and not the rest of the record that the song is on.
        let songs = readArtists.shelves(of: artist, in: model.albums).songs.map(\.track)

        let byKey = readArtists.albums(model.albums)

        return ArtistPage(
            artist: artist,
            shelves: readArtists.shelves(of: artist, in: model.albums),
            covers: covers, articles: model.articles, worldPlays: model.worldPlays,
            backdrops: model.backdrops,
            albums: byKey,
            relatedFrom: RelatedArtists.Collection(
                artists: readArtists.artists(model.albums), genres: readGenres.genres(model.albums),
                albums: byKey, lists: model.playlists.map(\.tracks)),
            // The page supplies the play order: record by record for Play all, and the popular
            // songs for a popular song.
            onPlay: { tracks, at, tapped in Task { await model.play(tracks, from: at, tapped: tapped) } },
            onShuffle: { Task { await model.shuffle(songs) } },
            onOpen: open,
            onOpenArtist: openArtist,
            onBack: back,
            isTrackMarked: { model.isTrackMarked($0) },
            isTrackMine: { model.isTrackMine($0) },
            onMarkTrack: { track, on in Task { await model.mark(track, on) } },
            onFile: { model.filing = $0 },
            upNext: .send { model.playNext($0) })
    }

    /// - Parameters:
    ///   - open: what pressing a record in the page's Similar albums row does: push it onto
    ///     the same stack this page is on.
    ///   - openArtist: what pressing the artist line does: push that artist's page onto the
    ///     same stack.
    private func page(_ album: CloudAlbum, back: @escaping () -> Void,
                      open: @escaping (CloudAlbum) -> Void,
                      openArtist: @escaping (ArtistWallItem) -> Void) -> some View {
        albumPage(album, back: back, open: open, openArtist: openArtist)
            .toolbar(.hidden, for: .navigationBar)
            // One wall for each record. It is built when the page opens and not when the user
            // scrolls to it. It needs one request after the tracks, and a wall that appears only
            // when the user looks for it is not found.
            .task(id: album.key) {
                let made = ReviewWall(community: model.community, album: album)
                walls[album.key] = made
                await made.read()
            }
            .overlay {
                if writing == album.key, let wall = walls[album.key] {
                    WriteReviewSheet(
                        album: album.album, stars: wall.myStars,
                        words: wall.mine?.body ?? "",
                        onSave: { stars, words in await wall.write(stars: stars, body: words) },
                        onDelete: wall.mine == nil ? nil : { await wall.deleteMine() },
                        onClose: { writing = nil })
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: writing)
    }

    private func albumPage(_ album: CloudAlbum, back: @escaping () -> Void,
                           open: @escaping (CloudAlbum) -> Void,
                           openArtist: @escaping (ArtistWallItem) -> Void) -> some View {
        AlbumPage(album: album, covers: covers, articles: model.articles,
                  marked: model.isMarked(album),
                  // The shelf on the screen. On a borrowed shelf the result is its owner's.
                  classical: model.isClassical(album, on: model.viewing),
                  // Only for the user's own records. A download is signed as one of this
                  // account's tracks.
                  download: model.viewing.isOwn
                      ? DownloadKey(standing: model.downloads.standing(of: album.key),
                                    onDownload: { model.downloads.download(album) },
                                    onRemove: { model.downloads.remove([album.key]) })
                      : nil,
                  canPlay: { model.reading.isOnline || model.downloads.isOnPhone($0.rpmId) },
                  shelf: model.albums, onOpenAlbum: open,
                  artists: readArtists.artists(of: album, in: model.albums),
                  onArtist: openArtist,
                  playing: model.nowPlaying,
                  onPlay: { at, tapped in Task { await model.play(album, from: at, tapped: tapped) } },
                  onShuffle: { Task { await model.shuffle(album) } },
                  onMark: { on in Task { await model.mark(album, on) } },
                  onBack: back,
                  isTrackMarked: { model.isTrackMarked($0) },
                  isTrackMine: { model.isTrackMine($0) },
                  onMarkTrack: { track, on in Task { await model.mark(track, on) } },
                  onFile: { model.filing = $0 },
                  upNext: .send { model.playNext($0) },
                  wall: reviews(of: album),
                  rating: walls[album.key].map { (average: $0.average, count: $0.ratingCount) })
    }

    /// The record's wall as the page draws it, or `nil` while its community entry is still being
    /// resolved.
    private func reviews(of album: CloudAlbum) -> AnyView? {
        guard let wall = walls[album.key] else { return nil }

        return AnyView(
            ReviewsWall(average: wall.average, ratingCount: wall.ratingCount,
                        myStars: wall.myStars,
                        reviews: wall.reviews.map {
                            ReviewFace(review: $0, mine: $0.userId == model.who?.userId)
                        },
                        sort: wall.sort, reading: wall.reading,
                        hasMore: wall.hasMore, trouble: wall.trouble,
                        onSort: { order in Task { await wall.sorted(by: order) } },
                        onRate: { stars in
                            Task { _ = await wall.write(stars: stars, body: wall.mine?.body ?? "") }
                        },
                        onWrite: { writing = album.key },
                        onVote: { review, value in Task { await wall.vote(review, value) } },
                        onMore: { Task { await wall.more() } }))
    }

    private func waiting(_ what: String?) -> some View {
        VStack(spacing: 18) {
            RecordSpinner(diameter: 120)
            if let what {
                Text(what).font(.footnote).foregroundStyle(.secondary)
            }
            LaunchReadout()
        }
    }

    /// Built again with the view, which costs nothing: it is a struct that holds a few
    /// references. It is built here and not in the model because the screen scale comes from the
    /// environment, and a store that is used from a background task must be given the scale and
    /// cannot look it up.
    private var covers: CloudCovers {
        CloudCovers(store: model.artwork, lists: model.listPictures,
                    portraits: model.portraits,
                    shelves: model.shelves, scale: displayScale)
    }
}

/// The screenshot a Send feedback sheet opens with. A new value for every opening, so the sheet
/// is presented from it with `sheet(item:)`.
struct FeedbackShot: Identifiable {
    let id = UUID()
    let png: Data?
}
