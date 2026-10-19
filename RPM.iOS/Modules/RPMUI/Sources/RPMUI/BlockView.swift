import SwiftUI
import RPMSharedUI
import RPMStages

/// The flight through the block field, drawn.
///
/// The placing, the turning and the lighting are ``BlockFlow`` in `RPMStages`, shared with
/// the other two apps. This file only fills the faces. Every face already knows its own
/// colour, so they are drawn in the order given: far row first. This is the painter's
/// order, which keeps an opaque field readable without a depth buffer.
///
/// **This is the one look that does not hold sixty frames.** The cost is the number of
/// separate fills, not the geometry. The plate look puts thirty thousand shapes in ONE
/// path and draws at about 52 frames per second, but a thousand faces in a thousand paths
/// draw at about 22. Drawing straight to Core Graphics with `withCGContext` is no faster.
/// The faces cannot be merged, because each has its own colour and that colour is the
/// lighting.
///
/// These rates come from the simulator, not from a phone. `RPM_STAGE_DIAG` prints the
/// rate. Check on real hardware before thinning the field. The number of blocks is the
/// only figure that would help, and the other two apps also depend on it.
struct BlockView: View {
    let flow: BlockFlow

    /// Read so the drawing depends on it, and used as the field's own clock.
    let tick: Int
    let now: Double

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            _ = tick
            guard size.width > 0, size.height > 0 else { return }

            context.fill(Path(CGRect(origin: .zero, size: size)),
                         with: .color(Color(rgb: BlockFlow.background)))

            let halfWidth = size.width / 2, halfHeight = size.height / 2

            for face in flow.faces {
                var quad = Path()
                quad.move(to: at(face.a, halfWidth, halfHeight))
                quad.addLine(to: at(face.b, halfWidth, halfHeight))
                quad.addLine(to: at(face.c, halfWidth, halfHeight))
                quad.addLine(to: at(face.d, halfWidth, halfHeight))
                quad.closeSubpath()

                context.fill(quad, with: .color(Color(rgb: face.colour)))
            }
        }
        .allowsHitTesting(false)
    }

    /// Converts a point in normalised device coordinates to a point on the screen. The
    /// `Canvas` context counts y downwards (it matches SwiftUI), while the projection counts
    /// y upwards, so the y value is flipped.
    private func at(_ ndc: SIMD2<Float>, _ halfWidth: CGFloat, _ halfHeight: CGFloat) -> CGPoint {
        CGPoint(x: (CGFloat(ndc.x) + 1) * halfWidth,
                y: (1 - CGFloat(ndc.y)) * halfHeight)
    }
}
