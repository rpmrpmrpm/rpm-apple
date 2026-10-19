import Foundation
import RPMCast

/// What the room is holding of ours, and what the room's reports mean given that.
///
/// **This is the central rule of the whole cast.** A receiver uses the same report for
/// several different events, and which event it means depends on what this side did a
/// moment ago:
///
/// - *Nothing loaded.* Either a user at the speaker, or the short moment in the middle of
///   a track change when our stream has been taken away and the next one has not been
///   handed over yet.
/// - *IDLE, `CANCELLED`.* Either the user pressed stop, or the receiver noticed that the
///   stream it was fetching was cut, which is the first thing a track change does.
/// - *PAUSED.* Either a user at the speaker, or our own pause coming back to us.
///
/// If the reader cannot tell which, every skip looks like a stop: the track changes, the
/// speaker plays half a second of the new track, and the app stops the music and empties
/// the lock screen because the room reported that it was holding nothing.
///
/// So the state is kept here, the reading is a pure function of it, and both are tested.
/// Two facts decide everything:
///
/// - ``session``: the media session of the stream that the room is holding **of ours**.
///   A LOAD sets it and it is cleared as soon as the stream is taken away. Nil means the
///   room is empty because we emptied it, and nothing it reports is news.
/// - ``turns``: how many times that has changed. A report is only about the world it was
///   asked about. The poll reads this number before it asks and passes it back with the
///   answer, so a reply that crossed a track change on the network is dropped and not
///   acted on. **This is an order-independent fact and not a time window.**
public struct RoomStream: Sendable, Equatable {
    /// How far along the sitting is.
    ///
    /// **The stage is stated explicitly.** It is not inferred from which of several
    /// optionals are non-nil (`castingTo`, `sink`, `link`, `castApp`, this type's
    /// session, the engine's room, the sink's room, and three running tasks), each set at
    /// a different line of `Player.cast(to:)`. Inferring it would leave gaps: the poll
    /// would start before `isCasting` became true and every answer in between would be
    /// thrown away, and an error during connection would leave the fetch watchdog waiting
    /// twenty seconds for a cast that no longer exists.
    ///
    /// Each stage says what is true and what may be waiting on it, and leaving a stage
    /// ends the wait.
    public enum Stage: Sendable, Equatable {
        /// No cast.
        case none

        /// A speaker is being connected, or a stream has been taken off the receiver and
        /// the next one is not on yet. **Nothing it reports is news at this stage**: it
        /// holds nothing of ours, so its emptiness is our own doing.
        case connecting

        /// The receiver acknowledged the LOAD, and this is the session that every later key
        /// carries. It has not necessarily fetched anything yet.
        ///
        /// *Waiting on it:* the fetch watchdog. Without it, a speaker that accepts a LOAD
        /// and never fetches the stream would leave the cast silent forever.
        case holding(session: Int)

        /// The receiver is fetching the stream. *Waiting on it:* the stall watch, which
        /// treats a position that stops moving as a room that has gone away.
        case playing(session: Int)

        /// Over: it ended at the speaker, or it failed.
        case gone
    }

    public private(set) var stage: Stage = .none

    /// The media session that the receiver returned, or nil while the room holds nothing
    /// of ours.
    ///
    /// **Every transport message carries it**, and a PAUSE with the wrong one is refused.
    /// So this also answers "can the room be sent anything at all". It is read from
    /// ``stage`` and not stored separately, because two copies could disagree, and that
    /// is the kind of fault this type exists to prevent.
    public var session: Int? {
        switch stage {
        case .holding(let it), .playing(let it): return it
        case .none, .connecting, .gone: return nil
        }
    }

    /// Whether there is a sitting at all, which decides whether the room's reports are
    /// used. **True from the moment a speaker is picked up**, not only after the connect
    /// has finished.
    public var isOn: Bool {
        switch stage {
        case .connecting, .holding, .playing: return true
        case .none, .gone: return false
        }
    }

    /// How many times what the room holds has changed: once when the stream is taken away,
    /// and once when the room takes the next one.
    public private(set) var turns: Int = 0

    /// How many transport keys this side has sent the room.
    ///
    /// **This works like ``turns``, for the same reason, one level lower.** A pause takes
    /// effect here at once and in the room one round trip later. A poll reply that
    /// arrives in between describes a room that is still playing, which looks exactly like
    /// a user at the speaker pressing play, and the player would start playing again. The
    /// user would have to press pause twice.
    ///
    /// So each reply is dated. The poll reads this number before it asks and passes it
    /// back with the answer, and an answer from before the key was pressed says nothing
    /// about the key. **This is a fact that holds whenever it is asked**, not a time
    /// window in which reports are ignored: a slow room and a fast room are both handled
    /// correctly, and no timeout needs tuning.
    public private(set) var told: Int = 0

    /// Keys sent and not yet answered.
    ///
    /// **The date alone does not cover a question asked while a key is on its way.** The
    /// key is sent from a task and the poll asks from its own loop, so its GET_STATUS can
    /// reach the socket first. The room answers in order: first about its state before the
    /// key, but under the new date. A PAUSED from before a PLAY would then look like a user
    /// at the speaker pressing pause, and the player would pause itself just after play
    /// was pressed. So while a key is out, there is no date to ask under; see ``stamp``.
    public private(set) var keysOut: Int = 0

    /// The date that the poll asks under, or nil while a key is on its way. A nil date
    /// means the answer to that question is ignored.
    ///
    /// A question asked after the last key was answered is also answered after the key,
    /// because the room answers one connection in order, so the reply describes the room
    /// as the key left it. This relies on that fact.
    public var stamp: Int? { keysOut == 0 ? told : nil }

    public init() {}

    // ── the two things that can happen to it ──

    /// A transport key is being sent, so no report from before now, or from before the room
    /// has answered the key, decides what is playing.
    public mutating func toldIt() {
        told += 1
        keysOut += 1
    }

    /// The room answered a key, or sending it failed. Either way the key is no longer on its
    /// way.
    public mutating func heardBack() { keysOut = max(0, keysOut - 1) }

    /// A key that could not be sent, kept until it can be sent.
    ///
    /// **A key is not dropped just because the room cannot receive it yet.** Every
    /// transport message carries a media session, and there is no session during a track
    /// change: `takenBack` clears it when our stream comes off the receiver, and
    /// `nowHolding` sets it again only when the next LOAD is acknowledged, after a ring
    /// fill and a network round trip. A pause pressed in that gap would be lost silently
    /// and the speaker would keep playing. On a desktop the gap is about a millisecond. On
    /// a phone across a room from a speaker it is most of a second, long enough for a
    /// user to press a key.
    ///
    /// So the key is kept as a debt and sent when there is a session. The last key wins:
    /// a user who pressed pause and then play in the same gap asked for play.
    private var owing: Bool?

    /// Nothing could be sent, so the key is kept for the next session.
    public mutating func owe(playing: Bool) { owing = playing }

    /// The key that was owed, if any. It clears the debt: sending it twice could send a
    /// pause after the track that the user started.
    public mutating func settleUp() -> Bool? {
        defer { owing = nil }
        return owing
    }

    /// Our audio is off the receiver, and until it is given another stream **nothing it
    /// reports is news**.
    ///
    /// Cutting the connection and forgetting the session are one action. If the connection
    /// is cut but the session is kept, the poll reads our own track change as a user at
    /// the speaker. If the session is forgotten but the connection is kept, the old
    /// connection keeps consuming a ring that now holds the next track.
    /// `Player.takeTheRoomsStream` is the only place that does both.
    public mutating func takenBack() {
        if isOn { stage = .connecting }
        turns += 1
    }

    /// A speaker is being connected. **This is the first step**: the sitting begins here
    /// and not when the connect has finished, so reports that arrive while the cast is
    /// being set up are not dropped.
    public mutating func pickingUp() {
        stage = .connecting
        turns += 1
    }

    /// The receiver fetched the stream. Whatever was waiting on ``Stage/holding`` is done.
    public mutating func itFetched() {
        guard case .holding(let it) = stage else { return }
        stage = .playing(session: it)
    }

    /// The receiver took a new stream, and this is the session that every later key carries.
    public mutating func nowHolding(_ session: Int) {
        stage = .holding(session: session)
        turns += 1
    }

    /// The cast is over.
    public mutating func gone() {
        stage = .gone
        owing = nil
        turns += 1
    }

    // ── reading what it says ──

    /// Why the music is being stopped.
    ///
    /// This is a closed set and not free text, so a test can check which of the three cases
    /// happened without matching a sentence.
    public enum Because: String, Sendable, Equatable {
        /// The receiver answered and has no media. This is how a stop at the speaker looks
        /// on a receiver that keeps its app running.
        case holdingNothing = "the room is holding nothing"

        /// `IDLE`, and the reason is a stop and not a track that finished.
        case letTheMusicGo = "the room let the music go"

        /// The receiver **application** is gone. This is how a stop at the speaker looks on a
        /// Google speaker, which quits the app and does not just clear its media.
        case closedTheReceiver = "the room closed the receiver"
    }

    /// What the player should do about a report.
    public enum Word: Sendable, Equatable {
        /// The report contains nothing that this side should act on.
        case nothing

        /// A user paused at the speaker's own controls, in the Home app, or by voice.
        case pause

        /// A user started playback again.
        case resume

        /// **The user asked for silence.** The sitting ends: the queue is stopped and the
        /// cast is closed after it, because the speaker has already ended it on its side.
        /// The desktop does the same in one line: `sink.RemoteStopped += () => Stop()`.
        case stopped(Because)

        /// **The speaker stopped working as a destination.** This is a different case:
        /// nobody asked for silence, so the sound moves back to the phone and keeps
        /// playing there. `PlaybackService.cs` keeps the two cases apart in the same way:
        /// `sink.Failed` calls `StopCasting()`, and only `RemoteStopped` calls `Stop()`.
        case fellOver(String)
    }

    /// Interprets the room's reply to "where are you".
    ///
    /// - Parameters:
    ///   - askedUnder: ``turns`` at the moment the question was asked. A reply about a
    ///     state that has since been replaced is dropped.
    ///   - playback: what this side is doing, **as the object that owns that state
    ///     reports it**, and not a `Bool` that the caller reads from it. If the caller
    ///     passed a single fact, the caller would decide which question matters. Passing
    ///     the object lets this method ask what it needs, and a new question is a change
    ///     in one place. Here it needs to know whether we are already paused: the engine
    ///     pauses before the receiver reports it, so a report that agrees with us is
    ///     never news.
    ///   - toldUnder: ``stamp`` at the moment the question was asked. A reply from before
    ///     this side pressed a key describes the room as it was before the key. A room
    ///     that disagrees with a key it has not received yet is not a user at the speaker.
    public func reading(_ report: RoomReport, askedUnder: Int, toldUnder: Int?,
                        against playback: Playback) -> Word {
        // **The question was about a state that no longer exists.** A GET_STATUS sent
        // before a track change and answered after it describes the stream that was
        // replaced. Its answer (nothing loaded) looks exactly like a stop.
        guard askedUnder == turns else { return .nothing }

        // **Asked before a key was pressed and answered after it.** The room disagrees
        // with us only because it has not received the key yet. The reply is dropped and
        // not followed: the next poll asks again under the new number, and that answer is
        // about the key.
        //
        // **Or asked while a key was on its way**, which has no date: see ``stamp``.
        guard let toldUnder, toldUnder == told else { return .nothing }

        // Nothing of ours is in the room, so its emptiness is our own doing.
        guard let session else { return .nothing }

        switch report {
        case .noAnswer:
            return .nothing

        case .nothingLoaded:
            return .stopped(.holdingNothing)

        case .holding(let said):
            // A status about the stream that was replaced. It carries its own session id,
            // so this check is exact and does not depend on timing.
            guard said.mediaSessionId == session else { return .nothing }

            switch said.playerState {
            case "PAUSED" where !playback.isPaused:
                return .pause

            case "PLAYING" where playback.isPaused:
                return .resume

            // **Stopped, not finished.** `idleReason` tells them apart: our stream running
            // out means a track ended and the queue moves on, while a stop at the speaker
            // means the user asked for silence. Playing the next song then would be the
            // opposite of what the user asked for.
            case "IDLE" where said.idleReason == "CANCELLED" || said.idleReason == "INTERRUPTED":
                return .stopped(.letTheMusicGo)

            default:
                return .nothing
            }
        }
    }

    /// Interprets the **device's** own status. This is where a stop on a Google speaker
    /// shows up: it quits the receiver application, and the media transport goes with it,
    /// so a question to that transport gets no reply at all.
    ///
    /// The check looks for our session, not only for an empty list: a device that hosts
    /// some other application is not this cast either.
    ///
    /// **It has the same guards as the transport report above, for the same reason.**
    /// Without them, a track change could still be read as a stop. A receiver whose media
    /// has just been taken away has nothing to do, and a Google speaker quits the
    /// application in that state. If the device is asked in that gap, it correctly answers
    /// that our session is gone, and that answer would look like a user pressing stop in
    /// the room.
    ///
    /// - Parameter askedUnder: ``turns`` at the moment the question was asked. A reply
    ///   about a world that has since been replaced is dropped.
    public func reading(_ status: ReceiverStatus, ours session: String, askedUnder: Int) -> Word {
        guard askedUnder == turns else { return .nothing }

        // Nothing of ours is in the room, so the application leaving is our own doing and
        // not news. The LOAD that follows launches it again.
        guard self.session != nil else { return .nothing }

        guard !status.applications.contains(where: { $0.sessionId == session })
        else { return .nothing }

        return .stopped(.closedTheReceiver)
    }
}
