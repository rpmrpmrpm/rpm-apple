import Foundation

/// Where a page stands relative to the app's chrome. This decides how much of the foot of the
/// screen the page has already been given.
///
/// **Stated at every call site rather than defaulted.** The two answers differ by the full height
/// of the bar, and by the full height of the keyboard when it is up. A page with the wrong answer
/// runs its last row under the mini player, or ends its list a keyboard's height above the keys.
/// Neither problem shows until someone scrolls to the end of a long list.
public enum PageFoot: Sendable {
    /// The shell's own `safeAreaInset` reaches this page, and the shell ignores the keyboard. The
    /// page keeps its full height whether the keys are up or not. The chrome is already reserved,
    /// and the keyboard is left to the lists inside.
    case underTheChrome

    /// A `NavigationStack` sits between the shell and this page. The stack is a UIKit container. It
    /// gives its content the window's insets, so neither the shell's inset nor the shell's
    /// `ignoresSafeArea(.keyboard)` reaches the page. The page must reserve the chrome itself. The
    /// stack has already shortened the page to the top of the keyboard.
    case insideAStack
}

/// How much room a page reserves at the end of its scroll for what is drawn over the foot of it.
///
/// There are two parts, because they are applied in two places. The page reserves the chrome,
/// because the page's foot is where the bar stands. The scrolling list reserves the keyboard. An
/// inset on the page for the keys would shrink the area the list is laid out in. The list's own
/// dissolve mask would then be drawn over part of that area and hide the rest.
///
/// Both answers depend on where the page is. One of them also depends on the keyboard. A page
/// inside a stack has already been shortened to the keys by the stack. With the keys up, the page
/// reserves nothing for a bar that is now behind them, and the list inside reserves nothing at all.
public enum PageFootRoom {
    /// What a page reserves for the chrome.
    ///
    /// - Parameters:
    ///   - chrome: how tall the bar is, as the chrome reports it.
    ///   - below: what the phone keeps clear at the bottom of the screen. This is the home
    ///     indicator's inset, and zero on a phone with a home button.
    ///   - keys: how far up the screen the keyboard reaches. Zero while it is down.
    ///
    /// What the chrome covers is its own height plus the inset below it. The bar is laid out inside
    /// the safe area, and then drawn down into the home indicator. If the page reserves the bar less
    /// that inset, the last row is left under the bar by exactly the inset. The mini player then sits
    /// on the last line of text.
    ///
    /// Inside a stack, the page has already been given the deeper of the two: the indicator's inset
    /// or the keyboard. So what is left to reserve is the part of the bar that reaches above that. With
    /// the keyboard up, that part is nothing. The bar is behind the keys. Reserving it anyway would
    /// leave a band of empty space between the content and the keys.
    public static func chrome(_ chrome: Double, below: Double, keys: Double,
                              at place: PageFoot) -> Double {
        guard chrome.isFinite, below.isFinite, keys.isFinite else { return 0 }

        let bar = max(0, chrome)
        let indicator = max(0, below)
        let given = max(indicator, max(0, keys))

        return switch place {
        case .underTheChrome: 0
        case .insideAStack: max(0, bar + indicator - given)
        }
    }

    /// What a list reserves for the keyboard, on a page that has already reserved the chrome.
    ///
    /// The keys come up over the chrome, not under it. Under the chrome the page keeps its full
    /// height. So the list only owes the part of the keyboard that reaches past the bar. Reserving
    /// the whole keyboard would end the list a bar's height above the keys, with a band of empty
    /// space between.
    ///
    /// Inside a stack the answer is zero. The stack has already shortened the page to the top of the
    /// keyboard. If the list reserved the keyboard again, it would stop short. It would leave a gap
    /// the height of the keyboard under its last row.
    public static func keyboard(_ keys: Double, chrome: Double, below: Double,
                                at place: PageFoot) -> Double {
        guard keys.isFinite, chrome.isFinite, below.isFinite else { return 0 }

        return switch place {
        case .underTheChrome: max(0, keys - max(0, chrome) - max(0, below))
        case .insideAStack: 0
        }
    }
}
