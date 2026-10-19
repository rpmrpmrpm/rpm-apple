import SwiftUI
import RPMStages

/// The ribbon sea, drawn.
///
/// The projection is ``RibbonSea`` in `RPMStages`: the desktop's vertex shader, moved off the GPU
/// and shared with the other two apps. What is here is the stroke, and it is the same one that
/// the Uno phone app draws: three passes over one centreline, widest first, added together and
/// not painted over.
///
/// **Added, not drawn over.** Where lines cross, additive blending sums them into a bloom, which
/// is what the desktop's GL halo term does. If they were painted over each other, the crossings
/// would go flat and the sea would look like a stack of ribbons and not like light.
struct RibbonView: View {
    let sea: RibbonSea

    /// Read so that the drawing depends on it, and used as the sea's own clock.
    let tick: Int
    let now: Double

    /// The three passes that make one glowing line: half-width as a fraction of the ribbon's own,
    /// the colour, and how much of it is laid down. They are ordered widest first. Additive
    /// blending has no order of its own, but the core must be the last thing written for its
    /// edges to stay clean.
    private static let passes: [(width: CGFloat, ink: Color, alpha: Double)] = [
        // The deep-cyan bloom the GL halo term draws.
        (1.00, Color(red: 0x00 / 255, green: 0x57 / 255, blue: 0xFF / 255), 0x4D / 255),
        (0.45, Color(red: 0x2E / 255, green: 0x9B / 255, blue: 0xFF / 255), 0x66 / 255),
        // The white-hot filament.
        (0.16, Color(red: 0xCC / 255, green: 0xF2 / 255, blue: 0xFF / 255), 0xF2 / 255),
    ]

    /// The ribbon's half-width. The GL version offsets its two edges by 0.048 in clip space,
    /// which is this fraction of the half-height on screen.
    private static let halfWidth: CGFloat = 0.024

    /// The end fade per column. It depends only on the column index, so it is worked out once.
    private static let fade: [CGFloat] = (0..<RibbonSea.columns).map { c in
        let u = CGFloat(c) / CGFloat(RibbonSea.columns - 1)

        return smoothstep(0, 0.08, u) * smoothstep(1, 0.92, u)
    }

    /// GLSL's smoothstep, including the descending form that the end fade uses.
    private static func smoothstep(_ from: CGFloat, _ to: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - from) / (to - from), 0), 1)

        return t * t * (3 - 2 * t)
    }

    var body: some View {
        Canvas(opaque: true, rendersAsynchronously: false) { context, size in
            _ = tick
            guard size.width > 0, size.height > 0 else { return }

            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))

            var points = [SIMD2<Float>](repeating: .zero,
                                        count: RibbonSea.lines * RibbonSea.columns)
            sea.trace(now, aspect: Float(size.height / size.width), into: &points)

            context.blendMode = .plusLighter

            let half = Self.halfWidth * size.height
            var x = [CGFloat](repeating: 0, count: RibbonSea.columns)
            var y = [CGFloat](repeating: 0, count: RibbonSea.columns)

            for line in 0..<RibbonSea.lines {
                let bright = CGFloat(sea.brightness(line))

                // The centreline, once, in points. SwiftUI counts y downwards and the projection
                // counts it upwards, which is the flip. Every pass reads these values.
                let from = line * RibbonSea.columns
                for c in 0..<RibbonSea.columns {
                    x[c] = (CGFloat(points[from + c].x) * 0.5 + 0.5) * size.width
                    y[c] = (0.5 - CGFloat(points[from + c].y) * 0.5) * size.height
                }

                for pass in Self.passes {
                    context.fill(ribbon(x, y, half: half * pass.width),
                                 with: .color(pass.ink.opacity(min(1, pass.alpha * bright))))
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// One line as a closed strip over its centreline: along the top edge and back along the
    /// bottom edge. Both edges are pulled in to the centre at the ends, so the line tapers away
    /// and does not stop abruptly.
    private func ribbon(_ x: [CGFloat], _ y: [CGFloat], half: CGFloat) -> Path {
        var path = Path()

        for c in 0..<RibbonSea.columns {
            let w = half * Self.fade[c]
            let at = CGPoint(x: x[c], y: y[c] - w)

            if c == 0 { path.move(to: at) } else { path.addLine(to: at) }
        }

        for c in stride(from: RibbonSea.columns - 1, through: 0, by: -1) {
            path.addLine(to: CGPoint(x: x[c], y: y[c] + half * Self.fade[c]))
        }

        path.closeSubpath()
        return path
    }
}
