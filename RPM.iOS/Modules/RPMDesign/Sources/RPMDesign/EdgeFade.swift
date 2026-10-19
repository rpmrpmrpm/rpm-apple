import Foundation

/// How deep a scrolling list dissolves at the edge it is scrolling out of.
///
/// The desktop app's `PegasusChrome.RecordFade` follows the same rule. The rule has two parts:
///
/// - **The depth grows out of the scroll rather than being switched on.** A list at its top
///   has nothing running off it, so there is no band over its first row. Without this, the
///   first row would start already faded.
/// - **Depth, not opacity.** A mask at half strength is not a half dissolve. It is a veil over
///   the whole band. Every row in the band goes half transparent, including the rows far from
///   the edge.
public enum EdgeFade {
    /// How deep the dissolve goes at full stretch, in points. A deeper band leaves the top row
    /// of a wall permanently partly faded. A shallower band reads as an edge of its own, and
    /// removing that edge is the purpose of the dissolve.
    public static let depth: Double = 30

    /// The band to dissolve at the top of a list that has been scrolled `scrolled` points, in a
    /// viewport `viewport` points tall.
    ///
    /// The band is never deeper than the viewport. A shorter panel would otherwise be masked
    /// from end to end. Values that are not numbers, and a viewport that has not been measured
    /// yet, give no band at all.
    public static func head(scrolled: Double, viewport: Double, depth: Double) -> Double {
        guard scrolled.isFinite, viewport.isFinite, viewport > 0, depth > 0 else { return 0 }

        return min(max(scrolled, 0), min(depth, viewport))
    }
}
