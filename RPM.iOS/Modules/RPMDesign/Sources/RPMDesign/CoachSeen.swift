import Foundation

/// The first-run hints that have been shown and answered, by their keys.
///
/// A hint is answered once, with Next or with its close key, and is then never shown again. The
/// keys are the desktop's and the Android app's (`coach.seen`), so the same hint has the same name
/// everywhere. ``all`` stands for every hint at once: it is what a person who had the app before
/// the hints existed is given, so they are not walked through them.
///
/// The value is kept in the defaults as one string, one key per line (``stored``).
public struct CoachSeen: Equatable, Sendable {
    /// In ``keys``, every hint at once.
    public static let all = "*"

    /// The keys of the hints answered.
    public private(set) var keys: Set<String>

    public init(keys: Set<String> = []) {
        self.keys = keys
    }

    /// Every hint, answered.
    public static var everything: CoachSeen { CoachSeen(keys: [all]) }

    /// Read back from ``stored``. Nil or an empty string is no hint seen. Blank lines are left out.
    public init(stored: String?) {
        let lines = (stored ?? "").split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        keys = Set(lines.filter { !$0.isEmpty })
    }

    /// The form kept in the defaults: one key per line, sorted, so the same set is always the same
    /// string.
    public var stored: String { keys.sorted().joined(separator: "\n") }

    /// Whether the hint `key` was shown and answered.
    public func has(_ key: String) -> Bool {
        keys.contains(Self.all) || keys.contains(key)
    }

    /// Marks the hint `key` as answered.
    public mutating func see(_ key: String) {
        guard !has(key) else { return }
        keys.insert(key)
    }

    /// The hint of a tour to show now: the first in the tour's order that is not answered and whose
    /// part of the screen is shown. A hint whose part is not on the screen waits, and the next one
    /// in the tour can show before it.
    ///
    /// - Parameters:
    ///   - tour: the keys of the tour's hints, in order.
    ///   - shown: whether the part a hint points at is on the screen now.
    public func due(in tour: [String], shown: (String) -> Bool) -> String? {
        tour.first { !has($0) && shown($0) }
    }
}

/// Whether a phone is new to rpm, decided once, on the first run of a build that has the welcome.
///
/// A person who is already signed in then had the app before: they see neither the welcome nor the
/// hints. A person who still has to sign in is new, and sees both after signing in. The Android app
/// decides the same way (`settleFirstRun`).
public enum FirstRunRule {
    /// What to store, or nil when it was decided before and nothing changes.
    ///
    /// - Parameters:
    ///   - decided: whether the welcome's flag is already in the defaults.
    ///   - signedIn: whether an account is signed in on this launch.
    public static func settle(decided: Bool, signedIn: Bool) -> (welcomed: Bool, seen: CoachSeen)? {
        guard !decided else { return nil }
        return (welcomed: signedIn, seen: signedIn ? .everything : CoachSeen())
    }
}
