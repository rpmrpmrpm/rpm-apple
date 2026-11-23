import CoreGraphics

/// Where a folder's name goes on the folder frame (`FolderFrame.png`): centred in the black bar under
/// the window, on one line.
///
/// The drawing is 800 pixels square. Its window is the shape of a folder: 35 to 768 across, 104 to
/// 646 down, with a tab at the top right from 582 to 768 across that reaches up to 36. The bar below
/// the window runs from 647 to the bottom edge. Every number here is a share of the
/// square, so the same rule sets the name at any size. The Android app reads the same numbers
/// (`FolderFrameMetrics.kt`); change both together.
public enum FolderFrameMetrics {
    /// The middle of the bar, down the square: halfway between 647 and 800.
    public static let barCentre: CGFloat = (647.0 + 800.0) / 2 / 800

    /// How tall the gauge's ink is, as a share of the square. This sets the type size, as on a
    /// list's frame (``ListFrameMetrics/gauge``), so every folder's name is set at one size.
    public static let nameCross: CGFloat = 0.095

    /// The widest a name may run. A longer name is set smaller rather than cut.
    public static let nameRun: CGFloat = 0.86

    /// How the name is set: its size, and where the pen and the baseline go, in the square's units.
    public struct Lettering: Equatable, Sendable {
        public let size: CGFloat
        public let x: CGFloat
        public let baseline: CGFloat
    }

    /// The size and place of `name` on a square of `edge`, from a font that can measure itself.
    ///
    /// The name is centred across the square by its own ink. The baseline puts the middle of the
    /// gauge's ink on the bar's middle line, so every folder's name sits on the same line whatever
    /// letters it has. Nil when the font measures nothing.
    public static func lettering(_ name: String, edge: CGFloat,
                                 measuring: (String, CGFloat) -> ListFrameMetrics.Ink) -> Lettering? {
        guard edge > 0, !name.isEmpty else { return nil }

        let cross = edge * nameCross
        var size = cross

        // A font with no Latin letters measures the gauge as nothing; the name sets the size then.
        var gauged = measuring(ListFrameMetrics.gauge, size)
        if gauged.height <= 0 { gauged = measuring(name, size) }
        guard gauged.height > 0 else { return nil }

        size *= cross / gauged.height

        var ink = measuring(name, size)
        guard ink.width > 0 else { return nil }

        if ink.width > edge * nameRun {
            size *= (edge * nameRun) / ink.width
            ink = measuring(name, size)
        }

        var line = measuring(ListFrameMetrics.gauge, size)
        if line.height <= 0 { line = ink }

        return Lettering(size: size,
                         x: (edge - ink.width) / 2 - ink.left,
                         baseline: edge * barCentre - (line.top + line.bottom) / 2)
    }
}
