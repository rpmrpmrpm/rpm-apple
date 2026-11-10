import SwiftUI
import RPMSharedUI
import RPMKit
import RPMLibrary
import RPMAudio
import RPMDesign
import RPMArt
import RPMStages
import QuartzCore

/// One artist: their photograph, their records on the shelves their names put them on,
/// and the acts related to them in the collection. There is no list of every song: the
/// search finds any of them, as in the Android TV app.
///
/// This is the phone version of `RPM.Desktop/Presentation/Main/Artists/ArtistDetailView.xaml`.
/// It shows the discography, which is the half of that page that comes from the collection
/// itself, and the Wikipedia text about the artist, which the desktop app shows as their
/// biography. The rest of what comes from the network (the encyclopedia links, what
/// collectors on Discogs own, who is in the band) is not shown here.
///
/// The shelving is ``ArtistShelves``, which both heads share, so a record on the live
/// shelf here is on the live shelf there.
public struct ArtistPage: View {
    private let artist: ArtistWallItem
    private let shelves: ArtistShelves
    private let covers: any CoverStore

    /// Where the Wikipedia text under the keys comes from. See ``AboutText``.
    private let articles: ArticleStore

    /// Where the listen counts of all users for each of their records come from, for Popular tracks. See
    /// ``ArtistPopular``.
    private let worldPlays: WorldPlays

    /// Where the band's photograph comes from: their square picture if fanart.tv has one, and
    /// their first backdrop if not (see ``BackdropStore/portrait(artist:album:cutFor:)``). It is
    /// cut for the band with the face clear of the name, as the home banner's is. Nil in a
    /// preview, which uses the thumbnail from ``covers`` instead.
    private let backdrops: BackdropStore?

    /// The records by key, for the related acts' boxes. A box with no photograph of the act shows
    /// one of the act's records.
    private let albums: [String: CloudAlbum]

    /// What the related acts are read from. See ``RelatedArtists``.
    private let relatedFrom: RelatedArtists.Collection

    /// Play these songs from this position. Play all passes their work record by record,
    /// and a popular song passes the popular songs.
    private let onPlay: ([CloudTrack], Int, Tapped) -> Void
    private let onShuffle: () -> Void
    private let onOpen: (CloudAlbum) -> Void
    private let onOpenArtist: (ArtistWallItem) -> Void
    private let onBack: () -> Void

    private let isTrackMarked: (CloudTrack) -> Bool

    /// Whether a song is on this account's own shelf. It has no default, for the reason the
    /// album page states: a borrowed song can be neither marked nor filed, and this one answer
    /// decides whether those actions are offered.
    private let isTrackMine: (CloudTrack) -> Bool
    private let onMarkTrack: (CloudTrack, Bool) -> Void
    private let onFile: (CloudTrack) -> Void
    private let upNext: TrackActions.UpNext

    public init(artist: ArtistWallItem, shelves: ArtistShelves, covers: any CoverStore,
                articles: ArticleStore,
                worldPlays: WorldPlays,
                backdrops: BackdropStore?,
                albums: [String: CloudAlbum],
                relatedFrom: RelatedArtists.Collection,
                onPlay: @escaping ([CloudTrack], Int, Tapped) -> Void,
                onShuffle: @escaping () -> Void,
                onOpen: @escaping (CloudAlbum) -> Void,
                onOpenArtist: @escaping (ArtistWallItem) -> Void,
                onBack: @escaping () -> Void,
                isTrackMarked: @escaping (CloudTrack) -> Bool = { _ in false },
                isTrackMine: @escaping (CloudTrack) -> Bool,
                onMarkTrack: @escaping (CloudTrack, Bool) -> Void = { _, _ in },
                onFile: @escaping (CloudTrack) -> Void = { _ in },
                upNext: TrackActions.UpNext) {
        self.artist = artist
        self.shelves = shelves
        self.covers = covers
        self.articles = articles
        let read = AboutRead(.artist(artist.name), in: articles)
        self._about = State(initialValue: read)
        self.aboutAtOpen = read.article(for: .artist(artist.name)) != nil

        // What the band was last dressed in, so a page shown again has its photograph, its colour,
        // its room and its title from the first frame. See ``HeldBand``.
        if let band = Self.heldBands[artist.name] {
            self._portrait = State(initialValue: band.portrait)
            self._pixels = State(initialValue: band.pixels)
            self._lead = State(initialValue: band.lead)
            self._paint = State(initialValue: band.paint)
            self._looked = State(initialValue: true)
        }
        if let title = Self.heldTitles[artist.name] {
            self._titleRead = State(initialValue: title.read)
            self._logoInverted = State(initialValue: title.inverted)
        }
        self.worldPlays = worldPlays
        self._popular = State(initialValue: Self.popularKept(artist: artist.name, shelves: shelves,
                                                             in: worldPlays))
        self.backdrops = backdrops
        self.albums = albums
        self.relatedFrom = relatedFrom
        self.onPlay = onPlay
        self.onShuffle = onShuffle
        self.onOpen = onOpen
        self.onOpenArtist = onOpenArtist
        self.onBack = onBack
        self.isTrackMarked = isTrackMarked
        self.isTrackMine = isTrackMine
        self.onMarkTrack = onMarkTrack
        self.onFile = onFile
        self.upNext = upNext
    }

    @State private var portrait: Cover?

    /// The photograph's pixels, for reading whether a white logo would be lost on it
    /// (``logoIsLost(_:scale:on:plate:foot:)``). Nil without a photograph.
    @State private var pixels: CGImage?

    /// Whether the logo is drawn in its inverse colours: a white logo on a bright part of the
    /// photograph is drawn dark, so it can be read. Never in night mode, where the photograph is
    /// darkened.
    @State private var logoInverted = false

    /// Whether their Wikipedia text was there when the page was built, read before and kept. Text
    /// that arrives after comes in from the top (``CentredAboutText/arrives``).
    private let aboutAtOpen: Bool

    /// The photograph's colour, which leads the page's ground (``ArtGround``): its best vivid
    /// colour, no brighter than white text allows (``GroundLead``). Read once, when the photograph
    /// arrives. Nil without a photograph, or for one with no colour to give.
    @State private var lead: Color?

    /// What the title is, once the logo lookup has answered: their logo or their name. Nil until
    /// then. See ``title``.
    @State private var titleRead: TitleRead?

    @Environment(\.displayScale) private var displayScale

    /// The acts related to them, and the ask they were read for. See ``relatedSection``.
    @State private var related: (ask: RelatedAsk, acts: [ArtistWallItem])?

    /// Their Popular tracks, and the name they were ranked for. Filled from the store's memory when
    /// the page is built, so an artist opened earlier in this session has them on the first frame.
    @State private var popular: PopularSongs?

    /// Their Wikipedia text, and the name it was read for. Filled from the store's cache when the
    /// page is built, so an artist opened earlier has their text on the first frame.
    @State private var about: AboutRead

    /// Whether the photograph has been looked for and the answer is in. A band with no photograph
    /// yet and a band with no photograph at all both hold a nil portrait. Only the second shows the
    /// room, for the reason ``HomeFeatureCard`` gives.
    @State private var looked = false

    /// What the room is painted in: the colours of their first record, as a dissolve. See
    /// ``RoomDissolve``.
    @State private var paint = RoomDissolve.still

    @Environment(\.scenePhase) private var phase

    /// How far the page is pulled down past its top. The photograph is scaled up about its foot
    /// by just enough that its top stays at the top of the screen, so an over-pull zooms the
    /// photograph and does not show the page's ground above it. The writing is not scaled.
    @State private var pull: CGFloat = 0

    /// How wide the page is, measured from the background where it changes nothing.
    /// A `GeometryReader` around a scrolling page puts its rows in a coordinate
    /// space that does not always match the one that taps use.
    private struct PageWidth: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    @State private var width: CGFloat = 0

    /// A `List`, and it draws nothing a list draws, for the reason ``AlbumPage`` is one:
    /// `swipeActions` works only in `List` and does nothing anywhere else, so the two
    /// keys in ``TrackActions`` could be reached only by a long press.
    public var body: some View {
        List {
            Group {
                // The row the dissolve reads the scroll from. It is the first row and taller than
                // the dissolve's ramp, so it is on screen for the whole ramp.
                band.scrollProbe()

                popularSection

                // The first shelf opens a new part of the page, so it has the larger space above it.
                ForEach(shownShelves) { row in
                    shelf(row.heading, row.records, top: row.first ? Self.sectionTop : Self.shelfTop)
                }

                relatedSection

                Color.clear.frame(height: 40)
            }
            .plainRow()
        }
        .listStyle(.plain)
        .rowsKeepTheirWidth()
        .scrollContentBackground(.hidden)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: PageWidth.self, value: geometry.size.width)
            }
        }
        .environment(\.defaultMinListRowHeight, 1)
        .scrollIndicators(.hidden)
        // The band starts at the top of the screen, behind the status bar, as the home banner
        // does. The back key is placed over the page after this, so it keeps the safe area.
        .ignoresSafeArea(edges: .top)
        // What scrolls up behind the clock and the back key dissolves into the page's background
        // there, as on home.
        .dissolvesAtTop(under: RPMSafeArea.top + RPMLayout.backRow)
        .onPreferenceChange(PageWidth.self) { width = $0 }
        // A soft dark outline on all the page's text, so it stays readable where the photograph
        // under it is bright. See ``TextFeatherKey``.
        .environment(\.textFeather, true)
        .background { ground }
        .rpmFloatingBack(RPMBackKey(label: Loc.get("Artists_Back"), action: onBack))
        .task(id: BandAsk(artist: artist.name, width: bandWidth, plate: plate)) {
            await dress()
        }
        .task(id: logoAsk) { await letter(logoAsk) }
        .task(id: InvertAsk(title: titleRead?.id ?? "", photo: pixels.map { ObjectIdentifier($0) },
                            night: night)) {
            await judgeTheLogo()
        }
        .task(id: popularAsk) { await rankPopular() }
        .task(id: relatedAsk) { await readRelated(relatedAsk) }
        .task(id: subject.id) { await AboutRead.read(subject, from: articles, into: $about) }
    }

    /// What the Wikipedia text is about: the artist, asked with the name alone, as the desktop
    /// app's artist page asks.
    private var subject: ArticleStore.Subject { .artist(artist.name) }

    /// What Wikipedia says about them, if it says anything. It is under their name and above the
    /// keys, and below the photograph's foot, not on it.
    @ViewBuilder
    private var aboutThem: some View {
        if let article = about.article(for: subject) {
            CentredAboutText(article: article, arrives: !aboutAtOpen)
                .padding(.top, 10)
        }
    }

    private var bandWidth: CGFloat { width > 0 ? width : 390 }

    /// The band as drawn: a square as wide as the page, from the top of the screen, behind the
    /// status bar. Their square picture fills it whole. A backdrop is cut around the face.
    ///
    /// The band is square for every artist, not only for those with a square picture. Which
    /// picture an artist has is known only when it arrives, and a band that took its shape from
    /// the picture would change height under the page at that moment.
    private var plate: CGFloat { bandWidth.rounded() }

    /// The space above the Play and Shuffle keys and under them, before the first shelf.
    /// The two spaces are equal: ``writingFoot`` plus ``keysTop`` above, and ``keysBottom`` plus
    /// the shelf's own top padding below.
    private static let keysTop: Double = 14
    private static let keysBottom: Double = 10
    private static let keysHeight: Double = 50

    /// The keys' row, which stands on the band's reflection. This height is also kept when an
    /// artist has no songs and so no keys.
    private static let keysRow: Double = keysTop + keysHeight + keysBottom

    /// The space under the last line of writing: under the title, where it stands on the
    /// photograph's foot, and under the Wikipedia text when there is any.
    private static let writingFoot: Double = 14

    /// Where the photograph's blur starts, as a fraction of the plate from the top.
    private static let blurFrom = 0.6

    // ── the page's ground ──

    /// The photograph's main colour under the whole page, with the photograph blurred over it
    /// faintly, so the page reads as the artist's colour and not as a blurred picture (``lead``).
    /// Unlike a record's, it has no tint over it: the colour on an artist's page comes from the
    /// photograph. In night mode the blurred photograph is the ground, as it is on every other
    /// page. The layers are ``ArtGround``'s.
    private var ground: some View {
        ArtGround(picture: portrait?.image, showing: artist.name, lead: lead)
    }

    // ── the band across the top ──

    /// The photograph across the top, their title centred on its foot, the Wikipedia text under
    /// that, and the keys. The title is their logo if a catalogue has one and their name if not
    /// (see ``title``). There are no counts of records and songs under it.
    ///
    /// **The text is below the photograph, not on it.** The title stands in the same place whether
    /// or not there is text, and the text sits under it, past the photograph's foot. The band
    /// grows by the height of the text, so the same title covers the photograph whether or not
    /// there is anything to read.
    ///
    /// Text that arrives from the network moves the keys and the shelves down in one step, as on the
    /// album page: the row grows, and a row that grows is not animated (see `AboutRead`). The text
    /// fades in by itself.
    private var band: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                // Bottom-aligned in the plate less the space under it, so its foot stays in the
                // same place when there is no text under it. The height is fixed, so a logo that
                // replaces the name does not move anything below it.
                title
                    .frame(maxWidth: .infinity, minHeight: plate - Self.writingFoot,
                           maxHeight: plate - Self.writingFoot, alignment: .bottom)
                    .animation(.easeOut(duration: 0.25), value: titleRead?.id)

                // Under the name, so the reader sees it before they play the music.
                aboutThem
            }
            .shadow(color: .black.opacity(0.6), radius: 6, y: 1)
            .padding(.horizontal, RPMLayout.margin)
            .padding(.bottom, Self.writingFoot)

            // The clear row keeps the space when an artist has no songs and so no keys.
            ZStack(alignment: .top) {
                Color.clear.frame(height: Self.keysRow)
                keys
            }
        }
        // The photograph behind all of it. Its reflection runs under everything below the plate:
        // the text when there is any, and the keys. The depth is read from the band when it is laid
        // out, so it is right whether the text is there on the first frame, arrives later, or never
        // arrives. A background has the size of the band and takes no part in its layout. It stays
        // inside the band's own list row, because a row that draws past its bottom edge can end up
        // over or under the next row, depending on how the list orders its cells.
        .background(alignment: .top) {
            GeometryReader { box in
                photograph(depth: max(0, box.size.height - plate))
            }
        }
        .animation(.easeOut(duration: 0.25), value: portrait != nil)
    }

    /// The photograph, blurred toward its foot and mirrored `depth` points under the plate as it is
    /// drawn, fading out into the page's ground.
    private func photograph(depth: Double) -> some View {
        ZStack(alignment: .top) {
            // When there is no photograph: the room, in the colours of their first record, as the
            // home banner's card stands on it, blurred and mirrored as the photograph is
            // (``roomRunOff(depth:)``).
            if standingOnARoom {
                roomRunOff(depth: depth)
                    .transition(.opacity)
            }

            RunOff(plate: plate, depth: depth, blurs: portrait != nil, blurFrom: Self.blurFrom,
                   reflection: Self.reflection) {
                face
            }
        }
        .frame(height: plate + depth, alignment: .top)
        .mirrorFade(above: plate, depth: depth)
        .scaleEffect(1 + pull / plate, anchor: UnitPoint(x: 0.5, y: plate / (plate + depth)))
        .allowsHitTesting(false)
        // Where the band's top is on the screen. At rest it is the top of the screen, so any
        // value below that means the page is pulled down past its top. It is written from here and
        // not passed up as a preference, because a list row does not reliably pass a preference to
        // the page. Only changes are written, and the value is zero for every ordinary scroll.
        .background {
            GeometryReader { box in
                Color.clear.onChange(of: box.frame(in: .global).minY, initial: true) { _, top in
                    let now = max(0, top)
                    if now != pull { pull = now }
                }
            }
        }
    }

    /// The room, drawn as the photograph is: blurred toward the band's foot from where the
    /// photograph's blur starts (``blurFrom``), and mirrored under the band at the blur of its foot,
    /// all the way down (``reflection``). It fades in, as the photograph does, and the page stands on
    /// its colour (``lead``).
    ///
    /// Two passes of the one fragment program: the room as it is, folded at the plate so it draws its
    /// own mirror (``RoomView/fold``), and the same room blurred over it, let in from the blur's start
    /// and whole by the band's foot.
    private func roomRunOff(depth: Double) -> some View {
        ZStack(alignment: .top) {
            Color.clear.overlay { room }

            Color.clear
                .overlay { room }
                .blur(radius: Self.roomBlur, opaque: true)
                .mask {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: plate * Self.blurFrom)
                        LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                            .frame(height: plate * (1 - Self.blurFrom))
                        Color.white
                    }
                }
        }
        .frame(height: plate + depth)
        .clipped()
    }

    /// The room, in the colours of their first record.
    private var room: some View {
        RoomView(colours: paint, sound: .still, foot: 1,
                 running: phase == .active, breathes: true, zero: .whenShown,
                 seed: artist.name, fold: plate)
    }

    /// How far the room is blurred at the band's foot and under it: as far as the photograph's foot.
    private static let roomBlur: Double = 28

    /// The photograph mirrored at the blur of its foot all the way down, so the text and the keys
    /// stand on colour that is as soft as the band's foot.
    ///
    /// Not the photograph as drawn: a mirror as drawn reaches as far up the plate as it is deep under
    /// it, and so reflects the part of the photograph that is only lightly blurred, where a face can
    /// still be made out upside down behind the text. See ``RunOffReflection``.
    private static let reflection = RunOffReflection.blurred

    /// The photograph as it is, which ``RunOff`` blurs toward the foot and mirrors under the band.
    /// The name and the text over it are read by their shadow.
    ///
    /// In night mode (``NightMode``) the photograph is dimmed and has the wash that the name is read
    /// through, the same two layers as the home banner's card.
    private var face: some View {
        ZStack {
            if let portrait {
                Color.clear
                    .overlay {
                        portrait.image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
                    .overlay { if night { Color.black.opacity(HomeFeatureCard.held) } }
                    .transition(.opacity)
            } else if !RoomView.works {
                // There is no photograph and no room. The band is then the page's own
                // ground, and the name stands on it.
                Color.black.opacity(0x22 / 255)
            }

            if night { HomeFeatureCard.foot }
        }
    }

    /// Whether the photograph is drawn darker. See ``NightMode``.
    @AppStorage(NightMode.key) private var night = false

    /// Whether the band shows the room: the photograph was looked for and not found, and the room
    /// can be drawn.
    private var standingOnARoom: Bool { RoomView.works && looked && portrait == nil }

    /// What the band is made for. A new artist, or a new band size, cuts the photograph again.
    private struct BandAsk: Hashable {
        let artist: String
        let width: Double
        let plate: Double
    }

    /// How tall the title is at the band's foot. The crop keeps the face clear of this height. Two
    /// lines of the name, or a logo at ``logoCap``, both fit under it.
    private static let writing: Double = 96

    /// Reads the colours of their first record for the room, then their photograph, cut for the
    /// band: a square picture is kept from the top, and a backdrop is read for the face and cut
    /// with the face above the name. See ``BackdropStore/portrait(artist:album:cutFor:)``.
    private func dress() async {
        // Not before the page is measured: the band is cut for its width.
        guard width > 0 else { return }

        if let band = Self.heldBands[artist.name] {
            // Dressed before: shown at once, while the one held stays on screen. Cut again only for
            // another width, or looked for again where none was found, which may have been the
            // network and not the artist.
            portrait = band.portrait
            pixels = band.pixels
            lead = band.lead
            paint = band.paint
            looked = true
            if band.width == bandWidth && band.portrait != nil { return }
        } else {
            portrait = nil
            pixels = nil
            lead = nil
            looked = false
        }

        // The room's own colour leads the ground of an artist who stands on it (``GroundLead``).
        var roomLead: Color?
        if let first = shelves.records.first ?? shelves.together.first,
           let read = await covers.cover(for: first, edge: HomeBannerMetrics.sleeve)?.colours {
            paint = paint.toward(.from(tint: read.dominant?.asFloats,
                                       glow: read.highlight?.asFloats,
                                       shade: read.shade?.asFloats),
                                 at: CACurrentMediaTime())
            roomLead = GroundLead.of(glow: read.highlight, dominant: read.dominant)?.color
        }

        var found: Cover?
        var foundPixels: CGImage?
        var colour: RGB?
        if let backdrops {
            // The band starts at the top of the screen, so the status bar covers its top.
            let scene = ArtScene.forClearLeft(
                width: bandWidth, height: plate,
                clearTop: RPMSafeArea.top / max(1, plate),
                clearRight: HomeBannerMetrics.clearRight(plate: bandWidth),
                clearBottom: (plate - Self.writing) / plate)

            if let picture = await backdrops.portrait(artist: artist.name, album: nil,
                                                      cutFor: scene) {
                found = Cover(image: Image(decorative: picture, scale: 1), accent: nil)
                foundPixels = picture
                // The photograph's colour (``GroundLead``), from a 48 pixel copy, off the main actor.
                colour = await Task.detached(priority: .userInitiated) {
                    let read = Thumbnail.colours(of: picture)
                    return GroundLead.of(glow: read.highlight, dominant: read.dominant)
                }.value
            }
        } else {
            found = await covers.portrait(of: artist.name, edge: bandWidth)
        }

        guard !Task.isCancelled else { return }

        let led = colour?.color ?? (found == nil ? roomLead : nil)
        withAnimation(.easeOut(duration: 0.35)) {
            portrait = found
            pixels = foundPixels
            lead = led
            looked = true
        }
        Self.hold(artist.name, HeldBand(width: bandWidth, portrait: found, pixels: foundPixels,
                                        lead: led, paint: paint))
    }

    /// What an artist's band was last dressed in: the photograph cut for the band and its pixels,
    /// the colour that leads the ground, and the room's colours. Kept for the session, for the last
    /// few artists, so a page shown again (from another tab, or opened again) has them on its first
    /// frame instead of fading them in a second time.
    private struct HeldBand {
        let width: Double
        let portrait: Cover?
        let pixels: CGImage?
        let lead: Color?
        let paint: RoomDissolve
    }

    /// An artist's title, and whether their logo is drawn inverted, kept as ``HeldBand`` is.
    private struct HeldTitle {
        let read: TitleRead
        var inverted: Bool
    }

    @MainActor private static var heldBands: [String: HeldBand] = [:]
    @MainActor private static var heldTitles: [String: HeldTitle] = [:]

    /// How many artists' bands are kept.
    private static let heldMost = 12

    private static func hold(_ artist: String, _ band: HeldBand) {
        if heldBands[artist] == nil, heldBands.count >= heldMost, let any = heldBands.keys.first {
            heldBands[any] = nil
        }
        heldBands[artist] = band
    }

    private static func hold(_ artist: String, _ title: HeldTitle) {
        if heldTitles[artist] == nil, heldTitles.count >= heldMost, let any = heldTitles.keys.first {
            heldTitles[any] = nil
        }
        heldTitles[artist] = title
    }

    // ── the title ──

    /// Their logo, centred, if a catalogue has one; their name, centred, if not. Exactly one of
    /// the two is shown, as on the desktop (`ArtistDetailView.LogoAsync`): both would show the
    /// name twice.
    ///
    /// **Nothing is shown until the lookup has answered**, so the name is not drawn and then
    /// replaced by the logo a moment later. A lookup that fails shows the name, so the band always
    /// has a title. A title is drawn only while it belongs to this artist, so a title still held
    /// from another artist is never drawn here.
    ///
    /// The logo is drawn at its own pixel size, not resized: ``BackdropStore/logo(artist:album:box:)``
    /// cuts it to the screen pixels it is drawn at. See ``Lettering``.
    @ViewBuilder
    private var title: some View {
        switch titleRead {
        case let .logo(logo) where logo.artist == artist.name:
            Image(logo.picture, scale: logo.scale, label: Text(artist.name))
                .modifier(InvertedLogo(on: logoInverted && !night))
                .transition(.opacity)

        case let .name(who) where who == artist.name:
            Text(artist.name)
                .font(RPMFont.displayBold(26))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .transition(.opacity)

        default:
            EmptyView()
        }
    }

    /// The tallest a logo is drawn, in points. It matches `LogoCap` in the desktop app.
    private static let logoCap: Double = 50

    /// The widest a logo is drawn, as a share of the band. It is wider than the desktop app's 0.42
    /// because the phone's band is narrow: at 0.42 a long one-word mark would be half the height of
    /// the cap.
    private static let logoShare: Double = 0.7

    /// What the logo is cut for: the artist, and the box in screen pixels. Turning the phone, or
    /// moving to a screen with another scale, cuts it again from the mark that the store holds.
    private struct LogoAsk: Hashable {
        let artist: String
        let box: LetteringBox
        let scale: Double
    }

    private var logoAsk: LogoAsk {
        LogoAsk(artist: artist.name,
                box: LetteringBox(tall: Int((Self.logoCap * displayScale).rounded(.up)),
                                  wide: Int((bandWidth * Self.logoShare * displayScale).rounded(.down))),
                scale: displayScale)
    }

    /// A logo as cut, the artist it is of, and the screen scale it was cut for.
    private struct ShownLogo {
        let artist: String
        let picture: CGImage
        let scale: Double
    }

    /// What the title is, and whose it is. It is held with the artist so that a page reading it can
    /// check that it is still about the artist shown.
    private enum TitleRead {
        /// Their logo.
        case logo(ShownLogo)

        /// Their name: they have no logo, or the logo could not be fetched.
        case name(String)

        /// Which title for which artist, for the fade between the two.
        var id: String {
            switch self {
            case let .logo(logo): "logo\u{1}" + logo.artist
            case let .name(who): "name\u{1}" + who
            }
        }
    }

    /// Fetches their logo and sets the title: the logo if there is one, the name if there is none
    /// or the fetch failed. A logo already shown for this artist stays if a new cut for another
    /// size fails.
    private func letter(_ ask: LogoAsk) async {
        let picture = await backdrops?.logo(artist: ask.artist, album: nil, box: ask.box)
        guard !Task.isCancelled else { return }

        if let picture {
            titleRead = .logo(ShownLogo(artist: ask.artist, picture: picture, scale: ask.scale))
        } else if case let .logo(held) = titleRead, held.artist == ask.artist {
            return
        } else {
            titleRead = .name(ask.artist)
        }
        if let titleRead {
            Self.hold(ask.artist, HeldTitle(read: titleRead,
                                            inverted: Self.heldTitles[ask.artist]?.inverted ?? logoInverted))
        }
    }

    // ── a white logo on a bright photograph ──

    /// What the logo's colours are read for: the title, the photograph under it, and night mode.
    private struct InvertAsk: Hashable {
        let title: String
        let photo: ObjectIdentifier?
        let night: Bool
    }

    /// Reads, off the main actor, whether the logo would be lost on the photograph, and draws it
    /// inverted if so. Not in night mode, where the photograph is darkened and the logo is always
    /// drawn as it is, and not for a name, which has its shadow.
    private func judgeTheLogo() async {
        guard !night, case let .logo(logo)? = titleRead, logo.artist == artist.name,
              let photo = pixels else {
            return
        }

        let plate = self.plate
        let foot = Self.writingFoot
        let mark = logo.picture
        let scale = logo.scale
        let lost = await Task.detached(priority: .utility) {
            Self.logoIsLost(mark, scale: scale, on: photo, plate: plate, foot: foot)
        }.value

        guard !Task.isCancelled else { return }
        logoInverted = lost
        if var kept = Self.heldTitles[artist.name] {
            kept.inverted = lost
            Self.hold(artist.name, kept)
        }
    }

    /// Whether a white `logo` would be lost on the `photo` under it: the logo is mostly white and
    /// grey, and the part of the photograph it stands on is bright. The logo is drawn centred at the
    /// foot of a `plate`-point square band, `foot` points above its foot, at its own pixel size
    /// (`scale` pixels a point); the photograph fills the band as `.fill` fills it. Both are read
    /// small, not whole. The Android phone's `logoIsLost` is the same.
    nonisolated private static func logoIsLost(_ logo: CGImage, scale: Double, on photo: CGImage,
                                               plate: Double, foot: Double) -> Bool {
        // A logo this light on average, over its drawn pixels, is a white logo, and this grey: the
        // spread between its brightest and darkest channel, on average. A coloured logo is left
        // alone. A photograph this light on average, under the logo, is too bright for it.
        let white = 0.8
        let grey = 0.15
        let bright = 0.6

        guard let marks = rgba(logo, width: 48, height: 24) else { return false }
        var drawn = 0
        var light = 0.0
        var colour = 0.0
        for at in stride(from: 0, to: marks.count, by: 4) {
            let alpha = Double(marks[at + 3]) / 255
            guard alpha >= 0.5 else { continue }
            // Premultiplied, so each channel is divided by the alpha to be read as drawn.
            let r = min(1, Double(marks[at]) / 255 / alpha)
            let g = min(1, Double(marks[at + 1]) / 255 / alpha)
            let b = min(1, Double(marks[at + 2]) / 255 / alpha)
            drawn += 1
            light += 0.2126 * r + 0.7152 * g + 0.0722 * b
            colour += max(r, g, b) - min(r, g, b)
        }
        guard drawn > 0, light / Double(drawn) >= white, colour / Double(drawn) <= grey else {
            return false
        }

        // The photograph under it, mapped from the band to the photograph's pixels as `.fill`
        // maps them.
        let wide = Double(photo.width)
        let tall = Double(photo.height)
        guard wide > 0, tall > 0, plate > 0 else { return false }
        let fit = max(plate / wide, plate / tall)
        let left = (wide * fit - plate) / 2
        let top = (tall * fit - plate) / 2
        let logoWide = Double(logo.width) / scale
        let logoTall = Double(logo.height) / scale
        let x0 = ((plate - logoWide) / 2 + left) / fit
        let x1 = ((plate + logoWide) / 2 + left) / fit
        let y1 = (plate - foot + top) / fit
        let y0 = y1 - logoTall / fit

        let under = CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
            .intersection(CGRect(x: 0, y: 0, width: wide, height: tall))
            .integral
        guard !under.isNull, under.width >= 1, under.height >= 1,
              let cut = photo.cropping(to: under),
              let seen = rgba(cut, width: 32, height: 16) else { return false }

        var sum = 0.0
        for at in stride(from: 0, to: seen.count, by: 4) {
            sum += 0.2126 * Double(seen[at]) / 255 + 0.7152 * Double(seen[at + 1]) / 255
                + 0.0722 * Double(seen[at + 2]) / 255
        }
        return sum / Double(seen.count / 4) > bright
    }

    /// The picture drawn into `width` by `height` pixels of premultiplied RGBA, eight bits each.
    nonisolated private static func rgba(_ image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }

    /// Three keys in the middle of the page: a mixtape, Play, and Shuffle. Play is a round glass key
    /// and is the one in the middle. The two beside it are their glyphs alone, with no glass, so
    /// Play is the key the eye finds first.
    ///
    /// There is no mark, as on the album page, because a user marks a record or a song, and an
    /// artist is neither.
    ///
    /// The mixtape starts from one of their songs, chosen at random each time, so the key gives a
    /// different mix when it is pressed again. Without a way to start a mixtape (a preview), its
    /// place is kept empty so Play stays in the middle.
    @ViewBuilder
    private var keys: some View {
        if !shelves.songs.isEmpty {
            HStack(spacing: Self.keysApart) {
                if let startRadio {
                    Button {
                        if let song = shelves.songs.randomElement() { startRadio(song.track) }
                    } label: {
                        sideKey(Glyph.mixtape)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Loc.get("Track_StartMixtape"))
                } else {
                    Color.clear.frame(width: Self.sideKeyWidth, height: Self.keysHeight)
                }

                Button { onPlay(shelves.songs.map(\.track), 0, .list) } label: {
                    // The triangle's weight is left of its middle, so it is moved right a little
                    // to look centred in the circle.
                    Text(Glyph.play)
                        .font(RPMFont.icon(18))
                        .foregroundStyle(RPMInk.white(0xF5 / 255))
                        .offset(x: 2)
                }
                .buttonStyle(RPMGlassKey(edge: Self.keysHeight))
                .accessibilityLabel(Loc.get("Rpm_Artist_PlayAll"))

                Button(action: onShuffle) {
                    sideKey(Glyph.shuffle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.get("AlbumMenu_Shuffle"))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Self.keysTop)
            .padding(.bottom, Self.keysBottom)
        }
    }

    /// A key beside Play: its glyph, in a box as tall as Play, which is the part that answers a tap.
    private func sideKey(_ glyph: String) -> some View {
        Text(glyph)
            .font(RPMFont.icon(17))
            .foregroundStyle(RPMInk.white(0xF0 / 255))
            .feathered()
            .frame(width: Self.sideKeyWidth, height: Self.keysHeight)
            .contentShape(Rectangle())
    }

    /// The width a key beside Play answers taps in.
    private static let sideKeyWidth: Double = 56

    /// The space between Play and each key beside it.
    private static let keysApart: Double = 12

    /// Starts a mixtape from a song. Nil in a preview. See ``EnvironmentValues/startRadio``.
    @Environment(\.startRadio) private var startRadio

    // ── popular tracks ──

    /// The songs of theirs that all users play most, as the first section, in the style of the
    /// home page's quick selection panels. It is shown only if ``ArtistPopular`` finds enough songs
    /// to say something. A row plays that song and the key beside the heading plays all of them, as
    /// in the quick selection.
    ///
    /// The songs come from their songs that are still in the library, so a song that leaves the
    /// library while the page is open is not offered.
    @ViewBuilder
    private var popularSection: some View {
        let songs = shownPopular

        if !songs.isEmpty {
            HomePicksRow(heading: Loc.get("Artists_PopularTracks"),
                         picks: songs.map { QuickPick(kind: .song, key: $0.id) },
                         albums: [:],
                         songs: Dictionary(songs.map { ($0.id, $0.track) },
                                           uniquingKeysWith: { first, _ in first }),
                         lists: [:], stations: [:], covers: covers,
                         songLine: .record,
                         onOpen: onOpen, onOpenList: { _ in },
                         onPlay: { onPlay($0, 0, .song) }, onTune: { _ in },
                         songMenu: TrackMenu(isMarked: isTrackMarked, isMine: isTrackMine,
                                             upNext: upNext, onMark: onMarkTrack,
                                             onFile: onFile))
                .padding(.top, Self.sectionTop)
        }
    }

    private var shownPopular: [ArtistShelves.ArtistSong] {
        guard let popular, popular.artist == artist.name else { return [] }

        let here = Set(shelves.songs.map(\.id))
        let kept = popular.songs.filter { here.contains($0.id) }
        return kept.count >= ArtistPopular.fewest ? kept : []
    }

    /// A ranking, and the artist it was made for.
    private struct PopularSongs {
        let artist: String
        let songs: [ArtistShelves.ArtistSong]
    }

    /// What the ranking is made from: the artist, the records asked about, and how many songs they
    /// have here. A library change that adds or removes one of their songs makes a new ranking.
    private struct PopularAsk: Hashable {
        let artist: String
        let records: [String]
        let songs: Int
    }

    private var popularAsk: PopularAsk {
        PopularAsk(artist: artist.name, records: ArtistPopular.records(shelves.songs).map(\.key),
                   songs: shelves.songs.count)
    }

    /// The ranking from what the store already holds, if it holds an answer for every record.
    /// Nil otherwise, because a ranking from some of the records would be replaced by a different
    /// one when the rest arrive.
    private static func popularKept(artist: String, shelves: ArtistShelves,
                                    in store: WorldPlays) -> PopularSongs? {
        var plays: [String: [TrackPlace: Int64]] = [:]
        for record in ArtistPopular.records(shelves.songs) {
            guard let kept = store.cached(WorldPlays.Record(record)) else { return nil }
            plays[record.key] = kept
        }
        return PopularSongs(artist: artist, songs: ArtistPopular.ranked(shelves.songs, plays: plays))
    }

    /// How many records are asked about at once.
    private static let popularAsking = 4

    /// Asks for the listen counts of every record that their songs are on, four at a time, and
    /// ranks once all have answered. A record that could not be asked adds nothing this time and is
    /// asked again on the next visit (see ``WorldPlays``).
    ///
    /// The result is shown in one step, without animation. The section makes a row of the list
    /// grow, and a row that grows under an animation moves the header (see `AboutRead`).
    private func rankPopular() async {
        let songs = shelves.songs
        let records = ArtistPopular.records(songs)
        let store = worldPlays

        let plays = await withTaskGroup(of: (String, [TrackPlace: Int64]?).self,
                                        returning: [String: [TrackPlace: Int64]].self) { group in
            var plays: [String: [TrackPlace: Int64]] = [:]
            var next = 0

            // Start the first four, then start one more each time one answers.
            while next < records.count {
                if next >= Self.popularAsking, let (key, answer) = await group.next() {
                    if let answer { plays[key] = answer }
                }

                let key = records[next].key
                let asked = WorldPlays.Record(records[next])
                next += 1
                group.addTask { (key, await store.plays(asked)) }
            }

            for await (key, answer) in group {
                if let answer { plays[key] = answer }
            }
            return plays
        }

        guard !Task.isCancelled else { return }
        popular = PopularSongs(artist: artist.name, songs: ArtistPopular.ranked(songs, plays: plays))
    }

    // ── the shelves ──

    /// The space above Popular tracks, above the first shelf and above Related artists: the
    /// places where a new part of the page starts.
    private static let sectionTop: Double = 40

    /// The space above every shelf after the first.
    private static let shelfTop: Double = 18

    /// The shelves that hold something, in the order the page shows them. A shelf is drawn only
    /// when it holds something, because a heading over an empty row would tell the reader what
    /// this artist did not do.
    private var shownShelves: [ShelfRow] {
        let all: [(String, [CloudAlbum])] = [
            (Loc.get("Artists_Albums"), shelves.records),
            (Loc.get("Artists_Collaborations"), shelves.together),
            (Loc.get("Artists_Eps"), shelves.eps),
            (Loc.get("Artists_LiveAlbums"), shelves.live),
            (Loc.get("Artists_Mixtapes"), shelves.mixtapes),
            (Loc.get("Artists_Soundtracks"), shelves.soundtracks),
            (Loc.get("Artists_Compilations"), shelves.compilations),
            (Loc.get("Artists_Singles"), shelves.singles),
            (Loc.get("Artists_AppearsOn"), shelves.appearances)]

        return all.filter { !$0.1.isEmpty }.enumerated().map { index, shelf in
            ShelfRow(heading: shelf.0, records: shelf.1, first: index == 0)
        }
    }

    /// One shelf on the page: its heading, its records, and whether it is the first shelf shown.
    private struct ShelfRow: Identifiable {
        let heading: String
        let records: [CloudAlbum]
        let first: Bool

        var id: String { heading }
    }

    /// One shelf: its heading over a row of sleeves, `top` points under what is above it.
    private func shelf(_ heading: String, _ records: [CloudAlbum], top: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(heading)
                .rpmKicker()
                .textCase(.uppercase)
                .padding(.horizontal, RPMLayout.margin)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 14) {
                    ForEach(records) { album in
                        AlbumTile(album: album, art: sleeve, covers: covers)
                            .onTapGesture { onOpen(album) }
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.top, top)
    }

    /// The sleeve size that a shelf uses. One whole sleeve and the edge of the next one are
    /// visible, which shows that the row continues past the side of the screen. The size is a
    /// share of the width and not a fixed number, so the shelf looks the same on every phone.
    private var sleeve: Double {
        min(max(bandWidth * 0.38, 120), 200).rounded()
    }

    // ── the related acts ──

    /// The acts related to them in this collection (``RelatedArtists``), as the artists wall's own
    /// boxes, which open the same page. It is the last section, as in the Android TV app. It is
    /// shown only if there are related acts.
    @ViewBuilder
    private var relatedSection: some View {
        if let related, related.ask == relatedAsk, !related.acts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(Loc.get("Artists_Related"))
                    .rpmKicker()
                    .textCase(.uppercase)
                    .padding(.horizontal, RPMLayout.margin)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(related.acts) { act in
                            ArtistBox(artist: act, width: 200,
                                      first: albums[act.own.first ?? ""], covers: covers)
                                .onTapGesture { onOpenArtist(act) }
                        }
                    }
                    .padding(.horizontal, RPMLayout.margin)
                }
                .scrollIndicators(.hidden)
            }
            .padding(.top, Self.sectionTop)
        }
    }

    /// What the related acts are read for: the artist as the wall holds them, and the size of what
    /// they are read from. A library change that adds or removes a record, an act or a list reads
    /// the related acts again.
    private struct RelatedAsk: Equatable {
        let artist: ArtistWallItem
        let acts: Int
        let albums: Int
        let lists: Int
    }

    private var relatedAsk: RelatedAsk {
        RelatedAsk(artist: artist, acts: relatedFrom.artists.count,
                   albums: relatedFrom.albums.count, lists: relatedFrom.lists.count)
    }

    /// Reads the related acts off the main thread, because the rule goes over every track of the
    /// collection. The result is shown in one step, as the popular songs are.
    private func readRelated(_ ask: RelatedAsk) async {
        let from = relatedFrom
        let acts = await Task.detached(priority: .utility) {
            RelatedArtists.of(ask.artist, in: from)
        }.value
        guard !Task.isCancelled else { return }
        related = (ask, acts)
    }
}

/// A logo drawn in its inverse colours, keeping its alpha: white becomes black. See
/// ``ArtistPage``'s `judgeTheLogo`.
private struct InvertedLogo: ViewModifier {
    let on: Bool

    func body(content: Content) -> some View {
        if on {
            content.colorInvert()
        } else {
            content
        }
    }
}
