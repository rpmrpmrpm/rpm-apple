import SwiftUI
import UIKit
import RPMDesign

/// What the phone keeps clear at the bottom of the screen, in points.
///
/// This is read from the window and not from a `GeometryReader`. The two places that need it both
/// work out the chrome from OUTSIDE the layout it sits in: how far into the home indicator the
/// bar may reach, and how much of the chrome a page's scroll has to clear. A reader gives a view
/// its own insets, which by then already include what the chrome has done to them.
///
/// Zero on a phone with a home button. That is correct there: nothing is kept clear, because
/// nothing is drawn over it.
enum RPMSafeArea {
    @MainActor static var bottom: CGFloat {
        keyWindow?.safeAreaInsets.bottom ?? 0
    }

    /// What the phone keeps clear at the top: the strip where the clock, the signal and the
    /// battery are drawn. It is read in the same way and for the same reason: the home banner
    /// runs up behind it and needs to know how far that is from outside its own layout.
    ///
    /// Zero on a phone with a home button, and zero before there is a window.
    @MainActor static var top: CGFloat {
        keyWindow?.safeAreaInsets.top ?? 0
    }

    /// The window itself. SwiftUI's `.global` coordinates are measured against it, so it is the
    /// one frame in which a picture drawn by several different containers can be laid out. See
    /// `VinylGround`.
    ///
    /// Zero before there is a window, which is a moment when nothing is being drawn.
    @MainActor static var window: CGSize {
        keyWindow?.bounds.size ?? .zero
    }

    @MainActor private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

/// How tall the app's foot is, sent up from the chrome to whoever has to leave room for it.
///
/// This matches `ShellPage.ChromeHeight` in the Uno app and exists for the same reason: the bar
/// grows and shrinks as the mini player comes and goes, and every page that scrolls owes its
/// content that much clearance at the END of the scroll. A figure written in two places can
/// differ between them, and the result is a row of records that nobody can reach.
public struct ChromeHeight: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

extension View {
    /// Room at the end of a page for the chrome drawn over it, and for the keyboard when the page
    /// is one that a `NavigationStack` has already shortened to the keys.
    ///
    /// Every page applies this once and states where it stands. See ``RPMDesign/PageFootRoom``.
    /// It also hands the lists inside the page the room THEY owe the keyboard. That follows from
    /// the same two facts and is not a second decision; see ``keyboardRoom()``.
    @MainActor public func footRoom(_ chrome: CGFloat, _ place: PageFoot) -> some View {
        modifier(FootRoom(chrome: chrome, place: place))
    }

    /// Room at the end of a scrolling list for the keyboard drawn over it.
    ///
    /// **On the list, not on the page.** An inset put on the page shrinks the area the list is
    /// laid out in. ``DissolvingScroll`` then draws its mask over a strip of the list and hides
    /// everything below it.
    ///
    /// The amount comes from the page's own ``footRoom(_:_:)`` and not from the caller. It depends
    /// on where the page stands, which is stated once at the shell and which a list several views
    /// deep inside the page does not know.
    public func keyboardRoom() -> some View { modifier(KeyboardRoom()) }
}

/// The page's own reservation, and the one it hands down to its lists.
private struct FootRoom: ViewModifier {
    let chrome: CGFloat
    let place: PageFoot

    /// How far up the screen the keyboard reaches, in points. Zero while it is down.
    @State private var keys: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: mine)
            }
            .environment(\.keyboardRoom, theirs)
            .keyboardReach(into: $keys)
    }

    @MainActor private var mine: CGFloat {
        PageFootRoom.chrome(chrome, below: RPMSafeArea.bottom, keys: keys, at: place)
    }

    @MainActor private var theirs: CGFloat {
        PageFootRoom.keyboard(keys, chrome: chrome, below: RPMSafeArea.bottom, at: place)
    }
}

/// The list's share of it, read from the page and not worked out again here.
private struct KeyboardRoom: ViewModifier {
    @Environment(\.keyboardRoom) private var room

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: room)
        }
    }
}

// ── how far up the keyboard reaches ──

private extension View {
    /// Writes the keyboard's reach into `reach`, animated to match the keyboard's own travel.
    func keyboardReach(into reach: Binding<CGFloat>) -> some View {
        modifier(KeyboardReach(reach: reach))
    }
}

private struct KeyboardReach: ViewModifier {
    @Binding var reach: CGFloat

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                    guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                        as? CGRect else { return }

                    // A keyboard that is leaving the screen has its top at the bottom of the
                    // screen, so this gives zero without a special case. An undocked or floating
                    // keyboard sits somewhere else, and the value is still how far up the
                    // screen it reaches.
                    settle(to: max(0, RPMSafeArea.window.height - end.minY))
                }
            .onReceive(NotificationCenter.default
                .publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                    settle(to: 0)
                }
    }

    /// A quarter of a second, which is the keyboard's own travel time. The page and the list
    /// inside it must not jump while the keyboard is still sliding.
    private func settle(to now: CGFloat) {
        withAnimation(.easeOut(duration: 0.25)) { reach = now }
    }
}

/// What the lists inside a page owe the keyboard, handed down by the page.
///
/// This is the figure that ``PageFootRoom/keyboard(_:chrome:below:at:)`` returns, worked out once
/// where the page's place is known. A list three views deep cannot receive it as an argument
/// unless every view in between passes it on, and a view that forgets passes zero.
private struct KeyboardRoomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var keyboardRoom: CGFloat {
        get { self[KeyboardRoomKey.self] }
        set { self[KeyboardRoomKey.self] = newValue }
    }
}
