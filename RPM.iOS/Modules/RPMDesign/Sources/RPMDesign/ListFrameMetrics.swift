import CoreGraphics

/// Where a generated list's name is set in the frame's band, and how big it is.
///
/// The desktop app's `CoverOverlay.Letter` does the same job. The fractions above it are measured
/// in that drawing, which is 800 pixels square. They are kept as fractions, so they still work at
/// whatever size a cover is drawn.
///
/// **Arithmetic, not a layout pass.** Every number here has an edge case that is hard to see until
/// someone hits it. A figure decided inside a drawing call cannot be checked by a test.
///
/// **Skia's coordinates.** y counts DOWN here. That matches the drawing these numbers were measured
/// in, and it matches UIKit's own text drawing. A box's top is above its bottom, and both are
/// negative above the baseline. Nothing is flipped, so the numbers can be compared with the desktop
/// app line by line.
public enum ListFrameMetrics {
    /// The middle of the band the name is set on, across the square.
    ///
    /// It is read from the "rpm" mark in the bottom right corner, so the name and the app's own mark
    /// line up.
    public static let nameCentre: CGFloat = 0.90813

    /// Where the lettering starts, down the square.
    public static let nameTop: CGFloat = 0.0375

    /// How tall the lettering is ACROSS the band. This sets the size. The name is turned on its side,
    /// so the width of the band is the height of the type.
    public static let nameCross: CGFloat = 0.08

    /// How far the name may run down the square before it reaches the app's own name in the corner.
    /// A longer name is set smaller rather than allowed to overlap. "Your mix" is eight letters, and
    /// 你的专属歌单 is six. A language this has not been checked with can be any length.
    public static let nameRun: CGFloat = 0.8375

    /// The string the size is measured on, for every cover. It has an ascender and a descender, which
    /// is the tallest span that Latin text takes up.
    ///
    /// **The size comes from this string, not from the name.** If the size were measured on the name's
    /// own ink box, it would depend on which letters the name contains. "Your mix" and "Loved and
    /// forgotten" would then come out at different sizes, and covers on one shelf would use different
    /// type sizes. This string is fixed, so every cover uses the same size.
    public static let gauge = "fg"

    /// One ink box, measured tight: the glyphs' own outlines, not the line the font reserves for
    /// them. Two fonts at one size put their caps in different places. What has to line up with the
    /// drawing is where the letters actually are.
    public struct Ink: Equatable, Sendable {
        /// How far the ink starts from the pen, and how wide it runs.
        public let left: CGFloat, width: CGFloat

        /// Its top and bottom about the baseline. y counts down, so both are negative for text that
        /// sits entirely above the line.
        public let top: CGFloat, bottom: CGFloat

        public var height: CGFloat { bottom - top }

        public init(left: CGFloat, width: CGFloat, top: CGFloat, bottom: CGFloat) {
            self.left = left; self.width = width; self.top = top; self.bottom = bottom
        }
    }

    /// How the name is set: at what size, and where its baseline goes.
    public struct Lettering: Equatable, Sendable {
        /// What to set the type at, in the units the square was given in.
        public let size: CGFloat

        /// Where the pen goes, relative to the anchor and in the turned frame: along the band, and
        /// across it. The first cancels the name's own left bearing, so the ink starts where the run
        /// starts. The second puts the middle of the gauge on the band's centre line. That gives
        /// every cover one baseline.
        public let alongBand: CGFloat, acrossBand: CGFloat
    }

    /// The size and the two offsets, from a font that can measure itself at a size.
    ///
    /// - Parameters:
    ///   - edge: the square being composed. Everything here is in its units.
    ///   - measuring: the ink box of a string at a size, in this font.
    ///
    /// Nil where the font measures nothing at all, which means a font with no letters in it. The
    /// caller then draws the frame with no name, instead of a row of boxes.
    public static func lettering(_ name: String, edge: CGFloat,
                                 measuring: (String, CGFloat) -> Ink) -> Lettering? {
        guard edge > 0, !name.isEmpty else { return nil }

        let band = edge * nameCross
        var size = band

        // A font with no Latin letters measures the gauge as nothing. The name then sets the size
        // instead. That is better than no name.
        var gauged = measuring(gauge, size)
        if gauged.height <= 0 { gauged = measuring(name, size) }
        guard gauged.height > 0 else { return nil }

        size *= band / gauged.height

        var ink = measuring(name, size)
        guard ink.width > 0 else { return nil }

        if ink.width > edge * nameRun {
            size *= (edge * nameRun) / ink.width
            ink = measuring(name, size)
        }

        // The band at the size the name is actually set at. It is measured again rather than scaled,
        // so the centre line is the one this font draws at.
        var across = measuring(gauge, size)
        if across.height <= 0 { across = ink }

        return Lettering(size: size,
                         alongBand: -ink.left,
                         acrossBand: -((across.top + across.bottom) / 2))
    }

    /// Where the lettering is anchored in the square, before it is turned on its side.
    public static func anchor(edge: CGFloat) -> CGPoint {
        CGPoint(x: edge * nameCentre, y: edge * nameTop)
    }
}
