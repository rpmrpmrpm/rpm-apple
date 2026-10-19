import SwiftUI
import UIKit
import RPMAudio

/// The player's seek bar. The remote reaches it with Up from the keys. The desktop app's
/// `PegasusChrome.Adjust` and `SeekBar` are the equivalents. When the bar has focus, Left and Right
/// move a preview of the playhead by 10 seconds per press. Holding a key moves it faster
/// (``SeekSteps``). A swipe across the remote's touch surface drags the preview. The seek happens
/// once: when the key is released, when the swipe ends, or when the bar loses focus. A preview
/// belongs to the track it started on. It is dropped if the track changes.
struct SeekBar: View {
    /// How far the line is inset from the bar's ends. This leaves room for the lit background under
    /// the focus.
    static let inset: CGFloat = 16

    @Environment(TVModel.self) private var model
    let width: CGFloat
    let onStep: () -> Void

    @State private var preview: Double?
    @State private var focused = false
    /// The track the preview started on: its place in the queue and its id.
    @State private var previewOf: Owner?

    private struct Owner: Equatable {
        let index: Int?
        let rpmId: String?
    }

    var body: some View {
        let duration = model.player.duration.seconds
        let position = preview ?? model.player.position.seconds

        VStack(alignment: .trailing, spacing: 6) {
            // Half the title's size, in the phone's white: the clock is 11 under a 22 point title.
            Text(duration > 0 ? "-" + remaining(duration - position) : " ")
                .font(.tv(Size.small).monospacedDigit())
                .foregroundStyle(Color.white.opacity(0x88 / 255))
                // Inset by the same amount as the line, so the time ends where the line ends.
                .padding(.horizontal, Self.inset)
            SeekLine(fraction: duration > 0 ? position / duration : 0,
                     knob: preview != nil ? 26 : 20, track: focused ? 6 : 4)
                .frame(height: 30)
                .padding(.horizontal, Self.inset)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(focused ? 0.16 : 0))
                }
                .scaleEffect(focused ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
                .overlay {
                    SeekKeys(
                        duration: { model.player.duration.seconds },
                        position: { preview ?? model.player.position.seconds },
                        move: { to in
                            if preview == nil { previewOf = owner }
                            preview = to
                            onStep()
                        },
                        commit: commit,
                        focusChanged: { now in
                            focused = now
                            if !now { commit() }
                        })
                }
        }
        .frame(width: width)
        .onChange(of: owner) { _, now in
            if previewOf != nil, previewOf != now {
                preview = nil
                previewOf = nil
            }
        }
        .onDisappear { commit() }
    }

    private var owner: Owner { Owner(index: model.player.index, rpmId: model.player.current?.rpmId) }

    private func commit() {
        guard let to = preview else { return }
        preview = nil
        defer { previewOf = nil }
        guard previewOf == owner else { return }
        _ = model.player.seek(to: .seconds(to))
    }
}

/// The remote input for the bar. It is a focusable view that sees the arrow keys go down and come
/// up, and it reads swipes on the touch surface. Up and Down are passed on, so the focus can move
/// away from the bar.
private struct SeekKeys: UIViewRepresentable {
    let duration: () -> Double
    let position: () -> Double
    let move: (Double) -> Void
    let commit: () -> Void
    let focusChanged: (Bool) -> Void

    func makeUIView(context: Context) -> KeysView {
        let view = KeysView()
        view.keys = self
        return view
    }

    func updateUIView(_ view: KeysView, context: Context) {
        view.keys = self
    }

    final class KeysView: UIView {
        var keys: SeekKeys?

        /// The arrow being held (-1 for left, 1 for right), when it went down, and when the last
        /// step was made.
        private var held: (way: Int, down: CFTimeInterval, last: CFTimeInterval)?
        private var ticker: CADisplayLink?

        /// How long an arrow must be down before it counts as held. This is about when the remote
        /// starts to repeat a key.
        private static let holdAfter: CFTimeInterval = 0.4

        /// The preview position when the current swipe started.
        private var swipeFrom: Double?

        override init(frame: CGRect) {
            super.init(frame: frame)
            let pan = UIPanGestureRecognizer(target: self, action: #selector(swiped(_:)))
            pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            addGestureRecognizer(pan)
        }

        required init?(coder: NSCoder) { fatalError("not built from a storyboard") }

        override var canBecomeFocused: Bool { true }

        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            let now = context.nextFocusedView === self
            if !now { stopHolding() }
            keys?.focusChanged(now)
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let press = presses.first, let way = Self.way(press.type), let keys else {
                return super.pressesBegan(presses, with: event)
            }
            keys.move(SeekSteps.next(from: keys.position(), way: way, held: false, since: 0,
                                     duration: keys.duration()))
            let now = CACurrentMediaTime()
            held = (way, now, now)
            // When the key is held past the repeat point, the preview moves on each frame.
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            ticker?.invalidate()
            ticker = link
        }

        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let press = presses.first, Self.way(press.type) != nil else {
                return super.pressesEnded(presses, with: event)
            }
            stopHolding()
            keys?.commit()
        }

        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            guard let press = presses.first, Self.way(press.type) != nil else {
                return super.pressesCancelled(presses, with: event)
            }
            stopHolding()
            keys?.commit()
        }

        /// Moves the preview on each frame while the arrow stays down, once it has been held long
        /// enough. The first press already moved it by 10 seconds.
        @objc private func tick() {
            guard let held, let keys else { return }
            let now = CACurrentMediaTime()
            guard now - held.down >= Self.holdAfter else { return }
            keys.move(SeekSteps.next(from: keys.position(), way: held.way, held: true,
                                     since: now - max(held.last, held.down + Self.holdAfter - 0.25),
                                     duration: keys.duration()))
            self.held = (held.way, held.down, now)
        }

        private func stopHolding() {
            ticker?.invalidate()
            ticker = nil
            held = nil
        }

        @objc private func swiped(_ pan: UIPanGestureRecognizer) {
            guard let keys, keys.duration() > 0 else { return }
            switch pan.state {
            case .began:
                swipeFrom = keys.position()
            case .changed:
                guard let from = swipeFrom else { return }
                // A swipe across the whole touch surface moves a fifth of the track.
                let across = pan.translation(in: self).x / max(1, bounds.width)
                let to = min(max(from + Double(across) * keys.duration() * 0.2, 0), keys.duration())
                keys.move(to)
            case .ended, .cancelled:
                swipeFrom = nil
                keys.commit()
            default:
                break
            }
        }

        private static func way(_ type: UIPress.PressType) -> Int? {
            switch type {
            case .leftArrow: -1
            case .rightArrow: 1
            default: nil
            }
        }
    }
}

/// The seek line. It is a thin track: white for the part that has played, with a knob at the
/// current position.
struct SeekLine: View {
    let fraction: Double
    var knob: CGFloat = 16
    var track: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let x = geo.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0x8B / 255)).frame(height: track)
                Capsule().fill(Color.white).frame(width: x, height: track)
                Capsule().fill(Color.white)
                    .frame(width: track, height: knob)
                    .offset(x: min(max(x - track / 2, 0), geo.size.width - track))
            }
            .frame(maxHeight: .infinity)
        }
    }
}
