import Foundation

/// What the engine is holding. This is not the same as what the user asked for.
public enum Loaded: Sendable {
    /// No source at all: after one track is released and before the next is handed over.
    case nothing

    case playing
    case paused
}

/// What pressing a transport key comes to.
public enum TransportMove: Equatable, Sendable {
    /// The key changes nothing: pause on a paused player, or play on a playing one.
    case nothing

    case pause
    case resume

    /// There is nothing to pause yet. Pause when the source arrives.
    case remember

    /// A remembered pause is cancelled: play was pressed before the source arrived.
    case forget
}

/// Play, pause, and the difference between what the player is doing and what the user
/// asked for.
///
/// Ported from `RPM.Core/Playback/Transport.cs`, with its tests. Every case below can
/// happen on the lock screen, where play and pause are separate commands and not one
/// toggle. A wrong answer there does not just do nothing, it does the opposite.
///
/// **Starting a track takes time.** An address is signed, an asset header is read and a
/// first block is decoded. The old source is released at the very start, so the previous
/// track stops at once and does not keep playing under the new track's title. During
/// this time the engine holds nothing, so "is it playing?" is false. That answer is
/// correct but it is the wrong question. If the user pressed next and then pause, they
/// asked for silence. A player that answered "there is nothing to pause" would ignore
/// the press and start playing a moment later.
///
/// So the press is remembered and applied as soon as a source exists. This type also
/// answers ``wantsToPlay(starting:loaded:)``, which the play key and the lock screen
/// show: **the user's intent, not the engine's state**. The key that was paused does not
/// change back to a play key while the paused track is still opening.
///
/// Pure, and separate from ``Player`` for the same reason as ``QueueEdit``: every one of
/// these cases can be tested without an audio engine.
public struct Transport: Sendable {
    /// Pause was pressed when there was nothing yet to pause.
    public private(set) var pausePending = false

    public init() {}

    /// A track is being prepared.
    ///
    /// Anything remembered for the previous track is cleared. Choosing a track means the
    /// user wants to hear it, so a pause pressed while the previous track was loading
    /// must not carry over and silence the track they just chose.
    public mutating func starting() { pausePending = false }

    /// Stopped, or handed to something that does not use the start path, such as a radio
    /// station. Nothing is coming, so there is no pause to apply.
    public mutating func forgotten() { pausePending = false }

    /// A source is being handed to the engine. Returns whether it should be paused on
    /// arrival.
    ///
    /// Consumes the pending press. It has been applied once, and applying it twice would
    /// also pause the next track.
    public mutating func arrives() -> Bool {
        let pending = pausePending
        pausePending = false
        return pending
    }

    /// Whether the user has asked for sound, which is different from whether sound is
    /// coming out yet. The play key shows this, and the lock screen uses it as the
    /// playback rate.
    ///
    /// When the engine holds a source, its state is the answer. Only while it holds
    /// nothing is the user's intent the only information.
    ///
    /// - Parameter starting: whether a track is on its way to the engine.
    public func wantsToPlay(starting: Bool, loaded: Loaded) -> Bool {
        switch loaded {
        case .playing: return true
        case .paused: return false
        case .nothing: return starting && !pausePending
        }
    }

    public mutating func pause(starting: Bool, loaded: Loaded) -> TransportMove {
        if loaded == .playing { return .pause }
        if loaded == .paused { return .nothing }

        // Nothing is coming, so the pause has nothing to apply to. A pause kept on an idle
        // player would silence whatever is chosen next.
        guard starting, !pausePending else { return .nothing }

        pausePending = true
        return .remember
    }

    public mutating func play(starting: Bool, loaded: Loaded) -> TransportMove {
        if loaded == .paused { return .resume }
        if loaded == .playing { return .nothing }

        guard starting, pausePending else { return .nothing }

        pausePending = false
        return .forget
    }

    /// The headphone button, the steering-wheel button and the key in the app: one press
    /// that means the opposite of what was asked for last.
    public mutating func toggle(starting: Bool, loaded: Loaded) -> TransportMove {
        wantsToPlay(starting: starting, loaded: loaded)
            ? pause(starting: starting, loaded: loaded)
            : play(starting: starting, loaded: loaded)
    }
}

extension Loaded: Equatable {}
