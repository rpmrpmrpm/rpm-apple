import SwiftUI
import RPMKit
import RPMLibrary
import RPMArt
import RPMRadio
import RPMDesign
import RPMSharedUI

/// The home screen, from top to bottom: the banner, quick selection, Made for you, then the record
/// rows. The content of each part comes from `HomeScreen`. The shared session works it out once per
/// launch, and the phone shows the same result. There is no mini player on the TV. The sidebar's
/// Now playing entry opens the player.
struct HomeView: View {
    @Environment(TVModel.self) private var model

    var body: some View {
        let session = model.session
        if session.albums.isEmpty, session.wallStanding != .reading {
            VStack {
                if case .trouble(let said) = session.wallStanding {
                    Trouble(said) { Task { await session.refresh() } }
                } else {
                    Message(Loc.get("Tv_Library_Empty"))
                }
            }
        } else if let home = session.home {
            if home.gate.open {
                HomeRows(home: home)
            } else {
                HomeLock(gate: home.gate)
            }
        } else {
            Waiting(Loc.get("Rpm_Library_Loading"))
        }
    }
}

/// This is shown in home's place until there is enough music for home to be useful (the phone's
/// HomeLock). With fewer records than the gate's number, the rows would only repeat the whole
/// collection in other orders. It shows what the gate waits for and how far along it is. There is
/// no Add music key, because music is added on a computer.
private struct HomeLock: View {
    let gate: FeatureGate

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(Loc.get("HomeLock_Kicker"))
                .font(.tv(Size.small, .semibold))
                .tracking(2)
                .foregroundStyle(Ink.dim)
            Text(Loc.get("HomeLock_Body"))
                .font(.tv(Size.note))
                .foregroundStyle(Ink.words)
                .fixedSize(horizontal: false, vertical: true)
            SeekLine(fraction: gate.fraction, knob: 0, track: 6)
                .frame(height: 12)
            HStack {
                Text(Loc.get("HomeLock_Progress", String(gate.have), String(gate.want)))
                Spacer()
                Text(gate.toGo == 1 ? Loc.get("HomeLock_ToGoOne") : Loc.get("HomeLock_ToGo", String(gate.toGo)))
            }
            .font(.tv(Size.small))
            .foregroundStyle(Ink.artist)
        }
        .frame(width: 900)
        .padding(48)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A failure, with a button to try again.
struct Trouble: View {
    let said: String
    let retry: () -> Void

    init(_ said: String, retry: @escaping () -> Void) {
        self.said = said
        self.retry = retry
    }

    var body: some View {
        VStack(spacing: 36) {
            Text(said)
                .font(.tv(Size.note))
                .foregroundStyle(Ink.dim)
                .multilineTextAlignment(.center)
            Button(Loc.get("Rpm_Library_Retry"), action: retry)
                .buttonStyle(.glass)
                .remembered("retry")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HomeRows: View {
    @Environment(TVModel.self) private var model
    let home: HomeScreen

    var body: some View {
        let albums = Dictionary(model.session.albums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let lists = home.lists.compactMap { HomeLists.set(named: $0, in: model.session.playlists) }

        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 64) {

                if !home.strip.isEmpty {
                    Banner(features: home.strip, albums: albums)
                }

                if !home.quickPicks.isEmpty {
                    QuickSelection(picks: home.quickPicks, albums: albums)
                }

                if !lists.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Heading(lists.contains { $0.origin == .stored } ? Loc.get("Viz_MenuPlaylists") : Loc.get("Home_MadeForYou"))
                        CardRow(space: "lists", items: lists) { ListCard(set: $0) }
                    }
                }

                ForEach(home.rows, id: \.kind) { row in
                    let records = row.keys.compactMap { albums[$0] }
                    if !records.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Heading(Self.title(row.kind))
                            CardRow(space: "\(row.kind)", items: records) { AlbumCard(album: $0) }
                        }
                    }
                }
            }
            // The banner's plate starts at 140 points. This keeps it clear of the sidebar pill,
            // even when the plate grows under the focus.
            .padding(.top, Size.top + 28)
            .padding(.bottom, 80)
        }
        .scrollClipDisabled()
    }

    static func title(_ kind: HomeRowKind) -> String {
        switch kind {
        case .listened: Loc.get("Home_Listened")
        case .suggested: Loc.get("Home_Suggested")
        case .taste: Loc.get("Home_Taste")
        case .played: Loc.get("Home_Played")
        case .added: Loc.get("Home_Added")
        }
    }
}

// ── the banner ──

/// The banner (HomeBanner, as the Android TV draws it). A plate is in the middle, with the cards
/// before and after it showing at both sides. Those cards are under the plate and a little shorter,
/// and they wrap round at the ends. There are arrows at the outer edges and a row of dots below.
///
/// The banner is one stop for the remote. Left and Right step it. The cards swap at once, and the
/// strip slides in from the side it came from. Select opens the card: a record's page, a list's
/// page, or a station. The banner steps itself every 7 seconds while the focus is elsewhere.
///
/// **Each card keeps one face for as long as the banner is up.** The face is keyed by the card.
/// Only the cards on show are placed, as on the Android TV. A card is drawn from what
/// ``BannerLooks`` prepared for it, at the plate's size wherever it stands. So a step moves faces
/// that are already drawn, and it requests nothing new. The focus is a key over the plate that
/// draws nothing. The plate's face grows under the focus.
private struct Banner: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    @Environment(\.displayScale) private var scale
    let features: [HomeFeature]
    let albums: [String: CloudAlbum]

    @State private var index = 0
    @State private var focused = false
    @State private var pressed = false
    /// How far the strip stands off its place while it slides in after a step.
    @State private var slide: CGFloat = 0
    /// One clock for every card's room, so a room stepping from a side to the plate goes on as it
    /// was.
    @State private var roomsFrom = Date()

    static let plate = BannerLooks.plate
    /// The cards at the sides are 30 points shorter. They reach from the screen's edge to 24 points
    /// under the plate.
    private static let peek = CGSize(width: (1920 - plate.width) / 2 + 24, height: plate.height - 30)

    /// The focus on the plate, shown. It is not shown before the first key press, when the opening
    /// put the focus there.
    private var lit: Bool { focused && screens.remoteUsed }

    var body: some View {
        let count = features.count
        let at = count > 0 ? min(index, count - 1) : 0

        VStack(spacing: 18) {
            ZStack {
                ZStack {
                    ForEach(Array(features.enumerated()), id: \.offset) { i, feature in
                        slot(feature, place: Self.place(of: i, at: at, count: count))
                    }
                    // With two cards, the card that is not on the plate shows at both sides. The
                    // right side gets a second face.
                    if count == 2 {
                        slot(features[(at + 1) % 2], place: 1)
                    }
                }
                .offset(x: slide)

                if count > 0 {
                    // The remote's one stop, over the plate. It draws nothing and does not slide.
                    Button { open(features[at]) } label: {
                        Color.clear.frame(width: Self.plate.width, height: Self.plate.height)
                    }
                    .buttonStyle(PlateFocusStyle(onFocus: { focused = $0 }, onPress: { pressed = $0 }))
                    .remembered("banner")
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
        // The cards that can come on show next are prepared before they do.
        .task(id: at) { await prepare(around: at, by: [-2, -1, 1, 2]) }
        .task(id: TickKey(at: at, lit: lit, count: count, covered: screens.openingUp)) {
            // Steps itself while the remote is elsewhere, or has not been used yet. It waits seven
            // seconds on each card, counted from when home shows, not from under the opening.
            guard !lit, count > 1, !screens.openingUp else { return }
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            // Does not step onto a card that is not ready. That is the next plate and the side card
            // that comes in with it.
            await prepare(around: at, by: [1, 2])
            guard !Task.isCancelled else { return }
            step(1)
        }
    }

    /// One card's face at `place`. -1 is the left side, 1 is the right side, and 0 is the plate,
    /// which is over the two side cards. Nil means not on show. The card is kept but not drawn.
    /// This one call is used for every place. Only the values below change with the place. So the
    /// face is the same view wherever it stands.
    private func slot(_ feature: HomeFeature, place: Int?) -> some View {
        let plate = place == 0
        let size = plate ? Self.plate : Self.peek
        let side: Alignment = place == -1 ? .leading : place == 1 ? .trailing : .center
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        return BannerFace(feature: feature, albums: albums,
                          look: model.bannerLooks.look(feature, on: model.session.viewing),
                          width: Self.plate.width, height: size.height,
                          shown: place != nil, roomsFrom: roomsFrom)
            // A side card shows the plate-sized face, cut to the side size. Its outer part shows,
            // and it is dimmed.
            .frame(width: size.width, height: size.height, alignment: side)
            .clipShape(shape)
            .overlay { Color.black.opacity(plate ? 0 : 0.45).clipShape(shape) }
            .scaleEffect(plate ? (pressed ? 0.99 : (lit ? 1.03 : 1)) : 1)
            .shadow(color: .black.opacity(plate ? (lit ? 0.5 : 0.3) : 0),
                    radius: lit ? 30 : 16, y: lit ? 16 : 8)
            .animation(.easeOut(duration: 0.18), value: lit)
            .frame(maxWidth: .infinity, alignment: side)
            .opacity(place == nil ? 0 : 1)
            .zIndex(plate ? 1 : 0)
            .allowsHitTesting(false)
    }

    private static func place(of i: Int, at: Int, count: Int) -> Int? {
        if i == at { return 0 }
        guard count > 1 else { return nil }
        if i == (at - 1 + count) % count { return -1 }
        if count > 2, i == (at + 1) % count { return 1 }
        return nil
    }

    private func prepare(around at: Int, by steps: [Int]) async {
        let count = features.count
        guard count > 0 else { return }
        let cards = steps.map { features[((at + $0) % count + count) % count] }
        await model.bannerLooks.prepare(cards, model: model, scale: scale)
    }

    private struct TickKey: Hashable { let at: Int; let lit: Bool; let count: Int; let covered: Bool }

    /// The cards swap at once. The strip then slides in from the side it came from
    /// (HomeBanner.Step).
    private func step(_ by: Int) {
        let count = features.count
        guard count > 1 else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            index = (index + by + count) % count
            slide = CGFloat(by) * 180
        }
        DispatchQueue.main.async {
            withAnimation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.22)) { slide = 0 }
        }
    }

    private func open(_ feature: HomeFeature) {
        switch feature.kind {
        case .madeForYou:
            if let set = HomeLists.set(named: feature.key, in: model.session.playlists) { screens.open(.list(set.id)) }
        case .radio:
            if let station = model.session.homeStations[feature.key] { model.tune(station); screens.playerShown = true }
        default:
            screens.open(.album(feature.key))
        }
    }
}

/// The key over a banner's plate, for home and for radio. It draws nothing. It reports when it has
/// the focus and when it is pressed. The plate's face then grows and settles, as a card does.
struct PlateFocusStyle: ButtonStyle {
    let onFocus: (Bool) -> Void
    let onPress: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        Plate(configuration: configuration, onFocus: onFocus, onPress: onPress)
    }

    private struct Plate: View {
        let configuration: Configuration
        let onFocus: (Bool) -> Void
        let onPress: (Bool) -> Void
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .onChange(of: focused, initial: true) { _, now in onFocus(now) }
                .onChange(of: configuration.isPressed) { _, now in onPress(now) }
        }
    }
}

/// One banner card, drawn from what ``BannerLooks`` prepared for it. A record's card shows the
/// artist's photo behind it (or the blurred cover). A shade rises from the bottom. The cover is
/// shown with three text lines. A list is shown in its colours and frame. A station is shown on a
/// room in its colours, with its logo and a description. Before its look is ready, the card shows
/// what it has, and then fades to the rest.
private struct BannerFace: View {
    @Environment(TVModel.self) private var model
    @Environment(\.displayScale) private var scale
    let feature: HomeFeature
    let albums: [String: CloudAlbum]
    let look: BannerLooks.Look?
    let width: CGFloat
    let height: CGFloat
    /// Whether the card is on show. Its room drifts only then.
    let shown: Bool
    let roomsFrom: Date

    /// The colours of the station's logo, for its room.
    @State private var wearing = Wearing()

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            switch feature.kind {
            case .radio:
                if let station = model.session.homeStations[feature.key] { stationFace(station) }
            case .madeForYou:
                if let set = HomeLists.set(named: feature.key, in: model.session.playlists) { listFace(set) }
            default:
                if let album = albums[feature.key] { recordFace(album) }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func recordFace(_ album: CloudAlbum) -> some View {
        let record: BannerLooks.Record? = if case .record(let made) = look { made } else { nil }
        ZStack(alignment: .bottomLeading) {
            Color(red: 0x30 / 255, green: 0x32 / 255, blue: 0x37 / 255)
            if let photo = record?.photo {
                Image(decorative: photo, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height, alignment: .trailing)
                    .clipped()
                    .transition(.opacity)
            } else if let sleeve = record?.sleeve {
                Image(decorative: sleeve.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: width, height: height)
                    .clipped()
                    .blur(radius: 40)
                    .opacity(0.8)
                    .transition(.opacity)
            }
            Shade()
            HStack(alignment: .bottom, spacing: 36) {
                Sleeve(album: album, edge: BannerLooks.picture, corner: 12)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                VStack(alignment: .leading, spacing: 10) {
                    Text(kicker.uppercased())
                        .font(.tv(22, .semibold))
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0xA8 / 255))
                    Text(AlbumNames.title(album))
                        .font(.tv(48, .bold))
                        .foregroundStyle(Ink.words)
                        .lineLimit(2)
                    // The artist's logo, or the artist's name. Both are in a line of the same
                    // height, so a logo that arrives late moves nothing above it.
                    ZStack(alignment: .leading) {
                        if let logo = record?.logo {
                            Image(decorative: logo, scale: scale)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: BannerLooks.logoBox.width, maxHeight: BannerLooks.logoBox.height,
                                       alignment: .leading)
                                .transition(.opacity)
                        } else {
                            Text(album.artist)
                                .font(.tv(30))
                                .foregroundStyle(Color.white.opacity(0.8))
                                .lineLimit(1)
                                .transition(.opacity)
                        }
                    }
                    .frame(height: BannerLooks.logoBox.height, alignment: .leading)
                }
            }
            .padding(44)
        }
    }

    @ViewBuilder
    private func listFace(_ set: PlaylistSet) -> some View {
        let framed = FramedList.of(set)
        ZStack(alignment: .bottomLeading) {
            if let framed, RoomView.works {
                RoomView(colours: framed.room, sound: .still, foot: 1, running: shown, breathes: true,
                         zero: .shared(roomsFrom), seed: set.id)
            } else {
                Color(red: 0x30 / 255, green: 0x32 / 255, blue: 0x37 / 255)
            }
            Shade()
            HStack(alignment: .bottom, spacing: 36) {
                ListPicture(set: set, edge: BannerLooks.picture, corner: 12, drifts: false)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
                VStack(alignment: .leading, spacing: 10) {
                    Text(Loc.get("Home_MadeForYou").uppercased())
                        .font(.tv(22, .semibold))
                        .tracking(2)
                        .foregroundStyle(Color.white.opacity(0xA8 / 255))
                    Text(set.name)
                        .font(.tv(48, .bold))
                        .foregroundStyle(Ink.words)
                        .lineLimit(2)
                    Text(ListLines.caption(set))
                        .font(.tv(30))
                        .foregroundStyle(Color.white.opacity(0.8))
                }
                .padding(.bottom, 6)
            }
            .padding(44)
        }
    }

    @ViewBuilder
    private func stationFace(_ station: RadioStation) -> some View {
        let line: String? = if case .station(let said) = look { said } else { nil }
        ZStack {
            StationRoom(colours: wearing.of(station, edge: BannerLooks.stationLogo), breathes: shown,
                        seed: station.uuid)
            Color.black.opacity(0x33 / 255)
            // Placed from the top, not centred. So the logo and the name stay still, whether or not
            // the station has a line, and when the line arrives.
            VStack(spacing: 18) {
                StationLogo(station: station, edge: BannerLooks.stationLogo, corner: 16,
                            onWearing: { wearing.said($0, by: station) })
                Text(station.display)
                    .font(.tv(40, .bold))
                    .foregroundStyle(Ink.words)
                if let line {
                    Text(line)
                        .font(.tv(27))
                        .foregroundStyle(Color.white.opacity(0xD1 / 255))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(maxWidth: 760)
                        .transition(.opacity)
                }
                if model.player.station?.isFiled(as: station.uuid) == true, !model.player.announced.isEmpty {
                    Text(Loc.get("Radio_NowPlayingLine", IcyTitle.line(model.player.announced)))
                        .font(.tv(24))
                        .foregroundStyle(Color.white.opacity(0x8C / 255))
                        .lineLimit(1)
                }
            }
            .padding(.top, 64)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var kicker: String {
        switch feature.kind {
        case .continue: Loc.get("Home_Continue")
        case .added: Loc.get("Home_Added")
        case .suggested: Loc.get("Home_Suggested")
        case .played: Loc.get("Home_Played")
        case .listened: Loc.get("Home_Listened")
        case .madeForYou: Loc.get("Home_MadeForYou")
        case .radio: Loc.get("Rpm_Tab_Radio")
        }
    }
}

/// The shade under a banner card's text. It is clear at the top and dark at the bottom.
private struct Shade: View {
    var body: some View {
        LinearGradient(stops: [.init(color: .black.opacity(0.2), location: 0),
                               .init(color: .black.opacity(0.2), location: 0.38),
                               .init(color: .black.opacity(0.45), location: 0.66),
                               .init(color: .black.opacity(0.75), location: 1)],
                       startPoint: .top, endPoint: .bottom)
    }
}

// ── quick selection ──

/// Quick selection (QuickPicks). The heading has the Play all tracks button beside it. Then come
/// columns of four entries. Each column is filled from top to bottom, and the columns scroll
/// together from left to right. An entry is a song (played on its own), a record, a list or a
/// station.
private struct QuickSelection: View {
    @Environment(TVModel.self) private var model
    let picks: [QuickPick]
    let albums: [String: CloudAlbum]

    var body: some View {
        let tracks = Dictionary(model.session.albums.flatMap(\.tracks).map { ($0.rpmId, $0) },
                                uniquingKeysWith: { first, _ in first })
        let songs = picks.filter { $0.kind == .song }.compactMap { tracks[$0.key] }
        let panels = QuickPicks.inPanels(picks, tall: QuickPicks.tall)
            .enumerated().map { QuickPanel(index: $0.offset, picks: $0.element) }

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Loc.get("Home_QuickPicks"))
                    .font(.tv(Size.heading, .semibold))
                    .foregroundStyle(Ink.card)
                Spacer()
                if !songs.isEmpty {
                    Button(Loc.get("Home_PlayAllTracks"), systemImage: "play.fill") {
                        model.play(songs, from: 0)
                    }
                    .buttonStyle(.glass)
                    .remembered("playAll")
                }
            }
            .padding(.horizontal, Size.side)

            CardRow(space: "quick", items: panels) { panel in
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(panel.picks.enumerated()), id: \.offset) { _, pick in
                        QuickEntry(pick: pick, albums: albums, tracks: tracks)
                    }
                }
                .frame(width: QuickEntry.width, alignment: .topLeading)
            }
        }
    }
}

private struct QuickPanel: Identifiable {
    let index: Int
    let picks: [QuickPick]
    var id: Int { index }
}

private struct QuickEntry: View {
    /// Three columns and two gaps fill the space between the margins.
    static let width: CGFloat = (1920 - 2 * Size.side - 2 * Card.gap) / 3

    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let pick: QuickPick
    let albums: [String: CloudAlbum]
    let tracks: [String: CloudTrack]

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 22) {
                picture
                    .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.tv(Size.cardTitle, .semibold))
                        .foregroundStyle(Ink.card)
                        .lineLimit(1)
                    Text(line)
                        .font(.tv(Size.cardLine))
                        .foregroundStyle(Ink.dim)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(width: Self.width, alignment: .leading)
        }
        .buttonStyle(.card)
        .remembered("quick:\(pick.kind):\(pick.key)")
        .contextMenu { menu }
    }

    /// The menu that a long press on Select offers, as on the phone's quick selection. A song shows
    /// its own menu. A record and a list show Play and Shuffle. A station shows its own menu.
    @ViewBuilder
    private var menu: some View {
        switch pick.kind {
        case .song:
            if let track = tracks[pick.key] { TrackMenu(track: track, queue: [track], at: 0) }
        case .album:
            if let album = albums[pick.key] {
                Button(Loc.get("AlbumMenu_Play"), systemImage: "play.fill") { model.play(album.tracks, from: 0) }
                Button(Loc.get("AlbumMenu_Shuffle"), systemImage: "shuffle") { model.shuffle(album.tracks) }
            }
        case .playlist:
            if let set = HomeLists.set(named: pick.key, in: model.session.playlists) {
                Button(Loc.get("Playlists_Play"), systemImage: "play.fill") { model.play(set.tracks, from: 0) }
                Button(Loc.get("AlbumMenu_Shuffle"), systemImage: "shuffle") { model.shuffle(set.tracks) }
            }
        case .station:
            if let station = model.session.homeStations[pick.key] { StationMenu(station: station) }
        }
    }

    @ViewBuilder
    private var picture: some View {
        switch pick.kind {
        case .song:
            let track = tracks[pick.key]
            Sleeve(album: track.flatMap { albums[AlbumGrouping.key(for: $0)] }, edge: 96, corner: 8)
        case .album:
            Sleeve(album: albums[pick.key], edge: 96, corner: 8)
        case .playlist:
            if let set = HomeLists.set(named: pick.key, in: model.session.playlists) {
                ListPicture(set: set, edge: 96, corner: 8, drifts: false)
            }
        case .station:
            if let station = model.session.homeStations[pick.key] {
                StationLogo(station: station, edge: 96, corner: 8)
            }
        }
    }

    private var title: String {
        switch pick.kind {
        case .song: tracks[pick.key]?.title ?? ""
        case .album: albums[pick.key].map(AlbumNames.title) ?? ""
        case .playlist: pick.key
        case .station: model.session.homeStations[pick.key]?.display ?? ""
        }
    }

    private var line: String {
        switch pick.kind {
        case .song: tracks[pick.key]?.artist ?? ""
        case .album: Loc.get("Home_QuickKindJoin", Loc.get("Home_QuickAlbum"), albums[pick.key]?.artist ?? "")
        case .playlist:
            Loc.get("Home_QuickKindJoin", Loc.get("Home_QuickPlaylist"),
                    HomeLists.set(named: pick.key, in: model.session.playlists).map(ListLines.caption) ?? "")
        case .station: Loc.get("Home_QuickStation")
        }
    }

    private func choose() {
        switch pick.kind {
        case .song:
            if let track = tracks[pick.key] {
                model.play([track], from: 0)
                screens.playerShown = true
            }
        case .album:
            screens.open(.album(pick.key))
        case .playlist:
            if let set = HomeLists.set(named: pick.key, in: model.session.playlists) { screens.open(.list(set.id)) }
        case .station:
            if let station = model.session.homeStations[pick.key] {
                model.tune(station)
                screens.playerShown = true
            }
        }
    }
}
