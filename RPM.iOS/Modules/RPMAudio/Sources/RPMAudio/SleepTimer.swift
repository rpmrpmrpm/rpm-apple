import Foundation

/// When the player pauses by itself: at a set time, or when the track playing ends.
///
/// Pure, like ``Transport``: ``Player`` holds one, runs the clock and asks it. Every
/// question takes the time it is asked at, so a test can ask it without waiting.
///
/// Take care when changing when the player asks it a question. A scheduled wake can
/// arrive after the setting has changed (see `deadlineArrived(now:)` and
/// `somebodyAskedForSound(now:)`).
public struct SleepTimer: Sendable, Equatable {

    /// What the timer is set to.
    public enum Setting: Sendable, Equatable {
        /// Pause at this instant. `ContinuousClock` keeps counting while the device
        /// sleeps, so the time asleep is counted.
        case at(ContinuousClock.Instant)

        /// Pause when the track playing ends by itself. Skipping to another track moves
        /// the timer to that track; it does not fire.
        case endOfTrack
    }

    /// One of the options offered in the menu.
    public enum Choice: Sendable, Hashable {
        case after(Duration)
        case endOfTrack
    }

    /// The options the menu offers, in order. The drawer adds the same durations to a
    /// running timer.
    public static let durations: [Duration] = [.seconds(5 * 60), .seconds(15 * 60),
                                               .seconds(30 * 60), .seconds(60 * 60)]

    public private(set) var setting: Setting?

    public init() {}

    public var isOn: Bool { setting != nil }

    /// Whether the timer waits for the track to end rather than for a time.
    public var endsWithTheTrack: Bool { setting == .endOfTrack }

    // ── set by the user ──

    public mutating func set(_ choice: Choice, now: ContinuousClock.Instant) {
        switch choice {
        case .after(let wait): setting = .at(now + wait)
        case .endOfTrack: setting = .endOfTrack
        }
    }

    /// Adds time to a running timer.
    ///
    /// A timer waiting for the end of the track becomes a timed one, counted from the
    /// moment the track would have ended. Example: adding 5 minutes during the last
    /// minute of a song gives 6 minutes from now, not 5.
    ///
    /// - Parameter trackLeft: how much of the track playing is left, or nil when there
    ///   is no track (a station). **No default**: without it an end-of-track timer would
    ///   be counted from now, and the rest of the song would be lost silently.
    public mutating func add(_ more: Duration, now: ContinuousClock.Instant,
                             trackLeft: Duration?) {
        switch setting {
        case .at(let deadline): setting = .at(max(deadline, now) + more)
        case .endOfTrack: setting = .at(now + (trackLeft ?? .zero) + more)
        case nil: break
        }
    }

    public mutating func turnOff() { setting = nil }

    // ── what the player asks ──

    /// Time left at `now`, or nil when the timer is off.
    ///
    /// - Parameter trackLeft: the track's own time left, which is the answer for an
    ///   end-of-track timer. Nil when there is no track, and then there is no value.
    public func left(now: ContinuousClock.Instant, trackLeft: Duration?) -> Duration? {
        switch setting {
        case .at(let deadline): return max(.zero, deadline - now)
        case .endOfTrack: return trackLeft
        case nil: return nil
        }
    }

    /// The scheduled wake for the deadline arrived. Returns whether to pause, and turns
    /// the timer off when it does.
    ///
    /// **The answer comes from the setting, not from the wake.** A wake scheduled before
    /// time was added can still arrive later, and then its deadline is no longer the
    /// current one. Answering from the setting makes a stale wake do nothing, in
    /// whichever order the wake and the change arrive.
    public mutating func deadlineArrived(now: ContinuousClock.Instant) -> Bool {
        guard case .at(let deadline) = setting, deadline <= now else { return false }
        setting = nil
        return true
    }

    /// The track playing ended by itself. Returns whether to pause, and turns the timer
    /// off when it does.
    public mutating func trackEnded() -> Bool {
        guard setting == .endOfTrack else { return false }
        setting = nil
        return true
    }

    /// Somebody asked for sound: play, a track, a station.
    ///
    /// **A deadline that has already passed is turned off**, so it cannot pause what was
    /// just asked for. Case: the timer runs out while the music is paused and iOS has
    /// suspended the app, then play is pressed on the lock screen. The app wakes with
    /// both the wake and the play due. If play were handled first, the wake would then
    /// silence it.
    public mutating func somebodyAskedForSound(now: ContinuousClock.Instant) {
        if case .at(let deadline) = setting, deadline <= now { setting = nil }
    }

    /// A station was tuned. A station has no end, so a timer waiting for one is turned
    /// off instead of waiting for ever. A timed one carries on.
    public mutating func stationTuned() {
        if setting == .endOfTrack { setting = nil }
    }
}
