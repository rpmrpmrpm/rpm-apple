import SwiftUI

/// Remembers where the focus was on a screen, so it returns there when the sidebar closes.
///
/// When the sidebar closes, tvOS gives the focus to the item nearest the sidebar's selected row. On
/// a scrolled screen that item is near the top, so the screen scrolls there and looks reset. A
/// screen that keeps its focus gives each card a name (``remembered(_:)``), records the last card
/// focused, and asks tvOS to return the focus to that card whenever focus comes in from outside the
/// screen.
///
/// **A name must be unique on its screen.** The same record can appear in two home rows. Each row
/// sets a ``focusSpace(_:)``, and the name is unique within that space.
///
/// **Every focusable item on a screen that keeps its focus must be named.** Focus on an unnamed
/// item looks like focus outside the screen. The next card it moves to would then be taken as a way
/// back in and sent to the last card. For that reason, a screen with keys that tvOS draws itself
/// (the search keyboard) or keys that are UIKit views (the dial, the seek bar) does not keep its
/// focus this way.
extension View {
    /// This screen keeps its focus position. Apply it to the screen of a tab, given as `tab`.
    /// `first` is the card that gets the focus when the screen is asked for focus before any card
    /// has had it. For home, this is the banner. Nil leaves the choice to tvOS.
    func keepsFocus(_ tab: TVTab, first: String?) -> some View {
        modifier(KeepsFocus(tab: tab, first: first))
    }

    /// This card's name on its screen, within the space around it.
    func remembered(_ name: String) -> some View {
        modifier(Remembered(name: name))
    }

    /// The space that the names inside are unique in: a row, a grid or a panel.
    func focusSpace(_ space: String) -> some View {
        environment(\.focusSpace, space)
    }
}

extension EnvironmentValues {
    /// The screen's focus binding, which the cards bind to. Nil outside a screen that keeps its
    /// focus.
    @Entry var focusMemory: FocusState<String?>.Binding? = nil
    @Entry var focusSpace: String = ""
}

private struct KeepsFocus: ViewModifier {
    @Environment(Screens.self) private var screens
    let tab: TVTab
    let first: String?
    @FocusState private var focused: String?
    @State private var last: String?

    func body(content: Content) -> some View {
        content
            .environment(\.focusMemory, $focused)
            .onChange(of: focused) { before, now in
                // Nil means the focus is outside the screen (the sidebar or the player). That is
                // not a place to return to, so the card before it stays recorded.
                guard let now else { return }
                // Focus came back in from outside, and tvOS put it on the card nearest the entry
                // point, not on the card that had it. Put it back. `defaultFocus` is not used here.
                // tvOS reads it only when it picks the focus by itself.
                if before == nil, let last, now != last {
                    focused = last
                    return
                }
                last = now
            }
            .defaultFocus($focused, last, priority: .userInitiated)
            // The shell sends this when the player comes down over this screen.
            .onChange(of: screens.focusBack) { _, _ in
                guard screens.tab == tab, screens.paths[tab, default: []].isEmpty else { return }
                focused = last ?? first
            }
    }
}

private struct Remembered: ViewModifier {
    @Environment(\.focusMemory) private var memory
    @Environment(\.focusSpace) private var space
    let name: String

    func body(content: Content) -> some View {
        if let memory {
            content.focused(memory, equals: space + "/" + name)
        } else {
            content
        }
    }
}
