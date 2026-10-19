import SwiftUI
import RPMSharedUI
import QuartzCore
import RPMKit
import RPMAudio
import RPMRadio
import RPMArt
import RPMDesign
import RPMStages

/// The player, shown over whatever the phone was already showing.
///
/// Ported from `RPM.Mobile/Presentation/NowPlayingSheet.xaml`. It shows the record, the text
/// about it (title, artist and lyrics), the seek bar, the transport keys, and the spectrum
/// that extends from both sides of the cover.
///
/// **Behind the cover is the room**, the same as in the desktop app and the Uno phone app,
/// drawn here in Metal (see ``RoomView``). The room is the background once it is shown, and
/// two backgrounds on top of each other would be too much, so the blurred cover underneath is
/// hidden. Where the room cannot be drawn, the blurred cover is the background.
///
/// The background is the same as on the album page, on purpose: the player and the album page
/// are two views of the same record, and a player with a different colour from the page it
/// opened from would look like a different app.
public struct NowPlayingSheet: View {
    private let player: Player
    private let art: CoverArt?

    /// The lyrics of what is playing, or `.empty` when there are none, which greys out the lyrics
    /// key. The owner of the record looks them up, and this view only draws them.
    private let lyrics: LyricSheet

    /// Whether the lyrics lookup is still running. This is the one state where the lyrics key
    /// is neither lit nor greyed out.
    private let lookingUpLyrics: Bool

    /// Requests the lyrics. It is called when the player is shown and when the record changes.
    /// **Nothing is requested while the player is hidden**, so normal listening sends no record
    /// name to any service.
    private let onNeedLyrics: () async -> Void

    private let marked: Bool
    private let onMark: (Bool) -> Void

    /// **Whether the player is shown, and its current position.** One value is used for both
    /// opening and closing the player, and the owner of the sheet holds it. See ``ScreenPull``,
    /// which explains why it is not two values.
    @Binding private var pull: ScreenPull

    /// The two actions for what is playing. Nil when the caller has nowhere to send them.
    ///
    /// **The queue is not one of them.** It belongs to what is already on this screen, so it
    /// opens over the sheet and does not navigate to another screen.
    private let onFile: (() -> Void)?
    private let onAlbum: (() -> Void)?

    /// Opens the page of the artist that is playing. Nil when the library has no page for them.
    private let onArtist: (() -> Void)?

    /// Reads the music for the room and for the spectrum next to the cover. It belongs to this
    /// sheet and starts and stops with it. The reader holds the audio engine's tap, and a tap
    /// that keeps running while nobody sees the picture only heats the phone.
    @State private var room = RoomReader()

    /// The colours of the station's square while a station is playing. See ``stationWears(_:)``.
    @State private var stationColours: SleeveColours?

    /// Whether the sheet is on the screen. The room's clock depends only on this. A shader that
    /// keeps drawing behind a hidden sheet only heats the phone.
    @State private var showing = false

    /// The y position of the bottom edge of the cover, in the sheet's own points. The room is
    /// dimmed below this line, because the text is there.
    ///
    /// It is measured and not calculated: the cover is centred in the space that the grip and
    /// the other controls leave, so only the layout knows where it ends. The Uno phone app gives
    /// its room the same value for the same reason (`PushCover`).
    @State private var foot: Double = 0

    /// The name of the coordinate space that the cover's box is measured in.
    private static let sheet = "sheet"

    /// The queue drawer: whether it is shown, and how far it has been pulled down. It is the same
    /// kind of value as the one that holds the player itself, one level further in.
    @State private var queue = ScreenPull()

    /// Whether the lyrics are shown in place of the cover.
    ///
    /// In debug builds a script can open it through `Harness`, as it can open the player itself.
    /// The simulator cannot receive synthetic taps, so otherwise a screen behind a key can only
    /// be reached by hand. See `RootView.openWhereTheScriptAsked`.
    @State private var showingLyrics = Harness.opensLyrics
    @State private var showingSpeakers = false

    /// Whether the user asked for the sleep timer drawer. It is shown only while a timer is
    /// running, so the drawer closes when the timer ends.
    @State private var showingSleepTimer = false

    /// How far a finger has pushed the cover sideways, and in which direction it will go.
    @State private var flick: CGFloat = 0

    /// The name of the room the sound is going to, or nil for the phone itself.
    private let playingOn: String?

    /// The speaker picker, built by the owner of the speakers. Nil when casting is not offered,
    /// and then the key is not shown on the sheet.
    private let onSpeakers: ((@escaping () -> Void) -> AnyView)?

    public init(player: Player, art: CoverArt?, marked: Bool,
                lyrics: LyricSheet = .empty, lookingUpLyrics: Bool = false,
                onNeedLyrics: @escaping () async -> Void = {},
                onMark: @escaping (Bool) -> Void, pull: Binding<ScreenPull>,
                onFile: (() -> Void)? = nil,
                onAlbum: (() -> Void)? = nil,
                onArtist: (() -> Void)?,
                playingOn: String? = nil,
                onSpeakers: ((@escaping () -> Void) -> AnyView)? = nil) {
        self.player = player
        self.art = art
        self.lyrics = lyrics
        self.lookingUpLyrics = lookingUpLyrics
        self.onNeedLyrics = onNeedLyrics
        self.marked = marked
        self.onMark = onMark
        self._pull = pull
        self.onFile = onFile
        self.onAlbum = onAlbum
        self.onArtist = onArtist
        self.playingOn = playingOn
        self.onSpeakers = onSpeakers
    }

    public var body: some View {
        VStack(spacing: 0) {
            grip

            // **The lyrics take the place of the cover**, as in the Uno phone app. The room behind
            // them stays, because its colours come from the record and the lyrics are read
            // against it.
            ZStack {
                if showingLyrics {
                    // **No part of the cover is shown during the intro.** A fade that depends
                    // on the playback position (which changes four times a second) would show the
                    // artwork on the lyrics screen and then remove it in steps. A user who opens
                    // the lyrics wants to see lyrics, and the intro shows what the intro IS. See
                    // `LyricView.opening`.
                    LyricView(sheet: lyrics, player: player)
                } else {
                    cover
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            chrome
        }
        .animation(.easeOut(duration: 0.25), value: showingLyrics)
        // Requested when the player is shown and again when the record changes. **Only while it
        // is shown**: normal listening sends no record name to any service.
        .task(id: player.current?.rpmId) {
            await onNeedLyrics()
        }
        // The lyrics were shown for a record that turns out to have none. Go back to the cover
        // and do not leave the user on an empty screen.
        .onChange(of: lyrics) { _, now in
            if showingLyrics && !now.isSynced && !lookingUpLyrics { showingLyrics = false }
        }
        // **The background and overlays are modifiers and not siblings in a stack**, which is the
        // same rule as on the album page and for the same reason. The background ignores the
        // safe area. As a sibling it would make the whole STACK extend to the screen edges, so
        // the grip would be laid out behind the sheet's own top edge and the transport under the
        // home indicator. A background has the size of the view it belongs to and takes no part
        // in its layout.
        .background {
            // **Square against the top of the screen, and rounded as soon as it moves away from
            // it**, like every card that is put down on this phone. The corners are cut on the
            // background and not on the sheet, because the background is the only part that is
            // drawn to the screen edges. A clip on the sheet would use its layout frame, which is
            // inside the safe area. It is a mask and not a clip for the same reason: the shape
            // must be allowed to extend past the safe area to meet the corners that it rounds.
            ground.mask {
                UnevenRoundedRectangle(topLeadingRadius: rounding, topTrailingRadius: rounding,
                                       style: .continuous)
                    .ignoresSafeArea()
            }
        }
        // **The player is full screen, so closing it is handled by this app.** A system sheet
        // has its own swipe to close. Here the player covers the whole shell, including the tab
        // bar, and the grip at the top puts it away. So the grip handles the gesture.
        //
        // **The whole screen moves with the finger**, as `SheetShift` does in the Uno phone app,
        // and the background moves with it: see ``SwiftUI/View/pulledDown(_:)``.
        // **Every touch on the player stops at the player**, including the edges past the safe
        // area. Without this, only the controls would take a touch, and a touch between them
        // (beside the title, around the cover) would go through to the page underneath. A tap
        // there would start that page's track row, and a long press would open the row's menu.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
        }
        .pulledDown(pull)
        // Always present: the drawer has its own `if`, next to its transitions. See
        // ``QueueOverlay``.
        .overlay { QueueOverlay(player: player, pull: $queue) }
        .overlay {
            if showingSpeakers, let onSpeakers {
                onSpeakers { showingSpeakers = false }
            }
        }
        .overlay {
            if showingSleepTimer, player.sleepTimer.isOn {
                SleepTimerSheet(player: player) { showingSleepTimer = false }
            }
        }
        // Start with the sheet and stop with it. `stop` is the only way to release the tap,
        // because the reader cannot do it in a `deinit`, so this pair is required and is not
        // only for convenience.
        .coordinateSpace(name: Self.sheet)
        .onPreferenceChange(SleeveFoot.self) { where_ in foot = where_ }
        .onAppear {
            showing = true
            room.start(with: player)
            let lit = art?.colours ?? stationColours
            room.paint(tint: lit?.dominant, glow: lit?.highlight, shade: lit?.shade)
        }
        .onDisappear {
            showing = false
            room.stop(player)
        }
        // The colours arrive after the sheet: a cover is decoded off the main thread, so it often
        // arrives a moment later, and it arrives again on every track change. The room changes
        // gradually to the new colours, so the change is a dissolve.
        .onChange(of: art?.colours) { _, now in
            let lit = now ?? stationColours
            room.paint(tint: lit?.dominant, glow: lit?.highlight, shade: lit?.shade)
        }
        // A station has no cover, so the room uses the colours of the station's square, including
        // its generated background, and this gives the room something to react to. The colours
        // are cleared when the station ends, so they do not mix with the next record's cover.
        .onChange(of: player.station?.uuid) { _, now in
            if now == nil { stationColours = nil }
        }
    }

    /// The station's square shows its logo, with a generated background where it needs one. This
    /// colours the room with those colours while no cover is shown.
    private func stationWears(_ colours: SleeveColours) {
        stationColours = colours
        guard art == nil else { return }
        room.paint(tint: colours.dominant, glow: colours.highlight, shade: colours.shade)
    }

    /// The spectrum, extending from both sides of the cover.
    ///
    /// **It is measured against the cover as it is drawn**, including the paused scale. The cover
    /// is drawn a tenth smaller when playback stops, and a spectrum that kept the playing size
    /// would be separated from the cover. The Uno phone app gives its room the same rectangle for
    /// the same reason (`PushCover`).
    private var spectrum: some View {
        // **Drawn at the screen's refresh rate, measured at the reader's rate.** A new spectrum
        // arrives forty times a second, because that is what the shortest analysis window
        // detects. This clock asks `RoomRamp` for the spectrum at the moment each frame is drawn,
        // so a 120 Hz screen draws 120 frames per second. The clock is paused when the sheet is
        // hidden, like the room behind it, because a clock that keeps running while nobody sees
        // the picture only heats the phone.
        TimelineView(.animation(paused: !showing)) { _ in
            SpectrumRunView(run: room.ramp.read(CACurrentMediaTime()).run,
                            side: Self.sleeveEdge * (player.isPlaying ? 1 : Self.pausedScale),
                            shift: flick, sides: .both,
                            tint: RGB(room.palette.tint), glow: RGB(room.palette.glow))
                // The same two animations as the cover, repeated exactly. The spectrum is
                // measured against the cover as it is DRAWN, so it must use the same springs.
                // See `SpectrumRunView.animatableData`.
                .animation(.spring(duration: 0.35), value: player.isPlaying)
                .animation(.spring(duration: 0.3), value: flick)
        }
    }

    // ── the background ──

    @ViewBuilder
    private var ground: some View {
        if RoomView.works {
            // The room IS the background once it is shown, and two backgrounds on top of each
            // other would be too much. It runs while the sheet is shown and stops with it.
            //
            // The foot is converted to a fraction of the sheet's own height, which is the height
            // that the cover was measured in. The room draws past that into the safe area
            // insets, so the line is a few per cent too low. The line is under a ramp about a
            // quarter of the screen deep, so measuring both exactly would give no visible
            // benefit.
            GeometryReader { geo in
                RoomView(colours: room.colours,
                         sound: room.ramp,
                         foot: foot > 0 ? foot / geo.size.height : 1,
                         running: showing,
                         // This is the one room in the app that IS the record being played, so
                         // the record lights it and it does not breathe on its own.
                         breathes: false, zero: .whenShown, seed: "stage")
            }
        } else {
            fallbackGround
        }
    }

    /// The background used where the room cannot be drawn: the app's grooves, the blurred cover
    /// over them, and the desktop app's ink colour down the frame.
    private var fallbackGround: some View {
        ZStack {
            // The app's own background under it. A sheet is its own window and cannot see what
            // is behind the app, so it draws the grooves itself.
            VinylGround()

            if let art {
                Color.clear
                    .overlay {
                        Image(decorative: art.image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 60, opaque: true)
                    }
                    .clipped()
                    .overlay(art.accent?.base.color.opacity(0.18) ?? .clear)
            }

            LinearGradient(
                stops: [.init(color: .black.opacity(0x59 / 255), location: 0),
                        .init(color: .black.opacity(0x8C / 255), location: 0.42),
                        .init(color: .black.opacity(0xBF / 255), location: 1)],
                startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.25), value: art?.image.width)
    }

    /// The radius of the top corners: **square against the top of the screen, and rounded as soon
    /// as it moves away from it**, like every card that is put down on this phone. The radius is
    /// full while the sheet is leaving, whether the user dragged it away or tapped to close it.
    /// See ``ScreenPull/putDown``.
    private var rounding: CGFloat { pull.putDown * 44 }

    /// The whole strip takes the tap, not only the bar drawn in it. A bar five points high is
    /// too small to touch.
    private var grip: some View {
        Color.clear
            .frame(height: 44)
            .overlay { Grabber() }
            // Pull it down to put the player away, or tap it. All of the behaviour is in
            // ``SwiftUI/View/pullGrip(_:)``.
            .pullGrip($pull)
            // The key is over the grip and not in a row of its own. The grip already takes
            // forty-four points of height, and a second bar at the top of a sheet would use the
            // full width of the phone for one key.
            //
            // **It is hidden while the sheet is being put away.** A sheet that is leaving shows
            // only its own edge and the grip, not a key that nobody will press. The finger is
            // already on the grip, and a key with square corners inside a corner that is being
            // rounded would look inconsistent.
            .overlay(alignment: .trailing) {
                speakerKey
                    .opacity(1 - pull.putDown)
                    .allowsHitTesting(pull.putDown == 0)
            }
    }

    /// Shows where the sound is going. It is lit when the sound goes to another device.
    ///
    /// **The key shows only that**, and the room's name is not on it. The Uno phone app puts
    /// "Playing on Kitchen" in the status line over the seek bar, where buffering and errors are
    /// also shown, and a name beside the key would show the same information twice. See
    /// `PlayerNeedle`.
    @ViewBuilder
    private var speakerKey: some View {
        if onSpeakers != nil {
            Button { showingSpeakers = true } label: {
                // The Cast mark and not a speaker glyph, as in the Uno phone app and the desktop
                // app. A speaker glyph shows what makes the sound, and this key is about where
                // the sound goes. The screen shape is filled when a room is playing the sound,
                // and the colour changes to white. The Uno phone app draws the same two states.
                CastMark(live: playingOn != nil)
                    .fill(playingOn == nil ? RPMInk.white(0xB8 / 255) : .white)
                    .frame(width: 17, height: 17)
            }
            // The same key as in the Uno phone app: 40 by 40 points, 12 points from the edge.
            .buttonStyle(RPMGlassKey(edge: 40))
            .padding(.trailing, 12)
            .accessibilityLabel(playingOn.map { Loc.get("Rpm_Cast_Playing", $0) }
                                ?? Loc.get("Rpm_Cast_PlayOn"))
        }
    }

    // ── the record ──

    /// The size of the cover, and the scale it shrinks to when the record is not playing. They
    /// are named constants and not written into the frame, because the spectrum next to the
    /// cover is measured against both.
    private static let sleeveEdge: CGFloat = 260
    private static let pausedScale: CGFloat = 0.9

    /// The cover in the space it is given, with the spectrum drawn in the margins on both sides.
    /// It uses the full width because the spectrum needs those margins. The cover keeps its own
    /// size and stays centred, so the centre line that the spectrum is mirrored about is still
    /// the cover's.
    private var cover: some View {
        sleeve
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { spectrum }
    }

    /// The cover, square and centred. It has full size while the record is playing and is drawn a
    /// tenth smaller when paused, so a stopped record is a smaller object on the screen and the
    /// room around it becomes more visible.
    ///
    /// A swipe across it goes to the next track or the previous one.
    private var sleeve: some View {
        let edge = Self.sleeveEdge

        return ZStack {

            // No cover and no card: show the record disc, not spinning. **Nothing playing at all
            // also comes here**, so an idle screen shows a waiting record and not an empty frame
            // with a glyph in it.
            if art == nil && player.station == nil {
                RecordDisc(diameter: edge, halo: .round, spinning: false)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0x22 / 255))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
                    }
            }

            if let art {
                Sleeve(image: Image(decorative: art.image, scale: 1))
                    .frame(width: edge, height: edge)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let station = player.station {
                // The station's own logo, as the desktop app draws it here, inset so it sits ON the
                // card and does not fill it. The logo is a square mark on its own background, not
                // a cover.
                //
                // The call sign is shown instead for stations whose logo address no longer works.
                // These are the letters that the radio dial is printed with, and an empty field of
                // 260 points would look like a hole and not like a placeholder.
                StationFace(station: station, edge: edge, inset: edge * 0.16,
                            onWearing: stationWears) {
                    VStack(spacing: 10) {
                        Text(Glyph.radio)
                            .font(RPMFont.icon(48))
                            .foregroundStyle(RPMInk.white(0x3A / 255))

                        Text(StationSign.of(station.display))
                            .font(.system(size: 34, weight: .semibold))
                            .tracking(4)
                            .foregroundStyle(RPMInk.cyan.opacity(0.85))
                    }
                }
                // The background behind a transparent logo fills the card, so it is clipped to the
                // card and the edge is drawn again over it.
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
                }
            }
        }
        .frame(width: edge, height: edge)
        .background {
            // Where the room's dimming starts: under the record. When the record is drawn a tenth
            // smaller, the line moves with it.
            GeometryReader { geo in
                // **The box measured here is the box as drawn**, including the paused scale.
                // `scaleEffect` is a geometry effect and `frame(in:)` reports the cover through
                // it, so a cover that is drawn a tenth smaller is already measured at that size.
                // Its bottom edge is therefore its own `maxY`, and the scale must not be applied
                // a second time.
                Color.clear.preference(key: SleeveFoot.self,
                                       value: geo.frame(in: .named(Self.sheet)).maxY)
            }
        }
        .scaleEffect(player.isPlaying ? 1 : Self.pausedScale)
        .offset(x: flick)
        .animation(.spring(duration: 0.35), value: player.isPlaying)
        .animation(.spring(duration: 0.3), value: flick)
        // A station has no next or previous track to go to, because it has no queue.
        .gesture(
            DragGesture(minimumDistance: 12)
                .onChanged { if !player.onTheRadio { flick = $0.translation.width } }
                .onEnded { thrown in
                    let far = abs(thrown.translation.width) > 80
                    flick = 0
                    guard far, !player.onTheRadio else { return }

                    Task {
                        if thrown.translation.width < 0 { await player.next() }
                        else { await player.previous() }
                    }
                })
    }

    // ── all text and controls on the screen ──

    private var chrome: some View {
        VStack(spacing: 4) {
            // The title, the artist and the heart key are all about the RECORD. While the lyrics
            // are shown, the lyrics are the content, and two sets of text over one room would
            // force the user to choose which to read.
            words
                .opacity(showingLyrics ? 0 : 1)
                .allowsHitTesting(!showingLyrics)
                .animation(.easeOut(duration: 0.25), value: showingLyrics)

            // The bar, the clocks and the bit rate are in a separate view. The position changes
            // four times a second, and every view that reads it is rebuilt that often. See
            // `PlayerNeedle`: an open menu in this column would be rebuilt four times a second,
            // which makes it flicker.
            PlayerNeedle(player: player, playingOn: playingOn)

            transport
            below
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// Title and artist, with the heart key beside them. The heart is about the **record** and
    /// not about how it is played. Apple's player puts it in the same place for the same reason.
    private var words: some View {
        HStack(alignment: .top, spacing: 8) {
            // A tap on either line opens the album page, the same as the menu item. It is
            // disabled when the menu item is missing: for a station, or an album that the
            // library does not have.
            Button { pull.putAway(); onAlbum?() } label: {
                VStack(alignment: .leading, spacing: 2) {
                    // Both lines scroll when they do not fit, as in the desktop app. A title that
                    // ends in an ellipsis cannot be read in full.
                    Marquee(title, font: RPMFont.displayBold(22), height: 28, ink: .white)

                    Marquee(said, font: RPMFont.display(15), height: 20,
                            ink: RPMInk.white(0xB3 / 255))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onAlbum == nil)
            .accessibilityHint(onAlbum == nil ? "" : Loc.get("AlbumMenu_AlbumPage"))

            // The heart is filled or hollow, and never changes colour.
            Button { onMark(!marked) } label: {
                Text(Glyph.heart)
                    .font(marked ? RPMFont.icon(15) : RPMFont.iconOutline(15))
                    .foregroundStyle(RPMInk.white(0xE6 / 255))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, -12)
            // A station is not a song, so it cannot be marked as a favourite. The key is hidden and
            // not greyed out, because a heart that cannot be pressed raises the question of what
            // it would do.
            .opacity(player.current == nil ? 0 : 1)
            .disabled(player.current == nil)
        }
    }

    /// A station reports what it is playing in the same two fields: the song that it announced,
    /// and below it the station's own name.
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

    /// How long the play key must be held before letting go stops playback instead of pausing.
    /// This is the system's long-press threshold, so the key responds to the same hold as every
    /// other long press on the phone.
    private static let holdsForStop: Duration = .milliseconds(500)

    /// How far a finger may move and still count as being on the key.
    private static let holdSlip: CGFloat = 40

    /// A press on the play key, from the touch down to the lift.
    ///
    /// **The lift reads this value and nothing else.** A tap and a hold are one gesture here, so
    /// what the lift means depends on the state of the press and not on which recogniser fired
    /// first. The glyph is read from the same value, so there is no second flag to keep in step
    /// with it.
    private enum Press {
        /// The finger is down but has not been held long enough. Letting go toggles play.
        case brief(watch: Task<Void, Never>)

        /// Held longer than ``holdsForStop``. The key shows stop, and letting go stops playback.
        case held

        /// The finger moved away from the key. Letting go does nothing, so the user can cancel a
        /// stop that they did not intend.
        case away
    }

    /// The current press on the play key, or nil while no finger is on it.
    @State private var press: Press?

    /// Whether there is anything for the key to act on. When nothing is playing, the key would do
    /// nothing. The app cannot reach this state, because this screen is shown only over
    /// something that is playing, but the debug harness can open the screen with nothing
    /// playing.
    private var hasSomethingOn: Bool { player.current != nil || player.station != nil }

    /// The glyph on the play key: stop once the hold is long enough that letting go would stop
    /// playback, and otherwise the state that the transport was asked for.
    private var playGlyph: String {
        if case .held = press { return Glyph.stop }

        return player.wantsToPlay ? Glyph.pause : Glyph.play
    }

    /// Tap to pause or play, hold to stop.
    ///
    /// This is one gesture and not a `Button` with a separate long press. A button also runs its
    /// own action on the lift, so a hold that turned the key into stop would also toggle play
    /// when the finger lifts.
    private var playKey: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { touch in
                // This is called when the finger goes down and again on every move. The timer
                // starts on the first call and stops when the finger is too far from the key to
                // be holding it.
                if press == nil {
                    press = .brief(watch: Task { @MainActor in
                        try? await Task.sleep(for: Self.holdsForStop)
                        guard !Task.isCancelled else { return }

                        Haptics.commit()
                        press = .held
                    })
                }

                if hypot(touch.translation.width, touch.translation.height) > Self.holdSlip {
                    cancelTheHold()
                    press = .away
                }
            }
            .onEnded { _ in
                let was = press
                cancelTheHold()
                press = nil

                switch was {
                case .brief: player.toggle()
                case .held: player.stop()
                case .away, nil: break
                }
            }
    }

    /// Cancels the timer of a press that will not become a stop.
    private func cancelTheHold() {
        if case .brief(let watch) = press { watch.cancel() }
    }

    /// The play key is in the exact centre of the screen, where a thumb can find it without
    /// looking, with the previous and next keys on either side. Nothing else is in this row: stop
    /// is a hold of the play key, not a separate key.
    private var transport: some View {
        HStack(spacing: 24) {
            key(Glyph.backward, 22) { Task { await player.previous() } }
                .opacity(player.onTheRadio ? 0.3 : 1)
                .disabled(player.onTheRadio)

            // **The glyph shows what was requested, not what is coming out.** During the second
            // that a track needs to open the engine, nothing is playing yet, so `isPlaying` is
            // false. That would turn a pause that the user just pressed back into a play key.
            // See `Transport`.
            //
            // **Stop is a hold of this key**, which is how the phone gives a button a second
            // action. Pause keeps the position, but stop removes the record: it empties the
            // queue, so the app has nothing playing, the strip at the bottom is removed, and this
            // screen closes. See ``playKey`` for the hold and `Player.stop` for what it does.
            BusyKey(busy: player.isBusy, ring: 24) {
                Text(playGlyph)
                    .font(RPMFont.icon(26))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .contentShape(Circle())
                    .gesture(playKey, including: hasSomethingOn ? .gesture : .none)
                    // The key is a `Text` and not a `Button`, so the traits and both actions are
                    // set here. VoiceOver cannot hold a key, and a glyph is not a name.
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Loc.get("Transport_PlayPause"))
                    .accessibilityAction { player.toggle() }
                    .accessibilityAction(named: Text(Loc.get("Rpm_NowPlaying_Stop"))) {
                        player.stop()
                    }
            }

            key(Glyph.forward, 22) { Task { await player.next() } }
                .opacity(player.hasNext ? 1 : 0.3)
                .disabled(!player.hasNext)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    /// The row under the transport.
    ///
    /// The desktop app has five items here: the lyrics, the stage, the queue, the speaker and a
    /// menu. In this app the speaker key is on the grip, and stop is a hold of the play key, so
    /// the row has the lyrics key, the queue key and the menu.
    ///
    /// The three share one glass capsule, the same group as the library's search and sort keys,
    /// with the same 40-point square keys inside it.
    private var below: some View {
        HStack(spacing: 0) {
            // First in the row, as in the Uno phone app: the lyrics, then what comes next.
            small("\u{f4ad}") {
                Haptics.pick()
                showingLyrics.toggle()
            }
            .accessibilityLabel(Loc.get("Details_Lyrics"))
            .foregroundStyle(showingLyrics ? .white : RPMInk.white(0x99 / 255))
            // Greyed out when there are no lyrics for this record, and lit while the lookup is
            // still running. A key that turns grey as soon as a record starts and lights up a
            // second later would look unreliable.
            .opacity(lyrics.isSynced || lookingUpLyrics ? 1 : 0.35)
            .disabled(!lyrics.isSynced)

            small("\u{f03a}") {
                Haptics.pick()
                queue.raise()
            }
            .accessibilityLabel(Loc.get("Viz_Queue"))
            .opacity(player.queue.isEmpty ? 0.35 : 1)
            .disabled(player.queue.isEmpty)

            Menu {
                if let onFile {
                    Button { pull.putAway(); onFile() } label: {
                        Label(Loc.get("Playlists_AddToPlaylist"), systemImage: "text.badge.plus")
                    }
                }
                if let onAlbum {
                    Button { pull.putAway(); onAlbum() } label: {
                        Label(Loc.get("AlbumMenu_AlbumPage"), systemImage: "square.stack")
                    }
                }
                if let onArtist {
                    Button { pull.putAway(); onArtist() } label: {
                        Label(Loc.get("Rpm_NowPlaying_ArtistPage"), systemImage: "music.mic")
                    }
                }

                sleepTimerItem
            } label: {
                Text(Glyph.more)
                    .font(RPMFont.icon(16))
                    .foregroundStyle(RPMInk.white(0x99 / 255))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            // The sleep timer is in the menu whenever anything is playing, including a station.
            .opacity(player.isOver ? 0.35 : 1)
            .disabled(player.isOver)
        }
        .rpmGlassGroup()
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    /// The sleep timer in the menu: the options while it is off, and the drawer with the time left
    /// while it runs.
    ///
    /// The time left is not shown in the menu. It changes every second, and a menu whose contents
    /// change is rebuilt by the system each time, which makes an open menu flicker (see
    /// `PlayerNeedle`).
    @ViewBuilder
    private var sleepTimerItem: some View {
        if player.sleepTimer.isOn {
            Button { showingSleepTimer = true } label: {
                Label(Loc.get("Rpm_Sleep_Title"), systemImage: "moon.zzz.fill")
            }
        } else {
            Menu {
                ForEach(SleepTimer.durations, id: \.self) { wait in
                    Button(SleepWords.after(wait)) { setSleepTimer(.after(wait)) }
                }

                // A station has no end of song to wait for.
                if !player.onTheRadio {
                    Button(Loc.get("Rpm_Sleep_EndOfSong")) { setSleepTimer(.endOfTrack) }
                }
            } label: {
                Label(Loc.get("Rpm_Sleep_Title"), systemImage: "moon.zzz")
            }
        }
    }

    private func setSleepTimer(_ choice: SleepTimer.Choice) {
        Haptics.pick()

        // A drawer that was requested for an earlier timer, which has since ended, must not be
        // shown for this new timer.
        showingSleepTimer = false
        player.setSleepTimer(choice)
    }

    private func small(_ glyph: String, _ press: @escaping () -> Void) -> some View {
        Button(action: press) {
            Text(glyph)
                .font(RPMFont.icon(16))
                .foregroundStyle(RPMInk.white(0x99 / 255))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func key(_ glyph: String, _ size: CGFloat,
                     _ press: @escaping () -> Void) -> some View {
        Button(action: press) {
            Text(glyph)
                .font(RPMFont.icon(size))
                .foregroundStyle(RPMInk.white(0xB8 / 255))
                .frame(width: 56, height: 56)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// The position of the cover's bottom edge, passed up from the layout to the room drawn behind it.
///
/// It is a preference and not a write from inside a `GeometryReader`, because the cover's box is
/// known during layout, and SwiftUI does not allow state changes there.
///
/// **"The last value wins" is not the same as "the last value that was set wins".** SwiftUI
/// combines every sibling subtree, whether or not it set this key, and a subtree that set nothing
/// contributes ``defaultValue``. With a plain `value = nextValue()`, the controls below the cover
/// would overwrite the cover's value with zero on every pass. The foot would always be zero,
/// which sets ``RoomView/foot`` to one, and then the room would light its whole area. There is
/// only one cover and it is never at the very top of the sheet, so the one value that is not the
/// default is the one that came from the cover.
private struct SleeveFoot: PreferenceKey {
    static let defaultValue: Double = 0

    static func reduce(value: inout Double, nextValue: () -> Double) {
        let next = nextValue()
        if next != defaultValue { value = next }
    }
}

/// Lets a debug script open screens that would otherwise need a finger.
enum Harness {
    static let opensLyrics: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["RPM_OPEN_LYRICS"] != nil
        #else
        return false
        #endif
    }()
}
