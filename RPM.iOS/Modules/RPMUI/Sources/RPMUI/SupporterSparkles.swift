import SwiftUI

/// Soft points of light that glow up and fade away around a supporter's photo, over it, and over the name under it.
/// It is the Android app's `SupporterSparkles`: the same timing, places and drawing; change both.
///
/// Each point lives a few seconds: it swells in, drifts upwards a little while it turns, and fades out, then waits
/// and comes back somewhere else. A point is a warm halo, two long thin rays crossed over it, two short ones between
/// them, and a white-hot centre, all added to the light under it (`plusLighter`), so it glows on the dark page instead
/// of sitting on top.
///
/// The view is ``fieldWide`` by ``fieldHigh`` photo diameters, with the photo's centre ``above`` diameters from its
/// top. Lay it over the photo and the name so its centre point sits on the photo's centre; it takes no touches.
struct SupporterSparkles: View {
    /// The photo's diameter.
    let photo: CGFloat

    static let fieldWide: CGFloat = 1.9
    static let above: CGFloat = 0.8
    static let below: CGFloat = 1.0
    static var fieldHigh: CGFloat { above + below }

    /// How many points can be lit at once.
    private static let points = 9
    private static let warmWhite = Color(red: 1, green: 0xF3 / 255, blue: 0xD6 / 255)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let now = timeline.date.timeIntervalSinceReferenceDate
                let centre = CGPoint(x: size.width / 2, y: photo * Self.above)
                context.blendMode = .plusLighter
                for slot in 0..<Self.points { glow(&context, slot: slot, now: now, centre: centre) }
            }
        }
        .frame(width: photo * Self.fieldWide, height: photo * Self.fieldHigh)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Draws the point in `slot` as it is at `now`, if it is lit.
    private func glow(_ context: inout GraphicsContext, slot: Int, now: TimeInterval, centre: CGPoint) {
        // Every slot has its own pace, and they start spread over one round so they never light together.
        let life = 2.6 + 1.4 * Self.noise(slot, 0, 1)
        let round = life + 1.2 + 1.8 * Self.noise(slot, 0, 2)
        let running = now + round * Double(slot) / Double(Self.points)
        let turn = Int((running / round).rounded(.down))
        let age = (running - Double(turn) * round) / life
        guard age < 1 else { return }
        // Swells in and fades out smoothly, brightest in the middle of its life.
        let light = pow(sin(age * .pi), 2)
        guard light > 0.01 else { return }

        var at = place(slot: slot, turn: turn, centre: centre)
        at.y -= photo * 0.05 * age
        let reach = photo * (0.045 + 0.035 * Self.noise(slot, turn, 3)) * (0.75 + 0.25 * light)
        let colour = Self.noise(slot, turn, 4) < 0.7 ? RPMInk.gold : Self.warmWhite

        // The halo: wide and faint, the warm air around the point.
        let halo = reach * 3.2
        context.fill(Path(ellipseIn: CGRect(x: at.x - halo, y: at.y - halo, width: halo * 2, height: halo * 2)),
                     with: .radialGradient(Gradient(stops: [.init(color: colour.opacity(0.50 * light), location: 0),
                                                            .init(color: colour.opacity(0.16 * light), location: 0.35),
                                                            .init(color: .clear, location: 1)]),
                                           center: at, startRadius: 0, endRadius: halo))

        // The rays, turning slowly through the point's life.
        let angle = Angle.degrees(360 * Self.noise(slot, turn, 5) + 25 * age)
        var turned = context
        turned.translateBy(x: at.x, y: at.y)
        turned.rotate(by: angle)
        turned.fill(rays(reach * 2.1, waist: 0.07), with: rayShading(reach * 2.1, colour, light))
        turned.rotate(by: .degrees(45))
        turned.fill(rays(reach * 0.9, waist: 0.10), with: rayShading(reach * 0.9, colour, light * 0.7))

        // The white-hot centre.
        let core = reach * 0.45
        context.fill(Path(ellipseIn: CGRect(x: at.x - core, y: at.y - core, width: core * 2, height: core * 2)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(light), .white.opacity(0)]),
                                           center: at, startRadius: 0, endRadius: core))
    }

    /// White at the centre, the point's colour along the rays, and nothing at their tips. Drawn about the origin.
    private func rayShading(_ reach: CGFloat, _ colour: Color, _ light: Double) -> GraphicsContext.Shading {
        .radialGradient(Gradient(stops: [.init(color: .white.opacity(light), location: 0),
                                         .init(color: colour.opacity(0.85 * light), location: 0.25),
                                         .init(color: colour.opacity(0), location: 1)]),
                        center: .zero, startRadius: 0, endRadius: reach)
    }

    /// Four rays crossing at the origin, `reach` long, narrowing from a waist of `waist` times their length to tips.
    private func rays(_ reach: CGFloat, waist: CGFloat) -> Path {
        let w = reach * waist * 0.4
        var path = Path()
        path.move(to: CGPoint(x: 0, y: -reach))
        path.addQuadCurve(to: CGPoint(x: reach, y: 0), control: CGPoint(x: w, y: -w))
        path.addQuadCurve(to: CGPoint(x: 0, y: reach), control: CGPoint(x: w, y: w))
        path.addQuadCurve(to: CGPoint(x: -reach, y: 0), control: CGPoint(x: -w, y: w))
        path.addQuadCurve(to: CGPoint(x: 0, y: -reach), control: CGPoint(x: -w, y: -w))
        path.closeSubpath()
        return path
    }

    /// Where a point lights, new for every `turn`: most on the ring around the photo, some over the photo, and some
    /// over the name under it.
    private func place(slot: Int, turn: Int, centre: CGPoint) -> CGPoint {
        let where_ = Self.noise(slot, turn, 6)
        let a = Self.noise(slot, turn, 7)
        let b = Self.noise(slot, turn, 8)
        switch where_ {
        case ..<0.6:
            let angle = a * 2 * .pi
            let distance = photo * (0.48 + 0.16 * b)
            return CGPoint(x: centre.x + cos(angle) * distance, y: centre.y + sin(angle) * distance)
        case ..<0.8:
            let angle = a * 2 * .pi
            let distance = photo * 0.38 * b
            return CGPoint(x: centre.x + cos(angle) * distance, y: centre.y + sin(angle) * distance)
        default:
            return CGPoint(x: centre.x + photo * (a - 0.5) * 1.3, y: centre.y + photo * (0.66 + 0.12 * b))
        }
    }

    /// A number from 0 to 1 that is always the same for the same three inputs. The Android app's `noise`, with the
    /// same 32-bit integer steps.
    private static func noise(_ slot: Int, _ turn: Int, _ which: Int) -> Double {
        var h = Int32(truncatingIfNeeded: slot) &* 374761393 &+ Int32(truncatingIfNeeded: turn) &* 668265263
            &+ Int32(truncatingIfNeeded: which) &* 1274126177
        h = (h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 13)) &* 1274126177
        h = h ^ Int32(bitPattern: UInt32(bitPattern: h) >> 16)
        return Double(h & 0xFFFFFF) / 16777216
    }
}
