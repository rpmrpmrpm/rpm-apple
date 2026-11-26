import Foundation

/// What the player does after the phone's output device changed under the engine
/// (``PcmEngine/deviceChanged``), for example when a Bluetooth device connects.
///
/// iOS stops the engine for such a change, and what was scheduled in front of the node can go
/// with the stop. The record must be fed to the engine again **from where it was heard**. The
/// feed the record is playing from can move to any second (a seek does the same), so the record
/// goes on from that second and is not opened again from its top.
///
/// **One device can post several changes.** A Bluetooth device that connects can change the route
/// and then the sample rate, and each change stops the engine and posts its own notification.
/// Acting on each one would feed the record to the engine several times in a row, and each time
/// is a gap in the sound. So the player waits for ``settle`` after a change and acts only if no
/// later change arrived in that time. The wait also lets the pause from a device going away arrive
/// first (see `RemoteControl.routeChanged`), so the record is not started again on the phone's own
/// speaker.
///
/// Pure, and separate from ``Player`` for the same reason as ``Transport``: every case can be
/// tested without an audio engine.
struct DeviceChanges: Sendable {
    /// How long the player waits after a change before it acts on it. Short next to the gap that
    /// iOS itself leaves when the output device changes.
    static let settle: Duration = .milliseconds(250)

    /// What to do once a change has settled.
    enum Answer: Equatable, Sendable {
        /// Nothing. A later change will answer instead, or the sound is not on this phone's
        /// engine, or a start is on its way and starts the engine again by itself.
        case nothing

        /// Paused: nothing is fed now, because that could make a sound. The next Play feeds the
        /// record again from where it was paused.
        case onPlay

        /// The record is fed to the engine again from the second where it was heard, from the
        /// feed it is already playing from.
        case carryOnHere

        /// There is no feed to carry on from (a station, or a record whose feed has gone), so the
        /// record is opened again.
        case openAgain
    }

    /// The number of the last change.
    private var last = 0

    /// Notes a change and returns its number.
    mutating func happened() -> Int {
        last &+= 1
        return last
    }

    /// Whether `change` is still the last one.
    func isLatest(_ change: Int) -> Bool { change == last }

    /// What to do once a change has settled.
    ///
    /// - Parameters:
    ///   - latest: whether no later change has arrived.
    ///   - onThisPhone: whether the sound plays on this phone's engine. A cast has no local graph,
    ///     and a station on AVFoundation does not use the engine.
    ///   - starting: whether a start is on its way. It puts a new source on the engine, and that
    ///     starts the engine again.
    ///   - wantsToPlay: whether the player has been asked for sound.
    ///   - canCarryOn: whether the record has a feed that can move to the second where it was heard.
    static func answer(latest: Bool, onThisPhone: Bool, starting: Bool, wantsToPlay: Bool,
                       canCarryOn: Bool) -> Answer {
        guard latest, onThisPhone, !starting else { return .nothing }
        guard wantsToPlay else { return .onPlay }
        return canCarryOn ? .carryOnHere : .openAgain
    }
}
