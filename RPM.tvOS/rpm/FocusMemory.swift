import SwiftUI

/// Remembers where the focus was on a screen, so it returns there when the sidebar closes.
///
/// When the sidebar closes, tvOS gives the focus to the item nearest the sidebar's selected row. On
/// a scrolled screen that item is near the top, so the screen scrolls there and looks reset. A
/// screen that keeps its focus gives each card a name (``remembered(_:)``), records the last card
/// focused, and asks tvOS to return the focus to that card whenever focus comes in from outside the
/// screen.
///
/// A page on a screen's stack can keep its focus in the same way. A playlist folder's page does, so
/// Back from a folder inside it puts the focus on that folder's card again.
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
        modifier(KeepsFocus(place: .tab(tab), first: first))
    }

    /// This page keeps its focus position in the same way. Apply it to a page on a screen's stack,
    /// given as `page`. `first` is the card that the focus starts on when the page opens. The focus
    /// returns to the last card when a page opened from this one closes.
    func keepsFocus(_ page: Page, first: String?) -> some View {
        modifier(KeepsFocus(place: .page(page), first: first))
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
    /// What keeps its focus: the screen of a tab, or a page on a screen's stack.
    enum Place {
        case tab(TVTab)
        case page(Page)
    }

    @Environment(Screens.self) private var screens
    let place: Place
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
                // A page that has just opened. tvOS can put the focus on the card nearest to
                // where it was on the page below. The page starts on its first card instead.
                if before == nil, last == nil, let opening, now != opening {
                    focused = opening
                    return
                }
                last = now
            }
            .defaultFocus($focused, last ?? opening, priority: .userInitiated)
            // The shell sends this when the player comes down over this screen.
            .onChange(of: screens.focusBack) { _, _ in
                guard onTop else { return }
                focused = last ?? first
            }
    }

    /// The card that a page gives the focus to when it opens. The screen of a tab leaves that
    /// choice to tvOS, and uses `first` only when it is asked for the focus back.
    private var opening: String? {
        if case .page = place { return first }
        return nil
    }

    /// Whether this screen or page is the one on top, with nothing opened over it.
    private var onTop: Bool {
        switch place {
        case .tab(let tab):
            return screens.tab == tab && screens.paths[tab, default: []].isEmpty
        case .page(let page):
            return screens.paths[screens.tab, default: []].last == page
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
