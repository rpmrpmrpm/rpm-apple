import SwiftUI
import UIKit
import RPMDesign

/// The spinning record.
///
/// **It follows the desktop app's disc.** The vinyl is a render made by
/// `scripts/make_vinyl_table.py`, the same pressing that the desktop background is made of. It has
/// a lead-in, a run-out and a rounded rim, and it is pressed in the colour of the record. The
/// label is drawn in code, with the rpm mark stamped into it. Every figure below comes from the
/// desktop control `RecordDisc.xaml`.
///
/// **Only the label turns.** Real grooves are concentric, so their rotation cannot be seen. A
/// still ring also keeps the glossy highlight fixed under the light while the record turns, as on
/// a real turntable.
public struct RecordDisc: View {
    private let diameter: CGFloat
    private let halo: Halo
    private let spinning: Bool
    private let hue: RGB?
    private let label: CGImage?
    private let disc: ScannedDisc?

    /// The shadow the record casts. Each app chooses its own: the iPhone record stands on its own
    /// background, and the Apple TV record comes out of a sleeve, as on the desktop.
    public enum Halo {
        /// Round and concentric with the disc, reaching 8% past its edge, so the band looks the
        /// same along the top as along the bottom. Used on iPhone.
        case round
        /// The desktop Pegasus layout (`PegasusLayout`, `RecordDisc.xaml`): 6% past the edge,
        /// shifted 2.5% right and 1.5% down, at 55% opacity. It casts nothing above the sleeve
        /// that the record comes out of. A round halo would cast above it on the Apple TV record
        /// page.
        case cast
    }

    /// - Parameters:
    ///   - diameter: the width of the record.
    ///   - halo: the shadow the record casts. See ``Halo``.
    ///   - spinning: whether it turns. A paused record stands still.
    ///   - hue: the colour the record is pressed in, taken from the sleeve. Nil gives a black
    ///     record, as for a sleeve with no colour. The default is the house pressing: the app's
    ///     azure over black, which is what an empty deck shows.
    ///   - label: the album's sleeve image, drawn on the label. Nil shows the rpm stamp, which is
    ///     what an empty deck shows. This is `Disc.LabelArtSource` in the desktop app.
    ///   - disc: a photographed record. A CD scan is the whole record and covers both the pressing
    ///     and the label. A label scan is drawn on the record that RPM presses, which stays
    ///     visible around it. ``ScannedDisc/coversRecord`` says which case applies, and it is
    ///     read from the picture.
    public init(diameter: CGFloat, halo: Halo, spinning: Bool = true, hue: RGB? = VinylPressing.houseHue,
                label: CGImage? = nil, disc: ScannedDisc? = nil) {
        self.diameter = diameter
        self.halo = halo
        self.spinning = spinning
        self.hue = hue
        self.label = label
        self.disc = disc
    }

    /// One turn every 1.8 s, which is 33 1/3 turns per minute.
    private static let revolution: Double = 1.8

    /// How long the record takes to reach full speed, like a real turntable.
    private static let spinUp: Double = 1.0

    /// Wobble of an off-centre pressing: the disc orbits a very small circle once per turn. It is a
    /// fraction of the disc size, so it stays slight at any scale.
    private static let wobble: Double = 0.005

    /// The halo extends past the disc's edge, so its box is larger than the disc.
    private static let haloScale: CGFloat = 1.16

    /// The cast halo values: the desktop's `DiscHaloScale`, `DiscShadowThrowX`/`Y` and the halo
    /// opacity on the record screen.
    private static let castScale: CGFloat = 1.06
    private static let castThrow = CGSize(width: 0.025, height: 0.015)
    private static let castOpacity: Double = 0.55

    // Everything below is a fraction of the 200-unit box that the desktop draws the disc in.

    /// The label is a third of the disc, like a real LP: the render has a 100 mm label on a 302 mm
    /// disc, and the app's label matches it exactly.
    private static let labelEdge: CGFloat = 66.0 / 200.0

    /// The mark on the label and how far down it sits: above the spindle, as on the pressed records
    /// in the background image, using the same script's numbers.
    private static let markWidth: CGFloat = 28.6 / 200.0
    private static let markHeight: CGFloat = 11.0 / 200.0
    private static let markDrop: CGFloat = 16.3 / 200.0

    /// The spindle hole at the real size: 3.62 mm on a 50 mm label radius, which is 4.8 in the
    /// 200-unit box. A larger hole would crowd the wordmark off the label.
    private static let spindleEdge: CGFloat = 4.8 / 200.0

    @State private var from = Date()
    @State private var pressed: Image?

    public var body: some View {
        TimelineView(.animation(paused: !spinning)) { timeline in
            let angle = spinning ? Self.angle(after: timeline.date.timeIntervalSince(from)) : 0
            let orbit = Double(diameter) * Self.wobble

            record(angle: angle)
                // Applied to the disc and its halo together, because a cast shadow follows the
                // object that casts it.
                //
                // **A CD does not wobble.** The orbit imitates an off-centre pressing (a record
                // stamped slightly away from its centre hole). A moulded CD has no such fault,
                // and with a CD picture the wobble looks like the picture sliding over the
                // record instead of the record turning.
                //
                // With a label scan the wobble stays on. That is why the check uses
                // `coversRecord` and not whether there is any picture: a label scan sits on the
                // app's own pressing, which still has the off-centre fault.
                .offset(x: wobbles ? orbit * cos(angle * .pi / 180) : 0,
                        y: wobbles ? orbit * sin(angle * .pi / 180) : 0)
        }
        // Pressing is a filter pass over a 1,000 x 1,000 pixel image, so it runs off the main
        // thread. The disc keeps its current look until the new one is ready.
        .task(id: hue) { pressed = await VinylPressing.press(hue) }
    }

    /// Whether the drawn record is hidden under the picture. Only a scan of a whole disc replaces
    /// it. A label scan sits on top of it.
    private var wearingCd: Bool { disc?.coversRecord == true }

    /// The off-centre wobble belongs to the app's own record, so it stops when the app's own record
    /// is no longer the one on the deck.
    private var wobbles: Bool { !wearingCd }

    private func record(angle: Double) -> some View {
        ZStack {
            // A soft halo just past the disc's edge, concentric with it, so the band looks the
            // same along the top as along the bottom. It is a sibling of the record, not a child,
            // because a child would turn with the record and the shadow must not turn.
            let spread = halo == .round ? Self.haloScale : Self.castScale
            Circle()
                .fill(RadialGradient(
                    stops: [.init(color: .black.opacity(0xB3 / 255), location: 0.86),
                            .init(color: .black.opacity(0x59 / 255), location: 0.94),
                            .init(color: .black.opacity(0), location: 1)],
                    center: .center, startRadius: 0,
                    endRadius: diameter * spread / 2))
                .frame(width: diameter * spread, height: diameter * spread)
                .opacity(halo == .round ? 1 : Self.castOpacity)
                .offset(x: halo == .round ? 0 : diameter * Self.castThrow.width,
                        y: halo == .round ? 0 : diameter * Self.castThrow.height)

            if let pressed, !wearingCd {
                // **Nothing under a CD.** A photographed record replaces the drawn one completely,
                // both the pressing and the label. During the flight animation, opacity is applied
                // to the disc as it shrinks away, and any layer under the picture would show
                // through it. That looks like the vinyl colour coming up through the CD, so no
                // layer is drawn under it.
                pressed
                    .resizable()
                    .frame(width: diameter, height: diameter)
            } else if !wearingCd {
                // Shown until the pressing is ready. Black is better than nothing, because a
                // disc-shaped hole in the screen looks worse than a plain record.
                Circle()
                    .fill(Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255))
                    .frame(width: diameter, height: diameter)
            }

            face
                .rotationEffect(.degrees(angle))

            // The spindle hole: exactly in the centre, not rotating, drawn over everything, as on
            // a real record.
            Circle()
                .fill(Color(red: 0x0B / 255, green: 0x11 / 255, blue: 0x1A / 255))
                .overlay {
                    Circle().strokeBorder(Color.white.opacity(0x22 / 255),
                                          lineWidth: max(0.5, diameter / 400))
                }
                .frame(width: diameter * Self.spindleEdge, height: diameter * Self.spindleEdge)
        }
        .frame(width: diameter * Self.haloScale, height: diameter * Self.haloScale)
    }

    /// The face of the record, and the only part that turns.
    ///
    /// A photographed CD is the whole face of the record, not a picture on the label, so it covers
    /// the label and the pressing. It is clipped to the disc's circle, because a square scan with
    /// its corners past the rim would look like a sticker on a record.
    ///
    /// **A label scan is drawn at the same size on purpose.** The desktop app always cuts a square
    /// the size of the whole disc, whichever kind of record was inserted. A CD fills it, and a
    /// label fills only the middle third, with the rest transparent. One frame therefore draws
    /// both, and the pressing shows through the transparent part.
    @ViewBuilder
    private var face: some View {
        if let disc {
            Image(decorative: disc.image, scale: 1)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: diameter, height: diameter)
                .clipShape(Circle())
                // In the face, so it turns with the disc. A label scan sits on the app's own
                // pressing, which has its own hole, and wears nothing.
                .overlay {
                    if disc.coversRecord { CdDress(diameter: diameter) }
                }
        } else {
            self.label(edge: diameter * Self.labelEdge)
        }
    }

    /// The label: the album's sleeve image if there is one, otherwise black with only the rpm mark.
    /// The mark is drawn as a path, so it stays sharp at every size and uses the same letterforms as
    /// the rest of the app's mark.
    ///
    /// The mark uses the dim strength that the desktop header uses while a track is playing, so it
    /// looks pressed into the label and not printed on it.
    private func label(edge: CGFloat) -> some View {
        Circle()
            .fill(Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255))
            .frame(width: edge, height: edge)
            .overlay {
                if let label {
                    Image(decorative: label, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: edge, height: edge)
                        .clipShape(Circle())
                } else {
                    // Nothing on the deck: show the house label.
                    RPMWordmark()
                        .fill(Color.white.opacity(0x40 / 255))
                        .frame(width: diameter * Self.markWidth,
                               height: diameter * Self.markHeight)
                        .position(x: edge / 2,
                                  y: diameter * Self.markDrop + diameter * Self.markHeight / 2)
                }
            }
            .overlay {
                Circle().strokeBorder(Color.black.opacity(0x59 / 255),
                                      lineWidth: max(0.5, diameter / 200))
            }
    }

    /// The angle of the record after this much time, starting from rest.
    ///
    /// The desktop original adds up a smoothstep speed ramp frame by frame. This is the same curve
    /// as a closed formula, so the angle depends on the clock and not on how many frames were
    /// drawn. Otherwise a device that dropped frames would show a record that had turned less than
    /// one that did not.
    static func angle(after elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }

        // The integral of the smoothstep 3u² - 2u³ over the ramp. At the end of the ramp it equals
        // half of the ramp's length.
        let turned: Double
        if elapsed >= spinUp {
            turned = spinUp / 2 + (elapsed - spinUp)
        } else {
            let u = elapsed / spinUp
            turned = spinUp * (u * u * u - u * u * u * u / 2)
        }

        return (turned / revolution * 360).truncatingRemainder(dividingBy: 360)
    }
}

/// The rpm wordmark.
///
/// The same geometry as the desktop splash screen, stored as path data and not as a picture. It
/// draws on the first frame, at any size, with no file to load.
public struct RPMWordmark: Shape {
    public init() {}

    /// Copied exactly from `SignInPage.xaml`.
    static let data =
        "M109 -143H102C85 -143 73 -136 66 -121V-140H18V0H67V-55C67 -81 76 -94 93 -94C98 -94 103 " +
        "-94 109 -93ZM207 -34C189 -34 180 -46 180 -71C180 -94 189 -106 207 -106C226 -106 236 -94 " +
        "236 -71C236 -46 226 -34 207 -34ZM218 3C259 3 284 -29 284 -69C284 -110 260 -143 216 " +
        "-143C199 -143 187 -137 180 -126V-140H132V52H178V-14C186 -3 199 3 218 3ZM525 -96C525 -127 " +
        "510 -143 480 -143C462 -143 448 -136 437 -123C427 -136 414 -143 399 -143C383 -143 369 " +
        "-136 358 -122V-140H312V0H361V-79C361 -96 367 -104 378 -104C389 -104 395 -97 395 -83V0H442" +
        "V-79C442 -96 448 -104 459 -104C470 -104 476 -97 476 -83V0H525Z"

    // `nonisolated(unsafe)` is needed because `CGPath` is not `Sendable`. It is safe because
    // `parse` returns a copy that nothing else can change, and every reader only measures it.
    private nonisolated(unsafe) static let drawn = VectorPath.parse(data)

    /// Width divided by height, so a caller can give one size and compute the other.
    public static let aspect: CGFloat = {
        let bounds = drawn.boundingBoxOfPath
        return bounds.height > 0 ? bounds.width / bounds.height : 1
    }()

    public func path(in rect: CGRect) -> Path {
        Path(VectorPath.fitted(Self.drawn, in: rect))
    }
}
