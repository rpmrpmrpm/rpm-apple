import SwiftUI
import RPMSharedUI
import RPMKit
import RPMLibrary
import RPMRadio
import RPMArt
import RPMDesign
import RPMStages
import QuartzCore

/// The look of the front card, passed up so the page behind it can use the same picture.
///
/// The desktop does the same: a page gives its background to the window, and it gives **what it
/// is actually showing** and not the value that chose it. One place decides, so it cannot differ
/// from what is on screen. See `PlaylistView.Lend` and ``ArtGround``.
public struct BannerDress: Equatable {
    /// Which card this came from and which of its pictures it shows. The background fades when
    /// either changes: when the ring moves, or when the card's photograph arrives over its cover.
    ///
    /// **It names both the card and the picture.** If it named only the card's key, a card that
    /// reported its cover and then its photograph would give the same value twice. ``ArtGround``
    /// changes only when this value changes, so the page would keep the cover's colours (for
    /// example an olive background under a grey photograph) until another card came round.
    public let wearing: String

    /// The photograph that fills the card, or nil when the card is drawn on a room instead.
    public let picture: Image?

    /// The colour taken from the cover, or nil when the picture is a photograph. The colour of a
    /// photograph belongs to the photograph, as on the artist page.
    public let accent: Accent?

    /// The three colours that light the card's room, from top to bottom. They are used when the
    /// card has no photograph and is drawn on a room. Empty when the card shows a picture.
    ///
    /// **It passes the colours and not the shader.** The users are a page background and a
    /// reflection, and neither needs a real room. A second lit room for a picture that nobody
    /// looks at directly would run another shader on every frame, in addition to the one the
    /// card already runs.
    public let colours: [Color]
}

/// The featured banner: a few cards, shown one at a time, changed by a swipe or the dots.
///
/// ``HomeScreen`` chooses the cards once per launch, not this view. A banner that rearranges
/// itself while the person is looking at it is worse than one that never changes. This view
/// owns only which of the chosen cards is in front, which depends on the person.
public struct HomeBannerView: View {
    private let strip: [HomeFeature]
    private let albums: [String: CloudAlbum]

    /// The generated lists by name, for the picture of a generated card and the colours that
    /// light its room.
    private let lists: [String: PlaylistSet]

    private let covers: any CoverStore
    private let backdrops: BackdropStore?
    private let onOpen: (CloudAlbum) -> Void
    private let onOpenList: (String) -> Void

    /// The stations that the strip names, by uuid, and what pressing one does.
    private let stations: [String: RadioStation]
    private let onTune: (RadioStation) -> Void

    /// How far the card reaches ABOVE the place where the page's rows begin: the status bar and
    /// the page's heading, which the picture runs up behind.
    ///
    /// The page measures it and passes it in, because only the page knows the height of its own
    /// heading. Zero means the banner starts where it is placed.
    private let overhang: Double

    /// Reports the look of the front card when its picture arrives and when the ring moves. The
    /// page behind uses it. **Only the front card is reported**, and only when it has something
    /// to show. A front card that is still loading leaves the background it already has, as the
    /// desktop's backdrop does for a page that is open but has no picture yet.
    ///
    /// **It is reported when the card is CHOSEN, not when it has arrived.** If it waited until the
    /// strip came to rest, the background would change after everything else had stopped moving.
    /// The reflection moves with the card under the finger, so the late change would look like a
    /// second event. The background starts to change when the card starts to move and is
    /// finished when the card arrives.
    private let onDressed: ((BannerDress) -> Void)?

    /// Called when the front card has its cover and has finished looking for its photograph,
    /// whether it found one or not. The launch keeps its wait mark until then, so the home screen
    /// appears fully drawn. See `RootView`. It is required: a banner that never calls it keeps
    /// the launch waiting until its time limit.
    private let onReady: () -> Void

    /// Whether the front card has finished looking. This starts the warming of the other cards.
    @State private var frontHasLooked = false

    /// The strip's width. Every card has exactly this width.
    @State private var width: Double = 0

    /// Whether the home screen is the one showing. It stays built under the other tabs so it is
    /// unchanged when the person returns, and while it is hidden nothing on it may animate.
    private let onScreen: Bool

    /// The slot in front. It is a slot and not a card, because the strip draws a copy of the
    /// first card after the last. See ``BannerRing``.
    @State private var at = 0

    /// Whether the strip is at rest: no finger on it and no scroll still settling. See
    /// ``ScrollRest``.
    @State private var still = true

    /// The start time of every card's room clock. There is one for the whole strip, so the copy of
    /// the first card and the first card draw the same frame when one replaces the other. See
    /// ``RoomView/Zero``.
    @State private var roomZero = Date()

    @Environment(\.scenePhase) private var phase

    /// The home page's scroll state, to know whether the page is at its top. Only
    /// ``ScrollReach/atTop`` is read here. It changes when the page leaves its top and when it
    /// returns, not on every frame.
    @Environment(\.scrollReach) private var reach

    public init(strip: [HomeFeature], albums: [String: CloudAlbum], lists: [String: PlaylistSet],
                stations: [String: RadioStation],
                covers: any CoverStore, backdrops: BackdropStore?, overhang: Double = 0,
                onScreen: Bool,
                onOpen: @escaping (CloudAlbum) -> Void,
                onOpenList: @escaping (String) -> Void,
                onTune: @escaping (RadioStation) -> Void,
                onReady: @escaping () -> Void,
                onDressed: ((BannerDress) -> Void)? = nil) {
        self.onReady = onReady
        self.stations = stations
        self.onTune = onTune
        self.strip = strip
        self.albums = albums
        self.lists = lists
        self.covers = covers
        self.backdrops = backdrops
        self.overhang = overhang
        self.onScreen = onScreen
        self.onOpen = onOpen
        self.onOpenList = onOpenList
        self.onDressed = onDressed
    }

    public var body: some View {
        VStack(spacing: 10) {
            // A paged scroll and not a stack with a drag gesture. The ring must follow the finger
            // and settle where it is released, which a paged scroll already does.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<ring.slots, id: \.self) { slot in
                        let feature = strip[ring.card(at: slot)]

                        card(feature, live: slot == at)
                            // **The card's identity is its content, not its slot.** The slot number
                            // is used for the scroll position. After a switch to another
                            // collection, a new home screen puts a different record in the same
                            // slot. If the identity were the slot alone, the card would keep the
                            // old record's cover and photograph under the new record's name,
                            // because its fetch depends on the width, which did not change.
                            .id("\(feature.kind)|\(feature.key)")
                            .containerRelativeFrame(.horizontal)
                            .id(slot)
                    }
                }
                .scrollTargetLayout()
            }
            // The cards cast their reflections below the strip, and a scroll clips its content to
            // its own bounds. Clipping is disabled for this. Sideways nothing changes: a card is
            // exactly the strip's width, so its neighbours are off the screen, where the page's
            // own scroll cuts them.
            .scrollClipDisabled()
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: Binding(
                get: { Optional(at) },
                set: { at = $0 ?? at }))
            // When the strip rests on the copy of the first card, it is moved to the first card
            // itself. This runs when the scroll comes to rest, so a swipe onto the copy is
            // handled in the same way as the banner's own step.
            .modifier(ScrollRest(still: $still, onRest: settle))
            // A new strip with fewer cards can leave the front slot beyond the end.
            .onChange(of: ring) { _, _ in
                if still { settle() }
            }
            .frame(height: HomeBannerMetrics.height(above: overhang))
            .onGeometryChange(for: Double.self, of: { $0.size.width }) { width = $0 }

            if strip.count > 1 {
                dots
            }
        }
        // Warms the cards that are not built yet, after the front card has looked. It also depends
        // on the strip, so a new strip (for example when playlists arrive after launch) warms its
        // new cards.
        .task(id: Warming(ready: frontHasLooked, cards: strip.map(\.key), width: width),
              priority: .utility) {
            guard frontHasLooked, width > 0 else { return }

            // Wait until the launch's wait mark has gone, so the warming does not compete with the
            // page's first frames. The mark stays until the front card has looked, then fades
            // for 0.35 s.
            try? await Task.sleep(for: .milliseconds(600))
            await warm(width: width)
        }
        // The banner steps itself every seven seconds, as on the desktop. The task depends on the
        // whole dwell value, so a swipe, a moving strip, the page leaving its top, a tab change or
        // the app leaving the foreground cancels the countdown and starts a new one.
        .task(id: dwell) {
            let step = dwell
            guard step.counts else { return }

            do { try await Task.sleep(for: BannerDwell.hold) } catch { return }

            // The sleep can finish and the id can change before this code runs, because both
            // arrive on the main actor in either order. A cancelled countdown must not step.
            guard !Task.isCancelled else { return }

            // When the step has finished, settle again in case the scroll does not report its own
            // animation as a phase. Only do this while the strip is at rest, so a finger that
            // touches the strip during the step is not interrupted.
            withAnimation(.default) { at = step.next } completion: {
                if still { settle() }
            }
        }
    }

    /// If the strip is on the copy of the first card, moves it to the first card itself, without
    /// animation. The two look the same, so the jump is not visible. It does nothing when the
    /// strip is on an ordinary card.
    ///
    /// **Call it when the strip has come to rest, never when the slot changes.** The slot changes
    /// at the START of a step, before the scroll reports that it is moving. A check at that time
    /// would see a strip at rest on the copy and move it back to the first card before it had
    /// moved, and the banner would stop at its last card.
    private func settle() {
        guard let card = ring.rest(at: at) else { return }

        var quiet = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) { at = card }
    }

    /// The strip as a loop. The copy of the first card is drawn only where the strip can report
    /// when it is at rest. See ``ScrollRest/reportsRest``.
    private var ring: BannerRing { BannerRing(cards: strip.count, loops: ScrollRest.reportsRest) }

    /// When the banner steps itself. See ``BannerDwell``.
    ///
    /// A banner with no scroll around it has no page to scroll away from, so it counts as at the
    /// top. On home it is always inside the page's ``DissolvingScroll``.
    private var dwell: BannerDwell {
        BannerDwell(at: at, ring: ring, onScreen: onScreen && phase == .active,
                    pageAtTop: reach?.atTop ?? true, still: still)
    }


    private struct Warming: Hashable {
        let ready: Bool
        let cards: [String]
        let width: Double
    }

    /// The front card has its cover and has looked for its photograph.
    private func frontLooked() {
        onReady()
        frontHasLooked = true
    }

    /// Fetches what the other cards will request, so a swipe lands on a card that already has
    /// its pictures and does not start loading then.
    ///
    /// **It makes the same requests as the cards**: the cover at the card's cover size and the
    /// photograph cut for ``HomeFeatureCard/scene(width:overhang:)``. Each result goes into the
    /// cache that the card reads (`ArtworkStore` for the cover, `BackdropStore` for the cut).
    /// `BackdropStore` keeps eight photographs and the strip has at most seven cards, so warming
    /// does not remove the front card's photograph.
    ///
    /// **It runs one card at a time, at low priority**, so it does not slow the page. Both stores
    /// are actors off the main thread, and cutting the photograph is the only real work.
    ///
    /// A station's card is not warmed: its cover is the station's logo, which the card fetches
    /// itself and which is never a photograph.
    private func warm(width: Double) async {
        let scene = HomeFeatureCard.scene(width: width, overhang: overhang,
                                          statusBar: RPMSafeArea.top)

        for (index, feature) in strip.enumerated() where index != ring.card(at: at) {
            guard !Task.isCancelled else { return }

            switch feature.kind {
            case .madeForYou:
                guard let set = lists[feature.key] else { continue }
                if await covers.picture(of: set.picture, edge: HomeBannerMetrics.sleeve) == nil,
                   let first = set.tracks.first {
                    _ = await covers.cover(for: first, edge: HomeBannerMetrics.sleeve)
                }

            case .radio:
                continue

            default:
                guard let album = albums[feature.key] else { continue }
                _ = await covers.cover(for: album, edge: HomeBannerMetrics.sleeve)
                _ = await backdrops?.portrait(artist: album.artist, album: album.album, cutFor: scene)
            }
        }
    }

    /// Shows the position in the ring. It is small and is the only control on the card. The
    /// desktop has two keys for a pointer, and a phone does not need them because the person can
    /// swipe.
    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(strip.indices, id: \.self) { index in
                Circle()
                    .fill(RPMInk.white(index == ring.card(at: at) ? 1 : 0x44 / 255))
                    .frame(width: 5, height: 5)
            }
        }
    }

    /// How deep the cards' reflections are. There is one value for the whole strip and not one per
    /// card, because the cards are the same size in the same place. Two depths in one ring would
    /// make the reflection change length as it moves.
    private var mirror: Double {
        HomeBannerMetrics.reflection(cards: strip.count, rowArt: HomeRowView.art)
    }

    /// - Parameter live: whether this is the card in front. The room behind a generated list's
    ///   card drifts only there, as on the desktop strip: a running shader heats the phone
    ///   whether or not anyone is looking at it. See `HomeView.ShowRooms`.
    @ViewBuilder
    private func card(_ feature: HomeFeature, live: Bool) -> some View {
        switch feature.kind {
        case .madeForYou:
            HomeFeatureCard(kicker: Loc.get("Home_MadeForYou"), title: feature.key,
                            subtitle: nil, album: nil, artist: nil,
                            list: lists[feature.key]?.picture,
                            track: lists[feature.key]?.tracks.first,
                            glyph: Glyph.playlists, room: true, live: live, onScreen: onScreen, mirror: mirror,
                            framed: FramedList.of(lists[feature.key]),
                            overhang: overhang, covers: covers, backdrops: backdrops,
                            key: feature.key, onDressed: onDressed, onLooked: frontLooked,
                            roomZero: roomZero)
                .onTapGesture { onOpenList(feature.key) }

        case .radio:
            // The station played most on the listener's devices. It is drawn on a room like a
            // generated list, because a station has no artist to photograph. Its logo is the
            // cover. Pressing it tunes the station, as the desktop's card does.
            if let station = stations[feature.key] {
                HomeFeatureCard(kicker: kicker(feature.kind), title: station.display,
                                subtitle: nil, album: nil, artist: nil,
                                list: nil, track: nil, glyph: Glyph.radio,
                                room: true, live: live, onScreen: onScreen, mirror: mirror,
                                station: station,
                                overhang: overhang, covers: covers, backdrops: backdrops,
                                key: feature.key, onDressed: onDressed, onLooked: frontLooked,
                                roomZero: roomZero)
                    .onTapGesture { onTune(station) }
            }

        default:
            if let album = albums[feature.key] {
                HomeFeatureCard(kicker: kicker(feature.kind), title: album.album,
                                subtitle: album.artist, album: album, artist: album.artist,
                                list: nil, track: nil, glyph: Glyph.record,
                                room: false, live: live, onScreen: onScreen, mirror: mirror,
                                overhang: overhang,
                                covers: covers, backdrops: backdrops,
                                key: feature.key, onDressed: onDressed, onLooked: frontLooked,
                                roomZero: roomZero)
                    .onTapGesture { onOpen(album) }
            }
        }
    }

    /// The label that says why this card is shown. It uses the same text as the row headings, so
    /// the banner and the rows below it name each reason in the same way.
    private func kicker(_ kind: HomeFeatureKind) -> String {
        switch kind {
        case .continue: return Loc.get("Home_Continue")
        case .added: return Loc.get("Home_Added")
        case .madeForYou: return Loc.get("Home_MadeForYou")
        case .suggested: return Loc.get("Home_Suggested")
        case .played: return Loc.get("Home_Played")
        case .listened: return Loc.get("Home_Listened")
        case .radio: return Loc.get("Rpm_Tab_Radio")
        }
    }
}

/// Reports whether a scroll view is at rest: not dragged, not decelerating, and not animating to
/// a position it was sent to. The banner's own step counts as moving, so its countdown starts
/// again after the step has finished.
///
/// **iOS 17 has no scroll phase**, so there the strip always reports at rest and a step can
/// happen while the person is dragging. The effect under the finger on iOS 17 is unknown.
private struct ScrollRest: ViewModifier {
    @Binding var still: Bool

    /// Called when the scroll comes to rest after moving. It is never called on iOS 17.
    let onRest: () -> Void

    /// Whether this system reports when a scroll is at rest. Where it does not, ``still`` is
    /// always true and has no meaning.
    static var reportsRest: Bool {
        if #available(iOS 18, *) { return true }
        return false
    }

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollPhaseChange { before, now in
                still = now == .idle
                if now == .idle, before != .idle { onRest() }
            }
        } else {
            content
        }
    }
}

/// One featured card: the artist's photograph fills it, with the cover and three lines of text at
/// the bottom.
struct HomeFeatureCard: View {
    let kicker: String
    let title: String
    let subtitle: String?
    let album: CloudAlbum?
    let artist: String?

    /// The list's own picture, when this card is a generated list. Nil on a record's card.
    let list: ListPicture?

    /// The record that the list opens on. The square uses it when the list has no picture.
    let track: CloudTrack?

    /// The mark shown in the square until a picture arrives.
    let glyph: String

    /// Whether this card is drawn on a room and not on a photograph.
    ///
    /// **A generated list has no artist to photograph**, so the desktop lights its card with the
    /// same shapes that Pegasus draws behind a record, in the list's own colours. The colours are
    /// taken from the picture at the bottom. A record's card removes the room, so the previous
    /// list's colours do not stay behind a photograph.
    let room: Bool

    /// Whether this is the front card. The room drifts only there.
    let live: Bool

    /// Whether the home screen is showing at all. See ``HomeBannerView/onScreen``.
    let onScreen: Bool

    /// How deep the reflection under this card is. Zero means no reflection.
    ///
    /// **Every card has its own reflection**, and there is no single reflection under the strip
    /// that swaps when the strip settles. A reflection belongs to the thing it reflects, so it
    /// moves with the card under the finger.
    var mirror: Double = 0

    /// The frame around this list's square, when the list is a generated one.
    ///
    /// **It is on the square and not on the plate**, as on the desktop's card. The drawing is a
    /// square with a window cut in it. If it were stretched across a card three times as wide as
    /// it is tall, it would look like a different picture. See `HomeView.xaml`.
    var framed: FramedList? = nil

    /// The station this card tunes, when it is the radio card. Its logo is the cover.
    var station: RadioStation? = nil

    /// How far the card reaches up behind the page's heading and the status bar. See
    /// ``HomeBannerView/overhang``.
    let overhang: Double

    let covers: any CoverStore
    let backdrops: BackdropStore?

    /// The key of this card's content. It is included in what the card reports, so the report
    /// says which card it came from. See ``BannerDress``.
    let key: String

    /// Receives the look of this card. See ``HomeBannerView/onDressed``.
    let onDressed: ((BannerDress) -> Void)?

    /// Called when this card, while it is the front card, has its cover and has finished looking
    /// for its photograph. See ``HomeBannerView/onReady``.
    let onLooked: () -> Void

    /// The start time of this card's room clock. It belongs to the strip and is shared by every
    /// card on it. See ``HomeBannerView/roomZero``.
    let roomZero: Date

    @State private var cover: Cover?
    @State private var picture: CGImage?

    /// The card drawn once into a bitmap, for one photograph and one size. It is shown only while
    /// ``bakeAsk`` still describes it; see ``RunOffPlate``.
    @State private var baked: RunOffPlate?

    @Environment(\.displayScale) private var displayScale

    /// Whether the photograph has been looked for and the result is known.
    ///
    /// **This is different from whether a photograph EXISTS.** A card that has not finished
    /// looking and a card that has no photograph both have a nil picture, but only the second
    /// should show the room. If the room were drawn for the first, it would appear for the few
    /// frames that the lookup takes and then be covered by the photograph, which looks like a
    /// flash on every card whose picture is not yet on this phone.
    @State private var looked = false

    /// The colours of the room. It is a transition and not a single value, because the picture is
    /// decoded in one step and a fade hides that step. It is the app's own blue until the
    /// picture arrives. See ``RoomDissolve``.
    @State private var paint = RoomDissolve.still

    /// The colours of a station's square, including its generated background. They light this
    /// card's room when the card is a station's, because a station has no cover to take them
    /// from.
    @State private var stationColours: SleeveColours?

    var body: some View {
        // The card fills the whole strip, edge to edge, with square corners and no border. The
        // desktop draws it as a plate with its neighbours visible on both sides, but a phone is
        // too narrow for a neighbour to be more than a sliver.
        GeometryReader { box in 
            let width = box.size.width

            // **The ground extends below the card and the text does not.** The reflection under
            // the card is the same drawing turned over, so it cannot be clipped at the card's
            // edge. The title, artist and cover belong to the card and stop at its edge. So there
            // are two clips and not one around both.
            ZStack(alignment: .top) {
                // Scaled up about the card's bottom while the page is pulled down past its top, so
                // the photograph zooms and the page's ground does not show above the card. The
                // text is not scaled. Only the front card is scaled: the next card waits just off
                // the edge of the screen, and if it grew about its centre it would reach over this
                // one.
                ground(width: width)
                    .growsWithPull(plate: plate,
                                   anchor: UnitPoint(x: 0.5, y: plate / (plate + mirror)),
                                   grows: live)

                ZStack(alignment: .bottomLeading) {
                    Color.clear

                    writing
                        .padding(HomeBannerMetrics.margin)
                }
                .frame(width: width, height: plate)
                .clipped()
            }
            .frame(width: width, height: plate, alignment: .top)
            .task(id: width) {
                await fetch(width: width)
            }
            .task(id: bakeAsk(width: width)) {
                await bake(width: width)
            }
        }
        .frame(height: plate)
        // The page behind takes its background from the front card, so two events are reported:
        // this card finding its picture, and this card becoming the front card. Nothing is
        // reported while there is nothing to report. See ``HomeBannerView/onDressed``.
        .onChange(of: wearing) { _, _ in
            if live, let dressing { onDressed?(dressing) }
        }
        .onChange(of: live) { _, now in
            if now, let dressing { onDressed?(dressing) }
        }
        .onAppear {
            if live, let dressing { onDressed?(dressing) }
        }
        // `looked` is set when the cover is loaded and the photograph has been looked for,
        // whether found or not. It is also checked on appear, for a card whose results were
        // already available.
        .onChange(of: looked) { _, now in
            if now, live { onLooked() }
        }
        .onAppear {
            if looked, live { onLooked() }
        }
    }

    /// Called when the station's square has its logo and, if needed, its generated background.
    /// It lights the room with those colours, as a record's card is lit with its cover.
    private func stationWears(_ colours: SleeveColours) {
        stationColours = colours
        paint = paint.toward(.from(tint: colours.dominant?.asFloats,
                                   glow: colours.highlight?.asFloats,
                                   shade: colours.shade?.asFloats),
                             at: CACurrentMediaTime())
    }

    /// The frame that a photograph is cut for, on a card of this width and overhang. The card's
    /// own fetch and ``HomeBannerView``'s warming of cards not yet built both use it, so a warmed
    /// cut is the same cut that the card requests.
    ///
    /// - Parameter statusBar: the height of the status bar. The card runs up behind it, so a face
    ///   placed there would be behind the Dynamic Island. See ``ArtScene/clearTop``.
    static func scene(width: Double, overhang: Double, statusBar: Double) -> ArtScene {
        let plate = HomeBannerMetrics.height(above: overhang)
        return ArtScene.forClearLeft(
            width: width, height: plate,
            clearTop: HomeBannerMetrics.clearTop(statusBar: statusBar, above: overhang),
            clearRight: HomeBannerMetrics.clearRight(plate: width),
            clearBottom: HomeBannerMetrics.clearBottom(above: overhang))
    }

    /// Which picture this card shows, as a value that changes exactly when the picture changes.
    ///
    /// **This value is watched and not `dressing` itself.** A `BannerDress` holds an `Image`, and
    /// an image created again on every pass of the body cannot be compared for equality. A
    /// comparison that said "different" every time would report on every frame, and each report
    /// writes the page's state and runs the body again.
    private var wearing: String {
        if picture != nil { return key + "\u{1}photograph" }
        if standingOnARoom, roomInk.count > 1 { return key + "\u{1}room" }
        if cover != nil { return key + "\u{1}sleeve" }
        return ""
    }

    /// What this card actually shows: the photograph if it has arrived, the room if the card is
    /// drawn on one, and the cover if it has neither. Nil means the card has nothing yet.
    ///
    /// **These are the three pictures the card itself draws, in the order it draws them.** See
    /// ``ground``. If a page or a reflection used a cover that the card does not show, it would
    /// differ from the card, and the difference would be visible where they meet.
    private var dressing: BannerDress? {
        if let picture {
            return BannerDress(wearing: wearing, picture: Image(decorative: picture, scale: 1),
                               accent: nil, colours: [])
        }

        if standingOnARoom, case let ink = roomInk, ink.count > 1 {
            return BannerDress(wearing: wearing, picture: nil, accent: nil, colours: ink)
        }

        if let cover {
            return BannerDress(wearing: wearing, picture: cover.image, accent: cover.accent, colours: [])
        }

        return nil
    }

    /// Whether the card is drawn on its room. This is the condition that ``ground`` uses, defined
    /// in one place so that what is reported always matches what is drawn.
    private var standingOnARoom: Bool { RoomView.works && (room || (looked && picture == nil)) }

    /// The room's three colours, from top to bottom: a generated list's own colours, or the three
    /// taken from the cover. These are the same three colours that light the room.
    private var roomInk: [Color] {
        if let framed {
            return [framed.look.trio.hot.color, framed.look.trio.mid.color,
                    framed.look.trio.deep.color]
        }

        guard let read = cover?.colours ?? stationColours else { return [] }
        return [read.highlight, read.dominant, read.shade].compactMap { $0?.color }
    }

    /// The height of this card: the composition plus the part that reaches up behind the heading.
    private var plate: Double { HomeBannerMetrics.height(above: overhang) }

    @ViewBuilder
    /// The card's ground, and the same ground again under it, upside down and fading out.
    ///
    /// **The room is not drawn twice.** It is one fragment program over a taller rectangle, told
    /// where the card ends: below that line it draws what is above it, mirrored. A second
    /// ``RoomView`` under the first would draw the most expensive part of the screen twice, on a
    /// second clock that would drift away from the first. See `rpmCardRoom` and
    /// ``RoomView/fold``.
    ///
    /// A picture has no such cost. ``RunOff`` mirrors it under the card, including the blur and
    /// the washes, so the reflection is never brighter than the card where they meet.
    private func ground(width: Double) -> some View {
        ZStack(alignment: .top) {
            RPMInk.ground

            // The room, in the colours of the picture at the bottom of this card. It is above the
            // ground and below the text, as the desktop's CardRoom is. A picture placed under it
            // could not be seen.
            //
            // **For a generated list it uses the list's own three colours**, and not the colours
            // taken from whatever picture the list has. This makes the plate, the square on it and
            // the row in the playlists tab look like one room, because all of them are derived from
            // the same kind, genre and decade. See ``FramedList/room``.
            //
            // **A record's plate also uses it until its photograph arrives.** On the desktop, a
            // plate with no photograph shows the blurred cover, which is a flat wash. Here the plate
            // shows the room in the same colours, which is the same picture with movement.
            //
            // The photograph is drawn over the room when it arrives. So the room is what a card
            // shows during the seconds before the photograph arrives, and permanently for an
            // artist who has no photograph.
            if standingOnARoom {
                // Inside a `Color.clear` for the same reason as the picture below. It is clipped
                // to its own frame and not to the card's, because this is the one layer that is
                // MEANT to be taller than the card.
                Color.clear
                    .overlay {
                        RoomView(colours: framed?.room ?? paint, sound: .still, foot: 1,
                                 running: live && onScreen, breathes: true,
                                 zero: .shared(roomZero), seed: key, fold: plate)
                    }
                    .frame(width: width, height: plate + mirror)
                    .clipped()
            }

            // The card's face, blurred toward its bottom and mirrored under the card.
            //
            // **It is baked once the photograph has arrived.** The live run-off is nine blurs
            // redrawn on every frame, and the baked version is one image. Until the bitmap for this
            // photograph at this size is ready (a moment after the photograph arrives or the card
            // is resized), the live version is shown and draws the same result.
            if let baked, baked.ask == bakeAsk(width: width) {
                Image(decorative: baked.image, scale: baked.ask.scale)
                    .resizable()
                    .frame(width: width, height: plate + mirror)
            } else {
                RunOff(plate: plate, depth: mirror, blurs: picture != nil, blurFrom: Self.blurFrom,
                       reflection: Self.reflection) {
                    face
                }
                .frame(width: width)
            }
        }
        .frame(width: width, height: plate + mirror, alignment: .top)
        .mirrorFade(above: plate, depth: mirror)
    }

    /// Where the card's blur starts, as a fraction of its height. The photograph is cut with the
    /// face in the upper half, and a blur that started higher would cover the face.
    private static let blurFrom = 0.6

    /// The mirror under the card is blurred all the way down. See ``RunOffReflection/blurred``.
    private static let reflection = RunOffReflection.blurred

    /// Describes the baked plate that is needed now (photograph, size and so on). Nil while there
    /// is no photograph, and then nothing is baked.
    private func bakeAsk(width: Double) -> RunOffPlate.Ask? {
        guard let picture, width > 0 else { return nil }
        return RunOffPlate.Ask(picture: ObjectIdentifier(picture), width: width, plate: plate,
                               depth: mirror, blurFrom: Self.blurFrom, reflection: Self.reflection,
                               scale: displayScale)
    }

    /// Draws the plate described by ``bakeAsk``. It runs again whenever that value changes. The
    /// result is kept only if the value is still the same when the bake finishes, so a slow bake
    /// for an old size or an old photograph never replaces a newer one.
    private func bake(width: Double) async {
        guard let picture, let ask = bakeAsk(width: width) else { return }
        guard baked?.ask != ask else { return }

        let plate = await RunOffPlate.bake(picture, for: ask)
        guard !Task.isCancelled, bakeAsk(width: width) == ask else { return }
        baked = plate
    }

    /// Everything on the card except the room and the text: the photograph and the washes over
    /// it. It is one card tall. ``RunOff`` blurs it toward the bottom and mirrors it.
    private var face: some View {
        ZStack {
            if let picture {
                // **The image is inside a `Color.clear` for a layout reason.** A resizable image
                // that fills its frame reports its SCALED size as its own size. A photograph that
                // is cut taller than this plate would make the stack as wide as the photograph.
                // The text is aligned to the leading edge of the stack, which would then be outside
                // the card, and the fixed frame around it would centre the pair. The cover would
                // move off the left of the screen, and the title would stay on one line because it
                // was never offered the card's width.
                //
                // `ArtistPage.ground` has a note about the same trap. `clipped` here limits the
                // size that this view reports and not what is drawn. The stack outside clips what
                // is drawn.
                Color.clear
                    .overlay {
                        Image(decorative: picture, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
                    // **The picture is darkened everywhere.** See ``held``, which the reflection
                    // under the banner also uses.
                    .overlay { Color.black.opacity(Self.held) }
                    .transition(.opacity)
            }

            // A wash from the bottom up, whatever the picture is. The text is drawn on it, so a
            // title over a bright photograph can still be read.
            Self.foot
        }
    }

    /// The wash at the bottom of the card. The flat darkening over the whole picture (see
    /// ``held``) is applied under it.
    ///
    /// It is drawn into ``face``, which ``RunOff`` mirrors under the card. A mirror without these
    /// would be brighter than the card at the line where the two meet.
    ///
    /// **It is level across the bottom and not darkest at the edge.** It rises to its full
    /// strength where the text starts and stays there to the bottom. A ramp that kept getting
    /// darker to the last row would be darkest on that row, and the mirror turns back at that
    /// row, so the card and its reflection would meet in a dark stripe that no blur can hide.
    /// With a level wash, the mirror continues the same shade, and the only change is the
    /// reflection fading out.
    static let foot = LinearGradient(
        stops: [.init(color: .clear, location: 0),
                .init(color: .black.opacity(0.25), location: 0.4),
                .init(color: .black.opacity(0.7), location: 0.68),
                .init(color: .black.opacity(0.7), location: 1)],
        startPoint: .top, endPoint: .bottom)

    /// How much the picture is darkened across the whole card. The desktop darkens its picture by
    /// the same amount. The text is drawn on the picture, and a photograph at full brightness
    /// makes the title hard to read over its light parts.
    ///
    /// `nonisolated` because `RunOffPlate` reads it while drawing off the main actor, and a
    /// constant `Double` can be read safely from any thread.
    nonisolated static let held: Double = 0.2

    private var writing: some View {
        HStack(alignment: .bottom, spacing: HomeBannerMetrics.margin) {
            sleeve

            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(RPMFont.display(12))
                    .tracking(1.5)
                    .foregroundStyle(RPMInk.white(0xCC / 255))

                Text(title)
                    .font(RPMFont.displayBold(22))
                    .lineLimit(2)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(RPMInk.white(0xD1 / 255))
                        .lineLimit(1)
                }
            }
            .shadow(color: .black.opacity(0.6), radius: 6, y: 1)

            Spacer(minLength: 0)
        }
    }

    private var sleeve: some View {
        ZStack {
            Color.black.opacity(0x22 / 255)

            if let framed, framed.look.roomed, RoomView.works {
                // There is nothing of its own to show behind the window. The room is static and
                // does not drift, because the plate behind it is already a live room, and two
                // shaders on every frame for one card would cost too much.
                RoomView(colours: framed.room, sound: .still, foot: 1,
                         running: false, breathes: true, zero: .whenShown, seed: key)
            } else if let station {
                StationFace(station: station, edge: HomeBannerMetrics.sleeve, inset: 14,
                            onWearing: stationWears) {
                    Text(glyph)
                        .font(RPMFont.icon(34))
                        .foregroundStyle(RPMInk.white(0x3A / 255))
                }
            } else if let cover {
                Sleeve(image: cover.image)
            } else if framed == nil {
                Text(glyph)
                    .font(RPMFont.icon(34))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: HomeBannerMetrics.sleeve, height: HomeBannerMetrics.sleeve)
        .listFrame(framed, edge: HomeBannerMetrics.sleeve)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
        }
        // The cover is drawn on a photograph and not on a flat plate. The shadow and border keep
        // it looking like a record and not like a hole in the picture.
        .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
    }

    /// Fetches the cover first and the photograph after it. The phone probably already has the
    /// cover file, and the photograph is a lookup by name over the network. The card is drawn as
    /// soon as it has the cover, and the photograph fades in when it arrives.
    private func fetch(width: Double) async {
        if let album {
            cover = await covers.cover(for: album, edge: HomeBannerMetrics.sleeve)
        } else if let list, let own = await covers.picture(of: list, edge: HomeBannerMetrics.sleeve) {
            // The list's OWN picture first, then the record it opens on. Every row in the app
            // uses this order. See PlaylistSleeve.
            cover = own
        } else if let track {
            cover = await covers.cover(for: track, edge: HomeBannerMetrics.sleeve)
        }

        // The colours that light the room, once there is a picture to take them from. The paint
        // moves toward the new colours and does not jump, so the colour fades in.
        //
        // **They are read for every card, not only for a list's card.** A record's plate is drawn
        // on the room until its photograph arrives, and the room uses the colours of its cover.
        if let read = cover?.colours {
            paint = paint.toward(.from(tint: read.dominant?.asFloats,
                                       glow: read.highlight?.asFloats,
                                       shade: read.shade?.asFloats),
                                 at: CACurrentMediaTime())
        }

        // Nothing to look for: this is a list's card, or a record with no artist name. The result
        // is known and it is "none", so the card stays on the room.
        guard let backdrops, let artist, width > 0 else {
            withAnimation(.easeOut(duration: 0.35)) { looked = true }
            return
        }

        // **It is cut for the height it is DRAWN at**, including the overhang. If it were cut for
        // the composition alone and then stretched to fill a taller plate, the face that the crop
        // placed in the clear area would end up behind the status bar.
        let scene = Self.scene(width: width, overhang: overhang, statusBar: RPMSafeArea.top)

        // The artist's square picture if fanart.tv has one. On a phone the card is nearly upright,
        // and a square picture centred on the person loses much less than a 16:9 press photo.
        // If there is no square picture, the artist's first backdrop is used. See
        // BackdropStore.portrait.
        let found = await backdrops.portrait(artist: artist, album: album?.album, cutFor: scene)

        withAnimation(.easeOut(duration: 0.35)) {
            picture = found
            looked = true
        }
    }
}
