import SwiftUI
import RPMLibrary
import RPMKit
import RPMArt
import RPMAudio
import RPMDesign
import RPMRadio
import RPMSharedUI

/// Where the player's focus is.
enum PlayerFocus: Hashable {
    case surface, queue, back, heart, lyrics, more, previous, play, next
}

/// The player: the spread view (`PegasusLayout` on the desktop), the centred view or the room view,
/// over the room, with the remote rules of the Android TV app:
///
/// - controls hidden: select pauses and resumes, Left and Right go 10 seconds back and forward;
///   Up or Down shows the controls with the play key focused;
/// - controls shown: the remote moves the focus along the keys and up to the seek bar, where
///   Left and Right move a preview of the playhead and the seek is made when the key is released;
/// - the controls hide after 5 seconds without a key, and stay up while paused or while the queue
///   is open;
/// - Back hides the controls first, then leaves the player;
/// - the room view has no keys: select pauses and Back leaves.
///
/// The view is the one chosen in the settings. A station shows only its play key.
struct PlayerScreen: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens

    @Environment(\.displayScale) private var scale
    @State private var controlsShown = true
    @State private var queueOpen = false
    @State private var lyricsWanted = false
    @State private var playOnShown = false
    /// The measured timing of the words of the playing track, for karaoke, and the track it belongs
    /// to. It is empty until read, and for a track that has not been measured.
    @State private var measured: (rpmId: String, lines: [MeasuredLine]) = ("", [])
    /// Counts key presses, so the wait that hides the controls starts again at each press.
    @State private var presses = 0
    @FocusState private var focus: PlayerFocus?

    private var view: PlayerView { model.settings.defaultView }
    private var station: RadioStation? { model.player.station }
    private var lyricsShown: Bool { lyricsWanted && model.words.sheet.isSynced && station == nil }
    private var hasKeys: Bool { view != .room || lyricsShown }
    private var shown: Bool { controlsShown && hasKeys }
    private var paused: Bool { !model.player.isPlaying && hasKeys && (model.player.current != nil || station != nil) }

    var body: some View {
        content
            // If no measured timing covers the sheet, the cloud is asked to time it from the record
            // (the transcoder, about half a minute for a song). The answer is read after 20 s and
            // then every 15 s, at most eight times, while the track plays (as in the Android TV app).
            .task(id: MeasureAsk(rpmId: model.player.current?.rpmId, karaoke: model.karaokeOn,
                                 lines: model.words.sheet.lines.count)) {
                await readMeasured()
            }
    }

    private struct MeasureAsk: Equatable {
        let rpmId: String?
        let karaoke: Bool
        let lines: Int
    }

    private func readMeasured() async {
        let sheet = model.words.sheet
        guard model.karaokeOn, sheet.isSynced, let track = model.player.current else { return }
        let rpmId = track.rpmId
        let shelf = model.session.shelves.shelf(of: rpmId)
        let cloud = model.cloud
        func read() async -> [MeasuredLine] { (try? await cloud.lyricTiming(rpmId: rpmId, on: shelf)) ?? [] }

        var lines = await read()
        guard !Task.isCancelled else { return }
        measured = (rpmId, lines)
        if MeasuredLyrics.covers(lines, sheet: sheet) { return }

        let ask = sheet.lines.enumerated().map { SheetLine(index: $0.offset, seconds: $0.element.seconds, text: $0.element.text) }
        guard (try? await cloud.measureLyrics(rpmId: rpmId, on: shelf, lines: ask)) != nil else { return }
        for read_ in 0..<8 {
            try? await Task.sleep(for: .seconds(read_ == 0 ? 20 : 15))
            guard !Task.isCancelled else { return }
            lines = await read()
            guard !Task.isCancelled else { return }
            measured = (rpmId, lines)
            if MeasuredLyrics.covers(lines, sheet: sheet) { return }
        }
    }

    private var content: some View {
        ZStack {
            Group {
                let heard = measured.rpmId == model.player.current?.rpmId ? measured.lines : []
                // The compact view keeps its record and shows the lyrics beside it (as in the Android TV
                // app). The other views give the lyrics the whole screen.
                if lyricsShown && view != .centred {
                    LyricsView(controls: controls, karaoke: model.karaokeOn, measured: heard)
                } else {
                    switch view {
                    case .spread: SpreadView(controls: controls, controlsShown: shown)
                    case .centred: CentredView(controls: controls, controlsShown: shown, beside: lyricsShown,
                                               karaoke: model.karaokeOn, measured: heard)
                    case .room: Color.clear
                    }
                }
            }
            .offset(x: queueOpen ? 1920 * 0.36 : 0)
            .animation(.easeOut(duration: 0.25), value: queueOpen)

            // A failure is shown where the keys would be, while the keys are hidden.
            if let trouble = model.player.trouble, !shown, !model.player.reconnecting {
                Text(trouble)
                    .font(.tv(Size.small + 2))
                    .foregroundStyle(Ink.failed)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 70)
            }

            // The surface: the only focus stop while the controls are hidden. It exists only then,
            // because a full-screen view over the keys, even one that cannot take the focus, stops
            // the arrows from moving the focus between the keys.
            if !shown && !queueOpen {
                Color.clear
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($focus, equals: .surface)
                    .onMoveCommand(perform: hiddenMove)
                    .onTapGesture { toggle() }
            }

            if queueOpen {
                QueueDrawer(close: {
                    queueOpen = false
                    focus = .queue
                })
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: queueOpen)
        // When the controls appear, the surface that held the focus goes away, and tvOS chooses the
        // next focus itself before the change below is read. Without this line it chooses the seek
        // bar, the first key on the screen, and the arrows then move the playhead.
        .defaultFocus($focus, .play)
        .onPlayPauseCommand { toggle() }
        .onChange(of: focus) { _, _ in presses += 1 }
        .onChange(of: paused) { _, now in if now { showControls() } }
        .onChange(of: shown) { _, now in
            focus = now ? .play : .surface
            // The surface that held the focus is gone by the next main-queue turn, and tvOS may have
            // chosen a key of its own by then. The keys always start on play.
            if now { DispatchQueue.main.async { if shown { focus = .play } } }
        }
        .task(id: HideKey(shown: shown, presses: presses, held: held, paused: paused)) {
            guard shown, !held, !paused else { return }
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.42)) { controlsShown = false }
        }
        .task(id: model.player.current?.rpmId) {
            let track = model.player.current
            await model.words.read(track, on: model.session.shelves.shelf(of: track?.rpmId))
        }
        // More opens the artist's page. The photograph and text are prepared before the user asks.
        .task(id: model.player.current?.artist) {
            if let artist = model.player.current?.artist { await model.warmArtist(artist, scale: scale) }
        }
        .onAppear {
            focus = shown ? .play : .surface
        }
        // The focus returns to More when the picker closes. Otherwise tvOS picks the first key on
        // the screen, the seek bar, where the arrows move the playhead.
        .sheet(isPresented: $playOnShown, onDismiss: { DispatchQueue.main.async { focus = .more } }) {
            PlayOnSheet()
        }
        .onDisappear {
            queueOpen = false
            screens.playerKeysUp = false
            screens.playerDrawerOpen = false
        }
        // What Back removes first, reported to the player's controller (`Screens.backInPlayer`).
        .onChange(of: shown, initial: true) { _, now in screens.playerKeysUp = now }
        .onChange(of: queueOpen, initial: true) { _, now in screens.playerDrawerOpen = now }
        // Back with the drawer open belongs to the drawer. Otherwise Back hides the keys.
        .onChange(of: screens.playerBackAsked) { _, _ in
            guard !queueOpen, shown else { return }
            withAnimation(.easeIn(duration: 0.42)) { controlsShown = false }
        }
    }

    private struct HideKey: Hashable {
        let shown: Bool
        let presses: Int
        let held: Bool
        let paused: Bool
    }

    /// Whether the keys stay up regardless of the wait: while the queue drawer or the speaker picker
    /// is open, and while the focus is off the keys, in the menu of More. If the keys went away
    /// there, the items of that menu would be disabled. The focus returns to a key, so the keys
    /// wait for it.
    private var held: Bool { queueOpen || playOnShown || focus == nil }

    private func showControls() {
        guard hasKeys else { return }
        withAnimation(.easeOut(duration: 0.14)) { controlsShown = true }
        presses += 1
    }

    private func toggle() {
        presses += 1
        model.togglePlay()
    }

    /// The arrow keys while the controls are hidden.
    private func hiddenMove(_ direction: MoveCommandDirection) {
        presses += 1
        switch direction {
        case .left: if station == nil { model.skip(by: -SeekSteps.press) }
        case .right: if station == nil { model.skip(by: SeekSteps.press) }
        case .up, .down: showControls()
        @unknown default: break
        }
    }


    /// The seek bar and the keys, as wide as the column they are in.
    private func controls(_ width: CGFloat, _ placing: KeysPlacing) -> some View {
        VStack(spacing: 22) {
            if station == nil {
                // The highlighted background under the focus extends past the column, so the line
                // itself starts and ends where the words and the keys do.
                SeekBar(width: width + 2 * SeekBar.inset, onStep: { presses += 1 })
                    .padding(.horizontal, -SeekBar.inset)
            }
            TransportRow(width: width, placing: placing, focus: $focus, lyricsShown: lyricsShown,
                         onQueue: { queueOpen = true },
                         onLyrics: {
                             lyricsWanted.toggle()
                             // The other layout draws its own keys, so the key that was pressed is
                             // gone and tvOS would pick the first key on the screen, the seek bar.
                             // The focus moves to the lyrics key in the new layout when it exists.
                             DispatchQueue.main.async { focus = .lyrics }
                         },
                         onBack: { screens.playerShown = false },
                         onPlayOn: { playOnShown = true })
        }
        .frame(width: width)
        .opacity(shown ? 1 : 0)
        // Beside the sleeve the lines rise first and the keys fade in after them (SpreadView).
        .animation(shown ? .easeInOut(duration: 0.14).delay(placing == .atTheEnds ? SpreadView<EmptyView>.rise : 0)
                         : .easeInOut(duration: 0.42), value: shown)
        .disabled(!shown)
    }
}

// ── the layouts ──

/// The side of the sleeve for the screen: 0.38 of the height, as in `PegasusLayout` on the desktop.
private let sleeveSide: CGFloat = 1080 * 0.38

/// The spread view: the sleeve in the middle with the record coming out of it, the three lines
/// down the left over a shade, the seek bar and keys under them, and the spectrum running out of
/// the sleeve to the right only, so it never runs behind the words.
///
/// While the keys are shown, the lines and the keys are centred together. When the keys go, the
/// lines move to the middle of the screen, level with the sleeve, after the keys have faded. When
/// the keys come back, the lines rise first and the keys fade in under them.
private struct SpreadView<Controls: View>: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let controls: (CGFloat, KeysPlacing) -> Controls
    let controlsShown: Bool

    /// How long the lines take to rise, which is also how long the keys wait before they fade in.
    static var rise: Double { 0.28 }

    /// Whether the lines are in the middle of the screen, with the keys hidden.
    @State private var settled = false
    /// The height of the seek bar and keys, with the space above them.
    @State private var keysHeight: CGFloat = 0

    var body: some View {
        // The desktop app starts the column 0.075 of the width from the edge and limits it to 0.30
        // of the width. The glass keys of tvOS are wider than the desktop keys, and seven of them
        // need the space, so the column starts at the margin of the screens and ends just before
        // the sleeve.
        let left: CGFloat = Size.side
        let column = (1920 - sleeveSide) / 2 - left - sleeveSide * 0.12
        ZStack(alignment: .leading) {
            LinearGradient(stops: [.init(color: .black.opacity(0x40 / 255), location: 0),
                                   .init(color: .black.opacity(0x1F / 255), location: 0.55),
                                   .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 1920 * 0.42)

            if model.player.station == nil {
                TimelineView(.animation) { _ in
                    let room = screens.room
                    SpectrumRunView(run: room.ramp.read(CACurrentMediaTime()).run,
                                    side: sleeveSide, shift: 0, sides: .right,
                                    tint: RGB(room.palette.tint), glow: RGB(room.palette.glow))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }

            Art(side: sleeveSide)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                Spacer()
                Lines(title: sleeveSide * 0.11, align: .leading)
                controls(column, .atTheEnds)
                    .padding(.top, 24 + max(20, sleeveSide * 0.08))
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { keysHeight = $0 }
                Spacer()
            }
            .frame(width: column)
            // Down by half the height of the keys: the block is centred together with the keys,
            // so with the keys hidden the lines are moved to be centred alone.
            .offset(x: left, y: settled ? keysHeight / 2 : 0)
        }
        .ignoresSafeArea()
        .onAppear { settled = !controlsShown }
        .onChange(of: controlsShown) { _, shown in
            if shown {
                withAnimation(.easeOut(duration: Self.rise)) { settled = false }
            } else {
                // After the keys have faded (0.42 s), not while they are still visible.
                withAnimation(.easeInOut(duration: 0.5).delay(0.42)) { settled = true }
            }
        }
    }
}

/// The centred view: the sleeve in the middle, the three lines centred under it, and the seek bar
/// and keys under them. It has no shade and no spectrum.
private struct CentredView<Controls: View>: View {
    let controls: (CGFloat, KeysPlacing) -> Controls
    let controlsShown: Bool
    /// Whether the lyrics are beside the record. The record, its lines and its keys are then left
    /// of the middle and the lyrics take the right of the screen. They glide there and back while
    /// the lyrics fade in or out.
    let beside: Bool
    let karaoke: Bool
    let measured: [MeasuredLine]

    /// Where the record's group is centred, and where the lyrics start, as shares of the width, and
    /// the margin kept from the other edges of the screen (the same values as the Android TV app).
    /// The disc extends about 0.29 of the sleeve's side to the right, which with these values
    /// leaves it clear of the lyrics.
    private static var besideCentre: CGFloat { 0.27 }
    private static var besideLyrics: CGFloat { 0.52 }
    private static var besideSafe: CGFloat { 0.05 }

    var body: some View {
        let column = max(240, min(1920 * 0.56, sleeveSide * 1.5))
        let narrow = min(column, 1920 * (Self.besideLyrics - 0.04))
        ZStack {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Art(side: sleeveSide)
                Lines(title: sleeveSide * 0.10, align: .center)
                    .frame(width: beside ? narrow : column)
                    .padding(.top, max(20, sleeveSide * 0.08))
                // Wider than the lines: the space that the left keys take is also kept at the right,
                // so the transport is centred under the sleeve.
                controls(beside ? narrow : 1920 * 0.56, .centred)
                    .padding(.top, 20)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(x: beside ? 1920 * (Self.besideCentre - 0.5) : 0)

            if beside {
                LyricColumn(karaoke: karaoke, measured: measured)
                    .padding(.leading, 1920 * Self.besideLyrics)
                    .padding(.trailing, 1920 * Self.besideSafe)
                    .padding(.vertical, 1080 * Self.besideSafe)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45), value: beside)
        .ignoresSafeArea()
    }
}

/// The record and its sleeve, with the disc extending 0.312 of the side to the right and turning
/// while it plays. For a station, the station's logo is in the sleeve and there is no record.
private struct Art: View {
    @Environment(TVModel.self) private var model
    let side: CGFloat

    var body: some View {
        let playing = model.record.playing
        let art = playing?.art
        let frame = art?.colours.dominant.map { Color(red: Double($0.r) / 255, green: Double($0.g) / 255, blue: Double($0.b) / 255) }
            ?? Color(red: 0x12 / 255, green: 0x16 / 255, blue: 0x1E / 255)
        let border = max(1, (side * 2 * 0.014).rounded() / 2)

        ZStack {
            if let station = model.player.station {
                StationLogo(station: station, edge: side, corner: max(2, side * 0.012), inset: 34)
                    .overlay {
                        RoundedRectangle(cornerRadius: max(2, side * 0.012), style: .continuous)
                            .strokeBorder(frame, lineWidth: border)
                    }
            } else {
                RecordDisc(diameter: side * 0.96, halo: .cast, spinning: model.player.isPlaying,
                           hue: art?.accent?.base ?? VinylPressing.houseHue,
                           label: art?.image, disc: playing?.disc)
                    .offset(x: side * 0.312)
                ZStack {
                    Color(red: 0x0A / 255, green: 0x0A / 255, blue: 0x0A / 255)
                    if let art {
                        Image(decorative: art.image, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .padding(border)
                            .transition(.opacity)
                    }
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: max(2, side * 0.012), style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: max(2, side * 0.012), style: .continuous)
                        .strokeBorder(frame, lineWidth: border)
                }
                .animation(.easeInOut(duration: 0.9), value: art?.image)
            }
        }
        .frame(width: side, height: side)
    }
}

/// The title, artist and album at sizes 1 : 0.75 : 0.62, in white, then softer, then softer still.
/// For a station, the first line is what it announces, or else its name. The second line is the
/// announced artist. The third line is the station's name when something is announced.
/// Reconnecting and an ad break are shown on the second line.
private struct Lines: View {
    @Environment(TVModel.self) private var model
    let title: CGFloat
    let align: HorizontalAlignment

    var body: some View {
        let (first, second, third) = lines
        VStack(alignment: align, spacing: 4) {
            line(first, title, .semibold, Ink.words)
            line(second, title * 0.75, .regular, Ink.artist)
            line(third, title * 0.62, .regular, Ink.album)
            // Where the sound goes, while it is on a speaker, as the phone's player shows it.
            if let speaker = model.player.castingTo {
                Label(Loc.get("Rpm_Cast_Playing", speaker.name), systemImage: "hifispeaker.fill")
                    .font(.tv(title * 0.5, .semibold))
                    .foregroundStyle(Ink.words)
                    .lineLimit(1)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: align, vertical: .center))
    }

    private func line(_ text: String, _ size: CGFloat, _ weight: Font.Weight, _ colour: Color) -> some View {
        Marquee(text: text.isEmpty ? " " : text, font: .tv(size, weight), colour: colour,
                align: Alignment(horizontal: align, vertical: .center))
    }

    private var lines: (String, String, String) {
        let player = model.player
        guard let station = player.station else {
            let track = player.current
            return (track?.title ?? "", track?.artist ?? "", track?.album ?? "")
        }
        if player.reconnecting { return (station.display, Loc.get("Radio_Reconnecting"), "") }
        if RadioAds.isAdBreak(player.announced) { return (station.display, Loc.get("Radio_AdBreak"), "") }
        let said = IcyTitle.split(player.announced)
        if let title = said.title, !title.isEmpty { return (title, said.artist ?? "", station.display) }
        return (station.display, "", "")
    }
}

// ── the keys ──

/// How the keys stand in their row.
enum KeysPlacing {
    /// Beside the sleeve (the spread view): the left keys are at the left end of the column and the
    /// transport is at the right end. Both ends line up with the ends of the seek bar, and neither
    /// moves when the heart key or the lyrics key appears or disappears.
    case atTheEnds
    /// Under a centred column (the centred and lyrics views): the space that the left keys take is
    /// also kept at the right, so the transport is centred.
    case centred
}

/// The keys under the seek bar (as `TransportRow` on the desktop). At the left are the queue, the
/// way back, the heart and, when there are synced lyrics, the lyrics key. Then come previous, play
/// or pause, and next. A station shows the play key alone, centred. The keys use Liquid Glass.
private struct TransportRow: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let width: CGFloat
    let placing: KeysPlacing
    let focus: FocusState<PlayerFocus?>.Binding
    let lyricsShown: Bool
    let onQueue: () -> Void
    let onLyrics: () -> Void
    let onBack: () -> Void
    let onPlayOn: () -> Void

    /// The size of a key's glyph box, and the glass around it (measured on the simulator: the
    /// glass adds 31).
    private static let key: CGFloat = 32
    private static let play: CGFloat = 52
    private static let glass: CGFloat = 31
    private static let inGroup: CGFloat = 10
    private static let inTransport: CGFloat = 24
    /// The space that five left keys take. It is kept whether or not the heart and lyrics keys are
    /// shown.
    private static let leftRoom: CGFloat = 5 * (key + glass) + 4 * inGroup

    var body: some View {
        let station = model.player.station != nil
        Group {
            if station {
                playKey
                    .frame(maxWidth: .infinity)
            } else {
                switch placing {
                case .atTheEnds:
                    HStack(spacing: 0) {
                        leftKeys
                        Spacer(minLength: 0)
                        transport
                    }
                case .centred:
                    HStack(spacing: 0) {
                        leftKeys
                        Spacer(minLength: 0)
                        transport
                        Spacer(minLength: 0)
                        Color.clear.frame(width: Self.leftRoom, height: 1)
                    }
                }
            }
        }
        .frame(width: width)
        .focusSection()
    }

    private var leftKeys: some View {
        let player = model.player
        return HStack(spacing: Self.inGroup) {
            key("list.bullet", Loc.get("Viz_Queue"), .queue, action: onQueue)
            key("arrow.left", Loc.get("Viz_BackToLibrary"), .back, action: onBack)
            if let track = player.current, model.session.isTrackMine(track) {
                let marked = model.session.isTrackMarked(track)
                key(marked ? "heart.fill" : "heart", marked ? Loc.get("Track_UnsetFavorite") : Loc.get("Track_SetFavorite"),
                    .heart, tint: marked ? Ink.loved : nil) { model.mark(track, !marked) }
            }
            if model.words.sheet.isSynced {
                key(lyricsShown ? "quote.bubble.fill" : "quote.bubble",
                    lyricsShown ? Loc.get("Viz_LyricsBack") : Loc.get("Viz_Lyrics"), .lyrics, action: onLyrics)
            }
            moreKey
        }
        .frame(width: Self.leftRoom, alignment: .leading)
    }

    /// More, as on the phone's player: the record's page, the artist's page, Add to playlist, and
    /// the sleep timer. The pages close the player and open on the screen under it.
    private var moreKey: some View {
        let player = model.player
        return Menu {
            if let track = player.current {
                let album = model.session.albums.first { $0.key == AlbumGrouping.key(for: track) }
                if let album {
                    Button(Loc.get("AlbumMenu_AlbumPage"), systemImage: "square.stack") {
                        screens.leavePlayer(for: .album(album.key))
                    }
                }
                let artist = album?.artist ?? track.artist ?? ""
                if !artist.isEmpty {
                    Button(Loc.get("Rpm_NowPlaying_ArtistPage"), systemImage: "music.mic") {
                        screens.leavePlayer(for: .artist(artist))
                    }
                }
                if model.session.isTrackMine(track) {
                    AddToPlaylistMenu(track: track)
                }
            }
            // Where the sound plays, as the phone's speaker key.
            Button(Loc.get("Rpm_Cast_PlayOn"), systemImage: "hifispeaker.2", action: onPlayOn)
            SleepTimerMenu()
        } label: {
            Image(systemName: player.sleepTimer.isOn ? "moon.zzz.fill" : "ellipsis")
                .font(.system(size: 20))
                .frame(width: Self.key, height: Self.key)
        }
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .focused(focus, equals: .more)
        .accessibilityLabel(Loc.get("Player_More"))
    }

    private var transport: some View {
        HStack(spacing: Self.inTransport) {
            key("backward.fill", Loc.get("Transport_Previous"), .previous) { Task { await model.player.previous() } }
            playKey
            key("forward.fill", Loc.get("Transport_Next"), .next) { Task { await model.player.next() } }
        }
    }

    private var playKey: some View {
        let player = model.player
        let station = player.station != nil
        return Button { model.togglePlay() } label: {
            Image(systemName: player.isPlaying ? (station ? "stop.fill" : "pause.fill") : "play.fill")
                .font(.system(size: 28))
                .frame(width: Self.play, height: Self.play)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .focused(focus, equals: .play)
        .accessibilityLabel(Loc.get("Transport_PlayPause"))
    }

    private func key(_ symbol: String, _ label: String, _ which: PlayerFocus, tint: Color? = nil,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 20))
                .keyTint(tint)
                .frame(width: Self.key, height: Self.key)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .focused(focus, equals: which)
        .accessibilityLabel(label)
    }
}

// ── the lyrics ──

/// The lyrics alone: the column is centred over the room, the line being sung stays in the
/// middle, and the lines around it fade by their distance from it. The seek bar and keys are at
/// the bottom.
private struct LyricsView<Controls: View>: View {
    let controls: (CGFloat, KeysPlacing) -> Controls
    let karaoke: Bool
    let measured: [MeasuredLine]

    var body: some View {
        let column = min(1920 * 0.78, 1400)
        ZStack(alignment: .bottom) {
            LyricColumn(karaoke: karaoke, measured: measured)
                .frame(width: column)
                .frame(maxHeight: .infinity)
            controls(column, .centred)
                .padding(.bottom, max(32, 1080 * 0.045))
        }
        .ignoresSafeArea()
    }
}

/// The lyric column (as "Lyrics" on the desktop): the sung line is white, and the opacity of the
/// other lines falls with distance: 1, 0.42, 0.24 and 0.12. Before the first line, the first line
/// is at 0.55 and the rest fall from 0.34. The song scrolls the column and the user does not. The
/// lit line is chosen for each frame from the position of the player.
private struct LyricColumn: View {
    @Environment(TVModel.self) private var model
    /// Whether the sung line lights word by word. It uses the moments measured from the record if
    /// they exist (`measured`), and otherwise spreads the words across the line by length
    /// (`LyricTiming`, the sweep of the desktop app).
    let karaoke: Bool
    let measured: [MeasuredLine]

    /// How many pieces on each side of the sung one are still shown.
    private static let reach = 3

    var body: some View {
        let sheet = model.words.sheet
        let size = min(max(1080 * 0.030, 15), 34) * 1.4
        // Every frame for karaoke, where the words light up within a line, and four times a
        // second otherwise.
        TimelineView(.periodic(from: .now, by: karaoke ? 1.0 / 30 : 0.25)) { _ in
            // The sheet is cut into stretches and rests (as the phone's LyricView does). Every
            // opacity changes only when the playhead reaches a new piece.
            let score = LyricScore.of(sheet)
            let position = model.player.position.seconds
            let at = karaoke ? Self.held(score.index(at: position), position, score: score, measured: measured)
                             : score.index(at: position)
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    LazyVStack(spacing: size * 0.62) {
                        ForEach(score.parts) { part in
                            row(part, of: score, at: at, position: position, size: size)
                                .id(part.id)
                        }
                    }
                    .padding(.vertical, 540)
                    .frame(maxWidth: .infinity)
                }
                .scrollDisabled(true)
                .onChange(of: at) { _, now in
                    withAnimation(.easeInOut(duration: 0.45)) { proxy.scrollTo(now ?? 0, anchor: .center) }
                }
                .onAppear { proxy.scrollTo(at ?? 0, anchor: .center) }
                // Before the first line: the song itself and the dots that count in to it.
                .overlay {
                    if at == nil { opening(sheet: sheet, position: position, size: size) }
                }
                .animation(.easeOut(duration: 0.35), value: at == nil)
            }
        }
        .allowsHitTesting(false)
    }

    /// The screen before the first line: whose song this is, and how much of the
    /// opening is left. This is only for the first break: a break in the middle shows the dots alone.
    private func opening(sheet: LyricSheet, position: Double, size: CGFloat) -> some View {
        let first = sheet.lines.first?.seconds ?? 0
        let countIn = first > 0 ? min(max(position / first, 0), 1) : 1
        return VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text(model.player.current?.title ?? "")
                    .font(.tv(size, .semibold))
                    .foregroundStyle(.white)
                Text(model.player.current?.artist ?? "")
                    .font(.tv(size * 0.82, .medium))
                    .foregroundStyle(Color(white: 0xEA / 255).opacity(0.66))
            }
            .multilineTextAlignment(.center)
            .lineLimit(3)
            LyricDots(through: countIn)
        }
    }

    @ViewBuilder
    private func row(_ part: LyricScore.Part, of score: LyricScore, at: Int?,
                     position: Double, size: CGFloat) -> some View {
        let here = at.map { score.parts[$0] }
        let distance = abs(part.id - (at ?? 0))
        let sung = part.id == at
        // During a rest only its dots are shown, and the words before it are hidden.
        let resting = here?.piece.isRest == true
        let ours = part.section == here?.section

        switch part.piece {
        case .rest(let from, let until):
            LyricDots(through: Self.through(from: from, until: until, position: position))
                .opacity(ours ? Self.fade(distance, started: at != nil) : 0)
                .animation(.easeOut(duration: 0.35), value: at)
        case .words(let line):
            Text(sung && karaoke ? Self.sweep(line, next: Self.next(after: part, in: score), measured: measured, now: position)
                                 : AttributedString(line.text))
                // The same weight on every line, sung or not. Brightness shows which line is
                // sung, so no line wraps differently on the beat.
                .font(.tv(size, .semibold))
                .foregroundStyle(sung ? Color.white : Color(white: 0xEA / 255))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .opacity(ours && !resting ? Self.fade(distance, started: at != nil) : 0)
                .animation(.easeOut(duration: 0.35), value: at)
        }
    }

    // ── karaoke ──

    /// The brightness of a word of the karaoke line that is not sung yet.
    private static let unsung = 0x73 / 255.0
    /// How long a word takes to brighten, in seconds, centred on its moment. The word starts to
    /// light a little before its moment, so the light reaches the word and not after it.
    private static let lightSeconds = 0.24

    /// The moment when the piece after `part` starts, or infinity after the last piece.
    static func next(after part: LyricScore.Part, in score: LyricScore) -> Double {
        let after = part.id + 1
        return score.parts.indices.contains(after) ? score.parts[after].seconds : .infinity
    }

    /// The measured words of a piece, if it is a line that the record was measured for.
    static func heard(_ part: LyricScore.Part, measured: [MeasuredLine]) -> [WordSpan]? {
        guard case .words(let line) = part.piece else { return nil }
        return MeasuredLyrics.forLine(measured, text: line.text, seconds: line.seconds)
    }

    /// The piece to show at `seconds`, given the piece that the time stamps give. This is the
    /// previous line while its measured words are still being sung and the words of this line have
    /// not started. A time stamp often comes before the last word of the line before it, and moving
    /// on at the stamp would leave that word unlit (the same rule as the Android TV app).
    static func held(_ piece: Int?, _ seconds: Double, score: LyricScore, measured: [MeasuredLine]) -> Int? {
        guard let piece, piece >= 1, !measured.isEmpty else { return piece }
        guard let before = heard(score.parts[piece - 1], measured: measured), let last = before.last,
              last.to > seconds else { return piece }
        if let starts = heard(score.parts[piece], measured: measured)?.first?.from, starts <= seconds { return piece }
        return piece - 1
    }

    /// The sung line for karaoke: the words already sung are white, the word being sung brightens
    /// across ``lightSeconds`` as it arrives, and the rest are faint.
    static func sweep(_ line: LyricLine, next: Double, measured: [MeasuredLine], now: Double) -> AttributedString {
        let spans = MeasuredLyrics.forLine(measured, text: line.text, seconds: line.seconds)
            ?? LyricTiming.sweep(line.text, from: line.seconds, until: next)
        let characters = Array(line.text)
        var out = AttributedString()
        var at = 0
        func piece(_ from: Int, _ to: Int, _ lit: Double) {
            guard to > from else { return }
            var run = AttributedString(String(characters[from..<to]))
            run.foregroundColor = Color.white.opacity(unsung + (1 - unsung) * lit)
            out.append(run)
        }
        for span in spans {
            piece(at, span.start, 0)
            let lit = min(max((now - (span.from - lightSeconds / 2)) / lightSeconds, 0), 1)
            piece(span.start, min(span.start + span.length, characters.count), lit)
            at = min(span.start + span.length, characters.count)
        }
        piece(at, characters.count, 0)
        return out
    }

    /// The opacity by distance from the sung line: 1, 0.42, 0.24, then 0.12 up to `reach`, then
    /// nothing. It is zero before the first line.
    static func fade(_ distance: Int, started: Bool) -> Double {
        guard started else { return 0 }
        switch distance {
        case 0: return 1
        case 1: return 0.42
        case 2: return 0.24
        default: return distance <= reach ? 0.12 : 0
        }
    }

    /// How far through a rest the record is, from zero to one, based on the playhead. A rest with
    /// no end (after the last line) never fills.
    static func through(from: Double, until: Double, position: Double) -> Double {
        let run = until - from
        guard run.isFinite, run > 0 else { return 0 }
        return min(max((position - from) / run, 0), 1)
    }
}

/// The three dots of a break. They fill in across the break, each with its share of the break, so
/// that together they look like one bar filling (as on the phone).
private struct LyricDots: View {
    let through: Double

    var body: some View {
        HStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { dot in
                let share = min(max(through * 3 - Double(dot), 0), 1)
                Circle()
                    .fill(Color.white.opacity(0.16 + 0.84 * share))
                    .frame(width: 14, height: 14)
            }
        }
        .frame(maxWidth: .infinity)
        // The playhead is read four times a second. A linear animation over exactly that interval
        // fills smoothly.
        .animation(.linear(duration: 0.25), value: through)
    }
}

/// One line that moves across its box when it does not fit (as `Marquee` on the desktop and the
/// player lines of the Android TV app do). It waits 10 seconds, moves to its end, rests 2 seconds,
/// and goes back, and repeats. A line that fits stays where `align` puts it.
struct Marquee: View {
    let text: String
    let font: Font
    let colour: Color
    let align: Alignment

    /// The width of the line itself, and the width of the box.
    @State private var full: CGFloat = 0
    @State private var box: CGFloat = 0
    @State private var offset: CGFloat = 0

    /// Points per second: the 21 dp of the Android TV app at its half scale.
    private static let pace: CGFloat = 42

    var body: some View {
        // The size of the line comes from a hidden copy that truncates, so it is never wider than
        // the space offered. The moving text is an overlay, which has no effect on the size. A
        // fixed-size text in the layout would widen the whole column of the player and push its
        // keys off the screen.
        Text(text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: align)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { box = $0 }
            .overlay(alignment: full > box ? .leading : align) {
                Text(text)
                    .font(font)
                    .foregroundStyle(colour)
                    .lineLimit(1)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { full = $0 }
                    .offset(x: offset)
            }
            .clipped()
            .task(id: Walk(text: text, full: full, box: box)) {
                offset = 0
                guard box > 0, full > box + 1 else { return }
                let travel = full - box
                let seconds = Double(travel / Self.pace)
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(10))
                    guard !Task.isCancelled else { return }
                    withAnimation(.linear(duration: seconds)) { offset = -travel }
                    try? await Task.sleep(for: .seconds(seconds + 2))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 0.4)) { offset = 0 }
                }
            }
    }

    private struct Walk: Hashable {
        let text: String
        let full: CGFloat
        let box: CGFloat
    }
}
