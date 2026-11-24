import CoreGraphics

/// Where a folder's name goes on the folder frame (`FolderFrame.png`): centred in the black bar under
/// the folder, on one line.
///
/// The drawing is 1000 pixels square: a folder-shaped window with round corners and a soft glow round
/// its edge, on black. The window runs from 77 to 920 across and from 82 to 714 down. Its tab is at the
/// top left, from 77 to about 420 across, and slopes down to the folder's top edge at 186. The black
/// bar under the folder runs from 715 to the bottom edge. Every number here is a share of the square, so the same rule sets the name at any size. The Android app reads the same numbers
/// (`FolderFrameMetrics.kt`); change both together.
public enum FolderFrameMetrics {
    /// The middle of the bar under the folder, down the square: halfway between 715 and 1000.
    public static let barCentre: CGFloat = (715.0 + 1000.0) / 2 / 1000

    /// How tall the gauge's ink is, as a share of the square. This sets the type size, as on a
    /// list's frame (``ListFrameMetrics/gauge``), so every folder's name is set at one size.
    public static let nameCross: CGFloat = 0.095

    /// The widest a name may run: as wide as the folder. A longer name is set smaller rather than cut.
    public static let nameRun: CGFloat = 0.84

    /// How the name is set: its size, and where the pen and the baseline go, in the square's units.
    public struct Lettering: Equatable, Sendable {
        public let size: CGFloat
        public let x: CGFloat
        public let baseline: CGFloat
    }

    /// The size and place of `name` on a square of `edge`, from a font that can measure itself.
    ///
    /// The name is centred across the square by its own ink. Down the square, the body of the
    /// letters is centred on ``barCentre``: the part from the top of the gauge's ink (the top of
    /// the tall letters, as high as the capitals) to the baseline. Hanging tails such as the "g"'s
    /// are left out, so a name looks centred in the bar, and every folder's name sits on the same
    /// line whatever letters it has. Nil when the font measures nothing.
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
                         baseline: edge * barCentre - line.top / 2)
    }
}
