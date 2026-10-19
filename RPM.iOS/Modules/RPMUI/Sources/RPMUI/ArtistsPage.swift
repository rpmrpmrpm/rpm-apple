import SwiftUI
import RPMSharedUI
import RPMKit
import RPMLibrary
import RPMDesign

/// The collection read by who made it: one box per act.
///
/// This is the phone's version of `RPM.Desktop/Presentation/Main/Artists/ArtistWallView.xaml`.
/// The wall itself is ``ArtistWall/build(_:)``, which both apps share, so the phone and the
/// computer show the same collection of artists and not two different readings of one tag.
///
/// It shares the library tab with the wall of records and is switched to from the same
/// key, so the header is the records wall's header with a different title on it.
public struct ArtistsPage: View {
    /// What the wall is doing, when it is not showing artists. The records wall's own
    /// three answers, for the reason it states them: an empty array can mean a collection that
    /// is empty, a read that has not finished, or a read that failed.
    public typealias Standing = LibraryPage.Standing

    private let standing: Standing

    /// The wall in whichever order the page asks for.
    ///
    /// **A function and not a list**, because putting a wall of artists in order means
    /// reading every record of every one of them, and this page is rebuilt whenever
    /// anything on the screen changes. The caller holds the cache that limits that work to once
    /// per change. The page holds the choice of order, because the choice is a preference and
    /// not a fact about the library. See ``ReadArtists/artists(_:in:)``.
    private let inOrder: (ArtistOrdering) -> [ArtistWallItem]

    private let albums: [String: CloudAlbum]
    private let covers: any CoverStore
    private let onOpen: (ArtistWallItem) -> Void
    private let onRefresh: () async -> Void

    /// Whose collection is on the wall, or nil for the user's own.
    private let lender: String?

    @Binding private var mode: LibraryMode

    public init(inOrder: @escaping (ArtistOrdering) -> [ArtistWallItem],
                albums: [String: CloudAlbum],
                standing: Standing, covers: any CoverStore,
                mode: Binding<LibraryMode>, lender: String? = nil,
                onOpen: @escaping (ArtistWallItem) -> Void,
                onRefresh: @escaping () async -> Void) {
        self.inOrder = inOrder
        self.albums = albums
        self.standing = standing
        self.covers = covers
        _mode = mode
        self.lender = lender
        self.onOpen = onOpen
        self.onRefresh = onRefresh
    }

    @State private var searching = false
    @State private var asked = ""
    @FocusState private var typing: Bool

    /// Which order the wall is in. Remembered across launches, as the records wall's own
    /// order is: a way of looking at a collection, not a thing to choose again every time
    /// the app opens.
    ///
    /// **Read here and handed back up**, not sorted here: putting the wall in
    /// order means reading every record of every artist, and the caller holds the cache
    /// that makes that happen once per change and not once per evaluation of the body.
    /// See ``ReadArtists``.
    @AppStorage("library.artistOrder") private var order: ArtistOrdering = .name

    /// How wide a box is drawn, remembered across launches the way the records wall
    /// remembers its own. A separate value from the sleeves': a box is a photograph
    /// with a name across it and a sleeve is a square, and they are not readable at the
    /// same size.
    ///
    /// The default is two across on every phone this runs on, not the desktop's 260. A
    /// box is sixteen by nine, so one across is a box a third of the screen tall and
    /// three artists fill the screen, which is too few to see a collection. Two
    /// across gives a box wide enough for a full name and about eight boxes in view.
    @AppStorage("library.artistBox.v1") private var stride: Double = 190

    @State private var pinching: Double?

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                switch standing {
                case .reading: waiting
                case .trouble(let said): failed(said)
                case .showing: wall
                }
            }
            .frame(maxHeight: .infinity)
            .scrollsUnder {
                VStack(spacing: 0) {
                    header.zIndex(1)
                    if searching { field }
                    LibraryModeTabs($mode)
                }
            }
        }
        .background { VinylGround() }
    }

    // ── the header ──

    private var header: some View {
        VStack(alignment: .leading, spacing: PageTitle.subtitleGap) {
            // The keys are drawn over the title's own line and are not placed in a row
            // with it. A forty-eight point key is taller than the letters, and in a row
            // it would set the height of the line, so the counts under it would sit as far
            // down as the tallest key and not as far down as the title.
            PageHeading(Loc.get("Artists_Title"), line: counts) { keys }
        }
        .padding(.leading, RPMLayout.margin)
        .padding(.trailing, 16)
        .padding(.bottom, 10)
    }

    /// The search, the sort, and the way back to the records.
    private var keys: some View {
        HStack(spacing: 0) {
            key(Glyph.search) {
                guard !searching else { closeSearch(); return }

                withAnimation(.easeOut(duration: 0.22)) { searching = true }
                typing = true
            }
            .accessibilityLabel(Loc.get("Artists_SearchPlaceholder"))

            // The same menu in the same place as the records wall's, so the two
            // sides of the library tab have the same header with only the title changed.
            Menu {
                Picker(Loc.get("Rpm_Library_Sort"), selection: $order) {
                    Text(Loc.get("ArtistSort_Name")).tag(ArtistOrdering.name)
                    Text(Loc.get("ArtistSort_Albums")).tag(ArtistOrdering.albums)
                    Text(Loc.get("ArtistSort_Tracks")).tag(ArtistOrdering.tracks)
                    Text(Loc.get("ArtistSort_Added")).tag(ArtistOrdering.added)
                }
            } label: {
                Text(Glyph.sort)
                    .font(RPMFont.icon(16))
                    .foregroundStyle(RPMInk.white(0xB8 / 255))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Loc.get("Rpm_Library_Sort"))
        }
        .rpmGlassGroup()
    }

    private func key(_ mark: String, _ press: @escaping () -> Void) -> some View {
        Button(action: press) {
            Text(mark)
                .font(RPMFont.icon(16))
                .foregroundStyle(RPMInk.white(0xB8 / 255))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var counts: String {
        let all = inOrder(order).count
        let held = all == 1 ? Loc.get("Artists_CountOne") : Loc.get("Artists_Count", all)

        guard let lender, !lender.isEmpty else { return held }
        return Loc.get("Rpm_Library_SharedBy", lender) + "  \u{b7}  " + held
    }

    /// The field, the records wall's own, with the artists' placeholder in it.
    private var field: some View {
        HStack(spacing: 6) {
            RPMSearchBox(text: $asked, prompt: Loc.get("Artists_SearchPlaceholder"),
                         clearLabel: Loc.get("Artists_SearchClear"), typing: $typing)

            Button {
                Haptics.pick()
                closeSearch()
            } label: {
                Text("\u{f00d}")
                    .font(RPMFont.icon(15))
                    .foregroundStyle(RPMInk.white(0xB8 / 255))
            }
            .buttonStyle(RPMGlassKey(edge: RPMSearchBox.height))
            .accessibilityLabel(Loc.get("Rpm_Cast_Close"))
        }
        .padding(.leading, RPMLayout.margin)
        .padding(.trailing, 12)
        .padding(.bottom, 10)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func closeSearch() {
        asked = ""
        typing = false
        withAnimation(.easeOut(duration: 0.22)) { searching = false }
    }

    // ── the wall ──

    /// Who answers to what is typed.
    ///
    /// Computed and not held, unlike the records wall's search: that one walks every
    /// track in the library and this walks a list of names, which is about a hundred times
    /// less work and needs no background task. The query is folded once here and not once
    /// per name, which is why ``ArtistWall/searchKey(_:)`` is public.
    private var shown: [ArtistWallItem] {
        let wall = inOrder(order)
        let wanted = ArtistWall.searchKey(asked)
        guard !wanted.isEmpty else { return wall }

        return wall.filter { ArtistWall.searchKey($0.name).contains(wanted) }
    }

    @ViewBuilder
    private var wall: some View {
        if inOrder(order).isEmpty {
            empty
        } else if shown.isEmpty {
            noMatch
        } else {
            boxes
                .refreshable { await onRefresh() }
        }
    }

    private var boxes: some View {
        GeometryReader { geometry in
            let (columns, width) = WallLayout.wall(
                available: geometry.size.width,
                targetStride: pinching ?? Self.bounded(stride),
                edge: AlbumWall.edge,
                gutter: Self.gutter,
                maxColumns: Self.maxColumns,
                minColumns: 1)

            DissolvingScroll {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Self.gutter),
                                   count: columns),
                    spacing: Self.gutter
                ) {
                    ForEach(shown) { artist in
                        ArtistBox(artist: artist, width: width,
                                  first: albums[artist.own.first ?? ""],
                                  covers: covers)
                            .onTapGesture { onOpen(artist) }
                    }
                }
                .padding(.horizontal, AlbumWall.edge)
                .padding(.top, 4)
                .padding(.bottom, RPMLayout.foot)
            }
            .scrollIndicators(.hidden)
            .keyboardRoom()
            .scrollDismissesKeyboard(.immediately)
            // simultaneousGesture, not gesture: a plain one loses the race to the
            // scroller's own pan and never fires. The records wall pinches the same way.
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { factor in pinching = Self.bounded(stride * factor.magnification) }
                    .onEnded { _ in
                        if let pinching { stride = pinching }
                        pinching = nil
                    })
        }
    }

    /// The gap between boxes, and how many go across. The gap is wider and there are fewer
    /// columns than for sleeves: a box carries a written name and not a picture of a cover,
    /// and at four across on a phone the name would not fit.
    private static let gutter: Double = 14
    private static let maxColumns = 3

    private static func bounded(_ box: Double) -> Double { min(max(box, 140), 900) }

    /// A collection that is known to be empty, which is not the same as one that has not
    /// arrived yet.
    private var empty: some View {
        VStack(spacing: 10) {
            ArtistMark.key(46)
                .foregroundStyle(RPMInk.white(0x3A / 255))

            Text(Loc.get(lender == nil ? "Artists_Empty" : "Rpm_Share_EmptyShelf"))
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The other empty wall, with a different sentence: there are artists, but none of
    /// them matches what has been typed. The two are kept apart because the fix is
    /// different: one needs music uploaded and the other needs the field cleared.
    private var noMatch: some View {
        VStack(spacing: 10) {
            Text(Glyph.search)
                .font(RPMFont.icon(34))
                .foregroundStyle(RPMInk.white(0x3A / 255))

            Text(Loc.get("Artists_NoMatch"))
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var waiting: some View {
        VStack(spacing: 16) {
            RecordSpinner(diameter: 96)

            Text(Loc.get("Rpm_Library_Loading"))
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0x88 / 255))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func failed(_ said: String) -> some View {
        VStack(spacing: 14) {
            Text(said)
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            Button(Loc.get("Rpm_Library_Retry")) { Task { await onRefresh() } }
                .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 40,
                                            stretches: false, inset: 16, size: 14))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// ── one artist ──

/// One box: their photograph, a veil that falls down it, and their name across the middle.
///
/// The whole box is the press target, as on the desktop. If only the name could be pressed,
/// the target would be the size of one word inside a box the size of a postcard.
struct ArtistBox: View {
    let artist: ArtistWallItem
    let width: Double

    /// One of their own records, for the box that has no photograph to show. Its sleeve,
    /// blurred, is the same ground the album page stands on, so an artist without a photograph
    /// still gets the colour of their own music and not a grey plate.
    let first: CloudAlbum?

    let covers: any CoverStore

    @State private var picture: Cover?
    @State private var sleeve: Cover?

    /// Sixteen by nine, which is ``ArtistPageLayout/TileShare`` on the desktop and is the
    /// shape the photographs arrive in: fanart.tv's backdrops are 1920 by 1080, and a box
    /// shows a backdrop, so it crops almost nothing away.
    ///
    /// Not the shape of the artist page's band, which is a square. The wall and the page it
    /// opens use two shapes on purpose. The desktop defines both in `ArtistPageLayout`, so
    /// the split can be read in one place.
    static let shape = 9.0 / 16.0

    private var height: Double { (width * Self.shape).rounded() }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0x22 / 255))

            ground

            // The veil gets darker down the box and is not flat across it. The name is
            // across the middle, and a gradient that started at the foot would be too
            // weak by the time it reached the writing.
            LinearGradient(
                stops: [.init(color: .black.opacity(0x26 / 255), location: 0),
                        .init(color: .black.opacity(0x8C / 255), location: 0.55),
                        .init(color: .black.opacity(0xB3 / 255), location: 1)],
                startPoint: .top, endPoint: .bottom)

            Text(artist.name)
                .font(RPMFont.displayBold(15))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 10)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.25), value: picture != nil)
        .animation(.easeOut(duration: 0.25), value: sleeve != nil)
        // Keyed on the artist and not on the size: the box asks again when it shows a
        // different artist, and a pinch does not change the artist. The store groups
        // widths into bands anyway, so asking again during a gesture would be one fetch
        // per frame to get the picture that is already on screen.
        .task(id: artist.name) { await dress() }
    }

    @ViewBuilder
    private var ground: some View {
        if let picture {
            // UniformToFill, as on the desktop: the box has the shape of the backdrops,
            // so a picture of any other shape loses its edges and not its subject.
            Color.clear
                .overlay {
                    picture.image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .clipped()
        } else if let sleeve {
            Color.clear
                .overlay {
                    sleeve.image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .blur(radius: 24, opaque: true)
                }
                .clipped()
                .overlay(sleeve.accent?.base.color.opacity(0.22) ?? .clear)
        }
    }

    /// The photograph first, and their own record's sleeve only where there is none.
    ///
    /// In that order and not both at once: most artists in most libraries have no
    /// photograph, and a wall that also fetched a sleeve for every box would double the work
    /// for a ground that is thrown away on every box that does have a photograph.
    private func dress() async {
        picture = nil
        sleeve = nil

        if let found = await covers.portrait(of: artist.name, edge: width) {
            picture = found
            return
        }

        guard let first else { return }
        sleeve = await covers.cover(for: first, edge: width)
    }
}
