import Foundation
import AVFAudio
import os

/// Keeps the app running while the sound is coming out of a speaker in another room.
///
/// Port of `RPM.Mobile/Services/Audio/CastKeepAlive.cs`.
///
/// An app with `UIBackgroundModes: audio` may keep running after the screen locks, but only
/// **while it is playing audio**. iOS checks this at the audio session, not at what the app
/// intends. Playing to the handset's own speaker satisfies it: the device is running, so the app
/// is not suspended.
///
/// Casting does not satisfy it. The phone is a source and a server: the engine's buffers go into
/// `PcmRing` and out over HTTP, and the handset's own output device is not used at all
/// (``PcmEngine/send(to:from:)`` stops it). As far as the session can tell, nothing is playing, so
/// locking the screen suspends the app, the server stops answering, and a few seconds later (the
/// length of the receiver's own buffer) the speaker goes quiet. The failure appears long after
/// the cause, so it is hard to trace back to here.
///
/// So while a cast is active, an engine that renders silence runs next to it.
/// **It is deliberately not part of the pump's own graph.** That graph is the engine's clock, and
/// a second output device pacing the same pump would give it two clocks that disagree. This is a
/// separate small engine, started when the sound leaves the phone and stopped when it comes back.
/// The pump does not know about it.
///
/// It uses one buffer, scheduled once, looping. `AVAudioPlayerNode` loops a buffer for as long as
/// it plays, so the loop needs no code and there is nothing to drop.
///
/// **This is what the lock screen reads.** The commands and the now-playing panel belong to the
/// app (`MPRemoteCommandCenter.shared()` and `MPNowPlayingInfoCenter.default()`, wired in
/// `RemoteControl`), but on iOS the playback *state* is not a field the app sets.
/// `MPNowPlayingInfoCenter.h` says `playbackState` "only applies on macOS, where playback state
/// cannot be determined by the application's audio session", and the rate in the dictionary only
/// runs the clock next to it. So what shows "playing" on a phone is a session that is making
/// audio, and this class makes some.
///
/// So it has to be **off while the sound is paused**, and `PcmEngine.pause` turns it off. The
/// silence exists to carry audio off the phone, and a paused cast carries none. If it kept
/// running, the lock screen would show the pause key for ever, even though the rate did reach it.
final class CastKeepAlive: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.rpm.player", category: "cast")

    /// One second of silence at the rate the rest of this engine uses. The buffer is scheduled
    /// once and loops, so the length only sets how much memory is allocated.
    private static let rate = 44_100.0
    private static let seconds = 1.0

    private let gate = NSLock()

    /// The engine and the node, or nil when nothing is running. They are kept as a pair because
    /// they are stopped together. While they are kept, a second ``start()`` does nothing, so it
    /// cannot create a second render thread that nobody can stop.
    private var running: (engine: AVAudioEngine, node: AVAudioPlayerNode)?

    /// Whether silence has been asked for: the sound is away, and the app must keep counting as
    /// a player.
    private var asked = false

    /// Whether the sound is away. This is only a record of the request, and it is true whatever
    /// the device did.
    var wanted: Bool { gate.withLock { asked } }

    /// What is rendering the silence, or nil because the device would not start.
    ///
    /// **Kept apart from ``wanted`` on purpose.** The two differ in exactly one case: silence was
    /// asked for but is not rendering. That cast plays correctly until the screen locks and then
    /// dies for no visible reason, so callers need to be able to detect it.
    var rendering: AVAudioEngine? { gate.withLock { running?.engine } }

    // ── on while the sound is away ──

    func start() {
        gate.lock()
        defer { gate.unlock() }

        guard !asked else { return }
        asked = true

        watch()
        fit()
    }

    /// Stops it, however many times it was started. Safe to call when it never ran.
    func stop() {
        gate.lock()
        asked = false
        letGo()
        gate.unlock()

        stopWatching()
    }

    // ── the device itself ──

    /// Puts silence on the output device. The gate is held by every caller.
    private func fit() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.rate, channels: 1),
              let silence = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(Self.rate * Self.seconds))
        else {
            Self.log.error("keep-alive: no buffer to be silent with; the cast dies when the screen locks")
            return
        }

        // Zero the samples explicitly. A new buffer is not documented to start empty, and this
        // must never play a second of stale memory through a speaker.
        silence.frameLength = silence.frameCapacity
        for channel in 0..<Int(format.channelCount) {
            silence.floatChannelData?[channel].update(repeating: 0,
                                                      count: Int(silence.frameCapacity))
        }

        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.prepare()

        do {
            try engine.start()
        } catch {
            // There is no device to keep the app alive with. The cast still works while the screen
            // is on, so it is not refused. The failure is logged because the symptom appears
            // minutes later, somewhere else.
            Self.log.error("""
                keep-alive would not start; the cast dies when the screen locks: \
                \(error.localizedDescription, privacy: .public)
                """)
            return
        }

        // **Do not set `volume = 0`.** The buffer holds zeros, so it is inaudible at any level.
        // A graph with zero volume is what iOS may treat as "nothing audible, safe to suspend".
        // The silence must be rendered as ordinary audio for the background-audio permission to
        // keep counting it.
        node.scheduleBuffer(silence, at: nil, options: .loops, completionHandler: nil)
        node.play()

        running = (engine, node)
        Self.log.notice("keep-alive running")
    }

    /// Takes it off the device, whether it is wanted or not. The gate is held by every caller.
    private func letGo() {
        guard let was = running else { return }
        running = nil

        was.node.stop()
        was.engine.stop()

        Self.log.notice("keep-alive stopped")
    }

    // ── surviving what stops it ──

    /// Anything that takes the audio stack away also stops this engine, and **nothing else
    /// restarts it**.
    ///
    /// A phone call, Siri, a media server restart or unplugged headphones each stops the session.
    /// The player's own resume goes to the room, because while casting there is nothing local to
    /// resume. Without this, the cast would survive the phone call and then die at the next screen
    /// lock, with nothing to connect it to the call.
    ///
    /// This is watched here and not in `RemoteControl` because no other code recovers this
    /// engine. The player's own recovery is `pickUpWhereItStopped`, and it does not cover an
    /// engine that plays silence.
    private func watch() {
        let centre = NotificationCenter.default

        // The engine's own signal. It also covers a route change. It is posted after the
        // configuration has changed and the engine has stopped, which is when the engine has to
        // be built again.
        listening.append(centre.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: nil
        ) { [weak self] _ in self?.again() })

        #if os(iOS)
        listening.append(centre.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt

            // **Only the end of an interruption.** Rebuilding while a call is still going would
            // be refused.
            guard let raw, AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }

            self?.again()
        })

        listening.append(centre.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil
        ) { [weak self] _ in self?.again() })
        #endif
    }

    private func stopWatching() {
        let centre = NotificationCenter.default
        for token in listening { centre.removeObserver(token) }
        listening = []
    }

    private var listening: [NSObjectProtocol] = []

    /// Builds it again, if it is still wanted.
    ///
    /// **It only rebuilds when the engine has actually stopped**, because starting a new engine
    /// posts the configuration change that would otherwise call this method again.
    ///
    /// It tries twice, 400 ms apart. The second try is needed, not extra caution. These
    /// notifications reach every observer at once: `RemoteControl` hears the same interruption and
    /// takes the session back on its own thread, and a request for the device before that has
    /// finished is refused. One attempt would lose that race often, and the failure is silent.
    private func again() {
        Task.detached(priority: .userInitiated) { [weak self] in
            for attempt in 0..<2 {
                if attempt > 0 { try? await Task.sleep(for: .milliseconds(400)) }
                guard let self, self.tryAgain() else { return }
            }
        }
    }

    /// One attempt. Returns whether another attempt is worth making.
    private func tryAgain() -> Bool {
        gate.lock()
        defer { gate.unlock() }

        // Either it is no longer wanted, or it never stopped. In both cases there is nothing to
        // do and no reason to try again.
        guard asked, running?.engine.isRunning != true else { return false }

        #if os(iOS)
        // Apple's documented step for the end of an interruption. The session may be asked from
        // any thread, and activating a session that is already active costs nothing.
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        Self.log.notice("keep-alive: the audio stack came back, fitting silence again")
        letGo()
        fit()

        return running == nil
    }

    deinit {
        stopWatching()
        letGo()
    }
}
