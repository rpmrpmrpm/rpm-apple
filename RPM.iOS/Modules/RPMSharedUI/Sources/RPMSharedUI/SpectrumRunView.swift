import SwiftUI
import RPMDesign
import RPMStages

/// The spectrum, coming out of the sides of the sleeve: bass where it leaves the cover, the top
/// end at the screen edge, mirrored about the sleeve's middle line like a waveform.
///
/// This is the run of the Uno app's `RoomStage`, with the same figures: the pitch, the fill, the
/// reach measured against the sleeve's height and not the device's, the damping that lets the run
/// settle as it travels outward, and the resting line, so silence looks like a spectrum at rest
/// and not like nothing.
///
/// **Bars, not a shader.** The Uno app draws them in Skia next to a shader room, for the same
/// reason: at this size a bar is a few points wide and its edge matters, and a properly drawn
/// rounded rectangle looks better than one approximated in a fragment program.
public struct SpectrumRunView: View, Animatable {
    /// The run, with each band from 0 to 1, as `RoomBands` folded it and as `RoomRamp` left it
    /// between two readings.
    public var run: [Float]

    /// The sleeve's side length, in points. The reach is measured against the sleeve that the run
    /// stands beside and not against the device.
    public var side: CGFloat

    /// How far the sleeve has been pushed away from the middle, which a swipe for the next track
    /// does.
    ///
    /// **The run is measured from the sleeve's edges, not from the middle of the screen.** If the
    /// sleeve is pushed left, the margin on its right grows: more bars fit, and the run comes out
    /// of the cover into the space that the cover has left. The Uno app gives its room the whole
    /// sleeve rectangle for this reason (`PushCover`, called on every delta of the drag). A run
    /// that is given only a width cannot do this.
    public var shift: CGFloat

    /// Which sides of the sleeve the run comes out of.
    public enum Sides: Sendable {
        /// Both sides: the sleeve is alone in the middle of the screen (iPhone).
        case both
        /// The right side only, where a column of text stands on the left (the Apple TV spread
        /// view, as the desktop app and Android TV draw it).
        case right
    }

    public var sides: Sides

    /// The record's colours: its dominant tone where the bars come out from behind the sleeve, and
    /// its vivid accent by the time they reach the edge.
    public var tint: RGB
    public var glow: RGB

    public init(run: [Float], side: CGFloat, shift: CGFloat, sides: Sides, tint: RGB, glow: RGB) {
        self.run = run
        self.side = side
        self.shift = shift
        self.sides = sides
        self.tint = tint
        self.glow = glow
    }

    /// **Both of the sleeve's values are animated, and the drawing must be animated too.** The
    /// sleeve springs when the record is paused and springs back when a swipe is released. A
    /// `Canvas` is not animatable by itself, so a run given the final values would jump to them in
    /// one step while the cover it is measured against was still moving. This property makes the
    /// two move together.
    ///
    /// `nonisolated` because `Animatable` is: SwiftUI drives this from its own interpolation and
    /// not from the main actor, and a `View` infers main-actor isolation from the protocol it
    /// conforms to.
    public nonisolated var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(side, shift) }
        set { side = newValue.first; shift = newValue.second }
    }

    /// The room one bar needs, including the gap. If it is smaller, the run looks like a texture
    /// and not like bars.
    private static let pitch: Double = 7

    /// The share of the pitch that a bar fills. The rest is the gap.
    private static let fill: Double = 0.55

    /// How far a bar at full level reaches from the middle line, as a fraction of the sleeve. The
    /// run is mirrored about that line, so a bar at full level is twice this tall.
    private static let reach: Double = 0.30

    /// How much of that reach is lost by the time the run arrives at the screen edge, and the
    /// curve exponent of the loss.
    private static let damp: Double = 0.30, dampBend: Double = 1.6

    /// The height of the resting line, as a fraction of the sleeve. Silence is shown as a spectrum
    /// at rest.
    private static let rest: Double = 0.006

    public var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard side > 0, !run.isEmpty else { return }

            let centre = size.height / 2
            let reach = Double(side) * Self.reach
            let rest = Double(side) * Self.rest

            // The two margins are not always the same width. A sleeve centred on an odd number of
            // points leaves one more point on one side, and a sleeve being swiped away leaves far
            // more room on one side than on the other. Each side is therefore its own run, and not one
            // run copied to both sides.
            let left = (size.width - side) / 2 + shift
            let right = left + side

            // If the sleeve is pushed far enough, it leaves the screen and one of the two rooms
            // becomes negative. `SpectrumRun` then reports that nothing fits, which is correct, but
            // clamping to 0 keeps the arithmetic simple.
            bars(context, from: right, room: max(0, size.width - right), direction: 1,
                 centre: centre, reach: reach, rest: rest)
            if sides == .both {
                bars(context, from: left, room: max(0, left), direction: -1,
                     centre: centre, reach: reach, rest: rest)
            }
        }
        .allowsHitTesting(false)
    }

    /// The bars for one side of the sleeve. It is named for what it draws and not for the side,
    /// because `side` already means the sleeve's side length in this file.
    private func bars(_ context: GraphicsContext, from: CGFloat, room: CGFloat,
                      direction: Double, centre: CGFloat, reach: Double, rest: Double) {
        let run = SpectrumRun.across(Float(room), pitch: Float(Self.pitch))
        guard run.fits else { return }

        let pitch = Double(run.pitch)
        let half = pitch * Self.fill * 0.5

        for i in 0..<run.columns {
            let level = Double(run.level(self.run, at: i))
            let u = run.columns > 1 ? Double(i) / Double(run.columns - 1) : 0

            let x = Double(from) + direction * (Double(i) + 0.5) * pitch
            let tall = rest + level * reach
                     * Double(SpectrumRun.damp(Float(u), by: Float(Self.damp), bend: Float(Self.dampBend)))

            // The bars use the sleeve's colours and blend between them along the run. The colour
            // is lifted well toward white, and more so for louder bars. The bars are drawn over a
            // background painted in these same colours, so at full saturation they would disappear
            // into it. The bars must read as light, and the hue shows whose light it is.
            let tone = Self.mix(Self.mix(tint, glow, u), RGB(255, 255, 255),
                                0.62 + level * 0.38)

            let bar = CGRect(x: x - half, y: Double(centre) - tall,
                             width: half * 2, height: tall * 2)

            context.fill(Path(roundedRect: bar, cornerRadius: half),
                         with: .color(tone.color.opacity(0.24 + level * 0.76)))
        }
    }

    /// A colour at a given fraction of the way from one colour to another.
    private static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        func at(_ x: UInt8, _ y: UInt8) -> UInt8 {
            UInt8(max(0, min(255, Double(x) + (Double(y) - Double(x)) * t)))
        }
        return RGB(at(a.r, b.r), at(a.g, b.g), at(a.b, b.b))
    }
}
