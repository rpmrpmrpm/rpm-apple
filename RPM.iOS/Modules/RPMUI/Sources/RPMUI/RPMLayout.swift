import Foundation

/// Where the screen's own edges are.
///
/// **One number for every page.** The headings, the rows, the walls and the cards all start on
/// the same line down the page. A screen with its own margin would have a first column that does
/// not line up with its own title. The value is 20 points, which the records wall, the radio, the
/// profile and every heading in the app use.
///
/// It is not the gap between two cards. That is each wall's own number, and the two are
/// unrelated: see ``AlbumWall/gutter``.
public enum RPMLayout {
    public static let margin: Double = 20

    /// The gap between the last row of a page and the chrome below it.
    ///
    /// The room for the chrome itself is reserved by ``PageFoot``, and that reservation is exact.
    /// Without this gap, the last line of text on a page would touch the top edge of the mini
    /// player. Every page uses this one value.
    public static let foot: Double = 16

    /// The row at the top of a page with no header, where its back key floats. Content that
    /// scrolls up behind it, and the status bar, fade into the page's background: see
    /// ``SwiftUI/View/dissolvesAtTop(under:)``.
    public static let backRow: Double = 44
}
