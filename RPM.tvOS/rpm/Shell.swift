import SwiftUI
import RPMKit
import RPMSession

/// The screens, shown in tvOS's sidebar. The sidebar is drawn by the system in Liquid Glass. It
/// opens when the focus moves left from a screen's first column. Each screen has its own stack of
/// pages. Back goes up one level. Back on the top page of a screen opens the sidebar, and a further
/// Back leaves the app, as tvOS does.
///
/// The player is presented over all of them while it is up (`PlayerPresenter`).
struct Shell: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    @Environment(Screensaver.self) private var saver
    @Namespace private var screensFocus

    var body: some View {
        @Bindable var screens = screens

        ZStack {
            TabView(selection: $screens.tab) {
                // A tab that opens the player. It is at the top, as in tvOS's own Music app, and it
                // is shown while something plays. The TV has no mini player.
                if model.player.current != nil || model.player.station != nil {
                    Tab(Loc.get("Atv_Tab_NowPlaying"), systemImage: "waveform", value: TVTab.nowPlaying) {
                        Color.clear
                    }
                }
                Tab(Loc.get("Atv_Tab_Home"), systemImage: "house", value: TVTab.home) {
                    Stacked(.home) { HomeView().keepsFocus(.home, first: "/banner") }
                }
                Tab(Loc.get("Viz_MenuSearch"), systemImage: "magnifyingglass", value: TVTab.search, role: .search) {
                    Stacked(.search) { SearchView() }
                }
                Tab(Loc.get("Viz_MenuAlbums"), systemImage: "square.grid.2x2", value: TVTab.albums) {
                    // The carousel's keys are a UIKit view, which the focus memory cannot name, so the
                    // carousel keeps its own front record instead (FocusMemory).
                    Stacked(.albums) {
                        if model.settings.albumCarousel {
                            AlbumsView()
                        } else {
                            AlbumsView().keepsFocus(.albums, first: nil)
                        }
                    }
                }
                Tab(Loc.get("Viz_MenuArtists"), systemImage: "music.mic", value: TVTab.artists) {
                    Stacked(.artists) { ArtistsView().keepsFocus(.artists, first: nil) }
                }
                Tab(Loc.get("Viz_MenuGenres"), systemImage: "guitars", value: TVTab.genres) {
                    Stacked(.genres) { GenresView().keepsFocus(.genres, first: nil) }
                }
                Tab(Loc.get("Viz_MenuPlaylists"), systemImage: "music.note.list", value: TVTab.playlists) {
                    Stacked(.playlists) { PlaylistsView().keepsFocus(.playlists, first: nil) }
                }
                Tab(Loc.get("Viz_MenuRadio"), systemImage: "dot.radiowaves.left.and.right", value: TVTab.radio) {
                    Stacked(.radio) { RadioView().keepsFocus(.radio, first: nil) }
                }
                TabSection(collectionName) {
                    Tab(Loc.get("Viz_MenuSwitch"), systemImage: "rectangle.stack", value: TVTab.collections) {
                        Stacked(.collections) { CollectionsView().keepsFocus(.collections, first: nil) }
                    }
                    Tab(Loc.get("Viz_MenuSettings"), systemImage: "gearshape", value: TVTab.settings) {
                        Stacked(.settings) { SettingsView().keepsFocus(.settings, first: nil) }
                    }
                }
            }
            .tabViewStyle(.sidebarAdaptable)
            .focusScope(screensFocus)

            // While a collection is loading, a wait screen covers the screens. The collection then
            // appears complete.
            if model.session.shelfArriving {
                Waiting(Loc.get("Viz_SwitchingCollection"))
                    .background(Ink.scrim)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: model.session.shelfArriving)
        // The queue has played to its end or was stopped. The player then closes, as on the phone.
        // This reads the player's `isOver` value. It does not depend on who pressed Stop, because a
        // queue that plays to its end never receives a key press.
        .onChange(of: model.player.isOver) { _, over in
            if over { screens.playerShown = false }
        }
        .onChange(of: screens.tab) { before, now in
            guard now == .nowPlaying else { return }
            screens.playerShown = true
            screens.tab = before == .nowPlaying ? .home : before
        }
        // The player over everything (`PlayerPresenter`).
        .background(PlayerPresenter(model: model, screens: screens, saver: saver, reach: model.reading))
        .fullScreenCover(isPresented: $screens.stationSearchShown, onDismiss: {
            // A station tuned from search opens the player after the search cover has closed. Only
            // one full-screen cover can be shown at a time.
            if screens.takePlayerAfterSearch() { screens.playerShown = true }
        }) {
            // The cover is see-through. The room's background is under it, with the same shade as
            // the collection screens.
            StationSearchPage()
                .background {
                    ZStack {
                        Ink.ground
                        Ink.scrim
                    }
                    .ignoresSafeArea()
                }
        }
        // Questions that a write asks the person. They are shown from the top view. A presentation
        // cannot be shown from a view that already shows the player.
        .modifier(WriteQuestions(active: !screens.playerShown))
    }

    /// The sidebar's lower section is headed with the owner of the open collection. It is the
    /// person's own name, or the name of the account that shares the collection on screen.
    private var collectionName: String {
        if let lender = model.session.lender { return lender }
        if let own = model.session.shelfRows.first(where: \.isOwn)?.face, own.isKnown {
            return own.displayName
        }
        let who = model.session.who
        let name = who?.displayName ?? ""
        return name.isEmpty ? (who?.email ?? Loc.get("Share_MyLibrary")) : name
    }
}

/// A screen with its own stack of pages.
private struct Stacked<Content: View>: View {
    @Environment(Screens.self) private var screens
    let tab: TVTab
    @ViewBuilder let content: () -> Content

    init(_ tab: TVTab, @ViewBuilder content: @escaping () -> Content) {
        self.tab = tab
        self.content = content
    }

    var body: some View {
        let pages = screens.paths[tab, default: []]
        NavigationStack(path: screens.path(tab)) {
            content()
                .toolbar(.hidden, for: .navigationBar)
                // Search is hidden but not disabled. tvOS's search controller does not take the
                // focus back once SwiftUI has disabled it. Going back to the results then left the
                // focus on nothing.
                .shownOnlyOnTop(pages.isEmpty, disabledUnder: tab != .search)
                .navigationDestination(for: Page.self) { page in
                    PageView(page: page)
                        .toolbar(.hidden, for: .navigationBar)
                        .shownOnlyOnTop(pages.last == page, disabledUnder: true)
                }
        }
        // tvOS draws the search field at the top of the stack, under the sidebar's pill. The stack
        // starts lower, so the field is below the pill.
        .padding(.top, tab == .search ? Size.belowPill - Size.top : 0)
    }
}

extension View {
    /// Drawn only when it is the top of its stack. Where `disabledUnder` is set, it also takes
    /// focus only when it is on top. Every screen and page is see-through, so the room shows
    /// through. A screen that tvOS keeps drawn under a page (search results under a record opened
    /// from them) would show through the page. So the view is hidden, not left to be taken away by
    /// the system. There is no default. A screen whose content is tvOS's own (search) must not be
    /// disabled, so each stack says which case it is.
    func shownOnlyOnTop(_ top: Bool, disabledUnder: Bool) -> some View {
        opacity(top ? 1 : 0)
            .disabled(disabledUnder && !top)
            .animation(.easeInOut(duration: 0.25), value: top)
            .accessibilityHidden(!top)
    }
}

/// A page, chosen by what it shows.
struct PageView: View {
    @Environment(TVModel.self) private var model
    let page: Page

    var body: some View {
        switch page {
        case .album(let key):
            if let album = model.session.albums.first(where: { $0.key == key }) {
                RecordPage(of: .album(album), page: page)
            } else {
                Message(Loc.get("Viz_BrowseNoAlbums"))
            }
        case .list(let id):
            if let set = model.session.playlists.first(where: { $0.id == id }) {
                RecordPage(of: .list(set), page: page)
            } else {
                Message(Loc.get("Viz_BrowseNoPlaylists"))
            }
        case .artist(let name):
            ArtistPage(name: name, page: page)
        case .genre(let name):
            GenrePage(name: name, page: page)
        case .tuner(let musicFirst):
            TunerPage(musicFirst: musicFirst)
        case .favourites:
            RecordPage(of: .favourites(model.session.favoriteTracks), page: page)
        }
    }
}
