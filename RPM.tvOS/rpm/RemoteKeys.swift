import MediaPlayer
import RPMAudio

/// Keys that a universal, IR or HDMI-CEC remote has but the Siri Remote does not. The behaviour
/// matches the Android TV app. Fast-forward and rewind move the playhead 10 seconds
/// (``SeekSteps/press``). Stop pauses at the start of the track and keeps the queue. While a
/// station plays, Stop stops the station.
///
/// TV only. These commands are not in the shared ``RemoteControl``, because on the phone they would
/// replace next and previous on the lock screen.
///
/// Each handler is `@Sendable` and does no work itself. The system calls handlers on a thread of
/// its own, and the work belongs on the main actor (the same reason as in ``RemoteControl``).
@MainActor
enum RemoteKeys {
    static func wire(_ model: TVModel) {
        let commands = MPRemoteCommandCenter.shared()
        let step = SeekSteps.press

        commands.skipForwardCommand.preferredIntervals = [NSNumber(value: step)]
        commands.skipForwardCommand.addTarget { @Sendable [weak model] _ in
            Task { @MainActor in model?.skip(by: step) }
            return .success
        }
        commands.skipBackwardCommand.preferredIntervals = [NSNumber(value: step)]
        commands.skipBackwardCommand.addTarget { @Sendable [weak model] _ in
            Task { @MainActor in model?.skip(by: -step) }
            return .success
        }

        // A held key arrives as a seek that begins and then ends. Each begin event is one step.
        commands.seekForwardCommand.addTarget { @Sendable [weak model] event in
            guard (event as? MPSeekCommandEvent)?.type == .beginSeeking else { return .success }
            Task { @MainActor in model?.skip(by: step) }
            return .success
        }
        commands.seekBackwardCommand.addTarget { @Sendable [weak model] event in
            guard (event as? MPSeekCommandEvent)?.type == .beginSeeking else { return .success }
            Task { @MainActor in model?.skip(by: -step) }
            return .success
        }

        commands.stopCommand.addTarget { @Sendable [weak model] _ in
            Task { @MainActor in model?.stopKey() }
            return .success
        }
    }
}
