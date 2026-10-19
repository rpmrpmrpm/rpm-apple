import SwiftUI
import RPMArt
import RPMDesign
import RPMKit
import RPMLibrary
import RPMSharedUI

/// The screens in the sidebar.
enum TVTab: String, Hashable, CaseIterable {
    /// Not a screen: the sidebar's way to the player while something plays. Chosen, it opens the
    /// player and the sidebar goes back to the screen it was on.
    case nowPlaying
    case home, search, albums, artists, genres, playlists, radio, collections, settings
}

/// A page opened over a screen, pushed on that screen's stack.
enum Page: Hashable {
    /// A record's page, by its wall key.
    case album(String)
    /// A list's page, by its id.
    case list(String)
    /// An artist's page, by the name the artists list shows.
    case artist(String)
    /// A genre's page, by its name.
    case genre(String)
    /// The radio tuner. True when it is opened from Music, which offers the genres first.
    case tuner(Bool)
    /// The account's favourite songs.
    case favourites
}

/// A song, and a list that already holds it.
struct FileAgain: Identifiable {
    let track: CloudTrack
    let list: PlaylistSet
    var id: String { list.id + "/" + track.rpmId }
}

/// Which screen is up, what is open over it, and whether the player covers it.
///
/// The room's colours come from the page on top of the current screen's stack (``pageColours``).
/// They do not come from each page reporting when it appears and disappears. Pushing and popping
/// fire those reports in no guaranteed order. The stack always holds the right answer when it is
/// asked.
@MainActor
@Observable
final class Screens {
    var tab: TVTab = Screens.firstTab

    /// The tab that opens first, which is home. In a debug build, the environment variable
    /// `RPM_TAB` (a tab's name, such as `playlists`) opens that tab instead. A script can then
    /// reach a screen without counting sidebar rows. Release builds do not read this variable.
    private static var firstTab: TVTab {
        #if DEBUG
        if let named = ProcessInfo.processInfo.environment["RPM_TAB"], let tab = TVTab(rawValue: named) {
            return tab
        }
        #endif
        return .home
    }
    var paths: [TVTab: [Page]] = [:]

    /// Whether the player is up over the screens.
    var playerShown = false

    /// Whether the opening screen still covers the screens. The banner holds its first card until
    /// the opening is gone.
    var openingUp = true

    /// Whether a key has been pressed since the app opened. Until then, the focus that the opening
    /// gave to home's banner is not shown. The banner then steps by itself, as the Android TV app
    /// does while its focus is not lit (`LocalFocusVisibility`).
    var remoteUsed = false

    /// Whether the station search is up, over everything except the player. It is shown as a whole
    /// screen, not pushed onto radio's stack. tvOS draws a search field at the top of the screen.
    /// On a pushed page that field is under the sidebar pill.
    var stationSearchShown = false

    /// What the player shows that Back takes away before it closes the player. The player and its
    /// queue drawer set these: the keys, and the drawer. The drawer first puts back a row that is
    /// being carried.
    var playerKeysUp = false
    var playerDrawerOpen = false

    /// Counts the Back presses that the player is asked to handle. The open drawer, or otherwise
    /// the player, answers each press.
    private(set) var playerBackAsked = 0

    /// Back in the player. Returns true when something in the player takes the press, and false
    /// when the player should close. The player is a presentation. tvOS gives Back to its
    /// controller before any view in it (`PlayerController`).
    func backInPlayer() -> Bool {
        guard playerShown, playerKeysUp || playerDrawerOpen else { return false }
        playerBackAsked += 1
        return true
    }

    /// A station tuned from the station search, whose player opens once the search has gone.
    private var playerAfterSearch = false

    /// Closes the station search. The player opens after the search has gone (`Shell`). Only one
    /// cover is shown at a time. A player requested while the search was still up would not be
    /// shown.
    func playAfterSearch() {
        playerAfterSearch = true
        stationSearchShown = false
    }

    /// Whether the station search, now gone, asked for the player. It is read only once.
    func takePlayerAfterSearch() -> Bool {
        defer { playerAfterSearch = false }
        return playerAfterSearch
    }

    /// The track that a new playlist is being named for, while the name is asked.
    var naming: CloudTrack?

    /// A song and a list that already holds it. Used while the question of adding it again is
    /// asked.
    var fileAgain: FileAgain?

    /// The room's reading of the audio. The room and the player's spectrum both use it. There is
    /// one for the whole app, and it starts once.
    @ObservationIgnored let room = RoomReader()

    /// The colours each page asked the room to be lit in, by page.
    private var colours: [Page: SleeveColours] = [:]

    func path(_ tab: TVTab) -> Binding<[Page]> {
        Binding(get: { self.paths[tab] ?? [] }, set: { self.paths[tab] = $0 })
    }

    func open(_ page: Page) {
        paths[tab, default: []].append(page)
    }

    /// Closes the player and opens `page` on the screen under it first. The player is a
    /// presentation. When it closes, tvOS gives the focus to the page on top. A page pushed after
    /// the player had gone would be pushed while tvOS was still giving the focus back to the screen
    /// under it. On search, such a page never got the focus.
    func leavePlayer(for page: Page) {
        open(page)
        playerShown = false
    }

    /// Increased to ask the screen on top to take back the focus it last had
    /// (``keepsFocus(_:first:)``). The screens lose the focus under the player, and nothing gives
    /// it back by itself. It is also used when the opening hands over. The tabs came up while home
    /// was still loading, with nothing on home to focus. So the focus starts in the sidebar. tvOS
    /// then closes the sidebar by itself, a few seconds after home shows, and moves every screen
    /// across.
    private(set) var focusBack = 0

    func giveFocusBack() {
        focusBack += 1
    }

    /// A screen picked from the sidebar opens on its top page, as on Android TV.
    func show(_ tab: TVTab) {
        self.tab = tab
    }

    func paint(_ page: Page, _ sleeve: SleeveColours) {
        colours[page] = sleeve
    }

    /// The colours of the page on top of the screen that is up. Nil when the screen has no page
    /// open, which leaves the room in the colours of what is playing.
    var pageColours: SleeveColours? {
        guard !playerShown, let top = paths[tab]?.last else { return nil }
        return colours[top]
    }

    /// Forgets everything that is open. Used when a collection is switched or an account is signed
    /// out.
    func reset() {
        paths = [:]
        colours = [:]
        playerShown = false
        stationSearchShown = false
        tab = .home
    }
}
