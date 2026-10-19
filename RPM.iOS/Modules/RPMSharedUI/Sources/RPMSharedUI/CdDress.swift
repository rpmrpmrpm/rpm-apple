import SwiftUI
import ImageIO

/// The two pictures the desktop draws over a whole CD (`CdOverlay.cs`): an even rim with the
/// rpm hub over the whole disc, which hides the table a photographed disc's clear rim shows,
/// and a CD player's spindle in the hole, 176/1400 of the disc across. The files are the
/// desktop's `Assets/cd-face.png` and `cd-spindle.png`.
///
/// Drawn only over a scan of the whole disc (``ScannedDisc/coversRecord``), at the disc's own
/// size and inside the face that turns, so both turn with the disc.
struct CdDress: View {
    let diameter: CGFloat

    /// The spindle's square against the disc's diameter.
    private static let spindleShare: CGFloat = 176.0 / 1400.0

    /// Read once and kept, found or not, as the playlist frame is.
    private static let facePicture: CGImage? = load("cd-face")
    private static let spindlePicture: CGImage? = load("cd-spindle")

    private static func load(_ name: String) -> CGImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    var body: some View {
        ZStack {
            if let face = Self.facePicture {
                Image(decorative: face, scale: 1)
                    .resizable()
                    .frame(width: diameter, height: diameter)
            }
            if let spindle = Self.spindlePicture {
                Image(decorative: spindle, scale: 1)
                    .resizable()
                    .frame(width: diameter * Self.spindleShare, height: diameter * Self.spindleShare)
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }
}
