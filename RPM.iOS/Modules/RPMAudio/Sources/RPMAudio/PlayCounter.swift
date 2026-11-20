import Foundation
import RPMKit

/// What turns readings of the player into plays.
///
/// **It returns the play, and the listen, to the caller and does not write them anywhere.** The tally underneath is a
/// running sum across seeks, so the readings must reach it in the order the player took them. If
/// the counter awaited a store on every reading, the readings would come from tasks that can
/// arrive in any order, and a stretch could be scored against the wrong reading. So this class is
/// main-actor and synchronous, and is driven by the player's own tick. The caller writes the
/// result to the ``PlayLog``, which does not depend on order: a play is an increment and a
/// timestamp is a maximum.
///
/// **There is one settle point.** It is the phone's version of the desktop's single entry into
/// `NoteListen`. A second way to add a play would be a second way for the tally and the log to
/// disagree.
@MainActor
public final class PlayCounter {
    /// A play that counted: the track it was for, and when the listen ended.
    public struct Counted: Equatable, Sendable {
        public let rpmId: String
        /// Unix seconds, for ordering what has been listened to.
        public let at: Int64
    }

    /// A listen worth writing down in the listening log: a play, or a skip. See ``Listen``.
    public struct Heard: Equatable, Sendable {
        public let rpmId: String
        /// When the listen ended, unix seconds.
        public let at: Int64
        /// Audio actually delivered, across seeks.
        public let heardSeconds: Double
        public let lengthSeconds: Double
        /// Whether it counted as a play.
        public let counted: Bool
        /// 0 to 23 on this device's clock when the listen ended.
        public let localHour: Int
        /// 0 = Sunday, on the same clock.
        public let localDayOfWeek: Int

        /// The play it was, or nil for a skip.
        public var play: Counted? { counted ? Counted(rpmId: rpmId, at: at) : nil }
    }

    private var tally = ListenTally()
    private let now: () -> Date
    private let zone: () -> TimeZone

    /// Where the current stretch began, in seconds into the track. This is why "heard" means audio
    /// delivered and not the position reached: a seek forward starts a new stretch at the
    /// position where it landed, so the skipped part is never credited.
    private var stretchFrom: Double = 0

    /// The playback position at the last reading. ``settle()`` starts the next stretch from here.
    private var position: Double = 0

    private var session = 0

    /// Whether the seek that is about to arrive has already reported where it landed. A reading
    /// taken before the engine follows still has the OLD position, and the stretch must not start
    /// there.
    private var toldWhereItLanded = false

    /// - Parameter zone: the clock the listen's hour and weekday are read on. This device's own,
    ///   except in a test.
    public init(now: @escaping () -> Date = Date.init, zone: @escaping () -> TimeZone = { .current }) {
        self.now = now
        self.zone = zone
    }

    /// Takes a reading of the player and returns the play it ended, if it ended one that counted.
    public func read(track: CloudTrack?, session: Int, position: Double, duration: Double) -> Counted? {
        readListen(track: track, session: session, position: position, duration: duration)?.play
    }

    /// Ends the current listen and returns the play, if it counted. See ``settleListen()``.
    public func settle() -> Counted? { settleListen()?.play }

    /// Takes a reading of the player and returns the listen it ended, if it ended one worth writing
    /// down: a play or a skip.
    ///
    /// - Parameter track: What is playing, or nil for nothing and for radio, which has no track to
    ///   count against.
    /// - Parameter session: The player's play session. It changes on every play, stop, station and
    ///   seek. It tells a seek apart from a track that plays on, which the position alone cannot.
    public func readListen(track: CloudTrack?, session: Int, position: Double, duration: Double) -> Heard? {
        // A new stream: the stretch starts at the current position. The exception is when the seek
        // that made it has already reported where it landed. Then that value is correct and this
        // reading may still hold the old position: on the casting path the position changes
        // several awaits before the room receives the new stream.
        if session != self.session {
            if !toldWhereItLanded { stretchFrom = position }
            toldWhereItLanded = false
            self.session = session
        }

        self.position = position

        let finished = tally.read(
            track: track?.rpmId, session: session, startSeconds: stretchFrom,
            heardSeconds: max(0, position - stretchFrom), lengthSeconds: duration)

        // A new stretch starts where the new track does. For a changeover that is its beginning.
        if finished != nil { stretchFrom = position }

        return heard(finished)
    }

    /// Ends the current listen. Use it when the player stops or the app goes to the background.
    ///
    /// **The next stretch starts at the current position**, because the audio does not stop when
    /// the app goes away. If the stretch start stayed where it was, the next reading would open a
    /// new listen and credit it with everything this settle just counted, so every trip to another
    /// screen and back would add a play.
    public func settleListen() -> Heard? {
        let finished = tally.settle()
        stretchFrom = position
        return heard(finished)
    }

    /// Where a seek landed.
    ///
    /// The seek reports its target directly and the next tick is not used, because the two
    /// disagree for a short time on the casting path: the position changes as soon as the user
    /// releases the control, but the room receives the new stream several awaits later. If the
    /// tick were used, the stretch would start at the OLD position and the jump itself would be
    /// credited as listening.
    public func seeked(to seconds: Double) {
        stretchFrom = seconds
        position = seconds
        toldWhereItLanded = true
    }

    /// The rules, applied in one place. A listen is written down when the track is long enough to
    /// judge and was heard for a few seconds (``Listen/worthRecording(heard:length:)``), and it has
    /// a cloud id (a row without a key cannot be sent). It counts as a play when it was heard for
    /// half of its length or four minutes.
    private func heard(_ listen: ListenTally.Listened?) -> Heard? {
        guard let listen,
              !listen.track.isEmpty,
              Listen.worthRecording(heard: listen.heardSeconds, length: listen.lengthSeconds)
        else { return nil }

        let ended = now()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone()
        let parts = calendar.dateComponents([.hour, .weekday], from: ended)

        return Heard(
            rpmId: listen.track,
            at: Int64(ended.timeIntervalSince1970),
            heardSeconds: listen.heardSeconds,
            lengthSeconds: listen.lengthSeconds,
            counted: Listen.counts(heard: listen.heardSeconds, length: listen.lengthSeconds),
            localHour: parts.hour ?? 0,
            // Calendar counts Sunday as 1. The log counts it as 0, as the desktop does.
            localDayOfWeek: (parts.weekday ?? 1) - 1)
    }
}
