import Foundation

/// What the player is doing, and where the sound is going.
///
/// **Two questions share one state**: what the player is doing, and where the sound goes. They
/// are kept together because answering them separately gives a pause that is true while a speaker
/// is attached and silently false when the sound comes back to the phone.
///
/// This type keeps the pause rule in one place. A rule that lives in several places is easy to
/// break: for example the pump's pause applying only to a cast, the node starter ignoring the
/// pause, `begin` clearing it for every source it puts on, or the room's poll reading a stale
/// status as a user action on the speaker.
///
/// **The rule this type enforces:** only a user action may move ``doing`` away from playing or
/// paused. Every way it can change is a named method below. The methods are either ones a person
/// triggers or ones the machinery triggers. The machinery methods cannot take a record that is
/// playing or paused and make it do something else. (They may start playback when there was
/// nothing, because nobody asked for silence then, so there is no pause to keep.) `PlaybackTests`
/// runs every method against every reachable state.
///
/// **The time before a source arrives is not handled here.** A key pressed while a record is
/// still being signed is ``Transport``'s concern, which is pure and tested. Answering it here as
/// well would duplicate it.
///
/// This type is pure and separate from ``PcmEngine``, as ``Transport`` is, so every question can be
/// tested without an audio engine.
public struct Playback: Sendable, Equatable {

    /// What the player is doing. Not where the sound goes: see ``sent``.
    public enum Doing: Sendable, Equatable {
        /// No source at all: before the first record, and between releasing one source and
        /// receiving the next.
        case nothing

        case playing
        case paused
    }

    /// Where the sound goes. This is separate from whether there is any sound. A paused player
    /// still has a destination, and a cast that returns to the phone does not start playing
    /// because of that.
    public enum Sent: Sendable, Equatable {
        case toTheHandset
        case toTheRoom
    }

    /// Why a record is put on. This decides whether a pause pressed against the previous record
    /// still applies.
    ///
    /// **No call site has a default value.** Every caller must choose one, and the compiler
    /// enforces it. A forgotten choice would let anything that starts a source discard a pause.
    public enum Start: Sendable, Equatable {
        /// A tap on a track, a press of next or previous, a station tuned. Asking to hear
        /// something means asking it to play.
        case somebodyAskedForIt

        /// The queue moved on by itself, a record was moved through, or a record was opened again
        /// after the engine refused to resume. Nobody asked for anything.
        case carryOnAsBefore
    }

    public private(set) var doing: Doing = .nothing
    public private(set) var sent: Sent = .toTheHandset

    public init() {}

    // ── called for a user action: these may change `doing` ──

    /// The user pressed play.
    public mutating func somebodyPressedPlay() {
        doing = .playing
    }

    /// The user pressed pause.
    ///
    /// **This works while a record is still opening.** If the user pressed next and then pause,
    /// they asked for silence, and the record that is on its way must arrive paused. A pause
    /// pressed when there is nothing at all is not handled here: that is
    /// ``Transport/pausePending``, a separate question.
    public mutating func somebodyPressedPause() {
        guard doing != .nothing else { return }
        doing = .paused
    }

    /// A record went on, and ``Start`` says who put it there.
    ///
    /// **This is the only method that puts a source on**, and the only one whose result depends on
    /// the reason. When the user asks for a record, it clears a pause that was set against the
    /// previous one. When the queue moves on by itself, the pause stays. This difference is the
    /// reason for this type.
    ///
    /// A record that goes on when there was nothing plays, whoever put it there. Nobody asked for
    /// silence, so there is no pause to keep.
    public mutating func aRecordWentOn(_ why: Start) {
        switch why {
        case .somebodyAskedForIt: doing = .playing
        case .carryOnAsBefore: if doing == .nothing { doing = .playing }
        }
    }

    /// The room reported what it is doing. A user action on the speaker counts as a user action.
    ///
    /// **The report is only used while the sound is going to the room.** A receiver's report about
    /// a stream this player no longer sends says nothing about this player. Following it would
    /// let a cast that already ended change the state of the local player.
    public mutating func theRoomSaid(playing: Bool) {
        guard sent == .toTheRoom, doing == .playing || doing == .paused else { return }
        doing = playing ? .playing : .paused
    }

    // ── called by the machinery: these must not change `doing` ──

    /// The queue moved on by itself, because a record ended and there is another.
    ///
    /// **Nobody asked for anything**, so the state does not change. This matters for a record that
    /// ends under a paused player: while casting, the look-ahead is never ready with the pump
    /// parked, so the ending takes the slow path through the same call that a tap uses. That call
    /// would otherwise clear the pause.
    public mutating func theQueueMovedOn() {
        if doing == .nothing { return }
    }

    /// A seek. The user moves through the record and does not ask for it again.
    ///
    /// A scrub on a paused record leaves it paused, as in other players. `begin` must not clear
    /// the pause unconditionally, or a seek would start playback.
    public mutating func theRecordWasMovedThrough() {}

    /// The sound is going to a speaker from now on.
    ///
    /// **This is not a reason to start playing, and not a reason to stop.** A user who was
    /// listening continues in the other room. A user who was paused when they chose a speaker has
    /// not asked to hear anything yet.
    public mutating func movedToTheRoom() {
        sent = .toTheRoom
    }

    /// The sound goes back to the handset: the room failed, the speaker was switched off, or the
    /// cast ended. ``doing`` does not change.
    public mutating func cameHome() {
        sent = .toTheHandset
    }


    /// Nothing is left: the queue is finished, or it was stopped.
    public mutating func nothingIsLeft() {
        doing = .nothing
        sent = .toTheHandset
    }

    // ── what everything else reads ──

    /// Whether the user asked for silence. **This is the only question the pump asks**, and it
    /// does not ask where the sound is going at the same time.
    public var isPaused: Bool { doing == .paused }

    /// Whether the sound is going to a speaker instead of the phone.
    public var isCasting: Bool { sent == .toTheRoom }

    /// What ``Transport`` decides from.
    public var loaded: Loaded {
        switch doing {
        case .nothing: return .nothing
        case .playing: return .playing
        case .paused: return .paused
        }
    }
}
