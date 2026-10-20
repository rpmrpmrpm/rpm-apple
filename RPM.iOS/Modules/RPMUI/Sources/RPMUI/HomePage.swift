import SwiftUI
import RPMSharedUI
import RPMKit
import RPMLibrary
import RPMArt
import RPMDesign
import RPMRadio

/// The home screen: what was played, what to play next, and what was added last.
///
/// It draws what ``HomeScreen`` returns and decides nothing. The rows are fixed once per launch
/// and are not rebuilt each time the page appears. A screen that rearranges itself while the
/// person is looking at it is worse than one that never changes.
public struct HomePage: View {
    private let screen: HomeScreen?
    private let albums: [CloudAlbum]

    /// The generated lists, so a row that has a list name can draw the picture of that list.
    /// ``HomeScreen`` holds names only, as the desktop's cards do.
    private let lists: [PlaylistSet]

    private let covers: any CoverStore
    private let backdrops: BackdropStore?
    private let onOpen: (CloudAlbum) -> Void
    private let onOpenList: (String) -> Void

    /// Plays these tracks in this order: one song from the quick selection, or all its songs.
    private let onPlay: ([CloudTrack]) -> Void

    /// The stations the screen names, by uuid, and what pressing one does. They are used by the
    /// banner's radio card and the quick selection's stations. See `AppModel.homeStations`.
    private let stations: [String: RadioStation]
    private let onTune: (RadioStation) -> Void

    private let onAddMusic: () -> Void

    /// The long-press menu on the quick selection's songs. See ``HomePicksRow/songMenu``.
    private let songMenu: TrackMenu

    /// Whether anyone shares a collection with this account. If nobody does, the key would open
    /// a list with one entry, so it is not drawn.
    private let canSwitch: Bool

    /// Opens the list of collections this account can read.
    private let onSwitch: () -> Void

    /// Whether this page is the one showing.
    ///
    /// **The page stays built under the other tabs**, so that when the person returns from a
    /// record opened here, the scroll position, the front card and each row are as they were.
    /// While hidden, the page must cost nothing: every room on it stops drifting while this is
    /// false. There is no default value, because a page built without it would keep drifting
    /// behind the other tabs.
    private let onScreen: Bool

    /// Called when the page has drawn what it opens on: the banner's front card has its cover and
    /// has looked for its photograph, or there is no banner. The launch keeps its wait mark until
    /// then (see `RootView`), so the page appears fully drawn.
    private let onReady: () -> Void

    public init(screen: HomeScreen?, albums: [CloudAlbum], lists: [PlaylistSet],
                stations: [String: RadioStation],
                covers: any CoverStore, backdrops: BackdropStore? = nil,
                canSwitch: Bool, onSwitch: @escaping () -> Void, onScreen: Bool,
                onOpen: @escaping (CloudAlbum) -> Void,
                onOpenList: @escaping (String) -> Void,
                onPlay: @escaping ([CloudTrack]) -> Void,
                onTune: @escaping (RadioStation) -> Void,
                onAddMusic: @escaping () -> Void,
                songMenu: TrackMenu,
                onReady: @escaping () -> Void) {
        self.onReady = onReady
        self.songMenu = songMenu
        self.screen = screen
        self.stations = stations
        self.onTune = onTune
        self.albums = albums
        self.lists = lists
        self.covers = covers
        self.backdrops = backdrops
        self.onOpen = onOpen
        self.onOpenList = onOpenList
        self.onPlay = onPlay
        self.onAddMusic = onAddMusic
        self.canSwitch = canSwitch
        self.onSwitch = onSwitch
        self.onScreen = onScreen
    }

    /// The measured height of the heading. The heading writes it and the banner reads it.
    @State private var headingHeight: CGFloat = 0

    /// The look of the card in front of the banner. The page background uses it, because the
    /// screen has no picture of its own and the banner is the only part that has one.
    ///
    /// It is kept when the ring moves to a card that has no picture yet. The background under a
    /// card that is still loading is then the last picture and not the default wallpaper. See
    /// ``BannerDress``.
    @State private var dress: BannerDress?

    /// The records by key, so a row of keys can be drawn without searching the library for each
    /// card.
    private var byKey: [String: CloudAlbum] {
        Dictionary(albums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The lists by the name the screen uses for them. If two lists share a name, the first is
    /// used, as ``HomeLists`` does when it opens a list.
    private var listsByName: [String: PlaylistSet] {
        Dictionary(lists.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// The heading of the lists row. It is "Playlists" when the row holds someone's own
    /// playlists (a borrowed shelf), and "Made for you" when it holds only generated lists. The
    /// desktop names its row in the same way.
    private func listsHeading(_ screen: HomeScreen) -> String {
        let lent = screen.lists.contains { listsByName[$0]?.origin == .stored }
        return Loc.get(lent ? "Playlists_Title" : "Home_MadeForYou")
    }

    /// Only the songs that the quick selection names. One pass over the listing finds the dozen
    /// or so tracks on screen, so there is no table of every song in the collection.
    private func songs(of screen: HomeScreen) -> [String: CloudTrack] {
        // A radio entry is keyed by its song too, and drawn from it.
        let wanted = Set(screen.quickPicks.filter { $0.kind == .song || $0.kind == .radio }.map(\.key))
        guard !wanted.isEmpty else { return [:] }

        var found: [String: CloudTrack] = [:]
        found.reserveCapacity(wanted.count)

        for album in albums {
            for track in album.tracks where wanted.contains(track.rpmId) {
                found[track.rpmId] = track
                if found.count == wanted.count { return found }
            }
        }

        return found
    }

    public var body: some View {
        ZStack {
            // The colours of what the banner is showing, under the whole screen. The desktop
            // also colours a page from the item being shown and not from its own wallpaper, and
            // here that item is the front card. See ``ArtGround``.
            // The change is slower than on a page that opens on its own picture, because it
            // happens while a card moves across the strip and has that long to finish.
            ArtGround(picture: dress?.picture, accent: dress?.accent,
                      showing: dress?.wearing ?? "", colours: dress?.colours ?? [],
                      dissolve: 0.45)

            if let screen, screen.gate.open {
                open(screen)
            } else if let screen {
                HomeLock(gate: screen.gate, onAddMusic: onAddMusic)
                    // No banner here to wait for.
                    .onAppear(perform: onReady)
            } else {
                // The shelf has not been read yet. An empty-state message here would wrongly tell
                // the person that their collection is empty while it is still loading.
                Color.clear
            }
        }
        .navigationTitle(Loc.get("Home_Heading"))
    }

    /// The heading is drawn OVER the scroll and not above it. The banner runs up behind the
    /// heading and behind the phone's own status icons.
    ///
    /// **Over, not inside.** The title stays on the same line as every other page's title. The
    /// banner is still the first item in the scroll and scrolls away.
    ///
    /// The heading does not take touches, so a tap on it reaches the card underneath.
    private func open(_ screen: HomeScreen) -> some View {
        scroll(screen)
            .onPreferenceChange(HeadingHeight.self) { headingHeight = $0 }
    }

    /// How far the banner reaches up: the heading plus the strip the phone keeps for its own
    /// icons.
    ///
    /// Zero when there is no banner, so the rows stay below the heading and not under it. Also
    /// zero until the heading has been measured, so the card is not drawn at a wrong height for
    /// one frame.
    @MainActor private func overhang(_ screen: HomeScreen) -> Double {
        guard !screen.strip.isEmpty, headingHeight > 0 else { return 0 }
        return headingHeight + RPMSafeArea.top
    }

    private func scroll(_ screen: HomeScreen) -> some View {
        // Built once per body. These are computed properties over the whole library, and reading
        // them inside the rows loop would rebuild them for every key.
        let byKey = self.byKey
        let listsByName = self.listsByName
        let songs = songs(of: screen)
        let quick = HomePicksRow.drawable(screen.quickPicks, albums: byKey, songs: songs,
                                          stations: stations)

        return Group {
            // Starts at the top of the screen, under the status bar. Content that scrolls up behind
            // the clock and the title fades into the page's background there once the page is
            // scrolled. At rest nothing is removed: the banner runs up behind both.
            DissolvingScroll(under: RPMSafeArea.top + headingHeight) {
                // **This is not a lazy stack, to prevent the page from jumping.** A lazy stack
                // does not know the height of children it has not built yet, so the content
                // height grows as they are created. The scroll indicator then changes length
                // halfway down, and if the correction is above the visible area the page moves
                // under the finger. This is most visible with the quick selection, which is one
                // child with sixteen rows: its whole height is added at the moment it is first
                // built.
                //
                // Building everything costs little. The screen has a banner, the quick selection,
                // at most five rows and a row of lists: eight children, fixed once per launch.
                // Each row is still lazy inside, which matters because a row can be as long as
                // the library.
                VStack(alignment: .leading, spacing: 26) {
                    // The banner. It is not drawn at all (no empty plate) when there is no card to
                    // show, which means the collection is empty.
                    Group {
                        if !screen.strip.isEmpty {
                            HomeBannerView(strip: screen.strip, albums: byKey, lists: listsByName,
                                           stations: stations,
                                           covers: covers, backdrops: backdrops,
                                           overhang: overhang(screen),
                                           onScreen: onScreen,
                                           onOpen: onOpen, onOpenList: onOpenList,
                                           onTune: onTune,
                                           onReady: onReady,
                                           onDressed: { dress = $0 })
                        } else {
                            // Nothing runs up behind the heading, so this spacer takes the room the
                            // banner would have taken: the heading and the status bar, because the
                            // scroll starts at the top of the screen either way.
                            Color.clear.frame(height: headingHeight + RPMSafeArea.top)
                                // No banner to wait for.
                                .onAppear(perform: onReady)
                        }
                    }

                    // **Directly under the banner**, as on the desktop. The banner offers one thing
                    // to play and this offers sixteen, which is a quicker way to music the person
                    // already likes than any row of records.
                    if !quick.isEmpty {
                        HomePicksRow(heading: Loc.get("Home_QuickPicks"), picks: quick,
                                     albums: byKey, songs: songs, lists: listsByName,
                                     stations: stations, covers: covers,
                                     songLine: .artist,
                                     onOpen: onOpen, onOpenList: onOpenList, onPlay: onPlay,
                                     onTune: onTune, songMenu: songMenu)
                    }

                    ForEach(screen.rows, id: \.kind) { row in
                        let records = row.keys.compactMap { byKey[$0] }
                        if !records.isEmpty {
                            HomeRowView(heading: title(of: row.kind), albums: records,
                                        covers: covers, onOpen: onOpen)
                        }
                    }

                    if !screen.lists.isEmpty {
                        HomeListsRow(heading: listsHeading(screen), names: screen.lists,
                                     lists: listsByName, covers: covers, onOpen: onOpenList)
                    }
                }
                // Space under the last row only. The header above already provides the space over
                // the first row, as on the library.
                .padding(.bottom, RPMLayout.foot)
            }
            // **Over the scroll, and fixed while the page scrolls**, like every other page's
            // header. The banner runs up behind it at rest. Once the page is scrolled, the blur
            // that the scroller draws under the status bar also extends under the title.
            .overlay(alignment: .top) {
                heading
                    .background {
                        GeometryReader { box in
                            Color.clear.preference(key: HeadingHeight.self,
                                                   value: box.size.height)
                        }
                    }
                    // Measured first and padded after. The banner reaches up behind the heading and
                    // the strip for the phone's own icons, and `overhang` adds the two. If the
                    // padding were measured too, the strip would be counted twice.
                    .padding(.top, RPMSafeArea.top)
                    .allowsHitTesting(false)
            }
            // Shows whose collection is on screen, on the title's line where the library's keys
            // are. It is a separate layer because the heading lets touches through to the
            // banner under it, and this key must receive them.
            .overlay(alignment: .topTrailing) {
                if canSwitch { switcher }
            }
            // The scroll starts at the top of the SCREEN, not below the status bar, because the
            // top of the banner fills that strip. The heading over it keeps its own safe area, so
            // the title does not move.
            .ignoresSafeArea(edges: .top)
        }
    }

    /// The height of the heading, which is part of how far the banner reaches up. It is measured
    /// and not fixed, because the heading can be two lines of text at the person's own text
    /// size.
    private struct HeadingHeight: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    /// The page's title, with the same font, insets and line as every other page's title. The
    /// numbers are kept in `LibraryPage.header`, and these are the same numbers. There is no top
    /// padding, because a header starts at the safe area.
    private var heading: some View {
        // The title only. The album count belongs to the collection page, not to home.
        PageTitle(Loc.get("Home_Heading"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, RPMLayout.margin)
            .padding(.trailing, 16)
            .padding(.bottom, 10)
    }

    /// The key that chooses whose collection the app shows. It is here and not in the settings,
    /// as on the desktop deck: a way to open someone's collection that exists only in settings
    /// is easy to forget, and a borrowed shelf with no obvious way out can make the person think
    /// their own records are gone. It is on home because the whole app follows the choice, not
    /// only the library tab.
    private var switcher: some View {
        Button {
            Haptics.pick()
            onSwitch()
        } label: {
            Text("\u{f5db}")
                .font(RPMFont.icon(16))
                .foregroundStyle(RPMInk.white(0xB8 / 255))
        }
        .buttonStyle(RPMGlassKey(edge: 40))
        .accessibilityLabel(Loc.get("Rpm_Share_Pick"))
        // 16 points from the edge, where the library's glass keys end.
        .padding(.top, RPMSafeArea.top + 4)
        .padding(.trailing, 16)
    }

    /// The heading for each kind of row. The strings are the desktop's, so both apps name the
    /// same row in the same way.
    private func title(of kind: HomeRowKind) -> String {
        switch kind {
        case .listened: return Loc.get("Home_Listened")
        case .suggested: return Loc.get("Home_Suggested")
        case .taste: return Loc.get("Home_Taste")
        case .played: return Loc.get("Home_Played")
        case .added: return Loc.get("Home_Added")
        }
    }
}

/// The generated lists, drawn as the same square as a record: the list's own picture, at the
/// size of a cover in the rows above.
///
/// The picture is the one the list uses everywhere else in the app, so the card here and the
/// head of the list that it opens show the same picture. If no picture is available, the list's
/// mark is drawn in the middle of the square.
struct HomeListsRow: View {
    let heading: String

    /// The list names that the screen holds, in the order they were received.
    let names: [String]

    /// The lists themselves, by name, for the picture of each one.
    let lists: [String: PlaylistSet]

    let covers: any CoverStore

    let onOpen: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(RPMFont.display(19))
                .padding(.horizontal, RPMLayout.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(names, id: \.self) { name in
                        Button { onOpen(name) } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                PlaylistSleeve(list: lists[name]?.picture,
                                               track: lists[name]?.tracks.first,
                                               glyph: Glyph.playlists,
                                               edge: HomeRowView.art, corner: 10, mark: 26,
                                               covers: covers,
                                               framed: FramedList.of(lists[name]),
                                               // Static: a room drifts only on the banner plate,
                                               // because each square here runs a shader of its
                                               // own.
                                               roomDrifts: false)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
                                    }

                                Text(name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            .frame(width: HomeRowView.art, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
            }
            .scrollClipDisabled()
        }
    }
}

/// The quick selection: the items this listener plays most, of any kind, taken one kind at a
/// time. It is drawn as lines and not squares, because it is a list of things to play and not a
/// shelf to browse. Each line has a small square with the picture for its kind, which lets the
/// person tell a song from its record at a glance.
///
/// It is laid out in panels of ``QuickPicks/tall`` lines, filled downward and then across. The
/// person swipes sideways one panel at a time, and the edge of the next panel is visible. The
/// desktop shows four columns, but a phone has room for one, so the others are beyond the
/// right-hand edge. Home, an artist's page and a genre's page all draw it this way.
struct HomePicksRow: View {

    /// What the line under a song's title says.
    enum SongLine {
        /// The artist, where the songs are by several artists: home and a genre's page.
        case artist

        /// The record, where every song is by one artist: the artist page, like its All tracks
        /// rows.
        case record
    }

    let heading: String
    let picks: [QuickPick]
    let albums: [String: CloudAlbum]
    let songs: [String: CloudTrack]
    let lists: [String: PlaylistSet]
    let stations: [String: RadioStation]
    let covers: any CoverStore
    let songLine: SongLine
    let onOpen: (CloudAlbum) -> Void
    let onOpenList: (String) -> Void
    let onPlay: ([CloudTrack]) -> Void
    let onTune: (RadioStation) -> Void

    /// The long-press menu on a song's line, the same as every other song row in the app.
    /// Records, playlists and stations have no menu on the phone.
    let songMenu: TrackMenu

    /// What a radio entry does. See ``EnvironmentValues/startRadio``.
    @Environment(\.startRadio) private var startRadio

    /// The cover size beside a line. The desktop uses 48, and the phone uses 4 points less
    /// because its lines are narrower.
    private static let art: Double = 44

    /// The height of one line. The panels' height is calculated from it.
    private static let lineHeight: Double = 60

    /// The height of the heading line. It equals the play key's height whether or not the key is
    /// drawn, so the block has the same height either way.
    private static let headingHeight: Double = 34

    /// The space between the heading and the first line.
    private static let underHeading: Double = 10

    /// How much of the next panel is visible at the right-hand edge. It shows that there is more
    /// of the selection to swipe to.
    private static let peek: Double = 32

    /// The space between two panels.
    private static let panelsApart: Double = 16

    /// The picks this screen can draw, in order.
    ///
    /// **They are removed before the panels are built, so the panels have no gaps.** A song or
    /// record that is no longer in the library has no title and cannot be opened (the play
    /// counts outlive the files, see HomeSongs). A station that is no longer in the log has no
    /// address to tune. The desktop skips the same entries when it builds its cards, before
    /// `QuickPicks.InPanels`.
    static func drawable(_ picks: [QuickPick], albums: [String: CloudAlbum],
                         songs: [String: CloudTrack],
                         stations: [String: RadioStation]) -> [QuickPick] {
        picks.filter { pick in
            switch pick.kind {
            case .song, .radio: return songs[pick.key] != nil
            case .album: return albums[pick.key] != nil
            case .playlist: return true
            case .station: return stations[pick.key] != nil
            }
        }
    }

    private var shown: [QuickPick] {
        Self.drawable(picks, albums: albums, songs: songs, stations: stations)
    }

    /// Every song in the selection, in the order shown. The play key plays these.
    private var everySong: [CloudTrack] {
        picks.compactMap { $0.kind == .song ? songs[$0.key] : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.underHeading) {
            HStack(spacing: 8) {
                Text(heading)
                    .font(RPMFont.display(19))

                // **Only the songs.** A record is about a dozen songs and a station is not a set
                // of songs at all. Playing "everything here" would make a queue whose length
                // depends on what the selection holds. The desktop does the same.
                if !everySong.isEmpty {
                    let songs = everySong
                    Button { Haptics.pick(); onPlay(songs) } label: {
                        Text(Glyph.play)
                            .font(RPMFont.icon(12))
                            .foregroundStyle(RPMInk.white(0xB8 / 255))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Loc.get("Home_PlayAllTracks"))
                }

                Spacer(minLength: 0)
            }
            .frame(height: Self.headingHeight)
            .padding(.horizontal, RPMLayout.margin)

            panels
        }
    }

    /// The panels side by side. Each is one screen width minus the visible edge of the next. The
    /// scroll snaps to a panel when a swipe ends, so a panel never stops half visible. Every
    /// panel, including the last, stops at the page's margin: see ``PanelStrip``.
    private var panels: some View {
        let panels = QuickPicks.inPanels(shown, tall: QuickPicks.tall)
        let lines = panels.map(\.count).max() ?? 0

        return GeometryReader { box in
            let strip = PanelStrip(screen: box.size.width, margin: RPMLayout.margin,
                                   peek: Self.peek, panels: panels.count)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Self.panelsApart) {
                    ForEach(Array(panels.enumerated()), id: \.offset) { _, panel in
                        VStack(spacing: 0) {
                            ForEach(Array(panel.enumerated()), id: \.offset) { _, pick in
                                row(pick)
                            }
                        }
                        .frame(width: strip.width, alignment: .top)
                    }
                }
                .scrollTargetLayout()
            }
            // Margins on the content and not padding inside it, so a panel snaps to the page's
            // margin and not to the edge of the glass.
            .contentMargins(.leading, strip.leading, for: .scrollContent)
            .contentMargins(.trailing, strip.trailing, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            // The panels scroll sideways inside a page that scrolls down. Clipping is disabled so
            // that content is not cut off at the bounds.
            .scrollClipDisabled()
        }
        .frame(height: Double(lines) * Self.lineHeight)
    }

    @ViewBuilder
    private func row(_ pick: QuickPick) -> some View {
        switch pick.kind {
        case .song:
            if let track = songs[pick.key] {
                Button { onPlay([track]) } label: {
                    line(title: track.title ?? "",
                         subtitle: songLine == .record ? track.album : track.artist,
                         glyph: Glyph.song, track: track, list: nil)
                }
                .buttonStyle(.plain)
                .trackActions(track, songMenu)
            }

        case .radio:
            // Named for the song it starts from, the kind first on the line under it, so it
            // reads as a radio and not as the song's own line further on.
            if let track = songs[pick.key] {
                Button { startRadio?(track) } label: {
                    line(title: track.title ?? "",
                         subtitle: Self.kindLine("Home_QuickMixtape", track.artist),
                         glyph: Glyph.mixtape, track: track, list: nil)
                }
                .buttonStyle(.plain)
            }

        case .album:
            if let album = albums[pick.key] {
                Button { onOpen(album) } label: {
                    line(title: album.album,
                         subtitle: Self.kindLine("Home_QuickAlbum", album.artist),
                         glyph: Glyph.record, track: album.tracks.first, list: nil)
                }
                .buttonStyle(.plain)
            }

        case .playlist:
            let set = lists[pick.key]
            Button { onOpenList(pick.key) } label: {
                line(title: pick.key,
                     subtitle: Self.kindLine("Home_QuickPlaylist",
                                             set.map { Loc.get("Home_Songs", $0.tracks.count) }),
                     glyph: Glyph.playlists,
                     track: set?.tracks.first, list: set?.picture,
                     framed: FramedList.of(set))
            }
            .buttonStyle(.plain)

        case .station:
            if let station = stations[pick.key] {
                Button { onTune(station) } label: {
                    HStack(spacing: 12) {
                        stationSquare(station)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(station.display)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)

                            // The kind of entry, with the same text as the desktop.
                            Text(Loc.get("Home_QuickStation"))
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(height: Self.lineHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// A station's logo in the square that a cover uses, on a dark background so that both a
    /// transparent logo and a white square look correct. If the station has no logo, the radio
    /// mark is drawn.
    private func stationSquare(_ station: RadioStation) -> some View {
        let well = RoundedRectangle(cornerRadius: 5, style: .continuous)

        return ZStack {
            well.fill(Color.black.opacity(0x22 / 255))

            StationFace(station: station, edge: Self.art, inset: 4, onWearing: { _ in }) {
                Text(Glyph.radio)
                    .font(RPMFont.icon(15))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: Self.art, height: Self.art)
        .clipShape(well)
    }

    /// The line under an album's or playlist's name: the kind, then the artist or the list's
    /// caption ("Album • Sting", "Playlist • 24 songs"). This separates a record or a list from
    /// a song, whose line shows only the artist. If nothing follows the kind, only the kind is
    /// shown. The desktop writes the same line (`HomeView.KindLine`).
    private static func kindLine(_ kindKey: String, _ rest: String?) -> String {
        guard let rest, !rest.trimmingCharacters(in: .whitespaces).isEmpty else {
            return Loc.get(kindKey)
        }
        return Loc.get("Home_QuickKindJoin", Loc.get(kindKey), rest)
    }

    private func line(title: String, subtitle: String?, glyph: String,
                      track: CloudTrack?, list: ListPicture?,
                      framed: FramedList? = nil) -> some View {
        HStack(spacing: 12) {
            PlaylistSleeve(list: list, track: track, glyph: glyph,
                           edge: Self.art, corner: 5, mark: 15, covers: covers, framed: framed)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: Self.lineHeight)
        .contentShape(Rectangle())
    }
}
