import SwiftUI
import os.log
import RPMAudio
import RPMSharedUI
import RPMStages

/// Draws one of the stage's looks (``StageLook``) at the size it is given, with its own frame clock
/// and audio tap.
///
/// The stage (``StageView``) draws it in place of the artist's photograph, and the Modern player on
/// its side (``NowPlayingSheet``) draws it behind the cover, the text and the keys. Both screens
/// draw the same picture from this one piece of code.
///
/// **The clock runs only while this view is on screen and ``running`` is true.** A full-screen look
/// is the most expensive thing this app draws, and a phone gets hot from it whether or not anybody
/// is looking. When the view leaves the screen, or ``running`` turns false, the clock stops and the
/// tap is released. With ``running`` false the last frame stays on the screen, so a look that rests
/// shows a still picture and not a blank one.
///
/// **It is a view of its own, not a part of the screen that shows it.** The clock changes 60 times a
/// second. With `@Observable`, the view that reads ``StageClock/tick`` is the view that is drawn
/// again, so only this view is redrawn on each frame, and not the whole screen with its menus.
struct StageLookView: View {
    /// The look to draw. ``StageLook/artwork`` draws nothing and runs no clock: the photograph is
    /// drawn by the screen itself.
    let look: StageLook

    let player: Player

    /// Whether the clock may run. False keeps the last frame, for a look that rests while the music
    /// is paused.
    var running: Bool = true

    /// The frame clock and the audio tap, for the look that is drawing.
    @State private var clock = StageClock()

    /// The plate simulation, created once. Its sand is scattered once and never again, so a plate
    /// rebuilt on every frame would never form a pattern.
    @State private var plate = ChladniPlate()

    /// The ribbon sea, also created once: its band history is 100 columns covering the last few
    /// seconds, and a sea rebuilt every frame would lose that history.
    @State private var sea = RibbonSea()

    /// The block field, also created once. It holds the distance flown so far.
    @State private var flow = BlockFlow()

    /// The bloom field, also created once. It holds 2.5 seconds of the music at a time.
    @State private var bloom = BloomField()

    /// The three band levels that light the ray-marched looks. All of them share one reading: they
    /// draw different things but listen to the same audio.
    @State private var bands = MarchBands()

    var body: some View {
        // The clock is given the frame size here, not from inside a draw. A look that builds
        // geometry needs the size BEFORE it is drawn, and a draw that sets state cannot be moved
        // off the thread it runs on.
        GeometryReader { geo in
            looking
                .onChange(of: geo.size, initial: true) { _, size in clock.drawnInto = size }
        }
        .onAppear { follow() }
        // A new look needs its own listener: ``runTheLook()`` connects the one that is chosen now.
        .onChange(of: look) { _, _ in follow() }
        .onChange(of: running) { _, _ in follow() }
        .onDisappear { clock.stop(player) }
    }

    /// Starts the clock for the look, or stops it when there is nothing to run.
    private func follow() {
        if running && look != .artwork { runTheLook() } else { clock.stop(player) }
    }

    /// Draws the look that is currently selected.
    @ViewBuilder
    private var looking: some View {
        switch look {
        case .plate:
            PlateView(plate: plate, tick: clock.tick)
        case .ribbon:
            RibbonView(sea: sea, tick: clock.tick, now: clock.now)
        case .blocks:
            BlockView(flow: flow, tick: clock.tick, now: clock.now)
        case .lattice:
            MarchedView(march: "rpmLattice", uniforms: latticeUniforms,
                        bloom: 0.6 + 0.6 * bands.air, saturate: 1.35,
                        tick: clock.tick, seconds: clock.now)
        case .kaleidoscope:
            MarchedView(march: "rpmKaleidoscope", uniforms: kaleidoscopeUniforms,
                        bloom: 0.20 + 0.35 * bands.middle, saturate: 1.55,
                        tick: clock.tick, seconds: clock.now)
        case .tunnel:
            MarchedView(march: "rpmTunnel", uniforms: tunnelUniforms,
                        bloom: 0.6, saturate: 1.0,
                        tick: clock.tick, seconds: clock.now)
        case .butterfly:
            // No finishing pass for this look: it has no camera, no room and no beat,
            // and the desktop also draws it directly to the screen without a bloom pass.
            ButterflyView(spectrum: bands.spectrum, tick: clock.tick)
        case .bloom:
            BloomView(field: bloom, tick: clock.tick)
        case .artwork:
            EmptyView()
        }
    }

    /// The values passed to the lattice shader, in the order the shader takes them.
    ///
    /// Same as the desktop's `LatticeStage.Upload`, value for value. The slice moves with
    /// the plain beat count, not a stepped one: the same value also moves the grid past the
    /// camera, and easing it made the flight jerk on every beat and slow down before the
    /// next. The rotations are slow, because a four-dimensional rotation changes every cell
    /// at once and a fast one is unreadable.
    private func latticeUniforms(_ shot: VizShot, _ size: CGSize) -> [Shader.Argument] {
        let walls = VizRoom.blend(shot.was, shot.now, shot.blend)

        return [
            .float2(size),
            .float3(shot.orbit, shot.fov, shot.sway),
            // The rotations must be smooth only. The shot's roll is a camera change and is
            // already applied to the ray. Adding it here would rotate the whole
            // four-dimensional grid at every cut, which looks like the picture being
            // replaced and not like the camera moving.
            .float4(shot.beats * 0.22, shot.beats * 0.010, shot.beats * 0.007, shot.beats * 0.004),
            // The values the music drives. None of them changes the picture's brightness.
            .float4(0.85 + walls.ring * 0.15,                                     // the cell
                    walls.girth * (0.35 + 0.55 * bands.middle),                    // the wire
                    walls.girth * (0.45 + 0.85 * bands.bass) * (1 + walls.cross * 0.4),  // the bead
                    3.2 + 2.4 * bands.air),                                        // the space
            .float3(shot.beats, shot.pulse, shot.drop),
            .float3(bands.bass, bands.middle, bands.air),
            .float(Float(shot.palette)),
            .float(MarchedView.steps),
        ]
    }

    /// The values passed to the kaleidoscope shader, in the order the shader takes them.
    ///
    /// Same as the desktop's `KaleidoscopeStage.Upload`, value for value.
    private func kaleidoscopeUniforms(_ shot: VizShot, _ size: CGSize) -> [Shader.Argument] {
        let walls = VizRoom.blend(shot.was, shot.now, shot.blend)

        // The glitch fires when a section starts and on a drop. It is derived from the
        // blend and not counted from the beats: the blend is 0 at a section's first beat
        // and 1 once it has settled, and it knows how long a bar is in this track, which
        // a hard-coded 32 does not.
        let glitch = max(shot.blend < 0.25 ? 1 - shot.blend * 4 : 0,
                         shot.drop > 0.85 ? (shot.drop - 0.85) * 6.6 : 0)

        return [
            .float2(size),
            // The distance actually travelled. The flight speed is constant, as in the
            // desktop version, and does not jump when the shot changes speed.
            .float(shot.travelled * 1.3),
            .float3(shot.orbit, shot.fov, shot.sway),
            .float3(shot.now.folds, walls.arm, walls.twist),
            .float3(walls.ring, walls.girth, walls.cross),
            .float3(shot.beats, glitch, shot.drop),
            // Which solid the mirrors show, for this section and the previous one.
            .float3(shot.now.solid, shot.was.solid, shot.blend),
            .float(Float(shot.palette)),
            .float3(bands.bass, bands.middle, bands.air),
            .float(MarchedView.steps),
        ]
    }

    /// The values passed to the tunnel shader, in the order the shader takes them.
    ///
    /// Same as the desktop's `TunnelStage.Upload`, value for value.
    private func tunnelUniforms(_ shot: VizShot, _ size: CGSize) -> [Shader.Argument] {
        let walls = VizRoom.blend(shot.was, shot.now, shot.blend)

        return [
            .float2(size),
            // The distance actually travelled, not the speed times the beat count.
            // Multiplying makes the picture jerk every two bars, because a cut picks a new
            // speed and the whole journey is then rescaled by it.
            .float(shot.travelled * 1.6),
            .float3(shot.orbit, shot.fov, shot.sway),
            .float3(shot.now.folds, walls.arm, walls.twist),
            .float3(walls.ring, walls.girth, walls.cross),
            .float3(shot.beats, shot.pulse, shot.drop),
            .float3(bands.bass, bands.middle, bands.air),
            .float(Float(shot.palette)),
            .float(MarchedView.steps),
        ]
    }

    /// Starts the clock for the selected look and connects the audio input for that look.
    ///
    /// It is called again when the look changes, so the listener and the frame step always belong
    /// to the look that is drawn. The clock itself starts only once: ``StageClock/start(with:)``
    /// does nothing while it already runs.
    private func runTheLook() {
        // The flight is advanced on every frame, not on every audio read: distance is
        // travelled by the clock, and 40 steps a second under a 60 Hz picture would move
        // in visible jerks.
        //
        // **Only for the look that needs it.** If this ran for every look, it would project
        // 1000 blocks 60 times a second behind the plate and the sea, for a picture that is
        // not drawn.
        clock.onFrame = { size in
            guard look == .blocks else { return }

            flow.advance(clock.since)

            // Projected here, not inside the draw: it is arithmetic over 1000 blocks,
            // and a draw that also computes what it draws cannot be moved off the thread
            // it runs on.
            if size.width > 0, size.height > 0 {
                flow.fill(clock.now, widthOverHeight: Float(size.width / size.height))
            }
        }

        clock.hear = { frame in
            switch look {
            case .plate:
                plate.listen(frame)
                plate.settle(Float(clock.since))
            case .ribbon:
                sea.listen(frame, now: clock.now)
            case .blocks:
                flow.listen(frame, now: clock.now)
            case .bloom:
                bloom.listen(frame, now: clock.now)
            case .lattice, .kaleidoscope, .tunnel, .butterfly:
                bands.listen(frame)

                // Every look that is lit by the bands has a minimum brightness, so all four
                // draw normally even when the bands are all zero, and the screen alone
                // cannot show that. This log shows that the values arrived.
                if clock.tick % 120 == 0 {
                    Self.say("""
                        bass \(bands.bass), middle \(bands.middle), air \(bands.air), \
                        loudest bin \(bands.spectrum.max() ?? 0)
                        """)
                }
            default:
                break
            }
        }

        clock.start(with: player)
    }

    /// When the `RPM_STAGE_DIAG` environment variable is set, the look logs the levels it hears.
    /// See ``StageView``, which logs what the stage was asked to do under the same switch.
    private static let diag = ProcessInfo.processInfo.environment["RPM_STAGE_DIAG"] != nil
    private static let log = Logger(subsystem: "com.rpm.player", category: "stage")

    private static func say(_ what: String) {
        guard diag else { return }

        log.notice("\(what, privacy: .public)")
    }
}
