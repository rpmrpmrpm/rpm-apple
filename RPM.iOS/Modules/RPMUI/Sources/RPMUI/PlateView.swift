import SwiftUI
import RPMStages

/// Draws Chladni's plate of sand.
///
/// The physics is in ``ChladniPlate`` in `RPMStages`: the modes, the weight the spectrum gives
/// each mode, and thirty thousand grains that are thrown until they land where the plate is not
/// moving. The desktop and Uno phone apps share this code, and it alone makes the figure.
/// Only the drawing differs. The desktop app puts the grain array in a vertex buffer and draws
/// it with OpenGL, the Uno phone app gives it to Skia as points, and this view draws one filled
/// path.
///
/// **One fill for all grains.** Thirty thousand separate draws would be far too slow, but
/// thirty thousand rectangles in one path need only a single pass. The grains are square, not
/// round. At a grain's size (about a point and a half) a smooth round dot and a square dot look
/// the same, and the round dot costs much more to rasterise.
struct PlateView: View {
    let plate: ChladniPlate

    /// Read inside the drawing so the view redraws when it changes. The grains are changed in
    /// place, so nothing in them tells SwiftUI that a new frame is ready.
    let tick: Int

    /// Flat black, the same as the desktop app clears to. There is no vignette and no gradient,
    /// so only the figure is visible.
    private static let ground = Color(red: 0x03 / 255, green: 0x03 / 255, blue: 0x04 / 255)

    /// A grain keeps its size on screen at any display density, as the desktop app's
    /// point-size uniform does.
    private static let grain: CGFloat = 1.4, grainPerSide: CGFloat = 1 / 560

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            _ = tick

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Self.ground))

            // The plate is square and the screen is not. The plate is fitted to the shorter
            // side and centred, so the figure keeps its proportions. A plate stretched to the
            // shape of a phone would not match the figure that the physics computed.
            let side = min(size.width, size.height)
            let half = side / 2
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            let grain = max(Self.grain, side * Self.grainPerSide)

            var sand = Path()
            for at in plate.grains {
                sand.addRect(CGRect(x: middle.x + CGFloat(at.x) * half - grain / 2,
                                    y: middle.y + CGFloat(at.y) * half - grain / 2,
                                    width: grain, height: grain))
            }

            context.fill(sand, with: .color(.white))
        }
        .allowsHitTesting(false)
    }
}
