import Foundation

/// The record's time for the karaoke words: the player's position, made steady. The same clock as the
/// Android phone's (`KaraokeClock` in its `core`).
///
/// The position the player reports moves in steps. It is read from the engine a few times a second,
/// and the reading can be early or late by a part of a second, forward or back, while the sound itself
/// plays on evenly. The lit letters follow the time they are given, so a step back would put out
/// letters that are already lit, and a step forward would light several at once.
///
/// This clock runs at the speed of the caller's clock and moves towards the reported position slowly,
/// never faster than ``slew`` of the time that passes, so it never goes back while the record plays.
/// A step of a quarter of a second is taken up over about five seconds, and steps forward and back in
/// turn mostly cancel. A difference larger than ``snap`` is a seek or a new record, and the clock goes
/// straight there; so does a record that stands still.
///
/// One clock serves one view of the lyrics, on one thread. It is a class so that the view can keep it
/// across redraws without the redraws counting as changes.
public final class KaraokeClock {
    /// How much faster or slower than the caller's clock this clock may run while it moves to the
    /// reported position.
    public static let slew = 0.05

    /// A difference from the reported position, in seconds, past which the clock goes straight there.
    public static let snap = 0.6

    /// The time shown, in seconds of the record, at `at` on the caller's clock.
    private var shown = Double.nan
    private var at = 0.0

    public init() {}

    /// The time to show at `now`, in seconds of the record. `reported` is the player's position at
    /// `now`, carried forward from its last reading. `advancing` is whether the record plays. `now`
    /// is any clock in seconds that only goes forward, the same one on every call.
    public func seconds(reported: Double, advancing: Bool, at now: Double) -> Double {
        if !advancing || shown.isNaN { return set(reported, at: now) }
        // Asked about a moment before the last one: read off the clock, which is not moved.
        if now < at { return shown - (at - now) }

        let passed = now - at
        let carried = shown + passed
        let off = reported - carried
        if abs(off) > Self.snap { return set(reported, at: now) }
        return set(carried + min(max(off, -passed * Self.slew), passed * Self.slew), at: now)
    }

    private func set(_ seconds: Double, at now: Double) -> Double {
        shown = seconds
        at = now
        return seconds
    }
}
