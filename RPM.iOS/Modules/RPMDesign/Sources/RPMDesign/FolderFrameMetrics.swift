import CoreGraphics

/// Where a folder's name goes on the folder frame (`FolderFrame.png`): centred under the folder, on
/// one line.
///
/// The drawing is 1000 pixels square: a folder-shaped window with round corners and a soft glow round
/// its edge, on black. The window runs from 77 to 920 across and from 82 to 714 down. Its tab is at the
/// top left, from 77 to about 420 across, and slopes down to the folder's top edge at 186. The name's
/// capitals stand on the line at 911, with the middle of the gauge's ink at 880. Every number here is a
/// share of the square, so the same rule sets the name at any size. The Android app reads the same numbers
/// (`FolderFrameMetrics.kt`); change both together.
public enum FolderFrameMetrics {
    /// The line the middle of the gauge's ink sits on, down the square.
    public static let barCentre: CGFloat = 0.88

    /// How tall the gauge's ink is, as a share of the square. This sets the type size, as on a
    /// list's frame (``ListFrameMetrics/gauge``), so every folder's name is set at one size.
    public static let nameCross: CGFloat = 0.126

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
    /// The name is centred across the square by its own ink. The baseline puts the middle of the
    /// gauge's ink on ``barCentre``, so every folder's name sits on the same line whatever
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
