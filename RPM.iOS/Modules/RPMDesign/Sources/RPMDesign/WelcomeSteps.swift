/// A page of the phone's welcome, in the order the pages show. The greeting is not a numbered step.
/// The Android app's welcome has the same pages (`WelcomePage`).
public enum WelcomePage: Int, CaseIterable, Sendable {
    case hello, language, look, layout, support, spin

    /// The page called `name`, such as "support". Nil for any other word.
    public static func named(_ name: String) -> WelcomePage? {
        allCases.first { "\($0)" == name }
    }
}

/// Which numbered steps the welcome has now, and which one shows for the page asked for.
///
/// The support step is there only while the account is asked to support rpm, and the song step only
/// when there is a song to play. Both can change while the welcome is open: the account's standing can
/// arrive late, and a purchase on the support step ends the ask while that step is on screen. So the
/// steps are worked out again on every draw, and a page that is no longer among them shows the next
/// step that is (``shown(for:)``).
public struct WelcomeSteps: Equatable, Sendable {
    /// The numbered steps, in order.
    public let steps: [WelcomePage]

    /// - Parameters:
    ///   - asks: the account is asked to support rpm.
    ///   - hasSong: there is a song for the last step to play.
    public init(asks: Bool, hasSong: Bool) {
        steps = [.language, .look, .layout]
            + (asks ? [.support] : [])
            + (hasSong ? [.spin] : [])
    }

    /// The page on screen when `page` is asked for: `page` while it is among the steps (or the
    /// greeting), else the next step after it. Nil when no step is left after it.
    public func shown(for page: WelcomePage) -> WelcomePage? {
        page == .hello || steps.contains(page) ? page : after(page)
    }

    /// The step that follows `page`, or nil when it is the last. `page` itself need not be among
    /// the steps.
    public func after(_ page: WelcomePage) -> WelcomePage? {
        steps.first { $0.rawValue > page.rawValue }
    }

    /// The number of `page` in "Step 2 of 4". 1 for a page that is not a step.
    public func number(of page: WelcomePage) -> Int {
        (steps.firstIndex(of: page) ?? 0) + 1
    }
}
