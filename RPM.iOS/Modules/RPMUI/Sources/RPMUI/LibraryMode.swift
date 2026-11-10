import SwiftUI
import RPMKit

/// How the library tab shows the collection: by record, by artist, by playlist or by genre.
///
/// It is stored where all the pages can read it and is saved to the defaults, so the tab opens
/// in the mode the person last used. The sort order next to it is remembered for the same
/// reason.
public enum LibraryMode: String, CaseIterable, Sendable {
    case albums
    case artists

    /// The playlists. They are another way of grouping the same music, not a different place.
    case playlists

    /// What kind of music it is: one card per genre. See ``GenresPage``.
    case genres

    public var label: String {
        switch self {
        case .albums: Loc.get("Artists_Albums")
        case .artists: Loc.get("Artists_Title")
        case .playlists: Loc.get("Playlists_Title")
        case .genres: Loc.get("Genres_Title")
        }
    }

    /// The mark on the key while this mode is selected.
    ///
    /// It is a view and not a glyph string, because the marks are drawn in different ways.
    /// Albums use Font Awesome's `compact-disc`, as the desktop's rail does. Artists use
    /// ``ArtistMark``, because the font has no suitable glyph.
    @ViewBuilder
    var mark: some View {
        switch self {
        case .albums: Text(Glyph.record).font(RPMFont.icon(14))
        case .artists: ArtistMark.key(14)
        case .playlists: Text(Glyph.playlists).font(RPMFont.icon(14))
        case .genres: Text(Glyph.genres).font(RPMFont.icon(14))
        }
    }
}

/// The row of tabs under each library view's header that switches between the four modes.
///
/// It is the app's tab capsule at a smaller size, with the same glass. Only the selected tab shows
/// its name beside its mark. The others show the mark alone, so four tabs fit in every language.
/// The pill slides to the tab chosen, that tab opens as its name fades in, and the one left closes
/// as its name fades out, all on the tab bar's spring.
///
/// **Each view draws its own row, so the row remembers where the last one stood**
/// (``lastShown``). The row of the view that comes in starts at the tab the last row showed and
/// moves from there, while the two views fade into one another. A row that started at its own
/// tab would arrive already finished.
public struct LibraryModeTabs: View {
    @Binding private var mode: LibraryMode

    /// The tab the row is showing, as far as the motion has got: it follows ``mode`` on the spring.
    @State private var shown: LibraryMode

    public init(_ mode: Binding<LibraryMode>) {
        _mode = mode
        _shown = State(initialValue: Self.lastShown ?? mode.wrappedValue)
    }

    /// The tab the last row on screen showed, for the row that replaces it.
    @MainActor private static var lastShown: LibraryMode? = nil

    /// A closed tab is as wide as its mark's box; the open one takes the rest.
    private static let unlit: CGFloat = 52
    private static let tall: CGFloat = 32

    /// The tab bar's spring.
    private static let motion = Animation.spring(response: 0.35, dampingFraction: 0.8)

    public var body: some View {
        GeometryReader { box in
            let all = LibraryMode.allCases
            let lit = max(Self.unlit, box.size.width - Self.unlit * CGFloat(all.count - 1))
            let at = CGFloat(all.firstIndex(of: shown) ?? 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(RPMInk.white(0x24 / 255))
                    .frame(width: lit, height: Self.tall)
                    .offset(x: Self.unlit * at)

                HStack(spacing: 0) {
                    ForEach(all, id: \.self) { choice in
                        key(choice, lit: lit)
                    }
                }
            }
        }
        .frame(height: Self.tall)
        .padding(3)
        .rpmGlass(Capsule())
        .padding(.horizontal, RPMLayout.margin)
        // Space between the capsule and the first row below it, which scrolls up under the
        // capsule.
        .padding(.bottom, 16)
        .onAppear {
            Self.lastShown = mode
            if shown != mode { withAnimation(Self.motion) { shown = mode } }
        }
        .onChange(of: mode) { _, now in
            Self.lastShown = now
            withAnimation(Self.motion) { shown = now }
        }
    }

    /// One tab: its mark, and its name while it is open. The name is clipped by the tab as the tab
    /// opens and closes, and fades with it.
    private func key(_ choice: LibraryMode, lit: CGFloat) -> some View {
        let open = choice == shown

        return Button {
            guard mode != choice else { return }
            Haptics.pick()
            Self.lastShown = mode
            mode = choice
        } label: {
            HStack(spacing: 0) {
                choice.mark
                    .foregroundStyle(open ? .white : RPMInk.white(0x99 / 255))

                // The system font and not Cabin, as the tab bar's names.
                Text(choice.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .fixedSize()
                    .frame(width: open ? nil : 0, alignment: .leading)
                    .clipped()
                    .opacity(open ? 1 : 0)
            }
            .frame(width: open ? lit : Self.unlit, height: Self.tall)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.label)
        .accessibilityAddTraits(mode == choice ? .isSelected : [])
    }
}
