import SwiftUI
import RPMKit

/// How the library tab shows the collection: by record, by artist, by playlist or by genre.
///
/// It is stored where all the pages can read it and is saved to the defaults, so the tab opens
/// in the mode the person last used. The sort order next to it is remembered for the same
/// reason.
public enum LibraryMode: String, CaseIterable, Sendable, PageTab {
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

/// The row of tabs under each library view's header that switches between the four modes. See
/// ``PageTabs``.
typealias LibraryModeTabs = PageTabs<LibraryMode>
