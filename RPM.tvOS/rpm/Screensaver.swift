import SwiftUI
import UIKit

/// Whether the screens are hidden so that only the room shows. When the remote has not been used
/// for the number of minutes in the settings, the screens fade out. The next press brings them back
/// as they were, and does nothing else.
///
/// The idle time is worked out from the time of the last press. It is not a timer that a press must
/// cancel. ``watch(minutes:)`` wakes when the time is up, checks the last press again, and only
/// then hides the screens. A press that arrives while the wait ends moves the last-press time on,
/// so the check sees it. Everything runs on the main actor.
@MainActor
@Observable
final class Screensaver {
    private(set) var shown = false
    @ObservationIgnored private var lastPress = ContinuousClock.now

    /// A press or a touch on the remote.
    func pressed() {
        lastPress = .now
    }

    /// The press watcher calls this before a press reaches the screens. Returns true when the
    /// screens were hidden. In that case the press brings them back and does not reach them.
    func wake() -> Bool {
        lastPress = .now
        guard shown else { return false }
        shown = false
        return true
    }

    /// Hides the screens each time `minutes` pass with no press, until the task is cancelled. Does
    /// nothing when `minutes` is 0.
    func watch(minutes: Int) async {
        guard minutes > 0 else { return }
        let wait = Duration.seconds(minutes * 60)
        while !Task.isCancelled {
            let left = lastPress + wait - .now
            if left > .zero {
                try? await Task.sleep(for: left)
                continue
            }
            shown = true
            while shown, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(250)) }
        }
    }
}

extension PressWatcher {
    /// The app's watcher. It covers the window that holds the screens and the player's window,
    /// which tvOS shows in a window of its own. A press anywhere restarts the screensaver's wait. A
    /// press while the screensaver is showing only wakes the screens.
    @MainActor
    static func app(saver: Screensaver, screens: Screens) -> PressWatcher {
        PressWatcher(onPress: {
            saver.pressed()
            if !screens.remoteUsed { screens.remoteUsed = true }
        }, swallow: { saver.wake() })
    }
}

/// Sees every press and touch from the remote without taking them from the screens. It uses a
/// gesture recogniser on the window that never recognises a gesture. The exception is a press that
/// wakes the screens from the screensaver. That press is recognised, which cancels it for the views
/// under the window.
struct PressWatcher: UIViewRepresentable {
    let onPress: () -> Void
    let swallow: () -> Bool

    func makeUIView(context: Context) -> WatchingView {
        let view = WatchingView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: WatchingView, context: Context) {
        view.watcher.onPress = onPress
        view.watcher.swallow = swallow
    }

    final class WatchingView: UIView {
        let watcher = Watcher(target: nil, action: nil)

        override func didMoveToWindow() {
            super.didMoveToWindow()
            watcher.view?.removeGestureRecognizer(watcher)
            window?.addGestureRecognizer(watcher)
        }
    }

    final class Watcher: UIGestureRecognizer {
        var onPress: () -> Void = {}
        var swallow: () -> Bool = { false }

        override init(target: Any?, action: Selector?) {
            super.init(target: target, action: action)
            cancelsTouchesInView = true
            delaysTouchesBegan = false
            delaysTouchesEnded = false
            // The remote's presses, and a keyboard's keys for them (the simulator, a keyboard paired with
            // the TV), whose press type is 2000 plus the key's HID usage. A view that reads the keyboard's
            // key itself (the album carousel) takes it before it is turned into the remote's press, so the
            // key is watched as itself.
            let keys: [UIKeyboardHIDUsage] = [.keyboardUpArrow, .keyboardDownArrow, .keyboardLeftArrow,
                                              .keyboardRightArrow, .keyboardReturnOrEnter, .keyboardEscape]
            allowedPressTypes = ([UIPress.PressType.upArrow, .downArrow, .leftArrow, .rightArrow,
                                  .select, .menu, .playPause].map(\.rawValue)
                                 + keys.map { 2000 + $0.rawValue })
                .map { NSNumber(value: $0) }
            allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent) {
            onPress()
            // The play key also does its own work, even when it wakes the screens. So it is not
            // swallowed.
            let ownWork = presses.contains { $0.type == .playPause }
            if swallow(), !ownWork {
                state = .recognized
            } else {
                state = .failed
            }
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            onPress()
            state = swallow() ? .recognized : .failed
        }

        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }
}
