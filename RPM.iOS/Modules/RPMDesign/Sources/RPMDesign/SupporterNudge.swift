/// When the supporter pop-up (`SupporterNudgeCard`) asks a listener to become a supporter, counted in launches that
/// reach the signed-in app: every ``every``th launch for an account that does not pay, every ``everyForTesters``th for
/// a closed beta tester, and never for a paying supporter. The Android app has the same rule (`SupporterNudge`).
public enum SupporterNudge {
    /// What the account has, as far as the pop-up is concerned.
    public enum Plan: Sendable, Equatable {
        /// A paying supporter. Never asked.
        case pays
        /// A closed beta tester: the supporter features without paying. Asked less often.
        case tester
        /// Neither.
        case free

        /// The plan from the account's quota (`CloudQuota.supporter` and `tester`). A tester is a tester whatever
        /// the supporter flag says.
        public static func of(supporter: Bool, tester: Bool) -> Plan {
            tester ? .tester : supporter ? .pays : .free
        }
    }

    /// The pop-up is due on launch 50, 100, 150 and so on for an account that does not pay.
    public static let every = 50

    /// The pop-up is due on launch 100, 200, 300 and so on for a closed beta tester.
    public static let everyForTesters = 100

    /// Where the launches are counted in the defaults. The Android app uses the same key.
    public static let launchesKey = "supporter.nudge.launches"

    /// Whether launch number `launch` (the first launch is 1) is one that may show the pop-up to anybody. Every
    /// ``everyForTesters``th launch is also an ``every``th one.
    public static func onLaunch(_ launch: Int) -> Bool {
        launch > 0 && launch % every == 0
    }

    /// Whether the pop-up shows on launch number `launch`.
    ///
    /// - Parameter plan: the account's plan, or nil while it is not known. Not known is never a yes: a supporter
    ///   must never be asked.
    public static func due(launch: Int, plan: Plan?) -> Bool {
        guard launch > 0 else { return false }
        switch plan {
        case .free: return launch % every == 0
        case .tester: return launch % everyForTesters == 0
        case .pays, nil: return false
        }
    }
}
