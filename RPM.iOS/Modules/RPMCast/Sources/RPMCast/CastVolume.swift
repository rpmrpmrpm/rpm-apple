import Foundation

/// The volume conversation with a cast speaker, in one place. It holds the level that the room is set to, the level
/// that this app has asked for, and the rule for which of the two to believe when they disagree.
///
/// This matches `RPM.Core/Audio/CastVolume.cs`. Both apps use the same rules, so the volume behaves the same on each.
///
/// While casting, the speaker owns the volume. Its own buttons, the Google Home app, a voice command, and this app can all
/// change it. So the volume is a shared conversation, not a plain setting. A conversation has two failure modes that a
/// simple `setVolume` call runs into.
///
/// **First problem: echo.** Every level change that is sent comes back as a status. So does the level the speaker had a
/// moment before. If the app believed every status, it would move back to its own old values. For example, it asks for
/// 40, is told 55, and then goes back to 55. So a report that differs from the last request counts only after the speaker
/// has been quiet long enough that the change must have come from someone else.
///
/// **Second problem: order.** A drag on a slider, or a held volume key, sends changes faster than the speaker can answer.
/// If two sends are in flight, they can arrive in either order, and the one that arrives last wins. So sends are merged to
/// the latest value, sent at a steady rate, with one send in flight at a time.
public final class CastVolume: @unchecked Sendable {
    /// How often a change is sent while the level is still moving.
    ///
    /// A drag can produce a change for each pixel. Sending each one is chatty. The speaker answers each one, and the answers
    /// arrive out of order with the drag. Sending the latest value at a steady rate avoids both problems. A hardware volume
    /// knob works the same way.
    public static let interval: Duration = .milliseconds(120)

    /// How long after our own change the speaker's reports are ignored.
    ///
    /// The speaker reports the level it had when it answered, not the level we have just asked for. So a status that is in
    /// flight during a drag is always out of date. Believing it would pull the level backwards, under the finger that is
    /// moving it. After this time with nothing sent, the speaker's reports are believed again. The change may have come
    /// from someone in the room.
    public static let echo: Duration = .seconds(2)

    private let send: @Sendable (Double) async -> Void
    private let every: Duration
    private let quiet: Duration

    private let gate = NSLock()

    /// The level that was last requested, and when. Negative means that nothing has been requested yet.
    private var wanted = -1
    private var sentAt: ContinuousClock.Instant?
    private var sending = false

    private var at = 100
    private var closed = false

    public init(every: Duration = CastVolume.interval,
                quiet: Duration = CastVolume.echo,
                send: @escaping @Sendable (Double) async -> Void) {
        self.send = send
        self.every = every
        self.quiet = quiet
    }

    /// Where the knob is, from 0 to 100, as far as this side knows.
    public var level: Int { gate.withLock { at } }

    /// The listener has moved the knob.
    ///
    /// `live` says whether a stream is playing for the speaker to turn up. **There is no default, on purpose.** A level sent
    /// to a sink as soon as it is created, before anything is loaded, causes a real bug. A room at 20% would jump to whatever
    /// level the phone was at. If `live` is false, the number is stored and nothing is sent. The room's own level arrives
    /// shortly after through ``adopt(_:)``, and it replaces this number.
    public func set(_ volume: Int, live: Bool) {
        let go = gate.withLock { () -> Bool in
            at = min(100, max(0, volume))
            guard live, !closed else { return false }

            wanted = at
            sentAt = ContinuousClock.now

            // The sender is already awake, and it will pick this up.
            guard !sending else { return false }
            sending = true
            return true
        }

        guard go else { return }
        Task { await pushUntilItSettles() }
    }

    /// The speaker has reported where its knob is, from 0 to 1.
    ///
    /// Returns the level to move the player to, or nil when nothing should change. That covers four cases: the speaker has
    /// not reported a level; the report is an echo of our own change; the level has not really changed; and the cast is over.
    /// The last case matters. A status that is already on the wire when a cast ends arrives afterwards. A player that acted on
    /// it would set the volume of something else to a level that was never meant for it.
    public func adopt(_ deviceLevel: Double?) -> Int? {
        guard let deviceLevel else { return nil }

        return gate.withLock {
            guard !closed else { return nil }

            let volume = Int((min(1, max(0, deviceLevel)) * 100).rounded())
            let since = sentAt.map { ContinuousClock.now - $0 } ?? .seconds(86400)

            // Our own level, echoed back, or long enough after our change that it is someone else's doing.
            guard wanted < 0 || volume == wanted || since >= quiet else { return nil }

            // A difference of one point either way is the speaker's own rounding, not a person turning the knob.
            // Following it would move the level away from the number that the listener chose.
            guard abs(volume - at) > 1 else { return nil }

            at = volume
            return volume
        }
    }

    /// Nothing more is sent to this speaker. The sender stops at its next turn.
    public func close() { gate.withLock { closed = true } }

    /// Sends the latest requested level, no faster than the interval, until the level stops changing.
    /// **Only one send is in flight at a time.** Two sends that overlap can arrive at the speaker in either order.
    /// The speaker keeps whichever one arrives last.
    private func pushUntilItSettles() async {
        defer { gate.withLock { sending = false } }

        while true {
            let (asking, over) = gate.withLock { (wanted, closed) }
            guard !over else { return }

            await send(Double(asking) / 100)
            try? await Task.sleep(for: every)

            let settled = gate.withLock { () -> Bool in
                guard wanted == asking else { return false }
                sending = false
                return true
            }
            if settled { return }
        }
    }
}
