import SwiftUI
import RPMSharedUI
import UIKit
import os.log
import RPMKit
import RPMAudio
import RPMRadio
import RPMArt
import RPMDesign
import RPMStages

/// The stage: the landscape now-playing screen. The record is drawn turning at the right
/// edge, and one column of text and controls runs down the left.
///
/// Port of `RPM.Mobile/Presentation/Controls/StageView.xaml`, and all its figures are
/// the same: the record is 1.08 times the frame height, so it runs off the top and the
/// bottom as well as off the right; the column is 24 from the left and 20 up from the
/// foot; the title is 34 points; the chrome hides after six seconds.
///
/// It belongs to the app, not to a tab, because turning the phone is not navigation.
/// Whatever screen the user was on, the stage appears over it, and turning the phone back
/// returns to that screen. It is only shown while something is loaded.
///
/// **It is meant to be viewed from further away than a phone usually is**, for example
/// propped on an amp or a desk. This is why the type and the buttons are large, and why
/// the chrome hides by itself and comes back on a tap.
///
/// The artist photograph shown comes from `BackdropStore`, which uses `BackdropChooser`
/// to keep the one that leaves the face clear. A swipe pages through the others
/// (`BackdropDeck`).
public struct StageView: View {
    private let player: Player

    /// The record on the deck and both of its pictures, as one value.
    ///
    /// **Use this, not `player.current`.** A track's album name is known the moment the
    /// track starts, but its pictures arrive later. Taking the identity from one source and
    /// the face from the other would tell the deck that a new record is on before the
    /// pictures exist. See ``PlayingRecord``.
    private let playing: PlayingRecord?

    private var art: CoverArt? { playing?.art }

    /// The name of the speaker the sound is going to, or `nil` for the phone.
    private let playingOn: String?

    /// The speaker picker, built by the owner of the speakers, in the same form as the
    /// player sheet takes it. `nil` when casting is not offered, and then the button is
    /// not shown.
    private let onSpeakers: ((@escaping () -> Void) -> AnyView)?

    /// Pictures of the artist. `nil` means the stage shows no photographs.
    private let backdrops: BackdropStore?

    public init(player: Player, playing: PlayingRecord?,
                playingOn: String? = nil,
                backdrops: BackdropStore? = nil,
                onSpeakers: ((@escaping () -> Void) -> AnyView)? = nil) {
        self.player = player
        self.playing = playing
        self.playingOn = playingOn
        self.backdrops = backdrops
        self.onSpeakers = onSpeakers
    }

    /// The artist's photographs, which one is shown, and the swipe that pages them.
    ///
    /// **This is a separate type, not a set of fields here**: a drag moves the picture 60
    /// times a second, and each frame would otherwise re-evaluate this whole screen.
    @State private var deck = BackdropDeck()

    /// The measured screen size: the whole screen, not only the safe area, because the
    /// picture fills the whole screen and its crop window is cut to that size.
    @State private var glass: CGSize = .zero

    /// The height of the text column, which covers the foot of the picture. It is passed
    /// up from the layout, because the same layout pass decides what covers the picture.
    @State private var columnHeight: Double = 0

    // MARK: Figures

    /// The record's diameter as a multiple of the frame's height. It is more than 1 on
    /// purpose: the vinyl runs off the top and the bottom as well as off the right, so it
    /// looks like a record on a turntable and not a circle in a picture.
    private static let discDiameter: CGFloat = 1.08

    /// How far the record moves off screen when the chrome hides, as a multiple of its
    /// diameter. Its centre is already on the right edge, so half a diameter clears the
    /// screen. The rest covers the halo the disc draws past its own rim.
    private static let discAway: CGFloat = 0.62

    /// How long the chrome stays visible when nothing is touched. It is long enough to
    /// read the title and reach a button, and short enough that an untouched stage shows
    /// only the record and the picture.
    private static let idleSeconds: Double = 6

    /// The text column: its distance from the left, its distance from the bottom, and the
    /// widest it may grow on a phone with enough room.
    private static let columnInset: CGFloat = 24, columnFoot: CGFloat = 20
    private static let columnWidest: CGFloat = 520

    /// The side of the small album cover at the top of the column.
    private static let coverEdge: CGFloat = 64

    // MARK: State

    /// The turntable rule: **a record's face only changes while it is out of sight**.
    /// See ``RecordChange``, which is ported from the desktop.
    @State private var turntable = RecordChange(onDeck: false)

    /// Whether the record is off the deck: shrunk into the corner and faded out. The
    /// flight animation changes this, and this is the only moment its face may be swapped.
    @State private var aloft = true

    /// Whether the chrome, and the record with it, is visible.
    @State private var chromeUp = true

    /// The countdown until the chrome hides. It is a task, not a timer: cancelling the
    /// task restarts the countdown, so there is only ever one.
    @State private var idle: Task<Void, Never>?

    @State private var showingSpeakers = false
    @State private var showingLooks = false

    /// Which look the stage opens on.
    ///
    /// It is stored so it survives the app being closed, because the visualiser is a user
    /// preference. The `look` property checks the value when reading, so a stored look that
    /// this build no longer has opens as the artwork.
    @AppStorage("stage.look") private var chosen = StageLook.artwork.rawValue

    /// Whether the chrome is pinned visible.
    ///
    /// It is a user preference and is stored so it survives the app being closed. A user
    /// watching from across a room wants the text to stay, and tapping the screen every six
    /// seconds to keep it would be worse than a chrome that never hid.
    @AppStorage("stage.pinned") private var pinned = false

    private var look: StageLook {
        let want = StageLook(rawValue: chosen) ?? .artwork

        return want.isDrawn ? want : .artwork
    }

    /// The frame clock and the audio tap, for whichever look is drawing. It is created
    /// here but started only when there is something to draw: a display link running behind
    /// the artwork would keep the phone busy redrawing a still picture.
    @State private var clock = StageClock()

    /// The plate simulation, created once. Its sand is scattered once and never again, so
    /// a plate rebuilt on every frame would never form a pattern.
    @State private var plate = ChladniPlate()

    /// The ribbon sea, also created once: its band history is 100 columns covering the
    /// last few seconds, and a sea rebuilt every frame would lose that history.
    @State private var sea = RibbonSea()

    /// The block field, also created once. It holds the distance flown so far.
    @State private var flow = BlockFlow()

    /// The bloom field, also created once. It holds 2.5 seconds of the music at a time.
    @State private var bloom = BloomField()

    /// The three band levels that light the ray-marched looks. All of them share one
    /// reading: they draw different things but listen to the same audio.
    @State private var bands = MarchBands()

    public var body: some View {
        ZStack {
            // The visualiser takes the artist picture's place. It is opaque and drawn over
            // the ground, so switching to it only changes visibility, and the views
            // underneath keep running.
            if look != .artwork {
                // The clock is given the frame size here, not from inside a draw. A look
                // that builds geometry needs the size BEFORE it is drawn, and a draw that
                // sets state cannot be moved off the thread it runs on.
                GeometryReader { geo in
                    looking
                        .onChange(of: geo.size, initial: true) { _, size in clock.drawnInto = size }
                }
                .ignoresSafeArea()
            }

            // Measured against the whole screen, not the safe area: the record's centre
            // belongs on the screen's right edge, and in landscape the safe edge is
            // several millimetres inside it.
            GeometryReader { geo in
                disc(in: geo.size)
            }
            .ignoresSafeArea()

            // A tap anywhere on the frame brings the chrome and the record back.
            //
            // **This is a sibling under the chrome, not a gesture on the stack.** As a
            // gesture on the stack it wraps every button on the screen and takes the tap
            // first, so the chrome would show on every tap and no button would fire.
            // Declared here it is the lowest view that takes touches, so everything above
            // it (the buttons, the seek bar, the picker) receives touches first. The Uno
            // app declares its tap the same way, for the same reason.
            Color.clear
                .contentShape(Rectangle())
                // **Exclusive, in this order.** The tap and the swipe use the same layer.
                // If they were declared side by side, the tap would also fire at the end of
                // every swipe, and paging a photograph would bring the chrome and the record
                // back. A drag that has moved 12 points wins outright. A finger that never
                // moves is a tap, and the drag never recognises it.
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { drag in deck.dragged(drag.translation.width, width: glass.width) }
                        .onEnded { drag in
                            deck.released(drag.translation.width,
                                          velocity: drag.velocity.width,
                                          width: glass.width)
                        }
                        .exclusively(before: TapGesture().onEnded { _ in tapped() }))

            // The scrim runs from left to right, not top to bottom: the text column is
            // on the left and the record is on the right, so the left third needs the
            // dark cover for readability. The right stays clear for the vinyl.
            //
            // It hides with the chrome, because it only exists to make text readable on
            // a picture. Without the text it would just darken the record for no reason.
            scrim
                .ignoresSafeArea()
                .opacity(chromeUp ? 1 : 0)

            chrome
                .opacity(chromeUp ? 1 : 0)
                .allowsHitTesting(chromeUp)
        }
        // The artist picture fills the frame. It is drawn over the vinyl ground and
        // under everything else, and only when no visualiser is active. A look is drawn
        // in the artist picture's place, so switching to one only changes visibility and
        // does not rebuild anything.
        //
        // **Both pictures are backgrounds, not siblings in the stack.** They fill by
        // aspect ratio, so as children of the stack they would report the size they want
        // and not the size they are given, and the stack would grow to match. For example,
        // a stack of 874 x 402 would become 874 x 422, which uses up the home indicator
        // clearance. For `VinylGround` the effect is much
        // larger: it would grow the stack to the picture's filled size (about 750 by 1600),
        // so the record would take its diameter from a frame twice the screen height and
        // the column would be laid out far below the screen. Everything in the stack would
        // move, and on a phone in landscape the title would slide under the sensor housing.
        // A background is sized to the view it belongs to and takes no part in its layout.
        //
        // `VinylGround` draws its own 20 per cent veil, so do not add a second scrim here.
        .background {
            if look == .artwork {
                StagePictures(deck: deck, width: glass.width)
            }
        }
        .background { VinylGround() }
        .background(RPMInk.ground.ignoresSafeArea())
        // Measures the screen size. It is a background, not a wrapper, for the same
        // reason as the ground above: it takes no part in the layout of its parent.
        .background {
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size, initial: true) { _, size in glass = size }
            }
            .ignoresSafeArea()
        }
        // Logs the size the chrome is laid out in and the insets the phone keeps clear.
        // **This log line shows whether the stack has grown**: the size should be the
        // screen minus the sensor housing and nothing else. If it is not, every view with
        // a margin on this screen is in the wrong place.
        .background {
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size, initial: true) { _, size in
                        Self.say("chrome laid out in \(size), housing \(geo.safeAreaInsets)")
                    }
            }
        }
        .onPreferenceChange(ColumnHeight.self) { tall in columnHeight = tall }
        .overlay {
            if showingSpeakers, let onSpeakers {
                onSpeakers { showingSpeakers = false }
            }
        }
        // The look picker is a full screen while it is shown, and it dims what is below.
        .overlay {
            if showingLooks {
                LookPicker(showing: look,
                           onPick: { picked in
                               Self.say("picked \(picked.name), was \(look.name)")
                               chosen = picked.rawValue
                               showingLooks = false
                               showChrome()
                           },
                           onClose: { showingLooks = false; showChrome() })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: showingLooks)
        // Only one look runs at a time, and only while the stage is on screen. Running
        // the clock is what makes a look use CPU and GPU.
        .onChange(of: look, initial: true) { _, now in
            Self.say("the look is now \(now.name)")
            if now == .artwork { clock.stop(player) } else { runTheLook() }
        }
        .animation(.easeOut(duration: 0.3), value: chromeUp)
        // A new artist needs a new photograph, and so does a new frame shape. The task
        // is keyed on the ARTIST, not the track: every album of the same artist shows the
        // same photograph, and fetching it again at each track change would make the
        // picture fade into itself.
        .task(id: Wanted(artist: artistKey, scene: scene)) {
            // Do nothing until the stage has been laid out. A photograph is cropped for
            // the shape of the frame, so a crop made for a frame of zero size would be
            // wrong, and it would still be shown as if it were correct.
            guard scene.isLaidOut else { return }

            deck.say = { Self.say($0) }

            await deck.load(from: backdrops,
                            artist: player.current?.artist,
                            album: player.current?.album,
                            cutFor: scene)
        }
        .onAppear { showChrome() }
        // A countdown running while the stage is not on screen would waste power. The
        // next tap that shows the chrome starts it again.
        .onDisappear {
            idle?.cancel()
            idle = nil

            clock.stop(player)

            // Also release the photographs: they are three full-frame bitmaps for a
            // screen that is not visible. When the stage returns, the store has them
            // cached, so Vision does not run again.
            deck.clear()
        }
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

    // MARK: Photograph frame

    /// The measured areas that cover the picture: the record covers the right side
    /// starting half a diameter in from the edge, and the text column covers the foot.
    /// The clear upper-left area is where the crop places the artist.
    ///
    /// **The record is counted even though it moves away after a few seconds.** While it
    /// is shown, it is a black disc over the right third of the picture, and a face placed
    /// there would be hidden behind it. Choosing the crop for the harder of the two states
    /// costs nothing in the other: the artist just sits left of centre once the record has
    /// gone.
    ///
    /// This is measured here and does not use `ArtScene.fromPanel`, which is for the
    /// desktop strip. That method treats the column as a left-side obstruction of the full
    /// frame height, so the safe zone between it and the record would be only a few per
    /// cent wide and right next to the record, which is where a face must not be. Here the
    /// column runs along the foot, not down the side.
    private var scene: ArtScene {
        let width = Double(glass.width), height = Double(glass.height)

        let clearRight = (width - height * Double(Self.discDiameter) / 2) / max(1, width)

        // The measured column height already includes its foot gap, so nothing is
        // subtracted twice. Before the first layout a placeholder value (0.6) is used,
        // and the measurement replaces it one frame later.
        let clearBottom = columnHeight > 0 ? (height - columnHeight) / max(1, height) : 0.6

        // Nothing covers the top: the stage is landscape, where an iPhone shows no status bar.
        return ArtScene.forClearLeft(width: width, height: height, clearTop: 0,
                                     clearRight: clearRight, clearBottom: clearBottom)
    }

    /// The key of the backdrop task. The frame shape is part of the key, because a photograph
    /// cropped for one shape is wrong for another. Turning the phone runs the task again, and
    /// the store crops again from bytes it already has, without downloading anything.
    private struct Wanted: Equatable {
        let artist: String?
        let scene: ArtScene
    }

    /// The scale of the record when it has flown off, and the flight duration in seconds.
    /// They match the desktop's `Turntable.ExitScale` and `ArtDisplay.TransitionSeconds`.
    private static let exitScale: CGFloat = 0.24
    private static let flight: Double = 0.42

    /// Which record belongs on the deck, **as a comparable value and not as the pictures
    /// themselves**. The cover is decoded again for every track of an album, so a key made
    /// of the picture would treat each track as a new record. It compares the same three
    /// things as ``RecordFace/isSameRecord(as:)``.
    private struct WantedRecord: Equatable {
        let album: String
        let hue: RGB?
        let hasLabel: Bool

        /// Whether there IS a photographed disc, not which one. This is the same reason
        /// ``RecordFace/isSameRecord(as:)`` compares it this way: the picture is decoded
        /// again for each track, and comparing the decoded pictures would treat every
        /// track of an album as a new record.
        let hasDisc: Bool
    }

    /// **Every field comes from the one `playing` value.** If some fields came from the
    /// player and some from the pictures, the deck would be told the record changed when
    /// the TRACK changes, before the new cover exists. The record would then fly in with
    /// the previous album's cover and fly out again when the right one arrives. With one
    /// value, the old record stays on the deck a little longer, which is the intended
    /// behaviour for a record change.
    private var wantedRecord: WantedRecord {
        WantedRecord(album: playing?.album ?? "",
                     hue: art?.accent?.base ?? VinylPressing.houseHue,
                     hasLabel: art?.image != nil,
                     hasDisc: playing?.disc != nil)
    }

    /// Carries out what a `Move` asks for.
    ///
    /// The completion of the flight animation asks the turntable for the next move, not a
    /// timer of the same length. They are not the same: the moment the record lifts is when
    /// this screen is busiest, and a timer that fires while the disc is still at a third of
    /// its opacity would change the face of a record that is still visible.
    private func carry(_ move: Move) {
        if move.dress { turntable.dressed() }

        guard move.fly != .stay else { return }

        turntable.flying(move.fly)
        let inbound = move.fly == .drop

        withAnimation(.easeInOut(duration: Self.flight), completionCriteria: .logicallyComplete) {
            aloft = !inbound
        } completion: {
            carry(turntable.landed())
        }
    }

    /// The name whose photographs are shown. A station has no artist, so its own name is
    /// used, and the catalogues return whatever they have for it.
    private var artistKey: String? { player.current?.artist ?? player.station?.display }

    // MARK: Record

    private func disc(in size: CGSize) -> some View {
        let diameter = size.height * Self.discDiameter

        // **The face the record is WEARING now, not the face that is wanted.** The two
        // are the same except during the flight in between, and that case is the reason
        // for this code: see ``RecordChange``.
        let worn = turntable.worn

        return RecordDisc(diameter: diameter, halo: .round,
                          // It turns only if the record is still ON the screen (not moved
                          // away with the chrome) and sound is actually playing. When
                          // playback stalls while buffering, the record stops, instead of
                          // turning while no sound comes out.
                          spinning: chromeUp && player.isPlaying,
                          hue: worn.hue,
                          label: worn.label,
                          disc: worn.cd)
            // Off the deck it is about a quarter of its size and invisible (same values as the desktop).
            .scaleEffect(aloft ? Self.exitScale : 1)
            .opacity(aloft ? 0 : 1)
            // The centre is on the right edge, vertically centred, as on the desktop.
            // The label is the album cover, as in the Uno app, and the vinyl around it
            // takes its colour from the cover.
            .position(x: size.width + (chromeUp ? 0 : diameter * Self.discAway),
                      y: size.height / 2)
            .allowsHitTesting(false)
            // The record that belongs on the deck is decided by the album, not the track.
            // The next track of an album is the same record, and a disc that came off for
            // every track would be tiring to watch.
            .task(id: wantedRecord) {
                // **Press the vinyl first, then change the face.** The pressing is a
                // filter pass over a 1000 by 1000 pixel image, and the record is only off
                // the deck while this runs. Changing the face first would bring in a disc
                // that still has the previous album's colour and then change it while it
                // lands. Each colour is pressed only once, so the second track of an album
                // finds it already done.
                _ = await VinylPressing.press(wantedRecord.hue)

                carry(turntable.wear(RecordFace(album: wantedRecord.album,
                                                hue: wantedRecord.hue,
                                                label: art?.image,
                                                cd: playing?.disc)))
            }
    }

    private var scrim: some View {
        LinearGradient(
            stops: [.init(color: RPMInk.ground.opacity(0xCC / 255), location: 0),
                    .init(color: RPMInk.ground.opacity(0x73 / 255), location: 0.45),
                    .init(color: RPMInk.ground.opacity(0x1A / 255), location: 1)],
            startPoint: .leading, endPoint: .trailing)
            .allowsHitTesting(false)
    }

    // MARK: Chrome

    private var chrome: some View {
        ZStack {
            keys.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            column.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }

    /// The buttons for the screen and not for the music: the speaker picker and the way
    /// back to portrait.
    private var keys: some View {
        HStack(spacing: 10) {
            key { Self.say("the visualiser key"); showingLooks = true } label: {
                Text(StageLook.ribbon.glyph)
                    .font(RPMFont.icon(15))
                    .foregroundStyle(look == .artwork ? RPMInk.white(0xB8 / 255) : .white)
            }
            .accessibilityLabel(Loc.get("Rpm_Stage_Visualiser"))

            if onSpeakers != nil {
                key { showingSpeakers = true } label: {
                    CastMark(live: playingOn != nil)
                        .fill(playingOn == nil ? RPMInk.white(0xB8 / 255) : .white)
                        .frame(width: 15, height: 15)
                }
                .accessibilityLabel(playingOn.map { Loc.get("Rpm_Cast_Playing", $0) }
                                    ?? Loc.get("Rpm_Cast_PlayOn"))
            }

            // Pins the chrome visible. It is lit while pinned, like the visualiser button beside it.
            key { pinned.toggle(); showChrome() } label: {
                Text(Glyph.pin)
                    .font(RPMFont.icon(15))
                    .foregroundStyle(pinned ? .white : RPMInk.white(0xB8 / 255))
            }
            .accessibilityLabel(Loc.get(pinned ? "Rpm_Stage_PinOff" : "Rpm_Stage_PinOn"))

            key { StageOrientation.requestPortrait() } label: {
                Text(Glyph.compress)
                    .font(RPMFont.icon(15))
                    .foregroundStyle(RPMInk.white(0xB8 / 255))
            }
            .accessibilityLabel(Loc.get("Rpm_Stage_Portrait"))
        }
        .padding(.leading, Self.columnInset)
        .padding(.top, 14)
    }

    /// The column of album cover, track details and transport buttons. It runs down the
    /// left and along the bottom, as on the desktop, away from the record.
    private var column: some View {
        VStack(alignment: .leading, spacing: 2) {
            cover.padding(.bottom, 12)

            // This is the one screen in the app whose text is sized to be read from a
            // distance, not from hand-held range.
            Text(title)
                .font(RPMFont.displayBold(34))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text(said)
                .font(RPMFont.display(18))
                .foregroundStyle(RPMInk.white(0xB3 / 255))
                .lineLimit(1)

            Text(player.current?.album ?? "")
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0x77 / 255))
                .lineLimit(1)
                .padding(.top, 2)

            PlayerNeedle(player: player, playingOn: playingOn, liveLine: .leading)
                .padding(.top, 14)

            transport
        }
        .frame(maxWidth: Self.columnWidest, alignment: .leading)
        .padding(.leading, Self.columnInset)
        .padding(.bottom, Self.columnFoot)
        // Measured including the foot gap: the column covers the picture with its text AND
        // the empty space below it, and a crop that put a face in that space would still
        // hide it behind the transport buttons.
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: ColumnHeight.self, value: Double(geo.size.height))
            }
        }
    }

    /// The small album cover. It only identifies the album, because the large record on
    /// the right is already the main picture of this screen.
    ///
    /// With no cover it shows the placeholder used on every other screen: the card and the
    /// record glyph. It does not show a still record, because the turning record is on the
    /// right and two records on one screen would be redundant.
    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0x22 / 255))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
                }

            if let art {
                Image(decorative: art.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.coverEdge, height: Self.coverEdge)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Text(Glyph.record)
                    .font(RPMFont.icon(22))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: Self.coverEdge, height: Self.coverEdge)
    }

    /// The transport row is left-aligned, not centred, because the column is on the left
    /// of the screen and a centred row would not line up with it.
    ///
    /// The negative inset makes the row line up. A transport button is a circle with a
    /// glyph in the middle, so a row flush with the column would start its first GLYPH
    /// about half a button width to the right of the seek bar's left end, and the glyph is
    /// what the user sees, not the invisible circle. Moving the row back by that gap puts
    /// the tip of the rewind arrow at the start of the bar.
    private var transport: some View {
        HStack(spacing: 18) {
            transportKey(Glyph.backward) { Task { await player.previous() } }
                .opacity(player.onTheRadio ? 0.3 : 1)
                .disabled(player.onTheRadio)

            // This shows what the user asked for, not what is playing: while a track is
            // opening, the engine has nothing loaded. See `Transport`.
            BusyKey(busy: player.isBusy, ring: 20) {
                Button { player.toggle(); showChrome() } label: {
                    Text(player.wantsToPlay ? Glyph.pause : Glyph.play)
                        .font(RPMFont.icon(20))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(nothingLoaded)
            }

            transportKey(Glyph.forward) { Task { await player.next() } }
                .opacity(player.hasNext ? 1 : 0.3)
                .disabled(!player.hasNext)

            transportKey(Glyph.stop) { player.stop(); showChrome() }
                .opacity(nothingLoaded ? 0.3 : 1)
                .disabled(nothingLoaded)
        }
        .padding(.leading, -16)
        .padding(.top, 10)
    }

    private var nothingLoaded: Bool { player.current == nil && player.station == nil }

    /// When the `RPM_STAGE_DIAG` environment variable is set, the stage logs what it was
    /// asked to do. The picker is a panel over a visualiser and a phone accepts no
    /// synthetic taps, so otherwise the only way to know what a button did is to look at
    /// the screen later and guess.
    private static let diag = ProcessInfo.processInfo.environment["RPM_STAGE_DIAG"] != nil
    private static let log = Logger(subsystem: "com.rpm.player", category: "stage")

    private static func say(_ what: String) {
        guard diag else { return }

        log.notice("\(what, privacy: .public)")
    }

    /// Starts the clock for the selected look and connects the audio input for that look.
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

    // MARK: Text

    /// A station announces what it is playing itself: the song title is shown above the
    /// station's own name. The player sheet reads the values the same way, and the two
    /// screens must always agree about what is playing.
    private var title: String {
        guard let station = player.station else { return player.current?.title ?? Loc.get("Rpm_NowPlaying_Nothing") }

        let (_, said) = IcyTitle.split(player.announced)
        return said ?? station.display
    }

    private var said: String {
        guard let station = player.station else { return player.current?.artist ?? "" }

        let (artist, _) = IcyTitle.split(player.announced)
        return artist ?? station.display
    }

    // MARK: Hiding the chrome

    /// A tap on the picture shows or hides the chrome.
    ///
    /// **In the Uno app a tap only shows the chrome. Here it toggles, on purpose.** The
    /// stage is the screen a user props on an amp and views from across a room. A tap is the
    /// only thing they can reach from there, and making them wait six seconds to see the
    /// record uncovered would be an unnecessary delay.
    private func tapped() {
        guard chromeUp, !pinned else { showChrome(); return }

        hideChrome(asked: true)
    }

    private func showChrome() {
        chromeUp = true
        idle?.cancel()

        // When pinned there is no countdown at all. That is what pinned means.
        guard !pinned else { idle = nil; return }

        // The countdown restarts on every call: each tap gives the chrome another six
        // seconds.
        idle = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.idleSeconds))
            guard !Task.isCancelled else { return }

            hideChrome()
        }
    }

    /// Hides the chrome, and the record moves away with it off the right edge, which it
    /// is already half over. What remains is the picture behind it, fully visible.
    /// - Parameter asked: `true` when the user asked for this by tapping, `false` when the
    ///   countdown ran out. The countdown must check that there is something worth showing;
    ///   a tap does not.
    private func hideChrome(asked: Bool = false) {
        // Never while pinned. That is what the pin button is for.
        guard !pinned else { return }

        // Never while nothing is loaded: there is no record to look at, and hiding the
        // buttons would leave the user no way out of the screen.
        guard !nothingLoaded else { return }

        // Never while a picker is open: the picker is a panel about this screen, and the
        // chrome hiding behind it while the user reads it would be confusing.
        guard !showingLooks, !showingSpeakers else { return }

        // The countdown hides the chrome only when there is something worth seeing
        // behind it. A tap is different: a user who taps the text away has decided that the
        // ground is what they want to see, and the next tap brings the text back.
        guard asked || somethingToShow else { return }

        chromeUp = false
        idle?.cancel()
        idle = nil
    }

    /// Whether there is anything behind the chrome worth revealing.
    ///
    /// That means a running visualiser or the artist's photograph. If the catalogues have
    /// nothing for the artist, only the plain ground is left, and hiding the text over it
    /// would leave a blank screen where the user has to tap to see what is playing.
    private var somethingToShow: Bool { look != .artwork || deck.picture != nil }

    // MARK: Buttons

    private func key<Mark: View>(_ press: @escaping () -> Void,
                                 @ViewBuilder label: () -> Mark) -> some View {
        Button(action: press) { label() }
            .buttonStyle(RPMGlassKey(edge: 40))
    }

    private func transportKey(_ glyph: String, _ press: @escaping () -> Void) -> some View {
        Button {
            press()
            showChrome()
        } label: {
            Text(glyph)
                .font(RPMFont.icon(16))
                .foregroundStyle(RPMInk.white(0xB8 / 255))
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// The height of the text column, passed up from the layout so the crop knows what covers
/// the foot of the picture.
private struct ColumnHeight: PreferenceKey {
    static let defaultValue: Double = 0

    static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
}
