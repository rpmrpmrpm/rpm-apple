import SwiftUI
import Metal
import QuartzCore
import RPMStages

/// Draws the room that the record plays in.
///
/// This is the Apple version of the desktop Pegasus view and the Uno phone's `RoomStage`. It uses
/// the same figures (`RoomSource.cs`, ported in `RoomShader.metal`) driven by the same
/// measurement (`RoomBands`), so all three rooms show one picture from one reading.
///
/// **A colour effect, not a separate surface.** SwiftUI adds a Metal fragment function directly
/// to its own render pass. There is no `MTKView` to own, no drawable to schedule and no second
/// compositor to keep in step with the text drawn over it. The cost is the same as in the other
/// apps: a full-screen fragment program, which is the most expensive thing the app draws on a
/// phone.
///
/// This is why ``running`` exists. When the room is off screen it must be stopped, because a
/// phone gets hot from a shader whether or not anybody looks at it. ``RoomReader`` and the Uno
/// app's `SetActive` follow the same rule.
public struct RoomView: View {
    /// The colours that the record paints the room in, already lifted and separated. They are a
    /// transition toward the new colours, not one value. They are read below at the time of the
    /// frame being drawn, in the same way as ``sound``.
    ///
    /// **Both are read on one clock and nothing else drives them.** Nothing advances a
    /// ``RoomDissolve``, so a change of sleeve always arrives, with or without sound. Paused, or
    /// playing in another room, the room still takes the record's colour.
    public let colours: RoomDissolve

    /// The three envelopes, as the transition between the last two readings and not only the latest
    /// one. They are read below at the time of the frame being drawn.
    ///
    /// **The light and the bars must use one clock.** They follow the same three envelopes. If the
    /// room were lit from a reading that the bars have already passed, the glow would swell one
    /// frame after the run.
    public let sound: RoomRamp

    /// Where the text starts, as a fraction of the height from the top. The room is dimmed below
    /// it. 1 means there is no text anywhere and the whole room is lit.
    public let foot: Double

    /// Whether the clock runs. False shows a still frame, not a blank one.
    public let running: Bool

    /// Whether the room breathes on its own cycles instead of following the music.
    ///
    /// **There is no default, because this switch separates a living room from a still picture.** A
    /// stage shows the record that is playing and is lit by it. A card is a background with no
    /// record of its own. Given silence, the room contains only the slow drift, and the animation
    /// is barely visible. The desktop app draws the same two cases with the same values and the
    /// same switch. See ``RPMStages/CardRoomBreath``.
    ///
    /// It also speeds up the clock, for the reason given there: at the stage's rate a figure
    /// crosses only two per cent of a card in a second.
    public let breathes: Bool

    /// Where the room's clock starts. There is no default: see ``Zero``.
    public let zero: Zero

    /// Where a room's clock starts.
    public enum Zero {
        /// The time this room is first shown. Use it for a room that stands on its own.
        case whenShown

        /// A time shared with other rooms, so two views of the same card draw the same frame at the
        /// same moment. The home banner's cards use it: the copy of the first card after the last
        /// card hands over to the first card itself, and with a separate clock each the room would
        /// jump at that point.
        case shared(Date)
    }

    /// Which room this is. The figures start from a pose chosen from this name
    /// (``RPMStages/RoomPose``), so rooms that start together, or share a clock, do not move in step.
    /// There is no default: rooms that left it out would all start in the same pose. The same name
    /// on the same clock draws the same frame.
    public let seed: String

    /// How far along its drift this room starts, computed from ``seed``. It is computed once, not
    /// every frame.
    private let lead: Double

    /// Where the room folds: the position down the view where the card ends and the mirrored
    /// reflection that the card casts below itself begins. 0 means no reflection.
    ///
    /// **The mirror is part of the same pass.** This is why it is a number here and not a second
    /// ``RoomView`` under the first: one room, one clock, one fragment program. The view is drawn
    /// taller than the card and told where the card ends. See `rpmCardRoom`.
    ///
    /// Only a card's room folds. The stage's room (``breathes`` false) has a foot ramp and a
    /// vignette designed for a full screen, and mirroring those would not make sense.
    public var fold: Double = 0

    public init(colours: RoomDissolve, sound: RoomRamp, foot: Double, running: Bool,
                breathes: Bool, zero: Zero, seed: String, fold: Double = 0) {
        self.colours = colours
        self.sound = sound
        self.foot = foot
        self.running = running
        self.breathes = breathes
        self.zero = zero
        self.seed = seed
        self.lead = RoomPose.offset(of: seed)
        self.fold = fold
    }

    /// The time this room appeared, so the figures drift from a known zero and not from the
    /// current wall clock time.
    @State private var from = Date()

    /// The date at which this room's clock starts.
    private var start: Date {
        switch zero {
        case .whenShown: return from
        case .shared(let date): return date
        }
    }

    /// Whether this build can draw the room at all.
    ///
    /// The Metal library must be in the bundle and must contain the function. The Uno app asks Skia
    /// the same question through `SKCanvasElement.IsSupportedOnCurrentPlatform`. Where the answer
    /// is no, the plain background underneath is what the screen shows. The value is computed once,
    /// because it depends on the build and not on the moment.
    public static let works: Bool = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let library = try? device.makeDefaultLibrary(bundle: .module)
        else { return false }

        return library.makeFunction(name: "rpmRoom") != nil
            && library.makeFunction(name: "rpmCardRoom") != nil
    }()

    /// Compiles the room's two programs, the stage's and the card's, before any room is drawn, so
    /// the first screen that shows a room does not wait for the compiler. Call it once, at launch.
    /// It compiles the program itself. The values passed here only give the types of the arguments.
    @available(iOS 18.0, tvOS 18.0, *)
    public static func compileAhead() async {
        guard works else { return }
        let library = ShaderLibrary.bundle(.module)
        let black = Shader.Argument.float3(0, 0, 0)
        let stage = library.rpmRoom(.float2(CGSize(width: 1, height: 1)), .float(0),
                                    .float(0), .float(0), .float(0), black, black, black, black, .float(1))
        let card = library.rpmCardRoom(.float2(CGSize(width: 1, height: 1)), .float(0),
                                       .float(0), .float(0), .float(0), black, black, black, black, .float(0))
        try? await stage.compile(as: .colorEffect)
        try? await card.compile(as: .colorEffect)
    }

    public var body: some View {
        // The timeline is paused and not removed, so a room that comes back is the same room a
        // moment later and does not start again from zero.
        TimelineView(.animation(paused: !running)) { timeline in
            // **Two clocks, for two different things.** The timeline's date measures how far the
            // room has drifted since it appeared, and it needs its own zero. The ramp is read in
            // the reader's monotonic seconds, because its readings are stamped with that clock.
            let now = CACurrentMediaTime()
            let palette = colours.read(now)

            // A card uses its own faster clock, and the swell is read from the same clock. The
            // envelopes and the figures must not be read at two different times.
            let ran = timeline.date.timeIntervalSince(start) + lead
            let seconds = breathes ? CardRoomBreath.clock(ran) : ran
            let heard = breathes ? CardRoomBreath.at(seconds) : sound.read(now).levels

            GeometryReader { geo in
                Rectangle()
                    .fill(Color(rgb: palette.ground))
                    .colorEffect(shader(size: geo.size, at: seconds,
                                        heard: heard, palette: palette))
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    /// Converts a colour to a shader argument. `Shader.Argument.float3` takes three scalars and not
    /// the vector that the palette holds. Writing that out four times at the call site would hide
    /// what is being passed.
    private func rgb(_ colour: SIMD3<Float>) -> Shader.Argument {
        .float3(colour.x, colour.y, colour.z)
    }

    private func shader(size: CGSize, at seconds: TimeInterval,
                        heard: (bass: Float, middle: Float, air: Float),
                        palette: RoomPalette) -> Shader {
        let library = ShaderLibrary.bundle(.module)

        // **A card's background does not use the stage's treatment**, as on the desktop. The wash,
        // the foot ramp and the vignette exist for a screen with a title and a row of keys over it.
        // On a card they would leave it at about a quarter of the brightness and put its one lit
        // band along the top edge. See `rpmCardRoom`.
        //
        // The two argument lists are written out and not shared: a shader is called through a
        // dynamic member and takes its arguments one at a time, so there is no list to pass.
        if breathes {
            return library.rpmCardRoom(
                // **The card's size, which differs from the drawn size when the room folds.** The
                // composition belongs to the card. The extra height below it is the same picture
                // read backwards. A size that included it would spread the composition over both
                // halves and mirror something that was never on the card.
                .float2(CGSize(width: size.width, height: fold > 0 ? fold : size.height)),
                .float(Float(seconds)),
                .float(heard.bass), .float(heard.middle), .float(heard.air),
                rgb(palette.ground), rgb(palette.tint), rgb(palette.glow), rgb(palette.shade),
                .float(Float(max(0, fold))))
        }

        return library.rpmRoom(
            .float2(size),
            .float(Float(seconds)),
            .float(heard.bass), .float(heard.middle), .float(heard.air),
            rgb(palette.ground), rgb(palette.tint), rgb(palette.glow), rgb(palette.shade),
            // Clamped to the range that the room was tuned for. A value of 0 would dim the whole
            // picture because of a sleeve that has not been measured yet.
            .float(Float(min(1, max(0.2, foot)))))
    }
}

extension Color {
    /// A colour in the form the room's calculations use: each channel from 0 to 1.
    public init(rgb: SIMD3<Float>) {
        self.init(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))
    }
}
