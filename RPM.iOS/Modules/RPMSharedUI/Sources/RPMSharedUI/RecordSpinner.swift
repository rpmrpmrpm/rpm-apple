import SwiftUI

/// The wait mark: a record turning, drawn in the app's glass style. It is shown while something
/// is loading, in place of the system progress ring. A system spinner says nothing about what is
/// being waited for. This one shows that a record is coming.
///
/// Ported from `RPM.Desktop/Presentation/Controls/RecordSpinner.xaml`, ring for ring and gradient
/// stop for gradient stop, so the desktop and mobile apps show the same mark. It is drawn in the
/// same 100-unit box as the XAML, with every length a fraction of the requested diameter. This is
/// what the original's `Viewbox` does, written out in code.
///
/// **Glass by drawing, not by a live blur.** A `.ultraThinMaterial` disc looks like a hole cut in
/// the screen and not like an object on it, and this mark must look like it lies on the
/// background. Translucent whites over the content behind look frosted at this size, and cost
/// only a gradient.
///
/// This is not `RecordDisc`, and the two are not interchangeable. `RecordDisc` is the record that
/// is being played. This one is glass and means "wait". They turn at the same speed, because a
/// record has only one speed.
public struct RecordSpinner: View {
    private let diameter: CGFloat

    /// - Parameter diameter: the width of the record. Use 120 for a screen that is waiting, 48 for a
    ///   pane, and 34 or less for one line of a card.
    public init(diameter: CGFloat) {
        self.diameter = diameter
    }

    /// The same speed as a rate, used for the phase that is read from the clock below.
    private static let degreesPerSecond: Double = 360 / revolution

    /// The grooves: diameter in the design box and the alpha value of the ink. The alpha values
    /// alternate, so the grooves look like a stack of rings and not like hatching.
    private static let grooves: [(edge: CGFloat, ink: Double)] = [
        (89, 0x1F), (80, 0x14), (71, 0x1F), (62, 0x14), (53, 0x1F),
    ]

    /// One turn every 1.8 seconds, which is 33 1/3 turns per minute. This is the speed of an LP and
    /// of `RecordDisc`.
    private static let revolution: Double = 60 / 33.3333

    /// The record's angle when this spinner appears, so a spinner that starts late is in step with
    /// any spinner that is already turning. The desktop app uses one shared timer for this. Here
    /// the clock is read once and Core Animation continues from that angle.
    @State private var began: Double = 0
    @State private var turning = false

    public var body: some View {
        face
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
            .onAppear {
                began = Self.angle(at: Date())
                withAnimation(.linear(duration: Self.revolution).repeatForever(autoreverses: false)) {
                    turning = true
                }
            }
    }

    private var face: some View {
        ZStack {
            disc
            rim

            // The grooves do not rotate. Real grooves are concentric, so their turning cannot be
            // seen. On the spinning layer they would cost the same and show nothing.
            ForEach(Self.grooves, id: \.edge) { groove in
                Circle()
                    .strokeBorder(Color.white.opacity(groove.ink / 255), lineWidth: u(0.75))
                    .frame(width: u(groove.edge), height: u(groove.edge))
            }

            // WHAT TURNS: only the light on the rim and the label. Everything else is either
            // round and unchanging or exactly in the centre, and neither shows a rotation.
            ZStack {
                glint
                label
            }
            // **Turned by an animation, not by an angle computed every frame.** A wait mark is
            // shown when the app is busiest, and SwiftUI's own clock runs on the main thread. If a
            // launch spends 400 ms reading the library, a per-frame angle would leave the record
            // standing still for 400 ms, which must never happen. A rotation handed to Core
            // Animation is run by the render server and keeps turning during a stall, like the
            // system ring does.
            .rotationEffect(.degrees(began + (turning ? 360 : 0)))

            spindle
        }
        .frame(width: diameter, height: diameter)
    }

    /// The disc. The light comes from the top left, as everywhere else in the app.
    private var disc: some View {
        Circle()
            .fill(Self.glass([(0, 0x3D), (0.45, 0x1F), (1, 0x14)],
                             from: UnitPoint(x: 0.15, y: 0), to: UnitPoint(x: 0.85, y: 1)))
            .frame(width: diameter, height: diameter)
    }

    /// The disc's edge, bright where the light falls and dark where it does not. It is the same
    /// hairline border that every frosted card in the app has, bent into a circle.
    private var rim: some View {
        Circle()
            .strokeBorder(Self.glass([(0, 0x8C), (0.5, 0x26), (1, 0x5E)],
                                     from: UnitPoint(x: 0.1, y: 0), to: UnitPoint(x: 0.9, y: 1)),
                          lineWidth: u(1))
            .frame(width: diameter, height: diameter)
    }

    /// The light on the glass: a bright patch of rim that travels round as the record turns. At
    /// this size it is the only visible sign of motion, so it is wide and soft, not a sharp mark.
    private var glint: some View {
        Circle()
            .strokeBorder(Self.glass([(0, 0), (0.34, 0), (0.54, 0x5E), (0.74, 0), (1, 0)],
                                     from: .topLeading, to: .bottomTrailing),
                          lineWidth: u(6))
            .frame(width: u(94), height: u(94))
    }

    /// The label. The light on it is off-centre, so its turning is visible too. There is no
    /// wordmark: a third of the disc, at the size a list draws it, is only four points across, and
    /// letters that small are just a smudge.
    private var label: some View {
        Circle()
            .fill(Self.glass([(0, 0x4D), (1, 0x1F)],
                             from: UnitPoint(x: 0.2, y: 0), to: UnitPoint(x: 0.8, y: 1)))
            .frame(width: u(35), height: u(35))
            .overlay { Circle().strokeBorder(Color.white.opacity(0x4D / 255), lineWidth: u(1)) }
    }

    /// The spindle hole: exactly in the centre and not rotating, as on a real record.
    private var spindle: some View {
        Circle()
            .fill(Color(red: 0x0B / 255, green: 0x11 / 255, blue: 0x1A / 255)
                .opacity(0x66 / 255))
            .frame(width: u(4), height: u(4))
            .overlay { Circle().strokeBorder(Color.white.opacity(0x33 / 255), lineWidth: u(0.5)) }
    }

    /// Converts a length in the 100-unit design box to points at the requested diameter. Stroke
    /// widths use it too, so a small spinner in a card is the same drawing as a large one and not a
    /// heavier version of it.
    private func u(_ length: CGFloat) -> CGFloat { length * diameter / 100 }

    /// A white gradient, defined as the XAML defines it: byte alpha values at offsets, running from
    /// one corner of the box to another.
    private static func glass(_ stops: [(offset: Double, ink: Double)],
                              from: UnitPoint, to: UnitPoint) -> LinearGradient {
        LinearGradient(
            stops: stops.map { .init(color: Color.white.opacity($0.ink / 255), location: $0.offset) },
            startPoint: from, endPoint: to)
    }

    /// The angle of a record that has been turning since the reference date.
    ///
    /// It is read from the wall clock and does not start at 0, so every spinner on the screen is in
    /// step. This is correct because they all show the same wait. The desktop app shares one timer
    /// for this. Here the clock is read once when the mark appears, and the turn continues from
    /// that angle.
    static func angle(at date: Date) -> Double {
        (date.timeIntervalSinceReferenceDate * degreesPerSecond)
            .truncatingRemainder(dividingBy: 360)
    }
}
