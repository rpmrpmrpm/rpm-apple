import SwiftUI
import UIKit
import RPMKit
import RPMLibrary
import RPMSharedUI

/// The album wall as a carousel, the other way to show it (the Android TV's
/// `AlbumCarousel.kt`): the covers stand along an arc on a black ground under a soft light, the
/// one in front facing the reader and largest, the rest turned toward it and tilted along the
/// arc as it falls away to both sides, dimmed but the front one. Under it a card names the
/// record in front: its title, its artist, and its year, track count, length and format.
///
/// It never ends: Right after the last record is the first. Left and Right move it one record, over
/// ``tick``; Select opens the record in front. Up opens a wheel of the letters the wall runs through (the
/// decades, sorted by year), on the same arc over the covers blurred; Left and Right turn it, and Select or
/// Down jumps to the first record of the letter in front and closes it; Up from it leaves for the keys
/// above, and Back closes it. Which record is in front is kept by the albums screen (`front`), so Back from
/// a record comes back to it.
struct AlbumCarousel: View {
    @Environment(Screens.self) private var screens
    let albums: [CloudAlbum]
    let order: AlbumOrdering
    @Binding var front: Int

    /// Where the carousel stands, in records: what it is moving to. The covers are keyed by their place,
    /// so a step moves each one to the next place, animated.
    @State private var going = 0
    @State private var started = false
    @State private var wheelOpen = false
    @State private var wheelGoing = 0

    /// How long one step takes: a slow tick.
    static let tick = 0.52

    var body: some View {
        let letters = Self.letters(albums, order)
        GeometryReader { box in
            let wide = box.size.width, high = box.size.height
            let edge = high * Self.cardShare
            let middleY = high * Self.arcMiddle
            let radius = wide * Self.arcRadius
            ZStack(alignment: .topLeading) {
                ground(wide: wide, middleY: middleY, edge: edge, radius: radius)

                ZStack(alignment: .topLeading) {
                    ForEach(going - Self.slots...going + Self.slots, id: \.self) { slot in
                        let k = Double(slot - going)
                        cover(albumAt(slot), k: k, edge: edge, radius: radius)
                            .position(x: wide / 2, y: middleY)
                            .zIndex(Double(Self.slots + 1) - abs(k))
                    }
                }
                .blur(radius: wheelOpen ? 18 : 0)

                // As wide as its words, up to this: the room offered is the limit, and the card does
                // not stretch to it.
                frontCard(albumAt(going))
                    .frame(width: min(wide, 1100))
                    .position(x: wide / 2, y: middleY + edge / 2 + Self.infoGap + 60)
                    .opacity(wheelOpen ? 0 : 1)

                if wheelOpen, !letters.isEmpty {
                    Color.black.opacity(0.2)
                    LetterWheel(letters: letters.map(\.letter), at: wheelGoing,
                                tile: high * Self.letterShare, middleY: high * Self.letterMiddle,
                                wide: wide, radius: radius)
                        .transition(.opacity)
                }

                // Below the screen's keys, so Up from it finds them.
                CarouselKeys(wheelOpen: wheelOpen, hasLetters: !letters.isEmpty) { key in
                    press(key, letters: letters)
                }
                .frame(width: wide, height: high * 0.78)
                .position(x: wide / 2, y: high * 0.61)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !started else { return }
            started = true
            going = front
        }
    }

    private func albumAt(_ slot: Int) -> CloudAlbum {
        let count = albums.count
        return albums[((slot % count) + count) % count]
    }

    // ── the keys ──

    private func press(_ key: CarouselKeys.Key, letters: [WallLetter]) {
        switch key {
        case .left: wheelOpen ? turnWheel(-1) : step(-1)
        case .right: wheelOpen ? turnWheel(1) : step(1)
        case .select: wheelOpen ? jump(letters) : screens.open(.album(albumAt(going).key))
        case .down: if wheelOpen { jump(letters) }
        case .up: if !wheelOpen, !letters.isEmpty { openWheel(letters) }
        case .back, .lostFocus: closeWheel()
        }
    }

    private func step(_ by: Int) {
        withAnimation(.easeInOut(duration: Self.tick)) { going += by }
        front = going
    }

    private func openWheel(_ letters: [WallLetter]) {
        let initial = Self.initial(albumAt(going), order)
        wheelGoing = letters.firstIndex { $0.letter == initial } ?? 0
        withAnimation(.easeOut(duration: 0.25)) { wheelOpen = true }
    }

    private func turnWheel(_ by: Int) {
        withAnimation(.easeInOut(duration: Self.tick)) { wheelGoing += by }
    }

    private func closeWheel() {
        withAnimation(.easeOut(duration: 0.25)) { wheelOpen = false }
    }

    /// The covers jump to the first record of the letter in front, by the shorter way round, without a
    /// slide, and the wheel closes.
    private func jump(_ letters: [WallLetter]) {
        guard !letters.isEmpty else { return closeWheel() }
        let count = albums.count
        let first = letters[((wheelGoing % letters.count) + letters.count) % letters.count].first
        var delta = (((first - going) % count) + count) % count
        if delta > count / 2 { delta -= count }
        going += delta
        front = going
        closeWheel()
    }

    // ── what is drawn ──

    /// Black, a soft light behind the front cover, and the curved floor the covers stand on, lit faintly
    /// along its edge: a circle of the arc's own radius, so its edge runs under the covers' feet.
    private func ground(wide: CGFloat, middleY: CGFloat, edge: CGFloat, radius: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color.black
            RadialGradient(stops: [.init(color: .white.opacity(0x66 / 255), location: 0),
                                   .init(color: .white.opacity(0x24 / 255), location: 0.35),
                                   .init(color: .clear, location: 1)],
                           center: UnitPoint(x: 0.5, y: (middleY - edge * 0.1) / max(1, middleY * 2)),
                           startRadius: 0, endRadius: wide * 0.32)
                .frame(width: wide, height: middleY * 2)
            let floorTop = middleY + edge * 0.42
            Ellipse()
                .fill(LinearGradient(stops: [.init(color: Color(white: 0x2A / 255), location: 0),
                                             .init(color: Color(white: 0x0C / 255), location: 0.04),
                                             .init(color: .black, location: 0.3)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: radius * 2, height: radius * 2)
                .offset(x: (wide - radius * 2) / 2, y: floorTop)
        }
    }

    /// One cover at place `k` from the front (negative to the left): turned toward the front, tilted along
    /// the arc, smaller and dimmer the further it is, gone past ``slots``.
    private func cover(_ album: CloudAlbum, k: Double, edge: CGFloat, radius: CGFloat) -> some View {
        let angle = k * Self.stepDegrees
        let radians = angle * .pi / 180
        let near = min(abs(k), 1)
        let scale = 1 - near * 0.16 - max(abs(k) - 1, 0) * 0.035
        let fade = min(max(Double(Self.slots) + 0.5 - abs(k), 0), 1)
        return Sleeve(album: album, edge: edge)
            .overlay { Color.black.opacity((1 - Self.cardLight) * near) }
            .overlay { Rectangle().strokeBorder(Color.white.opacity(0x33 / 255), lineWidth: 1) }
            .shadow(color: .black.opacity(0.6), radius: 18, y: 8)
            .scaleEffect(scale)
            .rotation3DEffect(.degrees(-(k < 0 ? -1 : k > 0 ? 1 : 0) * near * Self.turnDegrees),
                              axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .rotationEffect(.degrees(angle * Self.tilt))
            .offset(x: radius * sin(radians), y: radius * (1 - cos(radians)))
            .opacity(fade)
    }

    /// The card under the arc, on glass: the record's title, artist, and its year, tracks, length and format.
    private func frontCard(_ album: CloudAlbum) -> some View {
        let year = AlbumSort.yearOf(album.tracks)
        let seconds = album.tracks.reduce(0) { $0 + $1.duration.seconds }
        let format = album.tracks.compactMap(\.tags).first(where: \.hasFormat)?.format.joined(separator: " ")
        let count = album.tracks.count == 1 ? Loc.get("Rpm_Album_TracksOne")
                                            : Loc.get("Rpm_Album_Tracks", String(album.tracks.count))
        var facts = [count, clock(seconds)]
        if year > 0 { facts.insert(String(year), at: 0) }
        if let format, !format.isEmpty { facts.append(format) }
        return VStack(spacing: 6) {
            Text(AlbumNames.title(album))
                .font(.tv(32, .semibold))
                .foregroundStyle(Ink.words)
                .lineLimit(1)
            Text(AlbumNames.artist(album))
                .font(.tv(Size.row))
                .foregroundStyle(Color.white.opacity(0xD9 / 255))
                .lineLimit(1)
            Text(facts.joined(separator: "  ·  "))
                .font(.tv(Size.rowLine))
                .foregroundStyle(Color.white.opacity(0xB0 / 255))
                .lineLimit(1)
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 20)
        // The system's glass, not a flat plate.
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .animation(nil, value: album.key)
    }

    private func clock(_ seconds: Double) -> String {
        let whole = Int(seconds.rounded())
        return whole >= 3600 ? String(format: "%d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60)
                             : String(format: "%d:%02d", whole / 60, whole % 60)
    }

    // ── the letters ──

    /// One letter of the wheel and the first record under it, by its place in the wall.
    struct WallLetter: Equatable {
        let letter: String
        let first: Int
    }

    /// The letter a record is filed under: the first letter of its title or its artist, in capitals, "#"
    /// for anything else; by year, its decade ("1970"), "#" for none.
    static func initial(_ album: CloudAlbum, _ order: AlbumOrdering) -> String {
        if order == .year {
            let year = AlbumSort.yearOf(album.tracks)
            return year > 0 ? String(year / 10 * 10) : "#"
        }
        let name = (order == .album ? album.album : album.artist).prefix(4)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        guard let first = name.first, first.isASCII, first.isLetter else { return "#" }
        return String(first).uppercased()
    }

    /// The letters the wall runs through in its order, in the order they first come, each with its first
    /// record; none unless it is sorted by album, by artist or by year.
    static func letters(_ albums: [CloudAlbum], _ order: AlbumOrdering) -> [WallLetter] {
        guard order == .album || order == .artist || order == .year else { return [] }
        var seen: [String: Int] = [:]
        var out: [WallLetter] = []
        for (at, album) in albums.enumerated() {
            let letter = initial(album, order)
            if seen[letter] == nil {
                seen[letter] = at
                out.append(WallLetter(letter: letter, first: at))
            }
        }
        return out
    }

    // ── its figures, the Android TV's ──

    /// How many covers stand to each side of the front one.
    static let slots = 5
    /// The angle between two covers along the arc, how far each tilts along it, and how far a cover beside
    /// the front one is turned toward it.
    static let stepDegrees = 5.8
    static let tilt = 0.81
    static let turnDegrees = 32.0
    /// The cover's edge as a share of the screen's height, where the front cover's middle stands, and the
    /// arc's radius as a share of the screen's width.
    static let cardShare: CGFloat = 0.34
    static let arcMiddle: CGFloat = 0.43
    static let arcRadius: CGFloat = 0.9
    /// How bright a cover not in front is: home's cards' 0.75.
    static let cardLight = 0.75
    /// The letter tiles' edge as a share of the screen's height, and where the front tile's middle stands.
    static let letterShare: CGFloat = 0.12
    static let letterMiddle: CGFloat = 0.17
    /// The gap between the front cover's foot and the card under it.
    static let infoGap: CGFloat = 110
}

/// The letters as the covers stand: tiles along the same arc, smaller and closer, the front one at full
/// brightness and the rest dimmed, never ending. `at` is the letter in front.
private struct LetterWheel: View {
    let letters: [String]
    let at: Int
    let tile: CGFloat
    let middleY: CGFloat
    let wide: CGFloat
    let radius: CGFloat

    static let slots = 7
    static let stepDegrees = 4.6

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(at - Self.slots...at + Self.slots, id: \.self) { slot in
                tile(slot)
            }
        }
    }

    private func tile(_ slot: Int) -> some View {
        let k = Double(slot - at)
        let letter = letters[((slot % letters.count) + letters.count) % letters.count]
        let angle = k * Self.stepDegrees
        let radians = angle * .pi / 180
        let near = min(abs(k), 1)
        let scale = 1 - near * 0.16 - max(abs(k) - 1, 0) * 0.03
        let turn = -(k < 0 ? -1.0 : k > 0 ? 1.0 : 0.0) * near * AlbumCarousel.turnDegrees
        let fade = min(max(Double(Self.slots) + 0.5 - abs(k), 0), 1)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let ground = Color(red: 0x2A / 255, green: 0x2A / 255, blue: 0x2E / 255)
        let face = Text(letter)
            .font(.tv(letter.count > 2 ? 30 : 52, .semibold))
            .foregroundStyle(Ink.words)
            .frame(width: tile, height: tile)
            .background(ground, in: shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0x40 / 255), lineWidth: 1) }
            .overlay { shape.fill(Color.black.opacity((1 - AlbumCarousel.cardLight) * near)) }
            .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        return face
            .scaleEffect(scale)
            .rotation3DEffect(.degrees(turn), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
            .rotationEffect(.degrees(angle * AlbumCarousel.tilt))
            .offset(x: radius * sin(radians), y: radius * (1 - cos(radians)))
            .opacity(fade)
            .position(x: wide / 2, y: middleY)
            .zIndex(Double(Self.slots + 1) - abs(k))
    }
}

/// The carousel's keys, read by a UIKit view that holds the focus. Left and Right never move the focus
/// out of it (the sidebar is to the left, and a press there would open it rather than turn the carousel);
/// Up moves it out only while the wheel is open, or where there is no wheel; Down moves it out only while
/// the wheel is closed. The press itself is handled where it is the carousel's and passed on otherwise,
/// which is what lets the focus engine move the focus at all.
struct CarouselKeys: UIViewRepresentable {
    enum Key { case left, right, up, down, select, back, lostFocus }

    let wheelOpen: Bool
    let hasLetters: Bool
    let onKey: (Key) -> Void

    func makeUIView(context: Context) -> KeyView { KeyView() }

    func updateUIView(_ view: KeyView, context: Context) {
        view.wheelOpen = wheelOpen
        view.hasLetters = hasLetters
        view.onKey = onKey
    }

    final class KeyView: UIView {
        var wheelOpen = false
        var hasLetters = false
        var onKey: (Key) -> Void = { _ in }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            // Swipes on the remote's surface: the focus engine is kept from moving (shouldUpdateFocus), so
            // these are what turn the carousel.
            for (direction, key) in [(UISwipeGestureRecognizer.Direction.left, Key.left), (.right, .right)] {
                let swipe = Swipe(target: self, action: #selector(swiped(_:)))
                swipe.direction = direction
                swipe.key = key
                addGestureRecognizer(swipe)
            }
        }

        required init?(coder: NSCoder) { fatalError("not from a storyboard") }

        override var canBecomeFocused: Bool { true }

        private final class Swipe: UISwipeGestureRecognizer { var key = Key.left }

        @objc private func swiped(_ swipe: UISwipeGestureRecognizer) {
            if let swipe = swipe as? Swipe { onKey(swipe.key) }
        }

        /// Whether a press up is the carousel's: it opens the wheel.
        private var holdsUp: Bool { !wheelOpen && hasLetters }

        override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
            guard context.previouslyFocusedView === self else { return true }
            switch context.focusHeading {
            case .left, .right:
                return false
            case .up:
                // A swipe up (a press up is handled in pressesBegan and never gets here).
                if holdsUp { onKey(.up); return false }
                return true
            case .down:
                if wheelOpen { onKey(.down); return false }
                return true
            default:
                return true
            }
        }

        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            // The focus left for the keys above: the wheel does not stay open behind them.
            if context.previouslyFocusedView === self, context.nextFocusedView !== self, wheelOpen {
                onKey(.lostFocus)
            }
        }

        /// What a press is, whether it comes from the remote or, in the simulator and from a keyboard,
        /// as a key: a keyboard's key is turned into the remote's press only when it is passed on, so it
        /// is read here as itself.
        private enum Pressed { case left, right, up, down, select, menu }

        private static func pressed(_ press: UIPress) -> Pressed? {
            if let key = press.key {
                switch key.keyCode {
                case .keyboardLeftArrow: return .left
                case .keyboardRightArrow: return .right
                case .keyboardUpArrow: return .up
                case .keyboardDownArrow: return .down
                case .keyboardReturnOrEnter: return .select
                case .keyboardEscape: return .menu
                default: return nil
                }
            }
            switch press.type {
            case .leftArrow: return .left
            case .rightArrow: return .right
            case .upArrow: return .up
            case .downArrow: return .down
            case .select: return .select
            case .menu: return .menu
            default: return nil
            }
        }

        /// Whether the carousel takes this press, rather than passing it on to move the focus or go back.
        private func takes(_ pressed: Pressed) -> Bool {
            switch pressed {
            case .left, .right, .select: true
            case .up: holdsUp
            case .down, .menu: wheelOpen
            }
        }

        /// The presses whose beginning this view took: their ends are not passed on either, and every
        /// other end is.
        private var taken: Set<ObjectIdentifier> = []

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let press = presses.first, let pressed = Self.pressed(press), takes(pressed) else {
                return super.pressesBegan(presses, with: event)
            }
            taken.insert(ObjectIdentifier(press))
            switch pressed {
            case .left: onKey(.left)
            case .right: onKey(.right)
            case .select: onKey(.select)
            case .up: onKey(.up)
            case .down: onKey(.down)
            case .menu: onKey(.back)
            }
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if let press = presses.first, taken.remove(ObjectIdentifier(press)) != nil { return }
            super.pressesEnded(presses, with: event)
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            if let press = presses.first, taken.remove(ObjectIdentifier(press)) != nil { return }
            super.pressesCancelled(presses, with: event)
        }
    }
}
