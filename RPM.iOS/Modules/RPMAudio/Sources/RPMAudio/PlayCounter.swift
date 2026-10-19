import Foundation
import RPMKit

/// What turns readings of the player into plays.
///
/// **It returns the play to the caller and does not write it anywhere.** The tally underneath is a
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

    private var tally = ListenTally()
    private let now: () -> Date

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

    public init(now: @escaping () -> Date = Date.init) {
        self.now = now
    }

    /// Takes a reading of the player and returns the play it ended, if it ended one that counted.
    ///
    /// - Parameter track: What is playing, or nil for nothing and for radio, which has no track to
    ///   count against.
    /// - Parameter session: The player's play session. It changes on every play, stop, station and
    ///   seek. It tells a seek apart from a track that plays on, which the position alone cannot.
    public func read(track: CloudTrack?, session: Int, position: Double, duration: Double) -> Counted? {
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

        return counted(finished)
    }

    /// Ends the current listen. Use it when the player stops or the app goes to the background.
    ///
    /// **The next stretch starts at the current position**, because the audio does not stop when
    /// the app goes away. If the stretch start stayed where it was, the next reading would open a
    /// new listen and credit it with everything this settle just counted, so every trip to another
    /// screen and back would add a play.
    public func settle() -> Counted? {
        let finished = tally.settle()
        stretchFrom = position
        return counted(finished)
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

    /// The rule, applied in one place: the track is long enough to judge, it was heard for half
    /// of its length or four minutes, and it has a cloud id (a row without a key cannot be sent).
    private func counted(_ listen: ListenTally.Listened?) -> Counted? {
        guard let listen,
              !listen.track.isEmpty,
              Listen.counts(heard: listen.heardSeconds, length: listen.lengthSeconds)
        else { return nil }

        return Counted(rpmId: listen.track, at: Int64(now().timeIntervalSince1970))
    }
}
