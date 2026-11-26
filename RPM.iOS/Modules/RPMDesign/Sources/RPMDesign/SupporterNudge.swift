/// When the supporter pop-up (`SupporterNudgeCard`) asks a listener to become a supporter: on every ``every``th launch
/// that reaches the signed-in app, and only for an account that does not pay. The Android app has the same rule
/// (`SupporterNudge`).
public enum SupporterNudge {
    /// The pop-up is due on launch 50, 100, 150 and so on.
    public static let every = 50

    /// Where the launches are counted in the defaults. The Android app uses the same key.
    public static let launchesKey = "supporter.nudge.launches"

    /// Whether launch number `launch` (the first launch is 1) is one that may show the pop-up.
    public static func onLaunch(_ launch: Int) -> Bool {
        launch > 0 && launch % every == 0
    }

    /// Whether the pop-up shows on launch number `launch`.
    ///
    /// - Parameter supporter: whether the account pays for its support (`CloudQuota.wearsMark`), or nil while that is
    ///   not known. A closed beta tester does not pay, so is asked, as the settings page and the welcome offer it the
    ///   subscription. Not known is never a yes: a supporter must never be asked.
    public static func due(launch: Int, supporter: Bool?) -> Bool {
        supporter == false && onLaunch(launch)
    }
}
