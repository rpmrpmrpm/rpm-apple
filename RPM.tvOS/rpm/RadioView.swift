import SwiftUI
import UIKit
import RPMKit
import RPMArt
import RPMAudio
import RPMRadio
import RPMSession
import RPMSharedUI

/// The radio's five ways in, which the desktop and the Android TV put on a wheel opened by a held
/// key. On Apple TV they are a row of keys at the top of the radio screen.
enum RadioMode: String, CaseIterable, Hashable {
    case tuner, search, music, news, local

    var label: String {
        switch self {
        case .tuner: Loc.get("Viz_RadioTuner")
        case .search: Loc.get("Viz_MenuSearch")
        case .music: Loc.get("Viz_RadioMusic")
        case .news: Loc.get("Viz_RadioNews")
        case .local: Loc.get("Viz_RadioLocal")
        }
    }

    var symbol: String {
        switch self {
        case .tuner: "dial.medium"
        case .search: "magnifyingglass"
        case .music: "music.note"
        case .news: "newspaper"
        case .local: "location"
        }
    }
}

/// Pegasus's radio screen: the five ways in, the banner of station cards (the stations heard most
/// on every device, then the favourites, then the essential stations, at most seven), the essential
/// stations for the TV's country, and the favourites. Select tunes a station and opens the player;
/// press and hold offers Play and the favourite.
struct RadioView: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens

    var body: some View {
        let radio = model.radio
        let essential: [RadioStation]
        let country: String?
        switch radio.essential {
        case .read(let stations, let code, _):
            essential = Array(radio.shown(stations).prefix(TVRadio.essentialCount))
            country = code
        default:
            essential = []
            country = nil
        }
        // The listener's own, or the owner's while a shared collection is open.
        let saved = model.savedStations
        let favourites = radio.shown(saved.stations)
        let heard = Array(radio.shown(radio.heard).prefix(5))
        var seen = Set<String>()
        let banner = (heard + favourites + essential).filter { seen.insert($0.uuid.lowercased()).inserted }.prefix(7)

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 50) {

                HStack(spacing: 20) {
                    ForEach(RadioMode.allCases, id: \.self) { mode in
                        Button { open(mode) } label: { Label(mode.label, systemImage: mode.symbol) }
                            .buttonStyle(.glass)
                            .remembered("mode:\(mode)")
                    }
                }
                .frame(height: PageBar<EmptyView>.height)
                .padding(.horizontal, Size.side)
                .focusSection()

                if !banner.isEmpty {
                    StationCarousel(stations: Array(banner)) { tune($0) }
                }

                VStack(alignment: .leading, spacing: 8) {
                    switch radio.essential {
                    case .notRead:
                        EmptyView()
                    case .unavailable:
                        Heading(Loc.get("Viz_RadioPopular"))
                        Text(Loc.get("Radio_DirectoryDown"))
                            .font(.tv(Size.note)).foregroundStyle(Ink.dim)
                            .padding(.horizontal, Size.side)
                    case .read:
                        Heading(country.flatMap { Locale.current.localizedString(forRegionCode: $0) }
                            .map { Loc.get("Viz_RadioEssential", $0) } ?? Loc.get("Viz_RadioPopular"))
                        if !essential.isEmpty {
                            CardRow(space: "essential", items: essential) { station in
                                StationCard(station: station, width: Card.wide, wide: true) { tune(station) }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Heading(Loc.get("Viz_RadioFavorites"))
                    if favourites.isEmpty {
                        switch saved {
                        case .reading:
                            RecordSpinner(diameter: 44).padding(.horizontal, Size.side)
                        case .mine, .owners, .unreadable:
                            Text(Self.noFavourites(saved))
                                .font(.tv(Size.note)).foregroundStyle(Ink.dim)
                                .padding(.horizontal, Size.side)
                        }
                    } else {
                        CardRow(space: "favourites", items: favourites) { station in
                            StationCard(station: station, width: Card.edge) { tune(station) }
                        }
                    }
                }
            }
            .padding(.top, Size.top)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
        .onAppear { radio.refresh() }
        // Asked each time the radio is shown and when another collection is opened, so a shared
        // collection's saved stations are its owner's as they are now.
        .task(id: [model.session.who?.userId ?? "", model.session.viewing.ownerId]) {
            await model.readSharedStations()
        }
    }

    /// What the favourites row says when it has no stations.
    private static func noFavourites(_ saved: SavedStations) -> String {
        switch saved {
        case .mine: Loc.get("Atv_Radio_NoFavorites")
        case .owners, .reading: Loc.get("Radio_SharedNoFavorites")
        case .unreadable: Loc.get("Radio_SharedFavoritesError")
        }
    }

    private func tune(_ station: RadioStation) {
        model.tune(station)
        screens.playerShown = true
    }

    /// The wheel's entries (PegasusChrome.RadioWheel). News and Local set the tuner's country and
    /// filters; Music opens it on its genre choice.
    private func open(_ mode: RadioMode) {
        let radio = model.radio
        switch mode {
        case .search:
            screens.stationSearchShown = true
            return
        case .tuner:
            break
        case .music:
            radio.tuner.savedOnly = false
        case .news:
            radio.tuner.savedOnly = false
            radio.tuner.country = nil
            radio.tuner.sieve = StationSieve(genre: "News")
        case .local:
            radio.tuner.savedOnly = false
            radio.tuner.sieve = .off
            if let code = TVRadio.listenerCountry { radio.tuner.country = code }
        }
        screens.open(.tuner(mode == .music))
    }
}

/// The radio banner, laid out as home's (and as the Android TV's), so that the cards do not clip
/// through each other: a plate in the middle with the stations before and after it showing at
/// both sides, under it and a little shorter, wrapping
/// round at the ends; arrows at the outer edges and a row of dots under it. Left and Right step it, the
/// cards swapping at once and the strip sliding in from the side it came from. One stop for the remote,
/// the plate; Select tunes it, and holding Select offers the station's menu.
///
/// Every station has one face for as long as the banner is up, keyed by the station, drawn at the
/// plate's size wherever it stands and cut to a peek at the sides, as on home's banner: a step moves
/// faces that are already drawn, so no logo, line or room starts again under the eyes.
private struct StationCarousel: View {
    @Environment(Screens.self) private var screens
    let stations: [RadioStation]
    let onTune: (RadioStation) -> Void

    @State private var front = 0
    /// How far the strip stands off its place while it slides in after a step.
    @State private var slide: CGFloat = 0
    @State private var focused = false
    @State private var pressed = false

    static let plate = BannerLooks.plate
    /// The cards at the sides: 30 shorter, from the screen's edge to 24 under the plate (home's).
    private static let peek = CGSize(width: (1920 - plate.width) / 2 + 24, height: plate.height - 30)

    /// The focus on the plate, shown: not before the first key.
    private var lit: Bool { focused && screens.remoteUsed }

    var body: some View {
        let count = stations.count
        let at = count > 0 ? min(front, count - 1) : 0
        VStack(spacing: 18) {
            ZStack {
                ZStack {
                    ForEach(Array(stations.enumerated()), id: \.element.uuid) { i, station in
                        slot(station, place: Self.place(of: i, at: at, count: count))
                    }
                }
                .offset(x: slide)

                if count > 0 {
                    // The remote's one stop, over the plate. It draws nothing and does not slide.
                    Button { onTune(stations[at]) } label: {
                        Color.clear.frame(width: Self.plate.width, height: Self.plate.height)
                    }
                    .buttonStyle(PlateFocusStyle(onFocus: { focused = $0 }, onPress: { pressed = $0 }))
                    .remembered("banner")
                    .contextMenu { StationMenu(station: stations[at]) }
                    .onKeyPress(.leftArrow) { step(-1); return .handled }
                    .onKeyPress(.rightArrow) { step(1); return .handled }
                }
                if count > 1 {
                    HStack {
                        Image(systemName: "chevron.left")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .padding(.horizontal, 36)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: 1920, height: Self.plate.height)

            if count > 1 {
                HStack(spacing: 12) {
                    ForEach(0..<count, id: \.self) { i in
                        Circle()
                            .fill(Color.white.opacity(i == at ? 1 : 0.32))
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .focusSection()
    }

    /// One station's face at `place`: -1 at the left, 1 at the right, 0 the plate, nil not on show.
    private func slot(_ station: RadioStation, place: Int?) -> some View {
        let plate = place == 0
        let size = plate ? Self.plate : Self.peek
        let side: Alignment = place == -1 ? .leading : place == 1 ? .trailing : .center
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return StationBannerFace(station: station, size: CGSize(width: Self.plate.width, height: size.height),
                                 shown: place != nil)
            // A side card shows the plate-wide face cut to the peek, its outer part showing, dimmed.
            .frame(width: size.width, height: size.height, alignment: side)
            .clipShape(shape)
            .overlay { Color.black.opacity(plate ? 0 : 0.45).clipShape(shape) }
            .scaleEffect(plate ? (pressed ? 0.99 : (lit ? 1.03 : 1)) : 1)
            .shadow(color: .black.opacity(plate ? (lit ? 0.5 : 0.3) : 0), radius: lit ? 30 : 16, y: lit ? 16 : 8)
            .animation(.easeOut(duration: 0.18), value: lit)
            .frame(maxWidth: .infinity, alignment: side)
            .opacity(place == nil ? 0 : 1)
            .zIndex(plate ? 1 : 0)
            .allowsHitTesting(false)
    }

    /// Where the station at `i` stands: the plate, the one before at the left, the one after at the
    /// right (with two, only the left), nil not on show.
    private static func place(of i: Int, at: Int, count: Int) -> Int? {
        if i == at { return 0 }
        guard count > 1 else { return nil }
        if i == (at - 1 + count) % count { return -1 }
        if count > 2, i == (at + 1) % count { return 1 }
        return nil
    }

    /// The cards swap at once and the strip slides in from the side it came from (home's).
    private func step(_ by: Int) {
        let count = stations.count
        guard count > 1 else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            front = (front + by + count) % count
            slide = CGFloat(by) * 180
        }
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.22)) { slide = 0 }
        }
    }
}

private struct StationBannerFace: View {
    @Environment(TVModel.self) private var model
    let station: RadioStation
    let size: CGSize
    /// Whether the card is on show: its room drifts only then.
    let shown: Bool

    @State private var wearing = Wearing()
    @State private var blurb: String?

    private static let logo: CGFloat = 130

    var body: some View {
        let line = blurb ?? (model.radio.blurbs.answered(station) ?? nil)
        ZStack {
            StationRoom(colours: wearing.of(station, edge: Self.logo), breathes: shown, seed: station.uuid)
            Color.black.opacity(0x26 / 255)
            // From the top rather than centred, so the logo stands at the same height on every
            // card whether or not the station has a line about it.
            VStack(spacing: 12) {
                StationLogo(station: station, edge: Self.logo, corner: 14,
                            onWearing: { wearing.said($0, by: station) })
                Text(station.display)
                    .font(.tv(34, .bold))
                    .foregroundStyle(Ink.words)
                    .lineLimit(1)
                if let line {
                    Text(line)
                        .font(.tv(24))
                        .foregroundStyle(Color.white.opacity(0xD1 / 255))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: size.width - 120)
                        .transition(.opacity)
                }
                if model.player.station?.isFiled(as: station.uuid) == true, !model.player.announced.isEmpty {
                    Text(Loc.get("Radio_NowPlayingLine", IcyTitle.line(model.player.announced)))
                        .font(.tv(22))
                        .foregroundStyle(Color.white.opacity(0x8C / 255))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 30)
            .padding(.top, 40)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .task(id: station.uuid) {
            let known = model.radio.blurbs.answered(station) != nil
            let found = await model.radio.blurbs.of(station)
            guard !Task.isCancelled else { return }
            var put = Transaction()
            if !known { put.animation = .easeOut(duration: 0.3) }
            withTransaction(put) { blurb = found }
        }
    }
}

// ── the station search ──

/// The station search (RadioSearch): tvOS's search screen over everything, the directory asked
/// 450 ms after typing stops, the stations found six across. A new keystroke cancels the search
/// before it. Back closes it.
struct StationSearchPage: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    @State private var asked = ""
    @State private var found: Found = .idle

    enum Found: Equatable {
        case idle, searching, failed
        case stations([RadioStation])
    }

    var body: some View {
        ScrollView(.vertical) {
            Group {
                switch found {
                case .idle:
                    EmptyView()
                case .searching:
                    RecordSpinner(diameter: 72).frame(maxWidth: .infinity).padding(.top, 120)
                case .failed:
                    Message(Loc.get("Radio_DirectoryDown")).frame(height: 300)
                case .stations(let stations):
                    let shown = model.radio.shown(stations)
                    if shown.isEmpty {
                        Message(Loc.get("Radio_NoResults")).frame(height: 300)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Card.edge), spacing: Card.gap),
                                                 count: AlbumGrid.columns),
                                  alignment: .leading, spacing: 56) {
                            ForEach(shown) { station in
                                StationCard(station: station, width: Card.edge) {
                                    model.tune(station)
                                    // The search goes first; the player opens when it has gone.
                                    screens.playAfterSearch()
                                }
                            }
                        }
                        .padding(.horizontal, Size.side)
                    }
                }
            }
            .padding(.vertical, 40)
        }
        .scrollClipDisabled()
        // The search screen insets what is under its keyboard by the screen's margin; the grid keeps
        // its own, so it lines up with every other screen's.
        .ignoresSafeArea(.container, edges: .horizontal)
        .searchable(text: $asked, prompt: Loc.get("Radio_SearchPlaceholder"))
        .task(id: asked) {
            let text = asked.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { found = .idle; return }
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            found = .searching
            do {
                let answer = try await model.stations.directory.search(RadioQuery(name: text, limit: 120))
                guard !Task.isCancelled else { return }
                found = .stations(RadioResults.onePerStation(answer))
            } catch {
                guard !Task.isCancelled else { return }
                found = .failed
            }
        }
    }
}

// ── the tuner ──

/// The tuner (PegasusChrome.RadioTuner): the dial across the top, and under it the tools and the
/// station list on the left and the station playing on the right.
///
/// The focus starts on the dial. Left and Right walk its needle from station to station, faster
/// while held, without opening a stream; letting go tunes the station the needle is on. Select on
/// the dial stops the station playing, or tunes the last station tuned here, or the first listed.
/// Select on a row tunes it, or stops it when it is the one playing; the heart keeps it.
struct TunerPage: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    /// Opened from the Music key: the genre choice comes first.
    let musicFirst: Bool

    @State private var preview: Int?
    @State private var choosingGenre = false
    @State private var flash: String?

    var body: some View {
        @Bindable var radio = model.radio
        let saved = model.savedStations
        let list = radio.tunerList(saved: saved.stations)
        let stations = list.stations
        let playing = model.player.station
        let tuned = playing.flatMap { p in stations.firstIndex { $0.isFiled(as: p.uuid) || p.isFiled(as: $0.uuid) } }

        VStack(alignment: .leading, spacing: 30) {
            Dial(stations: stations, at: preview ?? tuned, tuned: tuned, playing: playing,
                 step: { by in step(by, stations: stations, tuned: tuned) },
                 commit: { commit(stations: stations, tuned: tuned) },
                 select: { playOrStop(stations) })
                .frame(height: 300)

            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 20) {
                    tools
                    if stations.isEmpty {
                        Text(note(list) ?? " ")
                            .font(.tv(Size.row))
                            .foregroundStyle(Ink.dim)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                        if list.asking { RecordSpinner(diameter: 56).frame(maxWidth: .infinity) }
                    }
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(stations.enumerated()), id: \.element.uuid) { at, station in
                                TunerRow(station: station, tuned: at == tuned,
                                         saved: saved.holds(station.uuid),
                                         onPress: {
                                             if at == tuned { model.stopStation() } else { tune(station, announce: false) }
                                         },
                                         // On a shared collection the heart shows the owner's mark
                                         // and cannot be pressed.
                                         onHeart: saved.mayChange ? { radio.saved.toggle(station) } : nil)
                            }
                        }
                        .padding(.vertical, 10)
                    }
                    .scrollClipDisabled()
                    .focusSection()
                }
                .frame(maxWidth: .infinity)

                TunerPlayer(shown: tuned.map { stations[$0] } ?? radio.lastTuned, playing: playing,
                            onPlayOrStop: { playOrStop(stations) })
                    .frame(width: 640, height: 540)
            }
        }
        .padding(.horizontal, Size.side)
        .padding(.top, Size.belowPill)
        .overlay(alignment: .bottom) {
            FlashLine(text: flash, count: flash == nil ? 0 : 1).id(flash)
        }
        .onAppear {
            radio.startTuner()
            if musicFirst { choosingGenre = true }
        }
        .sheet(isPresented: $choosingGenre) {
            GenreChoice(all: false, chosen: radio.tuner.sieve.genre) { genre in
                radio.tuner.sieve.genre = genre
                choosingGenre = false
            }
        }
    }

    // ── the tools ──

    private var tools: some View {
        @Bindable var radio = model.radio
        let countries = radio.countries
        return HStack(spacing: 16) {
            TextField(Loc.get("Radio_SearchPlaceholder"), text: $radio.tuner.text)
                .frame(maxWidth: .infinity)
            Menu {
                Picker(Loc.get("Radio_AllCountries"), selection: $radio.tuner.country) {
                    Text(Loc.get("Radio_AllCountries")).tag(String?.none)
                    ForEach(countries) { Text($0.name).tag(String?.some($0.code)) }
                }
            } label: {
                Label(radio.tuner.country.flatMap { Locale.current.localizedString(forRegionCode: $0) } ?? Loc.get("Radio_AllCountries"),
                      systemImage: "globe")
            }
            .buttonStyle(.glass)
            Menu {
                Picker(Loc.get("Radio_SortHeading"), selection: $radio.tuner.order) {
                    ForEach(StationOrdering.allCases, id: \.self) { Text(Self.label($0)).tag($0) }
                }
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .buttonStyle(.glass)
            Menu {
                Picker(Loc.get("Radio_FilterFormat"), selection: $radio.tuner.sieve.format) {
                    Text(Loc.get("Radio_AllFormats")).tag(String?.none)
                    ForEach(StationSieve.formats, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
                Picker(Loc.get("Radio_FilterGenre"), selection: $radio.tuner.sieve.genre) {
                    Text(Loc.get("Radio_AllGenres")).tag(String?.none)
                    ForEach(RadioGenres.all, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .pickerStyle(.menu)
                Picker(Loc.get("Radio_FilterAds"), selection: $radio.tuner.sieve.ads) {
                    Text(Loc.get("Radio_AdsEither")).tag(AdsWanted.either)
                    Text(Loc.get("Radio_AdsWithout")).tag(AdsWanted.without)
                    Text(Loc.get("Radio_AdsWith")).tag(AdsWanted.with)
                }
                .pickerStyle(.menu)
                Divider()
                Button(Loc.get("Radio_ClearFilters")) { radio.tuner.sieve = .off }
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .buttonStyle(.glass)
            Button {
                radio.tuner.savedOnly.toggle()
            } label: {
                Image(systemName: radio.tuner.savedOnly ? "heart.fill" : "heart")
                    .keyTint(radio.tuner.savedOnly ? Ink.loved : nil)
            }
            .buttonStyle(.glass)
        }
        .focusSection()
    }

    static func label(_ order: StationOrdering) -> String {
        switch order {
        case .listed: Loc.get("Radio_SortListed")
        case .nameUp: Loc.get("Radio_SortNameUp")
        case .nameDown: Loc.get("Radio_SortNameDown")
        case .votes: Loc.get("Radio_SortVotes")
        case .quality: Loc.get("Radio_SortQuality")
        }
    }

    private func note(_ list: TunerList) -> String? {
        if list.directoryDown { return Loc.get("Radio_DirectoryDown") }
        switch list.empty {
        case .noResults: return Loc.get("Radio_NoResults")
        case .noFavorites: return Loc.get("Radio_NoFavorites")
        case .noFilterMatch: return Loc.get("Radio_NoFilterMatch")
        case nil: return nil
        }
    }

    // ── tuning ──

    private func tune(_ station: RadioStation, announce: Bool) {
        model.radio.lastTuned = station
        model.tune(station)
        if announce { flash = Loc.get("Radio_TunedTo", station.display) }
    }

    /// The dial's select and the player's key: stop what plays, or tune the last station tuned
    /// here, or the first listed.
    private func playOrStop(_ stations: [RadioStation]) {
        if model.player.station != nil {
            model.stopStation()
            return
        }
        if let again = model.radio.lastTuned ?? stations.first { tune(again, announce: true) }
    }

    private func step(_ by: Int, stations: [RadioStation], tuned: Int?) {
        guard !stations.isEmpty else { return }
        let from = preview ?? tuned
        let next = from.map { $0 + by } ?? (by > 0 ? 0 : stations.count - 1)
        guard stations.indices.contains(next) else { return }
        preview = next
    }

    private func commit(stations: [RadioStation], tuned: Int?) {
        guard let at = preview else { return }
        preview = nil
        guard stations.indices.contains(at), at != tuned else { return }
        tune(stations[at], announce: true)
    }
}

/// The genres a tuner can be narrowed to: Music leaves out the ones that are not music.
private struct GenreChoice: View {
    let all: Bool
    let chosen: String?
    let pick: (String?) -> Void

    var body: some View {
        List {
            Button { pick(nil) } label: {
                Label(Loc.get("Radio_AllGenres"), systemImage: chosen == nil ? "checkmark" : "")
            }
            ForEach(RadioGenres.all.filter { all || !RadioGenres.notMusic.contains($0) }, id: \.self) { genre in
                Button { pick(genre) } label: {
                    Label(genre, systemImage: chosen == genre ? "checkmark" : "")
                }
            }
        }
        .frame(width: 700)
    }
}

/// The dial: the desktop's card of call signs sliding under a fixed needle, the readout of the
/// station under the needle, and the station playing's logo. One stop for the remote.
private struct Dial: View {
    @Environment(TVModel.self) private var model
    let stations: [RadioStation]
    let at: Int?
    let tuned: Int?
    let playing: RadioStation?
    let step: (Int) -> Void
    let commit: () -> Void
    let select: () -> Void

    @State private var focused = false

    /// The desktop's dial is drawn in its own units, 176 tall; the TV draws it this much larger.
    private static let k: Double = 1.6

    private var tunedInk: Color { model.player.reconnecting ? Ink.amber : Ink.cyan }
    /// The band at the top kept for the readout, in the dial's units (the desktop's 54). The card
    /// is laid out below it.
    private static let readout: Double = 54

    var body: some View {
        GeometryReader { geo in
            let glass = Double(geo.size.width) / Self.k
            let captions = stations.map { StationSign.of($0.display).isEmpty ? $0.display : StationSign.of($0.display) }
            let card = DialCard.of(captions: captions, glass: glass,
                                   height: Double(geo.size.height) / Self.k, readoutBottom: Self.readout)
            let mark = at.map { card.markOf($0, of: stations.count) } ?? card.leftEdge
            let slide = card.slide(bringing: mark, to: glass / 2, glass: glass)
            let ink = tunedInk

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    context.scaleBy(x: Self.k, y: Self.k)
                    context.translateBy(x: slide, y: 0)
                    let tick = Color.white.opacity(0.35)
                    for x in card.ticks {
                        var line = Path()
                        line.move(to: CGPoint(x: x, y: card.scaleTop))
                        line.addLine(to: CGPoint(x: x, y: card.scaleBottom))
                        context.stroke(line, with: .color(tick), lineWidth: 1)
                    }
                    for printed in card.printed {
                        let y = card.namesTop + Double(printed.row) * DialCard.nameLine
                        let lit = printed.station == at
                        context.draw(Text(printed.caption)
                                        .font(.system(size: DialCard.nameSize, weight: lit ? .bold : .regular))
                                        .foregroundStyle(lit ? Color.white : Color.white.opacity(0.6)),
                                     at: CGPoint(x: printed.nameLeft, y: y), anchor: .topLeading)
                        let square = CGRect(x: printed.markX - DialCard.squareSize / 2, y: y + 1,
                                            width: DialCard.squareSize, height: DialCard.squareSize)
                        // The tuned station's mark in cyan, amber while it reconnects (the Android TV's).
                        context.fill(Path(square), with: .color(printed.station == tuned ? ink : Color.white.opacity(lit ? 0.9 : 0.3)))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: at)

                // The needle, fixed in the middle of the glass: from its rise above the call signs
                // to the foot of the scale, in the card's own figures.
                let needleTop = (card.namesTop - DialCard.pointerRise) * Self.k
                let needleFoot = card.scaleBottom * Self.k
                Rectangle()
                    .fill(Color(red: 1, green: 0.27, blue: 0.22))
                    .frame(width: 3, height: needleFoot - needleTop)
                    .position(x: geo.size.width / 2, y: (needleTop + needleFoot) / 2)
                    .shadow(color: .red.opacity(0.6), radius: 6)

                // The readout, in the band the card keeps clear above itself.
                let name = at.map { stations[$0].display } ?? playing?.display
                HStack(spacing: 20) {
                    if let playing {
                        StationLogo(station: playing, edge: 56, corner: 8)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name ?? Loc.get("Radio_NothingTuned"))
                            .font(.tv(30, .semibold))
                            .foregroundStyle(Ink.words)
                            .lineLimit(1)
                        // Under a station's name only: with none, the line above already says it.
                        if name != nil {
                            Text(StationStatus.of(model.player))
                                .font(.tv(22))
                                .foregroundStyle(Ink.dim)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .frame(height: Self.readout * Self.k)
                .padding(.horizontal, 30)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(focused ? 0.8 : 0.15), lineWidth: focused ? 3 : 1)
            }
            .scaleEffect(focused ? 1.01 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
            .overlay {
                DialKeys(step: step, commit: commit, select: select, focusChanged: { focused = $0 })
            }
        }
    }
}

/// The dial's remote: Left and Right walk the needle, a station a press and on while held; the
/// tune is made when the key comes up. Select stops or tunes. Up and Down are passed on.
private struct DialKeys: UIViewRepresentable {
    let step: (Int) -> Void
    let commit: () -> Void
    let select: () -> Void
    let focusChanged: (Bool) -> Void

    func makeUIView(context: Context) -> KeysView {
        let view = KeysView()
        view.keys = self
        return view
    }

    func updateUIView(_ view: KeysView, context: Context) { view.keys = self }

    final class KeysView: UIView {
        var keys: DialKeys?
        private var held: (way: Int, down: CFTimeInterval, last: CFTimeInterval)?
        private var ticker: CADisplayLink?

        /// Held, the needle walks a station every this long, as a remote's key repeats.
        private static let repeatEvery: CFTimeInterval = 0.12
        private static let holdAfter: CFTimeInterval = 0.4

        override var canBecomeFocused: Bool { true }

        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            let now = context.nextFocusedView === self
            if !now, held != nil { stop(); keys?.commit() }
            keys?.focusChanged(now)
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let press = presses.first else { return super.pressesBegan(presses, with: event) }
            switch press.type {
            case .leftArrow, .rightArrow:
                let way = press.type == .leftArrow ? -1 : 1
                keys?.step(way)
                let now = CACurrentMediaTime()
                held = (way, now, now)
                let link = CADisplayLink(target: self, selector: #selector(tick))
                link.add(to: .main, forMode: .common)
                ticker?.invalidate()
                ticker = link
            case .select:
                keys?.select()
            default:
                super.pressesBegan(presses, with: event)
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let press = presses.first else { return super.pressesEnded(presses, with: event) }
            switch press.type {
            case .leftArrow, .rightArrow:
                stop()
                keys?.commit()
            case .select:
                break
            default:
                super.pressesEnded(presses, with: event)
            }
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            stop()
            super.pressesCancelled(presses, with: event)
        }

        @objc private func tick() {
            guard let held else { return }
            let now = CACurrentMediaTime()
            guard now - held.down >= Self.holdAfter, now - held.last >= Self.repeatEvery else { return }
            keys?.step(held.way)
            self.held = (held.way, held.down, now)
        }

        private func stop() {
            ticker?.invalidate()
            ticker = nil
            held = nil
        }
    }
}

/// One station on the tuner (PegasusStationRow): its logo, the on-air lamp, its name, the AD badge,
/// its country and format, and its call sign; then the heart. The row playing shows the stop.
private struct TunerRow: View {
    let station: RadioStation
    let tuned: Bool
    let saved: Bool
    let onPress: () -> Void
    /// Nil on a shared collection: the heart then shows the owner's mark and cannot be pressed.
    let onHeart: (() -> Void)?

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onPress) {
                HStack(spacing: 18) {
                    StationLogo(station: station, edge: 72, corner: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Circle()
                                .fill(station.reachable ? Color(red: 1, green: 0.27, blue: 0.22) : Color.white.opacity(0.2))
                                .frame(width: 10, height: 10)
                                .shadow(color: station.reachable ? .red.opacity(0.7) : .clear, radius: 5)
                            Text(station.display)
                                .font(.tv(Size.row))
                                .foregroundStyle(Ink.words)
                                .lineLimit(1)
                            if RadioAds.carriesAds(tags: station.tags, name: station.name, homepage: station.homepage) {
                                Text("AD")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(Color(red: 0x0B / 255, green: 0x0D / 255, blue: 0x10 / 255))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.white.opacity(0x8C / 255), in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        if let detail = StationLines.detail(station) {
                            Text(detail)
                                .font(.tv(Size.rowLine))
                                .foregroundStyle(Color.white.opacity(0x77 / 255))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 10)
                    let sign = StationSign.of(station.display)
                    if !sign.isEmpty {
                        Text("(\(sign))")
                            .font(.tv(20))
                            .tracking(1)
                            .foregroundStyle(Ink.dim)
                    }
                    Image(systemName: tuned ? "stop.fill" : "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Ink.words)
                        .frame(width: 44)
                }
            }
            .buttonStyle(RowStyle())

            if let onHeart {
                Button(action: onHeart) {
                    Image(systemName: saved ? "heart.fill" : "heart")
                        .keyTint(saved ? Ink.loved : nil)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            } else if saved {
                Image(systemName: "heart.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(Ink.loved)
                    .frame(width: 66)
                    .accessibilityLabel(Loc.get("Radio_SavedMark"))
            }
        }
    }
}

/// What the station playing is doing, in one line (the Android TV's `statusOf`): nothing tuned,
/// reconnecting, an ad break, the song announced, or no song announced.
enum StationStatus {
    @MainActor
    static func of(_ player: Player) -> String {
        guard player.station != nil else { return Loc.get("Radio_NothingTuned") }
        if player.reconnecting { return Loc.get("Radio_Reconnecting") }
        if RadioAds.isAdBreak(player.announced) { return Loc.get("Radio_AdBreak") }
        let said = IcyTitle.split(player.announced)
        let line = [said.artist, said.title].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " - ")
        return line.isEmpty ? Loc.get("Radio_NoTrack") : line
    }
}

/// The station beside the list: its room under glass, its logo, what it plays, and the round play
/// key. Not tuned, it says so under the last station tuned here.
private struct TunerPlayer: View {
    @Environment(TVModel.self) private var model
    let shown: RadioStation?
    let playing: RadioStation?
    let onPlayOrStop: () -> Void

    @State private var wearing = Wearing()

    var body: some View {
        let said = IcyTitle.split(model.player.announced)
        let station = shown ?? playing
        ZStack {
            // One seed whatever is tuned: a new station changes the room's colours, not its pose.
            StationRoom(colours: station.flatMap { wearing.of($0, edge: 200) }, breathes: true,
                        seed: "tuner")
            Color.black.opacity(0x33 / 255)
            VStack(spacing: 12) {
                if let station {
                    StationLogo(station: station, edge: 200, corner: 18, onWearing: { wearing.said($0, by: station) })
                        .padding(.bottom, 14)
                }
                // The song's title where one is announced; otherwise what the station is doing.
                Text(playing != nil && !RadioAds.isAdBreak(model.player.announced) && !model.player.reconnecting
                        ? (said.title ?? StationStatus.of(model.player)) : StationStatus.of(model.player))
                    .font(.tv(38, .bold))
                    .foregroundStyle(Ink.words)
                    .lineLimit(1)
                if playing != nil, let artist = said.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.tv(29))
                        .foregroundStyle(Color.white.opacity(0xD9 / 255))
                        .lineLimit(1)
                }
                if let name = (shown ?? playing)?.display {
                    Text(name)
                        .font(.tv(24))
                        .foregroundStyle(Ink.dim)
                        .lineLimit(1)
                }
                Button(action: onPlayOrStop) {
                    Image(systemName: playing != nil ? "stop.fill" : "play.fill")
                        .font(.system(size: 32))
                        .frame(width: 70, height: 70)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .padding(.top, 14)
            }
            .padding(30)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .focusSection()
    }
}
