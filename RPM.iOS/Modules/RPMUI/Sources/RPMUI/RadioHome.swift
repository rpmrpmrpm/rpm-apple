import SwiftUI
import RPMSharedUI
import RPMKit
import RPMLibrary
import RPMRadio
import RPMSession
import RPMDesign
import RPMArt

/// The radio tab's first page, built like home (``HomePage``). From the top:
///
/// - **The banner**: the stations heard most and the local stations, one of each in turn
///   (``RadioHomePicks/banner(heard:local:most:dressed:)``), the stations with both a card picture
///   and a description from the admin first. Each card shows its card picture, or else stands on
///   its station's room, as home's radio card does. It says why the station is there, and under
///   the name the station's description, or else its genre and country.
/// - **Quick selection**, drawn as home's is: the stations the person pinned, then their saved
///   stations, then stations suggested from the genres they listen to
///   (``RadioHomePicks/quick(pinned:saved:suggested:most:)``). A long press on any station pins it
///   here (``Holds``).
/// - **A row of local stations**: the most played stations of the listener's country. Left out
///   when the directory has none for that country: the stations read then are the world's, and the
///   last row already shows those.
/// - **A row of the world's most played stations**, without the local ones.
///
/// The round key on the title's line opens the tuner: the dial, the search and the full list of
/// stations (``RadioPage``).
///
/// The page is dressed in the front card's colours, as home is (``BannerDress``).
///
/// It draws what it is given and reads nothing itself, except a genre's stations for the
/// suggestions (`stationsOf`).
public struct RadioHome: View {
    /// The stations heard most on every device, the most heard first.
    private let heard: [RadioStation]

    /// The local stations as last read. See ``RadioShelves/Local``.
    private let local: RadioShelves.Local

    /// The world's most played stations.
    private let popular: [RadioStation]

    /// The listener's own saved stations, or a shared collection's owner's. Both are listed on
    /// Quick selection.
    private let saved: SavedStations

    private let covers: any CoverStore

    /// Whether this page is the one showing: the banner turns only then. See
    /// ``HomeBannerView``.
    private let onScreen: Bool

    /// The directory's most played stations of one genre, for the suggestions. See
    /// ``RadioShelves/stations(of:)``.
    private let stationsOf: (String) async -> [RadioStation]

    private let onTune: (RadioStation) -> Void
    private let onOpenTuner: () -> Void

    public init(heard: [RadioStation], local: RadioShelves.Local, popular: [RadioStation],
                saved: SavedStations, covers: any CoverStore, onScreen: Bool,
                stationsOf: @escaping (String) async -> [RadioStation],
                onTune: @escaping (RadioStation) -> Void,
                onOpenTuner: @escaping () -> Void) {
        self.heard = heard
        self.local = local
        self.popular = popular
        self.saved = saved
        self.covers = covers
        self.onScreen = onScreen
        self.stationsOf = stationsOf
        self.onTune = onTune
        self.onOpenTuner = onOpenTuner
    }

    /// What rpm hides and how it shows stations. Every list is drawn through these rules.
    @Environment(RadioState.self) private var radioState

    /// The stations the person pinned. See ``Holds``.
    @Environment(Holds.self) private var holds: Holds?

    /// The measured height of the heading. The heading writes it and the banner reads it.
    @State private var headingHeight: CGFloat = 0

    /// The look of the card in front of the banner, for the page's ground. See ``BannerDress``.
    @State private var dress: BannerDress?

    /// The directory's answers for the genres of the person's taste.
    @State private var answers = Answers(genres: [], stations: [])

    /// One list of stations for each genre, and the genres they answer. Kept together, so the
    /// answers for one taste are never read as the answers for another.
    private struct Answers: Equatable {
        let genres: [String]
        let stations: [[RadioStation]]
    }

    /// How many local stations the row under Quick selection shows.
    static let localRow = 20

    /// How many of the world's most played stations the last row shows.
    static let popularRow = 20

    /// Everything the page draws, worked out once per body.
    private struct Shown {
        let local: [RadioStation]
        let popular: [RadioStation]
        let banner: [StationPick]
        let quick: [StationPick]

        /// The genres the suggestions are asked for, most heard first.
        let genres: [String]

        /// Why each station on the banner is there, by uuid.
        let why: [String: StationWhy]
    }

    private func workOut(_ rules: StationRules) -> Shown {
        // The local stations are read for the listener's country. When it has none, the world's
        // stations are read instead: they are not local, and they stand in for the world's row
        // until that row has been read.
        var nearby: [RadioStation] = []
        var world: [RadioStation] = []
        if case .read(let stations, let country) = local {
            if country != nil { nearby = stations } else { world = stations }
        }

        let localShown = Array(rules.shown(nearby).prefix(Self.localRow))
        let heardShown = rules.shown(heard)
        // The stations the admin gave both a card picture and a description first: their cards
        // are the best looking ones.
        let banner = RadioHomePicks.banner(heard: heardShown, local: localShown) { station in
            rules.cards.has(station) && station.edit?.description != nil
        }
        let pinned = rules.shown(holds?.pinnedStations ?? [])
        let savedShown = rules.shown(saved.stations)

        // The person's own stations, the pinned and saved ones first: they decide a tie between
        // two genres.
        let theirs = pinned + savedShown + Array(heardShown.prefix(RadioHomePicks.tasteFrom))
        let genres = RadioHomePicks.taste(theirs)
        let popularShown = Array(RadioHomePicks.without(rules.shown(popular.isEmpty ? world : popular),
                                                        localShown)
                                     .prefix(Self.popularRow))

        // With no genres yet, the local and the world's stations stand in for the suggestions.
        let from: [[RadioStation]]
        if genres.isEmpty {
            from = [localShown, popularShown]
        } else if answers.genres == genres {
            from = answers.stations.map { rules.shown($0) }
        } else {
            from = []
        }
        let suggested = RadioHomePicks.suggested(from, known: theirs)
        let quick = RadioHomePicks.quick(pinned: pinned, saved: savedShown, suggested: suggested)

        return Shown(local: localShown, popular: popularShown, banner: banner, quick: quick,
                     genres: genres,
                     why: Dictionary(banner.map { ($0.station.uuid, $0.why) },
                                     uniquingKeysWith: { first, _ in first }))
    }

    public var body: some View {
        let shown = workOut(radioState.rules)

        ZStack {
            // The front card's colours, under the whole page, as home's ground takes them. The
            // app's own ground until a card has dressed the page.
            ArtGround(picture: dress?.picture, accent: dress?.accent,
                      showing: dress?.wearing ?? "", colours: dress?.colours ?? [],
                      dissolve: 0.45)

            page(shown)
                .onPreferenceChange(HeadingHeight.self) { headingHeight = $0 }
        }
        // The stations of each genre of the person's taste, asked again when the taste changes.
        // Each answer is kept 30 minutes by ``RadioShelves``.
        .task(id: shown.genres) { [genres = shown.genres] in
            guard !genres.isEmpty else { return }
            var found: [[RadioStation]] = []
            for genre in genres {
                let stations = await stationsOf(genre)
                guard !Task.isCancelled else { return }
                found.append(stations)
            }
            answers = Answers(genres: genres, stations: found)
        }
    }

    /// How far the banner reaches up: the heading plus the strip the phone keeps for its own
    /// icons. Zero until the heading has been measured, as on home.
    @MainActor private var overhang: Double {
        guard headingHeight > 0 else { return 0 }
        return headingHeight + RPMSafeArea.top
    }

    /// The heading is drawn over the scroll and not above it, and the banner runs up behind it,
    /// as on home. See `HomePage.open`.
    private func page(_ shown: Shown) -> some View {
        DissolvingScroll(under: RPMSafeArea.top + headingHeight) {
            // Not a lazy stack, for the reason given on home: a lazy stack does not know the
            // height of what it has not built, and the page would jump. Each row is lazy inside.
            VStack(alignment: .leading, spacing: 26) {
                banner(shown)

                quickSelection(shown.quick)

                if !shown.local.isEmpty {
                    StationShelf(heading: Loc.get("Radio_HomeLocal"), stations: shown.local,
                                 onTune: onTune)
                }

                if !shown.popular.isEmpty {
                    StationShelf(heading: Loc.get("Radio_HomePopular"), stations: shown.popular,
                                 onTune: onTune)
                }

                if shown.local.isEmpty && shown.popular.isEmpty {
                    waiting
                }
            }
            .padding(.bottom, RPMLayout.foot)
        }
        // The shade under the status bar and the title, as on home. Only over a banner.
        .overlay(alignment: .top) {
            if !shown.banner.isEmpty {
                HomeFeatureCard.topShade
                    .frame(maxWidth: .infinity)
                    .frame(height: HomeFeatureCard.topFade)
                    .allowsHitTesting(false)
            }
        }
        // Over the scroll and fixed while the page scrolls. It lets touches through to the
        // banner under it.
        .overlay(alignment: .top) {
            heading
                .background {
                    GeometryReader { box in
                        Color.clear.preference(key: HeadingHeight.self, value: box.size.height)
                    }
                }
                // Measured first and padded after, as on home: the overhang adds the status bar.
                .padding(.top, RPMSafeArea.top)
                .allowsHitTesting(false)
        }
        // Where home has its collections key: on the title's line, 16 from the edge.
        .overlay(alignment: .topTrailing) { tunerKey }
        // The scroll starts at the top of the screen, because the banner fills the strip under
        // the status bar. The heading keeps its own safe area.
        .ignoresSafeArea(edges: .top)
    }

    /// The banner, or the room it would take when there is no card yet.
    @ViewBuilder
    private func banner(_ shown: Shown) -> some View {
        if !shown.banner.isEmpty {
            HomeBannerView(strip: shown.banner.map { HomeFeature(kind: .radio, key: $0.station.uuid) },
                           albums: [:], lists: [:],
                           stations: Dictionary(shown.banner.map { ($0.station.uuid, $0.station) },
                                                uniquingKeysWith: { first, _ in first }),
                           covers: covers, backdrops: nil,
                           overhang: overhang,
                           onScreen: onScreen,
                           onOpen: { _ in }, onOpenList: { _ in },
                           onTune: onTune,
                           // Nothing waits for this page's first card: the launch waits for home.
                           onReady: {},
                           onDressed: { dress = $0 },
                           stationWords: { station in
                               HomeBannerView.StationWords.card(
                                   station,
                                   kicker: Loc.get(shown.why[station.uuid] == .local
                                                   ? "Radio_HomeNearYou" : "Radio_HomeOnRepeat"),
                                   state: radioState)
                           })
        } else {
            // Nothing runs up behind the heading, so this takes the room the banner would take.
            Color.clear.frame(height: headingHeight + RPMSafeArea.top)
        }
    }

    /// The page's title, with the same font, insets and line as every other page's title.
    private var heading: some View {
        PageTitle(Loc.get("Rpm_Tab_Radio"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, RPMLayout.margin)
            .padding(.trailing, 16)
            .padding(.bottom, 10)
    }

    /// The round glass key that opens the tuner.
    private var tunerKey: some View {
        Button {
            Haptics.pick()
            onOpenTuner()
        } label: {
            Text(Glyph.tuner)
                .font(RPMFont.icon(15))
                .foregroundStyle(RPMInk.white(0xB8 / 255))
        }
        .buttonStyle(RPMGlassKey(edge: 40))
        .accessibilityLabel(Loc.get("Radio_HomeTuner"))
        .padding(.top, RPMSafeArea.top + 4)
        .padding(.trailing, 16)
    }

    /// Quick selection, drawn as home's is: lines in panels of four, from the top down, swiped one
    /// panel at a time with the edge of the next panel showing. While it has nothing, a line says
    /// how to pin a station.
    private func quickSelection(_ picks: [StationPick]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Loc.get("Home_QuickPicks"))
                .font(RPMFont.display(19))
                .feathered()
                .frame(height: 34)
                .padding(.horizontal, RPMLayout.margin)

            if picks.isEmpty {
                Text(Loc.get("Radio_HomeQuickEmpty"))
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, RPMLayout.margin)
            } else {
                StationPanels(picks: picks, onTune: onTune)
            }
        }
    }

    /// Shown while there is no row of stations: a spinner while the directory is asked, or why
    /// there is nothing when it did not answer.
    @ViewBuilder
    private var waiting: some View {
        if local == .unavailable {
            Text(Loc.get("Radio_DirectoryDown"))
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0xAA / 255))
                .padding(.horizontal, RPMLayout.margin)
        } else {
            RecordSpinner(diameter: 34)
                .frame(maxWidth: .infinity)
        }
    }

    /// Example: "Jazz · Netherlands". The station's first genre and its country, either of them,
    /// or nil with neither.
    static func shortLine(_ station: RadioStation) -> String? {
        let genre = station.shownTags.lazy.compactMap { RadioGenres.names($0).first }.first
        let place = RadioCountries.short(station.country, station.countryCode)
        let parts = [genre, place.isEmpty ? nil : place].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "  \u{b7}  ")
    }

    /// The height of the heading, measured, because it can be two lines at the person's own text
    /// size. See `HomePage.HeadingHeight`.
    private struct HeadingHeight: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }
}

/// Quick selection's panels on the radio home, laid out as home's (``HomePicksRow``): each panel
/// one screen width less the visible edge of the next, snapping to a panel when a swipe ends.
private struct StationPanels: View {
    let picks: [StationPick]
    let onTune: (RadioStation) -> Void

    /// The height of one line, as on home.
    private static let lineHeight: Double = 60

    /// How much of the next panel shows at the right-hand edge, as on home.
    private static let peek: Double = 32

    /// The space between two panels, as on home.
    private static let panelsApart: Double = 16

    var body: some View {
        let panels = RadioHomePicks.inPanels(picks)
        let lines = panels.map(\.count).max() ?? 0

        return GeometryReader { box in
            let strip = PanelStrip(screen: box.size.width, margin: RPMLayout.margin,
                                   peek: Self.peek, panels: panels.count)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Self.panelsApart) {
                    ForEach(Array(panels.enumerated()), id: \.offset) { _, panel in
                        VStack(spacing: 0) {
                            ForEach(panel) { pick in line(pick) }
                        }
                        .frame(width: strip.width, alignment: .top)
                    }
                }
                .scrollTargetLayout()
            }
            // Margins on the content, so a panel snaps to the page's margin. See ``PanelStrip``.
            .contentMargins(.leading, strip.leading, for: .scrollContent)
            .contentMargins(.trailing, strip.trailing, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollClipDisabled()
        }
        .frame(height: Double(lines) * Self.lineHeight)
    }

    /// One line: the station's logo, its name, and why it is there with its country.
    private func line(_ pick: StationPick) -> some View {
        Button { onTune(pick.station) } label: {
            HStack(spacing: 12) {
                StationSquare(station: pick.station, edge: HomePicksRow.art, inset: 4, mark: 15)

                VStack(alignment: .leading, spacing: 1) {
                    Text(pick.station.display)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    Text(Self.kindLine(pick))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .feathered()

                Spacer(minLength: 0)
            }
            .frame(height: Self.lineHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Unpin it, or save it.
        .stationHold(pick.station)
    }

    /// Why the station is here, then its country: "Pinned • Netherlands". The kind alone when the
    /// station files no country.
    private static func kindLine(_ pick: StationPick) -> String {
        let kind: String
        switch pick.why {
        case .pinned: kind = Loc.get("Radio_HomePinned")
        case .saved: kind = Loc.get("Radio_HomeSaved")
        case .heard, .local, .forYou: kind = Loc.get("Radio_HomeForYou")
        }
        let place = RadioCountries.short(pick.station.country, pick.station.countryCode)
        return place.isEmpty ? kind : Loc.get("Home_QuickKindJoin", kind, place)
    }
}

/// A row of stations under a heading, scrolled sideways, at the size of home's rows of records
/// (``HomeRowView``).
private struct StationShelf: View {
    let heading: String
    let stations: [RadioStation]
    let onTune: (RadioStation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(heading)
                .font(RPMFont.display(19))
                .padding(.horizontal, RPMLayout.margin)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(stations) { station in
                        Button { onTune(station) } label: { tile(station) }
                            .buttonStyle(.plain)
                            // Pin it to Quick selection, or save it.
                            .stationHold(station)
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
            }
            // The row scrolls sideways inside a page that scrolls down. Clipping is disabled so
            // that the tiles are not cut off at the row's bounds.
            .scrollClipDisabled()
        }
    }

    private func tile(_ station: RadioStation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            StationSquare(station: station, edge: HomeRowView.art, inset: 16, mark: 30)
                .overlay {
                    RoundedRectangle(cornerRadius: CoverCorner.radius(HomeRowView.art),
                                     style: .continuous)
                        .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 1) {
                Text(station.display)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if let line = RadioHome.shortLine(station) {
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: HomeRowView.art, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A station's logo in the square that a cover uses, on a dark ground so that both a transparent
/// logo and a white square look right. The radio mark when the station has no logo. The tuner's
/// wall of stations draws the same square (``RadioPage``).
struct StationSquare: View {
    let station: RadioStation
    let edge: CGFloat
    let inset: CGFloat

    /// The size of the radio mark drawn when there is no logo.
    let mark: CGFloat

    var body: some View {
        let well = RoundedRectangle(cornerRadius: CoverCorner.radius(edge), style: .continuous)

        return ZStack {
            well.fill(Color.black.opacity(0x22 / 255))

            StationFace(station: station, edge: edge, inset: inset, onWearing: { _ in }) {
                Text(Glyph.radio)
                    .font(RPMFont.icon(mark))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(well)
    }
}
