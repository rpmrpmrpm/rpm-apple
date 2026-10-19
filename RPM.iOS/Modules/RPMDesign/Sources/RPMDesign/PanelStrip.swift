import Foundation

/// Panels side by side in a sideways scroller. The scroller comes to rest on a panel, and the edge
/// of the next panel shows past the right-hand margin. It is used for the quick selection on Home
/// and for Popular tracks on the artist page.
///
/// **The space after the last panel is not the margin.** A panel is narrower than the screen between
/// its margins, by the peek. If only the margin came after the last panel, that panel would stop with
/// its right edge on the margin. Its left edge would then sit a peek further in than every other
/// panel's left edge. On a 390-point screen that is an indent of 52 points. So the trailing space is
/// set so that the last panel also rests at the left margin. The empty room is where the next panel
/// would show.
public struct PanelStrip: Equatable, Sendable {
    /// Each panel's width.
    public let width: Double

    /// The space before the first panel.
    public let leading: Double

    /// The space after the last panel.
    public let trailing: Double

    /// - Parameters:
    ///   - screen: the scroller's width.
    ///   - margin: the page's margin, where every panel's left edge comes to rest.
    ///   - peek: how much of the next panel shows past the right-hand margin. It is not taken off a
    ///     single panel, which has no next panel to show.
    ///   - panels: how many there are.
    public init(screen: Double, margin: Double, peek: Double, panels: Int) {
        width = max(0, screen - 2 * margin - (panels > 1 ? peek : 0))
        leading = margin
        trailing = max(margin, screen - margin - width)
    }
}
