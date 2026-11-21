import Foundation
import Observation
import RPMDesign

/// Whether the welcome has been shown on this phone, and which first-run hints have been answered.
///
/// Kept in the defaults under the keys the Android app uses: `welcome.done` and `coach.seen` (one
/// hint key per line, see ``CoachSeen``). The welcome shows once, on the first launch with an
/// account. Each hint shows once. The Hints card in Settings puts both back (``replay()``).
///
/// One object for the app, because the shell, the player's hints and the settings card all read and
/// write the same two values, and each of them must see a change at once.
@MainActor
@Observable
public final class FirstRun {
    /// The one store for the whole app.
    public static let shared = FirstRun(store: .standard)

    /// Whether the welcome has been shown (or was never due).
    public private(set) var welcomed: Bool

    /// The hints answered.
    public private(set) var seen: CoachSeen

    private let store: UserDefaults

    init(store: UserDefaults) {
        self.store = store
        welcomed = store.bool(forKey: Self.welcomedKey)
        seen = CoachSeen(stored: store.string(forKey: Self.seenKey))
    }

    /// Decides once whether this phone is new to rpm. Call it as soon as the app knows whether an
    /// account is signed in. See ``FirstRunRule``.
    public func settle(signedIn: Bool) {
        guard let settled = FirstRunRule.settle(decided: store.object(forKey: Self.welcomedKey) != nil,
                                                signedIn: signedIn)
        else { return }
        welcomed = settled.welcomed
        seen = settled.seen
        save()
    }

    /// The welcome is over: played through, or skipped.
    public func finishWelcome() {
        welcomed = true
        save()
    }

    /// Marks the hint `key` as answered.
    public func see(_ key: String) {
        guard !seen.has(key) else { return }
        seen.see(key)
        save()
    }

    /// Marks every hint in `keys` as answered: what the close key on a hint does to its tour.
    public func see(_ keys: [String]) {
        var all = seen
        for key in keys { all.see(key) }
        guard all != seen else { return }
        seen = all
        save()
    }

    /// Puts the welcome and every hint back, from the Hints card in Settings. The welcome shows
    /// again at once.
    public func replay() {
        seen = CoachSeen()
        welcomed = false
        save()
    }

    private func save() {
        store.set(welcomed, forKey: Self.welcomedKey)
        store.set(seen.stored, forKey: Self.seenKey)
    }

    static let welcomedKey = "welcome.done"
    static let seenKey = "coach.seen"
}
