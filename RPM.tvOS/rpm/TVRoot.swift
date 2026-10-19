import SwiftUI
import AVFoundation
import RPMKit
import RPMLibrary
import RPMArt
import RPMRadio
import RPMSession
import RPMSharedUI

/// The whole screen: the room under everything, the screens over it, and what is over those
/// (the player, the line along the bottom, the stats, the opening).
struct TVRoot: View {
    @Environment(TVModel.self) private var model
    @Environment(\.scenePhase) private var phase
    @State private var screens = Screens()
    @State private var saver = Screensaver()

    /// Shown over everything from launch until the first library is ready, then faded away.
    @State private var opening = true
    @State private var openingFades = false
    @State private var sound = OpeningSound()
    /// What the opening hands over to, set when there is something to show. The opening hands
    /// over at the end of the sweep's pass after that.
    @State private var arrival: Arrival?
    /// The answer for home that is being warmed for the opening, and the last one whose warm-up
    /// ended.
    @State private var warming: HomeScreen?
    @State private var warmed: HomeScreen?
    @Environment(\.displayScale) private var scale

    private enum Arrival { case home, other }

    var body: some View {
        ZStack {
            RoomLayer(collection: !screens.playerShown, screensaver: saver.shown)
                .environment(screens)

            Group {
                switch model.standing {
                case .starting:
                    Color.clear
                case .signedOut:
                    SignInView()
                case .loading:
                    Waiting(Loc.get("Rpm_Library_Loading"))
                case .showing:
                    Shell()
                }
            }
            .environment(screens)
            .environment(saver)
            .opacity(saver.shown ? 0 : 1)
            .animation(.easeInOut(duration: saver.shown ? 1.5 : 0.4), value: saver.shown)

            FlashLine(text: model.flashText, count: model.flashCount)
                .opacity(saver.shown ? 0 : 1)

            // The one line about the network, as the phone's OfflineBar. It is over the screens and
            // does not push them down. It is at the top right, where the sidebar's pill is not.
            if !model.reading.isOnline {
                Label(Loc.get("Rpm_Net_Offline"), systemImage: "wifi.slash")
                    .font(.tv(Size.small, .semibold))
                    .foregroundStyle(Ink.words)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, Size.side)
                    .padding(.top, 50)
                    .opacity(saver.shown ? 0 : 1)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            // At the top right, because the top left has the sidebar's pill.
            if model.settings.showStats {
                StatsOverlay()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, 40)
                    .padding(.top, 30)
            }

            if opening {
                OpeningSplash(ready: arrival != nil, fading: openingFades, onSwept: finishOpening)
            }

            PictureLayers(look: model.settings.picture)
        }
        .ignoresSafeArea()
        // Passed down to the views that fetch a picture. It decides whether to fetch, and not
        // what to draw.
        .environment(\.rpmReach, model.reading)
        .animation(.easeInOut(duration: 0.3), value: model.reading.isOnline)
        .background(PressWatcher.app(saver: saver, screens: screens))
        .onPlayPauseCommand { model.togglePlay() }
        .task(id: model.settings.screensaverMinutes) { await saver.watch(minutes: model.settings.screensaverMinutes) }
        .onChange(of: model.standing) { _, now in
            if now == .signedOut { screens.reset() }
            handOver()
        }
        .onChange(of: model.session.home) { _, _ in handOver() }
        .onChange(of: model.session.playlistStanding) { _, _ in handOver() }
        .onChange(of: model.session.wallStanding) { _, now in
            handOver()
            // A borrowed collection that cannot be read: if the share has been withdrawn, go back
            // to the account's own collection with a notice, as the Android TV app does, and do not
            // show an error with a Retry key that cannot succeed.
            guard case .trouble = now, !model.session.viewing.isOwn else { return }
            Task {
                await model.session.readShares()
                let viewing = model.session.viewing
                guard !viewing.isOwn, !model.session.isShared(viewing) else { return }
                screens.paths = [:]
                screens.tab = .home
                await model.session.open(.own)
                model.flash(Loc.get("Rpm_Error_ShareUnavailable"))
            }
        }
        .onChange(of: model.player.isPlaying) { _, playing in
            if playing { sound.stop() }
            keepTheScreenOn()
            // A pause is where the needle stays for the next launch.
            model.keepTheQueue()
        }
        .onChange(of: model.player.index) { _, _ in model.keepTheQueue() }
        .onChange(of: model.player.queue.count) { _, _ in model.keepTheQueue() }
        .onChange(of: model.player.station) { _, _ in model.keepTheQueue() }
        .task(id: model.player.isPlaying) {
            // Also at intervals while playing, so a TV that is switched off at the power socket
            // loses at most this much of its position.
            guard model.player.isPlaying else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                model.keepTheQueue()
            }
        }
        .onChange(of: phase) { _, now in
            if now == .active {
                saver.pressed()
                model.cameToTheFront()
            } else {
                sound.stop()
                model.keepTheQueue()
                if now == .background {
                    // The record on the deck is counted before the app becomes inactive, and the log
                    // is written before tvOS can end the process, as on the phone.
                    model.player.settlePlay()
                    Task { await model.plays.save() }
                }
            }
        }
        .task {
            // The wait has a limit: a library that never arrives still hands over to its message.
            try? await Task.sleep(for: .seconds(12))
            arrive(.other)
        }
    }

    /// The opening hands over when there is something to show: the signed-out screen, the complete
    /// home screen, or the library's own failure.
    ///
    /// Home is complete when the home on screen has its first pictures (``TVModel/warmHome(scale:)``)
    /// and its lists have been read. Home is worked out again when the lists arrive, and they can
    /// change the cards of the banner. Each new answer for home is warmed. The answer that is still
    /// current when its warm-up ends, with the lists read, hands over. Four seconds after the first
    /// warm-up began, the opening hands over with whatever is ready, and the rest fades in on home.
    private func handOver() {
        switch model.standing {
        case .signedOut: arrive(.other)
        case .showing:
            if let home = model.session.home {
                // The opening does not wait for this. Putting the queue back opens its track, which
                // takes network time and is not part of the opening.
                Task { await model.putBackTheQueue() }
                // This is for the opening only. Home is worked out again later (when a library is
                // read again), and warming it then would help nobody.
                guard arrival == nil else { return }
                if warmed == home { homeIfWhole(); return }
                guard warming != home else { return }
                if warming == nil {
                    Task {
                        try? await Task.sleep(for: .seconds(4))
                        arriveHome()
                    }
                }
                warming = home
                Task {
                    await model.warmHome(scale: scale)
                    warmed = home
                    homeIfWhole()
                }
            }
            else if case .trouble = model.session.wallStanding { arrive(.other) }
            else if model.session.wallStanding == .showing, model.session.albums.isEmpty { arrive(.other) }
        default: break
        }
    }

    /// Hands over to home if the home on screen is the one warmed and its lists have been read.
    private func homeIfWhole() {
        guard let home = model.session.home, warmed == home,
              model.session.playlistStanding != .reading else { return }
        arriveHome()
    }

    private func arriveHome() {
        guard arrival == nil, model.standing == .showing, model.session.home != nil else { return }
        // Move into home while the opening still covers it. The tabs appear with nothing on home
        // to focus, so the focus starts in the sidebar, and the sidebar closes under the opening
        // and not in front of the person.
        if screens.openingUp { screens.giveFocusBack() }
        arrive(.home)
    }

    /// The first answer is used: the opening is told only once.
    private func arrive(_ what: Arrival) {
        guard arrival == nil else { return }
        arrival = what
    }

    /// The sweep has finished its pass: the opening fades and home appears under it.
    private func finishOpening() {
        guard opening, !openingFades else { return }
        openingFades = true
        screens.openingUp = false
        // The flourish plays as home fades in, as on the desktop. It does not play over a failure
        // or over music that is already playing.
        if arrival == .home, !model.player.isPlaying { sound.play() }
        if arrival == .home { Task { await model.warmRows(scale: scale) } }
        Task {
            try? await Task.sleep(for: .seconds(OpeningSplash.fade + 0.1))
            opening = false
        }
    }

    /// The system's screensaver stays off while music plays. The room is this app's own screensaver,
    /// and a key press brings the screens back from it.
    private func keepTheScreenOn() {
        UIApplication.shared.isIdleTimerDisabled = model.player.isPlaying
    }
}

/// The room behind every screen. It is lit from what is playing, or from the page on top when one
/// is open. On the collection screens it is under a flat shade.
struct RoomLayer: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens

    private var room: RoomReader { screens.room }

    /// The colours of the logo of the playing station, for a room lit by a station.
    @State private var stationColours = Wearing()

    let collection: Bool
    /// Whether the screensaver is shown. It shows the moving room, whatever the pages are drawn on
    /// (as in the Android TV app, so a still background gives way to the moving room).
    let screensaver: Bool

    private var wanted: SleeveColours? {
        screens.pageColours ?? model.record.art?.colours ?? model.player.station.flatMap { stationColours.of($0, edge: 96) }
    }

    var body: some View {
        let still = model.settings.background != .moving && !screensaver
        ZStack {
            Ink.ground
            if RoomView.works {
                // Stopped while a still background covers it on the pages.
                RoomView(colours: room.colours, sound: room.ramp, foot: 1, running: !(collection && still),
                         breathes: false, zero: .whenShown, seed: "stage")
            }
            Ink.scrim.opacity(collection ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: collection)

            // The still background of the pages (the Background setting). The player keeps the room.
            PageBackdrop(background: model.settings.background)
                .opacity(collection && still ? 1 : 0)
                .animation(.easeInOut(duration: 0.35), value: collection)
                // It goes away with the screens when the screensaver starts, and returns with them.
                .animation(.easeInOut(duration: screensaver ? 1.5 : 0.4), value: screensaver)

            // A station has no sleeve, so the colours of its logo light the room. They are read from
            // a logo that nobody sees, so the room has them on every screen.
            if let station = model.player.station {
                StationLogo(station: station, edge: 96, onWearing: { stationColours.said($0, by: station) })
                    .opacity(0)
                    .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            room.start(with: model.player)
            paint()
        }
        .onChange(of: wanted) { _, _ in paint() }
    }

    private func paint() {
        let lit = wanted
        room.paint(tint: lit?.dominant, glow: lit?.highlight, shade: lit?.shade)
    }
}

/// The still background of the pages: the desktop app's backdrop under the shade of the collection
/// screens, or the flat anthracite as it is (as `BackdropPicture` in the Android TV app). It shows
/// nothing for the moving room.
struct PageBackdrop: View {
    let background: PageBackground

    /// The anthracite colour of the dark background, #28282D.
    static let anthracite = Color(red: 0x28 / 255, green: 0x28 / 255, blue: 0x2D / 255)

    @State private var picture: UIImage?
    @State private var pictureOf: PageBackground?

    var body: some View {
        ZStack {
            switch background {
            case .dark:
                Self.anthracite
            case .still, .pegasus:
                if pictureOf == background, let picture {
                    Image(uiImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                    Ink.scrim
                }
            case .moving:
                Color.clear
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task(id: background) {
            guard let name = background.picture,
                  let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { return }
            let read = await Task.detached(priority: .userInitiated) { UIImage(contentsOfFile: url.path) }.value
            guard !Task.isCancelled else { return }
            picture = read
            pictureOf = background
        }
    }
}

/// The Picture setting over the screens: the colours are pulled toward grey by `saturation`, then
/// every colour is multiplied by `light`. These are two layers over what is drawn, so the setting
/// does not change anything under them.
struct PictureLayers: View {
    let look: PictureLook

    var body: some View {
        ZStack {
            Color.gray.blendMode(.saturation).opacity(1 - look.saturation)
            Color.black.opacity(1 - look.light)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// A whole screen that is waiting: the turning record and the thing that it waits for.
struct Waiting: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        VStack(spacing: 32) {
            RecordSpinner(diameter: 120)
            Text(text)
                .font(.tv(Size.note))
                .foregroundStyle(Ink.dim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The opening (the same design as the Android TV app): the rpm wordmark on black, dimmed, with a
/// band of light that sweeps across it from left to right once a second, lighting the letters that
/// it passes, and repeats until the app has something to show.
///
/// It hands over at the end of a pass, never in the middle of one. When `ready` is true, it waits
/// for the current pass to end, with the band clear of the letters, and calls `onSwept`. The caller
/// then sets `fading`, and the opening fades out.
///
/// **The sweep and the fade are Core Animation animations, played by the render server**, and not
/// frames drawn on the main thread. The opening is shown while the library is read and home is
/// built, which blocks the main thread for hundreds of milliseconds at a time, and an animation
/// drawn on the main thread would stop for as long.
struct OpeningSplash: View {
    let ready: Bool
    let fading: Bool
    let onSwept: () -> Void

    /// The duration of one pass of the band, in seconds.
    static let pass: Double = 1
    /// How long the opening takes to fade after it has handed over.
    static let fade: Double = 0.6

    /// When the first pass began, on the clock of Core Animation. The passes are counted from it.
    @State private var began = CACurrentMediaTime()

    var body: some View {
        SweptWordmark(began: began, fading: fading)
            .ignoresSafeArea()
            .task(id: ready) {
                guard ready else { return }
                let into = (CACurrentMediaTime() - began).truncatingRemainder(dividingBy: Self.pass)
                try? await Task.sleep(for: .seconds(Self.pass - into))
                guard !Task.isCancelled else { return }
                onSwept()
            }
    }
}

/// The layers of the opening: the dimmed wordmark, the lit wordmark under a mask that is the band,
/// the position of the band animated across, and the whole thing faded at the end.
private struct SweptWordmark: UIViewRepresentable {
    let began: CFTimeInterval
    let fading: Bool

    func makeUIView(context: Context) -> SweptView { SweptView(began: began) }

    func updateUIView(_ view: SweptView, context: Context) {
        if fading { view.fade() }
    }

    final class SweptView: UIView {
        /// The width of the wordmark: 260 on a screen 1080 high.
        private static let wide: CGFloat = 260
        /// The width of the band, as a share of the width of the wordmark.
        private static let band: CGFloat = 0.6

        private let began: CFTimeInterval
        private let dim = CAShapeLayer()
        private let lit = CAShapeLayer()
        private let light = CAGradientLayer()
        private var faded = false

        init(began: CFTimeInterval) {
            self.began = began
            super.init(frame: .zero)
            backgroundColor = .black
            isUserInteractionEnabled = false
            dim.fillColor = UIColor(white: 1, alpha: 0.32).cgColor
            lit.fillColor = UIColor.white.cgColor

            // The light of the band across its width: white in the middle and nothing at either
            // edge, falling along a smootherstep curve so that no hard edge shows.
            let stops = (0...16).map { Double($0) / 16 }
            light.colors = stops.map { at in
                let x = abs(2 * at - 1)
                return UIColor(white: 1, alpha: 1 - x * x * x * (x * (x * 6 - 15) + 10)).cgColor
            }
            light.locations = stops.map { NSNumber(value: $0) }
            light.startPoint = CGPoint(x: 0, y: 0.5)
            light.endPoint = CGPoint(x: 1, y: 0.5)
            lit.mask = light

            layer.addSublayer(dim)
            layer.addSublayer(lit)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        override func layoutSubviews() {
            super.layoutSubviews()
            let size = CGSize(width: Self.wide, height: Self.wide / RPMWordmark.aspect)
            let place = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2,
                               width: size.width, height: size.height)
            let band = Self.band * Self.wide
            let path = RPMWordmark().path(in: CGRect(origin: .zero, size: size)).cgPath

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for shape in [dim, lit] {
                shape.frame = place
                shape.path = path
            }
            light.bounds = CGRect(x: 0, y: 0, width: band, height: size.height)
            light.position = CGPoint(x: -band / 2, y: size.height / 2)
            CATransaction.commit()

            // From fully before the first letter to fully after the last, once a second, with
            // easing at both ends (quad, as the pass in the Android TV app), counted from `began`.
            let sweep = CABasicAnimation(keyPath: "position.x")
            sweep.fromValue = -band / 2
            sweep.toValue = size.width + band / 2
            sweep.duration = OpeningSplash.pass
            sweep.repeatCount = .infinity
            sweep.timingFunction = CAMediaTimingFunction(controlPoints: 0.455, 0.03, 0.515, 0.955)
            sweep.beginTime = light.convertTime(began, from: nil)
            if !faded { light.add(sweep, forKey: "sweep") }
        }

        func fade() {
            guard !faded else { return }
            faded = true
            // The fade starts as a pass ends, with the band clear of the letters, so no next pass
            // starts under it.
            light.removeAnimation(forKey: "sweep")
            let out = CABasicAnimation(keyPath: "opacity")
            out.fromValue = 1
            out.toValue = 0
            out.duration = OpeningSplash.fade
            out.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.opacity = 0
            layer.add(out, forKey: "fade")
        }
    }
}

/// The opening flourish, played once when home first appears.
@MainActor
final class OpeningSound {
    private var player: AVAudioPlayer?

    func play() {
        guard let url = Bundle.main.url(forResource: "rpm-open", withExtension: "mp3"),
              let made = try? AVAudioPlayer(contentsOf: url) else { return }
        player = made
        made.volume = 0.8
        made.play()
    }

    func stop() {
        player?.stop()
        player = nil
    }
}

/// The result of a menu's write, shown for a moment along the bottom of the screen. It fades in
/// over 140 ms, stays for 2.6 s, and fades out over 320 ms. A new `count` shows it again with the
/// same words.
struct FlashLine: View {
    let text: String?
    let count: Int

    @State private var shown = false

    var body: some View {
        VStack {
            Spacer()
            if let text {
                Text(text)
                    .font(.tv(Size.row))
                    .foregroundStyle(Ink.card)
                    .lineLimit(2)
                    .padding(.horizontal, 32)
                    .padding(.vertical, 16)
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(.bottom, 70)
                    .opacity(shown ? 1 : 0)
            }
        }
        .allowsHitTesting(false)
        .task(id: count) {
            guard count > 0 else { return }
            withAnimation(.easeOut(duration: 0.14)) { shown = true }
            try? await Task.sleep(for: .milliseconds(2600))
            withAnimation(.easeIn(duration: 0.32)) { shown = false }
        }
    }
}
