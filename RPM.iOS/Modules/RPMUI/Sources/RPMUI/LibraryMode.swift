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
/// It is the app's tab capsule at a smaller size, with the same glass and the same sliding
/// pill. Only the selected tab shows its name beside its mark. The others show the mark alone,
/// so four tabs fit in every language.
public struct LibraryModeTabs: View {
    @Binding private var mode: LibraryMode

    /// Shared by the tabs so the selection pill slides between them.
    @Namespace private var pill

    public init(_ mode: Binding<LibraryMode>) { _mode = mode }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(LibraryMode.allCases, id: \.self) { choice in
                Button {
                    Haptics.pick()
                    mode = choice
                } label: {
                    TabFace(lit: mode == choice, label: choice.label, layout: .inline,
                            pill: pill) { choice.mark }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(choice.label)
                .accessibilityAddTraits(mode == choice ? .isSelected : [])
            }
        }
        // Applied to this row only, so the pill slides but the view it switches to does not
        // animate.
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: mode)
        .padding(3)
        .rpmGlass(Capsule())
        .padding(.horizontal, RPMLayout.margin)
        // Space between the capsule and the first row below it, which scrolls up under the
        // capsule.
        .padding(.bottom, 16)
    }
}
