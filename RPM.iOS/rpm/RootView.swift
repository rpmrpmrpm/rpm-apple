import SwiftUI
import RPMSharedUI
import RPMUI
import RPMDesign
import RPMLibrary
import RPMArt
import RPMAudio
import RPMKit
import RPMRadio
import RPMSession

/// What the app opens on.
struct RootView: View {
    /// Created by the app delegate, not here. See `RPMDelegate`.
    @State private var model: AppModel

    @MainActor
    init(model: AppModel) {
        _model = State(initialValue: model)
        // Play next on a record puts its songs after the song playing, as on one song. A station's
        // menu saves it as its heart does, and only where the hearts may change it.
        _holds = State(initialValue: Holds(playNext: { [model] album in
            model.player.insertNext(album.tracks)
        }, savedStations: { [model] in
            model.savedStations
        }, toggleSaved: { [model] station in
            model.save(station)
        }))
    }

    /// Quick selection's own picks, the pinned playlists and the long-press menus on records and
    /// lists, for every page. See ``Holds``.
    @State private var holds: Holds
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
    ///
    /// Every change slides the pages (``slide(to:)``), wherever it comes from: the tab bar, the
    /// player's album and artist lines, the end of playback.
    private var tab: RPMTab {
        get { shownTab }
        nonmutating set { slide(to: newValue) }
    }

    /// The tab shown. Written only by ``slide(to:)``.
    @State private var shownTab: RPMTab = RootView.lastTab

    /// The tabs whose pages are still sliding off the screen. They are taken away when the slide
    /// ends.
    @State private var leavingTabs: Set<RPMTab> = []

    /// The tab shown before the last change: the side the new page comes in from.
    @State private var cameFrom: RPMTab = RootView.lastTab

    /// Whether the model was started: once for the life of the app, however often the screens are
    /// built.
    @MainActor private static var started = false

    /// Whether the crash reports were looked at, once for the life of the app.
    @MainActor private static var diagnosing = false

    /// The tab shown last, for as long as the app runs. The screens are built again when the user
    /// chooses another language (see `RPMApp`), and they open on this tab and not on Home, so the
    /// user stays on the settings where they made the choice.
    @MainActor private static var lastTab: RPMTab = .home

    /// Counts the changes of tab, so a slide that ends after a newer one began leaves the pages of
    /// the newer one alone.
    @State private var slides = 0

    /// The width the tabs' pages slide across, measured on the shell.
    @State private var pageWidth: CGFloat = 0

    /// Counts the taps on the Settings key while the settings are shown. Each one puts the section
    /// shown back at its top. See ``backToFirstPage(of:)``.
    @State private var settingsTops = 0

    /// Whether the music has been paused for a moment. The player's room and spectrum rest then
    /// (``SwiftUI/EnvironmentValues/roomsRest``): a still picture redrawn on every frame of the
    /// display only heats the phone.
    @State private var pausedAWhile = false

    /// The reader's own page. Made when the Feed tab is first shown; it rises over the app from the tab's profile key.
    @State private var me: PersonPage?

    /// Whether the reader's own page is open over the app.
    @State private var showingMe = false

    /// Other people's pages, opened from a name, newest last. They rise over the app, over the reader's own page
    /// too; the back key goes to the page before.
    @State private var people: [PersonPage] = []

    /// The reader's notifications, for the dot on the Feed tab's profile key and the list on their own page.
    @State private var notices: Notices?

    /// Everyone's posts and reviews, for the Feed tab.
    @State private var feed: FeedBook?

    /// The photos the sample people borrow: an artist's each, found once a sample is shown. Empty in a listener's
    /// build.
    @State private var sampleFaces: [String: URL] = [:]

    /// The covers the cover search found for reviewed records the reader does not have, by artist and title. A record
    /// with none found is kept as nil, so it is asked once.
    @State private var foundCovers: [String: URL?] = [:]

    /// The review on the Feed tab read in full, by its feed id.
    @State private var feedReview: String?

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

    /// How the player looks on its side: the stage (Classic) or the player itself laid out for
    /// landscape (Modern). See ``LandscapePlayer`` and `onChange(of: onStage)`.
    @AppStorage(LandscapePlayer.key) private var landscapeStyle = LandscapePlayer.initial

    /// Whether the phone on its side shows the Modern player instead of the stage.
    private var sidewaysPlayer: Bool { onStage && landscapeStyle == .modern }

    /// Whether the Modern player was on its side a moment ago. It stays true for ``turnSettles``
    /// after the phone turns back upright. See ``pagesHidden``.
    @State private var sidewaysLately = false

    /// How long the system's animation of a turn takes, with a margin.
    private static let turnSettles: Duration = .milliseconds(600)

    /// **Whether the pages under the player are hidden: while the Modern player is on its side,
    /// and while the phone turns back from it.**
    ///
    /// The pages are laid out again for the new size during the turn, and they slide and jump
    /// while they do so. The player does not cover them all the way through the system's
    /// animation, so without this they show around it and through it. Hidden, they are neither
    /// seen nor drawn, and the player is the only thing that turns.
    ///
    /// On the way into landscape the value turns true in the same update as the size, because
    /// ``sidewaysPlayer`` does. On the way back that is already false, so ``sidewaysLately``
    /// keeps the pages hidden until the turn has finished, but only while the player is up and at
    /// rest: a player that is put away or pulled down shows the page under it. A player put away
    /// on its side leaves nothing under it until the phone is upright again, because the pages
    /// are not drawn for landscape.
    private var pagesHidden: Bool {
        sidewaysPlayer || (sidewaysLately && playing.up && playing.putDown == 0)
    }

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

        /// The songs played lately, newest first. There is only one such list.
        case history
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

    /// The wall at the foot of each open artist page, by the artist's name, for the same reason
    /// as ``walls``: two pages of one artist can be on two stacks at once, and each reads its own.
    @State private var artistWalls: [String: ArtistPosts] = [:]

    /// The line on an artist's wall that the report card is open for.
    @State private var reporting: WallReport?

    /// Whether the list of downloaded albums is up, over the settings tab.
    @State private var showingDownloads = false

    /// The open Send feedback sheet, with the screenshot taken just before it opened.
    @State private var feedback: FeedbackShot?

    /// Whether the wait mark is still shown over the wall. See the overlay below.
    @State private var covering = false

    /// Whether the home screen has drawn what it opens on: the banner's front card, with its
    /// sleeve drawn and its photograph requested. The page sets it and the launch hold reads it.
    /// It is cleared when the shell goes away, because a new shell is a new home screen.
    @State private var homeReady = false

    /// Whether the opening screen is still up. It is shown once per launch. See the overlay that
    /// draws it.
    ///
    /// **It starts from ``openingDone``, not from true.** A new language builds the screens again
    /// (see `RPMApp`), and that resets every `@State` here. The opening waits for the launch hold
    /// below, which runs only when the model starts showing the collection, and the model is already
    /// showing it. So an opening shown again would never hand over.
    @State private var opening = !RootView.openingDone

    /// Whether the shell has been shown with its home screen drawn, so the opening may hand over.
    /// Set when the launch hold below ends. A shell built again after the opening is shown at once.
    @State private var shellShown = RootView.openingDone

    /// Whether the opening screen has handed over, for as long as the app runs.
    @MainActor private static var openingDone = false

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

    /// What is open on top of the radio tab's home: the tuner. The radio tab's own stack, so the
    /// tuner slides in over the home and back out to it, as a record does on home.
    @State private var radioPath: [RadioStep] = []

    enum RadioStep: Hashable {
        case tuner
    }

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

    /// The karaoke switch. It has an effect only for a supporter. See `KaraokeSetting`.
    @AppStorage(KaraokeSetting.key) private var karaokeWanted = KaraokeSetting.initial

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

        /// A genre or a list, which the records' search finds.
        case genre(String)
        case list(OpenList)
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
                // See ``pagesHidden``. Nothing is animated in the hidden pages: they are laid out
                // again for the new size in one step, and are already still when they are shown.
                shell
                    .opacity(pagesHidden ? 0 : 1)
                    .allowsHitTesting(!pagesHidden)
                    .accessibilityHidden(pagesHidden)
                    .transaction { [hidden = pagesHidden] change in
                        if hidden {
                            change.animation = nil
                            change.disablesAnimations = true
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Start radio, on every song menu and home's radio entries. See `StartRadio`.
        .environment(\.startRadio, { [model] track in model.startRadio(track) })
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
                                karaoke: karaokeWanted && model.isSupporter,
                                measured: model.measuredLines,
                                onNeedTiming: { await model.readMeasured() },
                                onWarmNext: { await model.warmNextTiming() },
                                onMark: { on in Task { await model.markTrack(on) } },
                                songMenu: songMenu,
                                pull: $playing,
                                // A starter track cannot go in a playlist: the cloud does not
                                // hold it (`StarterTracks`).
                                onFile: model.player.current
                                    .flatMap { StarterTracks.isStarter($0.rpmId) ? nil : $0 }
                                    .map { track in { model.filing = track } },
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
                                },
                                sideways: sidewaysPlayer)
                    // **This transition makes the whole movement of the player, in both
                    // directions.** The sheet moves itself only while a finger is on it
                    // (`NowPlayingSheet.putting`). When the finger lifts, the sheet hands over at
                    // its current position (`NowPlayingSheet.putAway`) and does not move again.
                    // This transition then continues downwards from that position, or from the
                    // top when a tap on the grip put the player away. Only one animation moves
                    // the player, so two animations never take it to different places with
                    // different timing, and no sheet animation has to finish before it closes.
                    .environment(\.roomsRest, pausedAWhile)
                    .transition(.belowWindow)
            }
        }
        .animation(.spring(duration: 0.35), value: playing.up)
        // The player's room and spectrum rest once the music has been paused for a moment. Not at
        // once: a track takes a second to open, and the light fades out after a pause.
        .task(id: model.player.isPlaying) {
            guard !model.player.isPlaying else {
                pausedAWhile = false
                return
            }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            pausedAWhile = true
        }
        // The first-run hints, over the app and the player, under the stage. See `CoachLayer`.
        .overlayPreferenceValue(CoachTargetFrames.self) { frames in
            CoachLayer(frames: frames, playerUp: playing.up, allowed: coachAllowed)
        }
        // The welcome, on the very first launch, over the app it opens on. See `Welcome`.
        .overlay {
            if welcomeDue {
                Welcome(covers: covers,
                        pick: { welcomeSong() },
                        onPlay: { album, at in
                            FirstRun.shared.finishWelcome()
                            Task { await model.play(album, from: at, tapped: .song) }
                            playing.raise()
                        },
                        onDone: { FirstRun.shared.finishWelcome() })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.4), value: welcomeDue)
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
            // **Modern: the player itself turns with the phone**, laid out for landscape
            // (`sidewaysPlayer`), and the stage is not shown. The player is raised if it was not
            // up, and it stays up when the phone turns back, so turning back shows the upright
            // player.
            //
            // **It is raised at once, without its slide from the foot of the screen.** The phone
            // is turning, and a sheet that slides up during the turn shows the pages around it.
            if now && landscapeStyle == .modern {
                var atOnce = Transaction()
                atOnce.disablesAnimations = true
                withTransaction(atOnce) { playing.raise() }
                withAnimation(.easeOut(duration: 0.25)) { staged = false }
                return
            }

            // Classic: the stage is declared after the player and so draws over it, but the player
            // is also put away and is not left under the stage. Turning the phone back therefore
            // shows the tab that the player was opened from. The Uno app differs: it returns to the
            // player.
            if now { playing.putAway() }

            withAnimation(.easeOut(duration: 0.25)) { staged = now }
        }
        // Keeps the pages hidden while the phone turns back from the Modern player. See
        // ``pagesHidden``.
        .task(id: sidewaysPlayer) {
            guard !sidewaysPlayer else {
                sidewaysLately = true
                return
            }
            try? await Task.sleep(for: Self.turnSettles)
            guard !Task.isCancelled else { return }
            sidewaysLately = false
        }
        // **A Modern player put away on its side turns the phone back.** The pages under the
        // player are drawn for an upright phone. The player's menu puts it away to open the album
        // page, the artist page or the playlist picker, and those must not be shown on their side.
        .onChange(of: playing.up) { _, up in
            if !up && sidewaysPlayer { StageOrientation.requestPortrait() }
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
        // The opening sound gives way to the music, as the desktop's does.
        .onChange(of: model.player.isPlaying) { _, playing in
            if playing { OpeningSound.stop() }
        }
        // The opening screen (`Opening`), over everything until the sign-in form is up or the home
        // screen has drawn what it opens on, then faded away. Once per launch: a later read of the
        // library (another collection, a retry) shows its own wait mark.
        .overlay {
            if opening {
                Opening(ready: model.standing == .signedOut || shellShown,
                        reading: model.standing == .loading ? Loc.get("Rpm_Library_Reading") : nil,
                        onSwept: {
                            Self.openingDone = true
                            withAnimation(.easeOut(duration: Opening.fade)) { opening = false }
                        })
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
        // Passed to the views that fetch a picture from an address that the app does not own. They
        // read it to decide whether to make the request. They do not draw anything with it.
        //
        // **It is set below the overlays, not above them.** An overlay is outside the modifiers
        // that come before it, so a value set above the player's overlay does not reach the
        // player's station tile.
        .environment(\.rpmReach, model.reading)
        // The covers of the songs stations announce, for the station tiles. Set below the
        // overlays for the same reason.
        .environment(\.songCovers, model.songCovers)
        // What rpm has decided about stations, for every station logo. It is set below the overlays
        // for the same reason. A `StationFace` without it stops the app.
        .environment(model.radioState)
        // Quick selection's own picks and the pinned lists, for the long-press menus. Set below the
        // overlays for the same reason.
        .environment(holds)
        // The equaliser, for its card on the settings page.
        .environment(model.equalizer)
        // Once for the life of the app. The screens are built again when the user chooses another
        // language (see `RPMApp`), and the model has already started by then.
        .task {
            guard !Self.started else { return }
            Self.started = true

            LaunchClock.mark("root appeared")
            MainActorWatch.start()
            openWhereTheScriptAsked()
            await model.start()
        }
        // Decides the report scope, then sends or asks about the crashes that are waiting. Once for
        // the life of the app, as above.
        .task {
            guard !Self.diagnosing else { return }
            Self.diagnosing = true
            await model.diagnostics.start()
        }
        // A shake of the phone opens Send feedback over whatever is on screen.
        .onReceive(NotificationCenter.default.publisher(for: .rpmShake)) { _ in openFeedback() }
        // The reader's own page and other people's pages rise over the app in one cover: someone else's page over
        // the reader's own, newest on top, as the Android app lays them over each other.
        .fullScreenCover(isPresented: Binding(get: { showingMe || !people.isEmpty },
                                              set: { if !$0 { showingMe = false; people = [] } })) {
            ZStack {
                if showingMe, let me {
                    PersonScreen(page: me, model: model, notices: notices,
                                 onBack: { showingMe = false },
                                 onOpenPerson: { openPerson($0) },
                                 onOpenAlbum: { album in showingMe = false; people = []; openAlbum(album) },
                                 ownBadges: ownBadges, faces: sampleFaces, coverFor: reviewCover)
                }
                if let page = people.last {
                    PersonScreen(page: page, model: model, notices: nil,
                                 onBack: { people.removeLast() },
                                 onOpenPerson: { openPerson($0) },
                                 onOpenAlbum: { album in showingMe = false; people = []; openAlbum(album) },
                                 faces: sampleFaces, coverFor: reviewCover)
                        .id(page.userId)
                        .transition(.move(edge: .bottom))
                }
            }
            .animation(.easeOut(duration: 0.3), value: people.count)
        }
        // The photos the sample people borrow, found once.
        .task(id: profileSample != nil) { await findSampleFaces() }
        // The size of the collection, for the counts on the reader's page. Sent again only when
        // it changes. The account and the shelf are in the key too: the collection can arrive
        // before the account is known, and the report is for the reader's own shelf only.
        .task(id: CountsAsked(albums: model.albums.count, own: model.viewing.isOwn,
                              userId: model.who?.userId)) { await model.reportCounts() }
        // The badges the collection unlocks, sent once the reader's own page is read, from here and
        // not only from the open page. A badge sent can be a notification, so the count for the
        // Feed tab's dot is read again after it. The badges are worked out in the task, not for its
        // key: they walk the genre wall.
        .task(id: BadgesAsked(albums: model.albums.count, own: model.viewing.isOwn,
                              reader: me?.profile?.userId)) {
            guard let me, me.profile != nil else { return }
            if await me.reportBadges(ownBadges) { await notices?.readUnread() }
        }
        // Another account signed in: its pages are not the last account's.
        .onChange(of: model.who?.userId) { _, _ in
            me = nil
            showingMe = false
            notices = nil
            feed = nil
            people = []
        }
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
                shellShown = true
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
        // A downloaded playlist follows its list: a song added on the computer or on this phone is
        // downloaded, and a song taken out leaves the phone. See `AlbumDownloads.follow(_:)`.
        .onChange(of: model.playlists, initial: true) { _, lists in
            model.downloads.follow(lists)
        }
        // Debug only. See `AppModel.start()`. The key is not known until the library has loaded,
        // so it cannot be read with the other script values.
        .onChange(of: model.openedByScript) { if let key = $1 { opened = [.album(key)] } }
        // The language of the artist and album descriptions, chosen on the settings page. The
        // next page opened reads it. See ``ArticleLanguages``.
        .onChange(of: articleLanguage) { _, chosen in
            model.articles.languages = ArticleLanguages.wikipedias(chosen: chosen,
                                                                   phone: Locale.preferredLanguages)
        }
    }

    /// What the settings page stores for the descriptions' language. See ``ArticleLanguages``.
    @AppStorage(ArticleLanguages.key) private var articleLanguage = ""

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

    /// Whether the welcome shows: on the first launch with an account (``FirstRun``), over the
    /// reader's own collection, once the opening screen and the wait mark have gone.
    private var welcomeDue: Bool {
        !FirstRun.shared.welcomed && model.standing == .showing && model.viewing.isOwn
            && !covering && !opening
    }

    /// Whether the first-run hints may show now: after the welcome, over the reader's own
    /// collection, and not while the wait mark, the opening screen, the stage or a picker is up,
    /// nor while the phone is on its side (the Modern player has no grip to point at).
    private var coachAllowed: Bool {
        FirstRun.shared.welcomed && model.standing == .showing && model.viewing.isOwn
            && !covering && !opening && !staged && !onStage && !model.pickingLibrary
            && model.filing == nil
    }

    /// The song the welcome plays: see ``WelcomeSong``. Only what can be played now: offline, a
    /// record on the phone.
    private func welcomeSong() -> (album: CloudAlbum, at: Int)? {
        let playable = PlayableHere(isOnline: model.reading.isOnline, onPhone: model.downloads.onPhone)
        return WelcomeSong.pick(model.albums, played: model.played,
                                isMarked: { model.isTrackMarked($0) },
                                canPlay: { playable.canPlay($0.key) })
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

        // RPM_SWITCH_TAB: another tab, opened after RPM_OPEN_AFTER seconds, as a press on the tab key
        // opens it. For looking at the change from one tab to another.
        if let name = asked["RPM_SWITCH_TAB"], let want = RPMTab(rawValue: name) {
            let wait = Double(asked["RPM_OPEN_AFTER"] ?? "") ?? 0
            Task {
                try? await Task.sleep(for: .seconds(wait))
                tab = want
            }
        }

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
            // RPM_OPEN_AFTER: the page is pushed after this many seconds and slides in, as after a
            // tap. See the same switch in `AppModel`.
            if let wait = Double(asked["RPM_OPEN_AFTER"] ?? "") {
                Task {
                    try? await Task.sleep(for: .seconds(wait))
                    browsing = [.artist(name)]
                }
            } else {
                browsing = [.artist(name)]
            }
        }

        // A person's page over the app: "me" for the reader's own, or a user id. It waits for the
        // sign-in, because the reader's own page is known by the account's id.
        if let person = asked["RPM_OPEN_PROFILE"], !person.isEmpty {
            Task {
                while model.who == nil { try? await Task.sleep(for: .milliseconds(250)) }
                openPerson(person == "me" ? model.who?.userId ?? "" : person)
            }
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
            // it. While another tab is shown, it receives no touches, is not read by VoiceOver,
            // and its animated rooms stop (`onScreen`), so it costs no frames.
            //
            // Its rooms rest while it is not shown, and under the player.
            //
            // **The offset is the only thing that shows or hides it.** Off the screen it stands
            // just past the edge, as every tab's page does (``TabSlide``), so it needs no opacity.
            // Do not add an opacity or an `animation(nil, value:)` here. The home screen is a
            // `NavigationStack`, which UIKit draws, and UIKit moves it with the animation that
            // reaches the stack itself. An `animation(nil, value:)` written before the offset
            // takes that animation away, and the page jumps off the screen instead of sliding.
            // An opacity that changes in the slide's animation fades the page instead.
            home
                .environment(\.roomsRest, tab != .home || playing.up)
                .offset(x: TabSlide.place(of: RPMTab.home.place, shown: tab.place) * pageWidth)
                .allowsHitTesting(tab == .home)
                .accessibilityHidden(tab != .home)

            // The other tabs' pages. Each is built when its tab is shown, slides in, and is taken
            // away once it has slid off the screen. See ``slide(to:)``.
            ForEach(pagesOnScreen, id: \.self) { which in
                tabPage(which)
                    .environment(\.roomsRest, which != tab || playing.up)
                    .offset(x: TabSlide.place(of: which.place, shown: tab.place) * pageWidth)
                    .transition(AnyTransition.offset(x: TabSlide.entry(from: cameFrom.place, to: which.place) * pageWidth))
                    .allowsHitTesting(which == tab)
                    .accessibilityHidden(which != tab)
            }
        }
        .background {
            GeometryReader { box in
                Color.clear.preference(key: ShellWidth.self, value: box.size.width)
            }
        }
        .onPreferenceChange(ShellWidth.self) { pageWidth = $0 }
        // `spacing: 0`, because the default spacing is eight points. With it, the content of the
        // pages that the shell's inset reaches would end eight points above the bar. That shows a
        // band of background over the bar on every screen outside a navigation stack.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RPMChrome(player: model.player, art: model.playingArt,
                      showing: Binding(get: { tab }, set: { tab = $0 }),
                      onAgain: { backToFirstPage(of: $0) },
                      onOpen: { playing.raise() })
                // Asked before a tap replaces a queue that the user changed. iOS points the
                // dialog's arrow at the view it is attached to, so it is attached here: it opens
                // above the mini player and leaves the song that is playing in sight. One dialog
                // for the whole app, because a tap on every page reaches `AppModel.play`.
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

    /// The page of a tab other than home. Home is built once in ``shell`` and is not built here.
    ///
    /// Each page is a property of its own, and so is each view of the library. In one expression
    /// they take the compiler too long to type-check, and the build fails.
    @ViewBuilder
    private func tabPage(_ which: RPMTab) -> some View {
        switch which {
        case .home: EmptyView()
        case .library: libraryTab
        case .radio: radioTab
        case .feed: feedTab
        case .settings: settingsTab
        }
    }

    /// The library tab. Its four views slide across one another in the order of the row of views,
    /// as the tabs do (``SlidingPages``).
    ///
    /// A view at its first page is held, as the settings page is: its row of views stays where it
    /// is, the pill in the row moves to the new view, and the header and what is under the row
    /// slide. A view with a page pushed on its stack slides whole, because the pushed page has no
    /// row. Held views draw no ground of their own, so the tab draws one behind them.
    private var libraryTab: some View {
        SlidingPages(mode, holding: { atFirstPage($0) }) { which in libraryView(which) }
            .groundBehindHeldPages()
    }

    /// Whether the stack of a library view shows its first page, with nothing pushed on it.
    private func atFirstPage(_ which: LibraryMode) -> Bool {
        switch which {
        case .albums: return opened.isEmpty
        case .artists: return browsing.isEmpty
        case .genres: return genrePath.isEmpty
        case .playlists: return lists.isEmpty
        }
    }

    /// One view of the library tab, with its own stack.
    @ViewBuilder
    private func libraryView(_ which: LibraryMode) -> some View {
        switch which {
        case .artists: artistsView
        case .genres: genresView
        case .playlists: playlistsView
        case .albums: albumsView
        }
    }

    /// This view has its own stack and its own path. Switching back to the records must
    /// not leave an artist's page on the screen, and returning to the artists must not
    /// show the place where the user was in the records.
    private var artistsView: some View {
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
    }

    /// This view has its own stack and path, as the artists view does. A genre opened
    /// here must not be on screen after the user goes to the records.
    private var genresView: some View {
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
    }

    /// The lists have their own stack, so that a playlist pushed here is not still on
    /// screen after the user goes to the records. Both views are on the library tab.
    private var playlistsView: some View {
        NavigationStack(path: $lists) {
            PlaylistsPage(
                playlists: model.playlists,
                mode: $mode,
                // Nil and not empty on a borrowed shelf. A track on a borrowed shelf
                // cannot be marked from a phone, so the list would always be empty.
                favorites: model.viewing.isOwn ? model.favoriteTracks : nil,
                covers: covers, lender: model.lender, owner: model.ownerName,
                standing: model.playlistStanding,
                albums: model.albums,
                onOpen: { row in if let open = named(row) { lists.append(open) } },
                onReread: { await model.rereadPlaylists() },
                onMake: { name, folder, tracks in
                    await model.makePlaylist(name: name, in: folder, tracks: tracks)
                },
                history: model.playedLately,
                onOpenHistory: { lists.append(.history) })
                .footRoom(chrome, .insideAStack)
                .navigationDestination(for: OpenList.self) { open in
                    page(open, back: { lists.removeLast() })
                        .toolbar(.hidden, for: .navigationBar)
                        .footRoom(chrome, .insideAStack)
                }
        }
        .task { await model.showPlaylists() }
    }

    /// The stack belongs to the library and not to the app. A record pushed here must
    /// not still be on screen after the user goes to the account.
    private var albumsView: some View {
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
                upNext: .send { model.playNext($0) },
                found: LibraryPage.Findable(
                    artists: readArtists.artists(model.albums),
                    genres: readGenres.genres(model.albums),
                    playlists: model.playlists,
                    albums: readArtists.albums(model.albums)),
                onOpenArtist: { opened.append(.artist($0.name)) },
                onOpenGenre: { opened.append(.genre($0.name)) },
                onOpenList: { opened.append(.list(.playlist($0.id))) })
                .footRoom(chrome, .insideAStack)
                .navigationDestination(for: LibraryStep.self) { step in
                    page(step, on: $opened).footRoom(chrome, .insideAStack)
                }
        }
        // The search finds playlists as well, so they are read with the records' view too:
        // once a session, as the playlists' own view reads them.
        .task { await model.showPlaylists() }
    }

    /// The radio tab: its home, and the tuner opened from it on the tab's own stack.
    private var radioTab: some View {
        NavigationStack(path: $radioPath) {
            radioHome
                .toolbar(.hidden, for: .navigationBar)
                .footRoom(chrome, .insideAStack)
                .navigationDestination(for: RadioStep.self) { _ in
                    tuner.footRoom(chrome, .insideAStack)
                }
        }
        // Run each time the radio is shown and when another library is opened, so that
        // a shared library's saved stations are its owner's current stations.
        .task(id: [model.who?.userId ?? "", model.viewing.ownerId]) {
            await model.readSharedStations()
        }
    }

    /// The radio tab's first page. See ``RadioHome``.
    private var radioHome: some View {
        RadioHome(heard: model.radioShelves.heard, local: model.radioShelves.local,
                  popular: model.radioShelves.popular, saved: model.savedStations,
                  covers: covers,
                  onScreen: tab == .radio && radioPath.isEmpty,
                  stationsOf: { await model.radioShelves.stations(of: $0) },
                  onTune: { model.tune($0) },
                  onOpenTuner: { radioPath.append(.tuner) })
            // Each time the home is shown: what is out of date is read again, and the rules on
            // which stations are hidden, at most once an hour.
            .task {
                model.radioShelves.refresh()
                await model.radioState.refresh()
            }
    }

    /// The tuner: the dial, the search and the full list of stations. See ``RadioPage``.
    private var tuner: some View {
        RadioPage(stations: model.stations, saved: model.savedStations,
                  countries: model.countries,
                  tuned: model.player.station?.uuid,
                  announced: model.player.announced,
                  standing: model.radioStanding,
                  onSearch: { asked, genre, country in
                      await model.searchStations(asked, genre: genre, country: country)
                  },
                  onTune: { model.tune($0) },
                  onSave: { model.save($0) },
                  onBack: { radioPath.removeLast() })
            .toolbar(.hidden, for: .navigationBar)
    }

    /// The feed tab.
    @ViewBuilder
    private var feedTab: some View {
        if let feed {
            FeedPage(items: feed.items, answered: feed.answered, trouble: feed.trouble,
                     hasMore: feed.next != nil, isSample: feed.isSample,
                     readerId: model.who?.userId ?? "", unread: notices?.unread ?? 0,
                     pictureOf: { model.community.avatar(userId: $0, hasAvatar: $1) ?? sampleFaces[$0] },
                     coverFor: reviewCover, actions: feedActions(feed))
                .footRoom(chrome, .underTheChrome)
                .task { await feed.read() }
                .task { await notices?.readUnread() }
                .sheet(isPresented: Binding(get: { feedReview != nil }, set: { if !$0 { feedReview = nil } })) {
                    feedReviewPage(feed)
                }
        } else {
            // Keyed on the account: the tab can be shown before the sign-in has finished,
            // and the pages are made for the account once it is known. A tab change makes them
            // before the slide (``slide(to:)``); this covers the app opening on this tab and an
            // account that is not known yet.
            Color.clear.task(id: model.who?.userId) { makeOwnPage() }
        }
    }

    /// The settings tab.
    private var settingsTab: some View {
        SettingsPage(name: model.who?.displayName ?? "",
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
                    downloaded: downloadedCount,
                    onDownloads: { showingDownloads = true },
                    version: model.version,
                    onClearCache: { Task { await model.clearCache() } },
                    onSignOut: { Task { await model.signOut() } },
                    onDeleteAccount: { await model.deleteAccount(confirmEmail: model.who?.email ?? "") },
                    onSupport: { openUrl(AppModel.becomeSupporter) },
                    crashReports: Binding(get: { model.diagnostics.sendsCrashReports },
                                          set: { model.diagnostics.sendsCrashReports = $0 }),
                    onFeedback: model.diagnostics.offersFeedback ? { openFeedback() } : nil,
                    sharesListening: Binding(get: { model.sharesListening },
                                             set: { on in Task { await model.setSharesListening(on) } }),
                    backToTop: settingsTops)
            .task { await model.readCacheSize() }
            .task { await model.readSharing() }
            .footRoom(chrome, .underTheChrome)
            .sheet(isPresented: $showingDownloads) {
                DownloadsPage(
                    rows: downloadRows,
                    covers: covers,
                    onRemove: { model.downloads.remove($0) },
                    onClose: { showingDownloads = false },
                    total: model.downloads.bytes)
            }
    }

    /// How many albums and playlists are downloaded, and what they take, for the Downloads card.
    private var downloadedCount: (albums: Int, playlists: Int, bytes: Int64) {
        let list = model.downloads.list
        let playlists = list.filter { DownloadBook.isPlaylistKey($0.album.key) }.count
        return (list.count - playlists, playlists, model.downloads.bytes)
    }

    /// The rows of the downloads page. A downloaded playlist is given its list, for its picture,
    /// when the list is among the playlists on the screen.
    private var downloadRows: [DownloadsPage.Row] {
        var lists: [String: PlaylistSet] = [:]
        for set in model.playlists where set.shelf.isOwn {
            lists[DownloadBook.playlistKey(set.id)] = set
        }
        return model.downloads.list.map {
            DownloadsPage.Row(album: $0.album, bytes: $0.bytes, standing: $0.standing,
                              list: lists[$0.album.key])
        }
    }

    /// The tabs other than home whose pages are on the screen: the one shown, and those still
    /// sliding away. In the tab bar's order.
    private var pagesOnScreen: [RPMTab] {
        RPMTab.allCases.filter { $0 != .home && ($0 == shownTab || leavingTabs.contains($0)) }
    }

    /// Shows `next`, sliding the pages the whole width in the order of the tab bar: to a tab on the
    /// right, the page shown leaves to the left and the new one comes in from the right; to a tab on
    /// the left, the reverse (``TabSlide``). The tab bar and the mini player do not move.
    ///
    /// The page left behind stays until the slide ends. Then home stays built, as always, and any
    /// other tab's page is taken away.
    private func slide(to next: RPMTab) {
        guard next != shownTab else { return }

        slides += 1
        let slide = slides

        Self.lastTab = next

        // The Feed tab's model is made on the tab's first visit. It is made here, before the slide,
        // so the Feed page is built in the slide's own change and comes in with it, as the other
        // pages do. Made from the tab's empty page (``feedTab``), it would arrive after the slide
        // had started, outside the slide's change, and appear at once.
        if next == .feed { makeOwnPage() }

        // All in one animated change, so the page coming in is inserted with its slide.
        withAnimation(.easeInOut(duration: TabSlide.duration)) {
            cameFrom = shownTab
            leavingTabs.insert(shownTab)
            shownTab = next
        } completion: {
            guard slides == slide else { return }
            leavingTabs = []
        }
    }

    /// A tap on the key of the tab that is already shown: the tab goes back to its first page. The
    /// stack of the tab is emptied, and the stack pops back to its first page as the back key does.
    ///
    /// On the library tab only the stack of the view shown is emptied. The other views keep theirs,
    /// as they do when the user switches views. The radio tab goes back from the tuner to its home.
    /// The Feed tab pushes no pages of its own: a person's page and a review rise over the whole
    /// app, tab bar included. The settings have no pages either, so the section shown goes back to
    /// its top.
    private func backToFirstPage(of which: RPMTab) {
        switch which {
        case .home: homePath = []
        case .library: backToFirstPageOfLibrary()
        case .radio: radioPath = []
        case .feed: break
        case .settings: settingsTops += 1
        }
    }

    /// Empties the stack of the library view shown. See ``backToFirstPage(of:)``.
    private func backToFirstPageOfLibrary() {
        switch mode {
        case .albums: opened = []
        case .artists: browsing = []
        case .genres: genrePath = []
        case .playlists: lists = []
        }
    }

    /// The long-press menu on a song. It is passed to pages that show songs among other content:
    /// home's quick selection and a genre's most played songs. The queue on the player uses it
    /// too, with each row's own play next. See `TrackMenu`.
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
                     lender: model.lender,
                     onScreen: tab == .home && homePath.isEmpty,
                     onOpen: { homePath.append(.album($0.key)) },
                     onOpenList: { name in
                         // The same lookup that the screen used for the card's picture, so the
                         // list that opens is the list that was pressed. See `HomeLists`.
                         if let set = HomeLists.set(named: name, in: model.playlists) {
                             homePath.append(.list(.playlist(set.id)))
                         }
                     },
                     onPlay: { tracks, from, tapped in
                         Task { await model.play(tracks, from: from, tapped: tapped) }
                     },
                     onTune: { model.tune($0) },
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

    /// One genre's page, on whichever stack opened it: the genres' own, or the records' search.
    @ViewBuilder
    private func genreScreen(_ name: String,
                             openAlbum: @escaping (CloudAlbum) -> Void,
                             openArtist: @escaping (ArtistWallItem) -> Void,
                             openList: @escaping (OpenList) -> Void,
                             openGenre: @escaping (String) -> Void,
                             back: @escaping () -> Void) -> some View {
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
                      onOpen: openAlbum,
                      onPlay: { tracks, from, tapped in
                          Task { await model.play(tracks, from: from, tapped: tapped) }
                      },
                      onArtist: openArtist,
                      onList: { openList(.playlist($0.id)) },
                      onGenre: openGenre,
                      onBack: back,
                      songMenu: songMenu)
                .toolbar(.hidden, for: .navigationBar)
        } else {
            // The genre was removed while the page was open. There is nothing to draw.
            RPMInk.ground.ignoresSafeArea()
        }
    }

    /// A genre, or a record opened from one.
    @ViewBuilder
    private func genrePage(_ step: GenreStep) -> some View {
        switch step {
        case .genre(let name):
            genreScreen(name, openAlbum: { genrePath.append(.album($0.key)) },
                        openArtist: { genrePath.append(.artist($0.name)) },
                        openList: { genrePath.append(.list($0)) },
                        openGenre: { genrePath.append(.genre($0)) },
                        back: { genrePath.removeLast() })

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

    private func named(_ row: PlaylistRow) -> OpenList? {
        switch row.kind {
        case .favorites: return .favorites
        case .playlist(let set): return .playlist(set.id)
        // A folder is opened on the tab itself. It never opens a page.
        case .folder: return nil
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
                         // The queue is not a playlist: nothing in the menu applies to it.
                         menu: .none,
                         isTrackMarked: { model.isTrackMarked($0) },
                         isTrackMine: { model.isTrackMine($0) },
                         onMarkTrack: { track, on in Task { await model.mark(track, on) } },
                         onFile: { model.filing = $0 },
                         // This list is the play order itself. A row here is already in the
                         // queue, so there is nothing to send to play next. The row is moved
                         // with the grip.
                         upNext: .itIsTheQueue)

        case .favorites:
            // The marked songs: a list that marking a song changes, so it has no menu. It is
            // shown as the computer's Favourite tracks list, with that list's frame and room, as
            // its row on the playlists tab is. The room is drawn instead of a cover, so no
            // picture is asked for.
            list(Loc.get("Playlists_FavoriteTracks"), model.favoriteTracks, missing: 0,
                 adding: nil, picture: nil,
                 showing: GeneratedLists.marked(model.favoriteTracks, among: model.playlists),
                 menu: .none, back: back)

        case .history:
            // The songs played lately: a list that playing changes, so it has no menu either.
            list(Loc.get("Playlists_RecentlyPlayed"), model.playedLately, missing: 0,
                 adding: nil, picture: nil, showing: nil, menu: .none, back: back)

        case .playlist(let id):
            if let set = model.playlists.first(where: { $0.id == id }) {
                // **Nothing can be added to a list that the computer generated, or to another
                // account's playlist.** A generated list's id does not exist in the store, and the
                // computer replaces the whole list at its next run, so a song added to it would be
                // lost. A borrowed playlist is written to its owner's account. Nil here greys Add
                // songs and Rearrange. See `PlaylistSet.isWritable`.
                list(set.name, set.tracks, missing: set.missing,
                     adding: set.isWritable ? set : nil,
                     picture: set.picture,
                     // The list itself, for the frame on the cover of a generated list. It is not
                     // the same as `adding`, which is nil for exactly the lists that have a frame.
                     showing: set,
                     menu: menu(for: set),
                     download: downloadKey(for: set),
                     back: back)
            } else {
                // The playlist was removed while the page was open. There is nothing to draw
                // and nothing to report.
                RPMInk.ground.ignoresSafeArea()
            }
        }
    }

    /// The download key of a playlist page, as the album page has one.
    ///
    /// Only for a list on the user's own shelf: a download is signed as one of this account's
    /// tracks. None for a list with nothing to download (no songs, or only starter tracks), unless
    /// it is downloaded already and can still be removed.
    private func downloadKey(for set: PlaylistSet) -> DownloadKey? {
        guard set.shelf.isOwn else { return nil }
        let key = DownloadBook.playlistKey(set.id)
        let standing = model.downloads.standing(of: key)
        guard standing != nil || !AlbumDownloads.entry(for: set).tracks.isEmpty else { return nil }
        return DownloadKey(standing: standing,
                           onDownload: { model.downloads.download(set) },
                           onRemove: { model.downloads.remove([key]) },
                           isPlaylist: true,
                           track: { model.downloads.track($0) })
    }

    /// What the menu of a playlist page offers. See ``PlaylistMenu``.
    private func menu(for set: PlaylistSet) -> PlaylistMenu {
        if set.isWritable {
            return .own(onRename: { await model.renamePlaylist(set, to: $0) },
                        onDelete: {
                            // A deleted list's download goes with it. Its songs stay on the
                            // phone where an album or another playlist holds them.
                            let failed = await model.deletePlaylist(set)
                            if failed == nil {
                                model.downloads.remove([DownloadBook.playlistKey(set.id)])
                            }
                            return failed
                        })
        }

        if set.origin == .generated {
            // Another selection of the same list, only where the computer sent enough tracks to
            // make one. A stored playlist has no such selection, because it holds exactly the
            // tracks that the user added.
            return .generated(onNewList: model.hasAnotherList(set)
                ? { model.newGeneratedList(set) }
                : nil)
        }

        // Another account's playlist: every item would write to their account.
        return .none
    }

    /// A list whose order this phone does not control: a stored playlist, or the marked songs.
    /// Songs can still be added to a stored playlist, which is what `adding` is for.
    ///
    /// - Parameter download: the download key beside Play, or nil for a list that has none, such
    ///   as the marked songs. See ``downloadKey(for:)``.
    private func list(_ title: String, _ tracks: [CloudTrack], missing: Int,
                      adding: PlaylistSet?,
                      picture: ListPicture?,
                      showing: PlaylistSet?,
                      menu: PlaylistMenu,
                      download: DownloadKey? = nil,
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
                     menu: menu,
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
                     upNext: .send { model.playNext($0) },
                     download: download)
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

        case .genre(let name):
            genreScreen(name, openAlbum: { path.wrappedValue.append(.album($0.key)) },
                        openArtist: { path.wrappedValue.append(.artist($0.name)) },
                        openList: { path.wrappedValue.append(.list($0)) },
                        openGenre: { path.wrappedValue.append(.genre($0)) },
                        back: { path.wrappedValue.removeLast() })

        case .list(let open):
            page(open, back: { path.wrappedValue.removeLast() })
                .toolbar(.hidden, for: .navigationBar)
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
            upNext: .send { model.playNext($0) },
            wall: artistWall(of: artist))
            // One page per artist. Go to artist in the player replaces the stack, and SwiftUI would
            // keep the open page and hand it the new artist. The page's photograph and colour are
            // its own state, and the ground would keep the first artist's under the new name.
            .id(artist.name)
            // Read when the page opens, as the album page's reviews are. See ``ArtistPosts``.
            .task(id: artist.name) {
                guard Self.hasWall(artist) else { return }
                let made = artistWalls[artist.name] ?? ArtistPosts(community: model.community,
                                                                   name: artist.name)
                artistWalls[artist.name] = made
                await made.read()
            }
            .overlay {
                if let reporting, reporting.artist == artist.name,
                   let wall = artistWalls[artist.name] {
                    ReportSheet(prompt: Loc.get("Album_ReportCommentPrompt"),
                                onSend: { note in await wall.report(reporting.line, note: note) },
                                onClose: { self.reporting = nil })
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: reporting)
    }

    /// Whether an artist has a wall. The compilations name nobody, and RPM refuses to make an
    /// entry for them.
    private static func hasWall(_ artist: ArtistWallItem) -> Bool {
        !ArtistCredit.isVariousArtists(artist.name)
    }

    /// The artist's wall as the page draws it, or nil for an artist with no wall.
    private func artistWall(of artist: ArtistWallItem) -> AnyView? {
        guard Self.hasWall(artist) else { return nil }

        guard let wall = artistWalls[artist.name] else {
            // Not made yet: the page's task makes it. The box is drawn already, so the page does
            // not grow under the reader when the wall arrives.
            return AnyView(ArtistWallSection(lines: [], answered: false, trouble: nil, sending: false,
                                             draft: .constant(""), onSend: {},
                                             onDelete: { _ in }, onReport: { _ in }))
        }

        let me = model.who?.userId
        return AnyView(
            ArtistWallSection(
                lines: wall.lines.map { WallFace(entry: $0, mine: me != nil && $0.userId == me) },
                answered: wall.answered, trouble: wall.trouble, sending: wall.sending,
                draft: Binding(get: { wall.draft }, set: { wall.draft = $0 }),
                onSend: { Task { await wall.post() } },
                onDelete: { line in Task { await wall.delete(line) } },
                onReport: { line in reporting = WallReport(artist: artist.name, line: line) },
                onAuthor: { openPerson($0) }))
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
                  // account's tracks. A starter record is inside the app already.
                  download: model.viewing.isOwn && !StarterTracks.isStarter(album)
                      ? DownloadKey(standing: model.downloads.standing(of: album.key),
                                    onDownload: { model.downloads.download(album) },
                                    onRemove: { model.downloads.remove([album.key]) },
                                    track: { model.downloads.track($0) })
                      : nil,
                  canPlay: { model.reading.isOnline || model.downloads.isOnPhone($0.rpmId)
                                 || StarterTracks.isStarter($0.rpmId) },
                  shelf: model.albums, onOpenAlbum: open,
                  artists: readArtists.artists(of: album, in: model.albums),
                  onArtist: openArtist,
                  readCredits: { await model.credits(of: $0) },
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

    // ── profiles and the Feed tab ──

    /// Makes the reader's own page, their notifications and the Feed tab's model, once for each account.
    private func makeOwnPage() {
        guard let who = model.who else { return }
        let own = me ?? PersonPage(community: model.community, userId: who.userId, isOwn: true, sample: profileSample)
        if me == nil { me = own }
        if notices == nil { notices = Notices(community: model.community, sample: profileSample) }
        if feed == nil {
            let wearsMark = model.quota?.wearsMark == true
            feed = FeedBook(community: model.community, sample: profileSample) {
                // The reader's own page is read first, as on the Android app. Their sample posts then
                // carry their page's name and photo, and once it is read the badges this phone worked
                // out are sent from the root (``BadgesAsked``), so the Feed tab's dot is right without
                // opening the page.
                if own.profile == nil { await own.read() }
                guard let profile = own.profile else { return nil }
                return FeedBook.Me(name: profile.displayName, userId: profile.userId, hasAvatar: profile.hasAvatar,
                                   supporter: profile.supporter || wearsMark || own.isSample)
            }
        }
    }

    private func feedActions(_ feed: FeedBook) -> FeedActions {
        var actions = FeedActions()
        actions.onMyProfile = {
            makeOwnPage()
            people = []
            showingMe = true
        }
        actions.onOpenPerson = { openPerson($0) }
        actions.onOpenPost = { post in openPerson(post.ownerId, post: post) }
        actions.onVote = { post, value in Task { await feed.vote(post, value) } }
        actions.onVoteReview = { shown, value in Task { await feed.voteReview(shown, value) } }
        actions.onReadReview = { feedReview = RPMFeedItem.review($0).id }
        actions.onMore = { Task { await feed.more() } }
        actions.onRefresh = { await feed.read() }
        return actions
    }

    /// A review on the Feed tab read in full. It is looked up in the feed each time, so a vote on it shows at once.
    @ViewBuilder
    private func feedReviewPage(_ feed: FeedBook) -> some View {
        let found = feed.items.lazy.compactMap { item -> RPMFeedReview? in
            if case .review(let shown) = item, item.id == feedReview { return shown }
            return nil
        }.first
        if let shown = found {
            let review = shown.review
            let album = model.album(for: shown)
            ReviewPage(shown: shown, isOwn: review.userId == model.who?.userId,
                       author: (photo: model.community.avatar(userId: review.userId, hasAvatar: review.hasAvatar)
                                    ?? sampleFaces[review.userId],
                                onPerson: {
                                    feedReview = nil
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(400))
                                        openPerson(review.userId)
                                    }
                                }),
                       coverFor: reviewCover, ground: "",
                       onVote: { value in Task { await feed.voteReview(shown, value) } },
                       onOpenAlbum: album.map { found in { feedReview = nil; openAlbum(found) } },
                       onClose: { feedReview = nil })
        }
    }

    /// The badges the reader's own collection unlocks, worked out here and sent once their page is read; the server
    /// notifies the reader of each new one. None while someone else's collection is open, and none for the starter
    /// tracks shown in place of an empty collection, which are not the reader's (`StarterTracks`).
    private var ownBadges: [String] {
        guard model.viewing.isOwn, !model.albums.isEmpty, !StarterTracks.isStarterShelf(model.albums) else { return [] }
        let shelves = Dictionary(readGenres.genres(model.albums).map { ($0.name, $0.albums.count) }, uniquingKeysWith: +)
        return RPMProfileBadges.unlocked(albums: model.albums.count,
                                         tracks: model.albums.reduce(0) { $0 + $1.tracks.count },
                                         genreAlbums: shelves)
    }

    /// A reviewed record's cover: the reader's own copy's, else the one the cover search finds.
    private func reviewCover(_ shown: RPMFeedReview, _ edge: CGFloat) async -> Image? {
        if let album = model.album(for: shown) {
            return await covers.cover(for: album, edge: edge)?.image
        }
        let key = shown.albumArtist.lowercased() + "\u{1F}" + shown.albumTitle.lowercased()
        let address: URL?
        if let known = foundCovers[key] {
            address = known
        } else {
            do {
                address = try await model.cloud.searchCover(artist: shown.albumArtist, album: shown.albumTitle)
                foundCovers[key] = .some(address)
            } catch {
                // Not kept: asked again the next time the card is drawn.
                return nil
            }
        }
        guard let address else { return nil }
        return await RemotePictures.image(address)
    }

    /// Finds the photo each sample person borrows: a picture of an artist, as the artist page finds one.
    private func findSampleFaces() async {
        guard sampleFaces.isEmpty, let shown = profileSample?() else { return }
        var found: [String: URL] = [:]
        for (userId, artist) in shown.faces {
            guard let pictures = try? await model.cloud.artistPictures(artist: artist, album: nil),
                  let picture = pictures.squares.first ?? pictures.backdrops.first else { continue }
            found[userId] = picture
        }
        sampleFaces = found
    }

    /// The sample page the reader's own profile shows while the server has no profile pages yet.
    /// Only in a test build (a debug build, or a TestFlight build that offers Send feedback): a
    /// listener's build never shows made-up posts.
    private var profileSample: (() -> RPMProfileSample?)? {
        #if DEBUG
        let testBuild = true
        #else
        let testBuild = model.diagnostics.offersFeedback
        #endif
        return testBuild ? { RPMProfileSample.load() } : nil
    }

    /// Opens a person's page over the app, and `post` on it with its replies when one is given. The reader's own name
    /// opens their own page.
    private func openPerson(_ userId: String, post: RPMPost? = nil) {
        guard !userId.isEmpty else { return }
        if userId == model.who?.userId {
            makeOwnPage()
            people = []
            // A page that is already open is not read again, so the post opens at once; otherwise once it is read.
            if let post {
                if showingMe { Task { await me?.open(post) } } else { me?.pendingPost = post }
            }
            showingMe = true
            return
        }
        let page = PersonPage(community: model.community, userId: userId, isOwn: false, sample: profileSample)
        page.pendingPost = post
        people.append(page)
    }

    /// Opens a record in the library tab, as Home's keys do.
    private func openAlbum(_ album: CloudAlbum) {
        tab = .library
        mode = .albums
        opened = [.album(album.key)]
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
                        onAuthor: { review in openPerson(review.userId) },
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

/// What the counts on the reader's page depend on. A change in any of them sends the counts again
/// (`AppModel.reportCounts`, which sends only a changed size).
private struct CountsAsked: Hashable {
    let albums: Int
    let own: Bool
    let userId: String?
}

/// What sending the reader's badges depends on: the collection's size, whether it is the reader's
/// own, and the reader's page once it is read.
private struct BadgesAsked: Hashable {
    let albums: Int
    let own: Bool
    let reader: String?
}

/// A line on an artist's wall that is being reported, and whose wall it is on.
struct WallReport: Equatable {
    let artist: String
    let line: RPMWallEntry
}

/// The screenshot a Send feedback sheet opens with. A new value for every opening, so the sheet
/// is presented from it with `sheet(item:)`.
struct FeedbackShot: Identifiable {
    let id = UUID()
    let png: Data?
}

/// The width of the shell, which the tabs' pages slide across.
private struct ShellWidth: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension RPMTab {
    /// The tab's place in the tab bar, counted from the left.
    var place: Int { RPMTab.allCases.firstIndex(of: self) ?? 0 }
}
