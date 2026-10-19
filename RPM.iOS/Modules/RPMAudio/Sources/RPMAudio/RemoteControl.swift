#if os(iOS) || os(tvOS)
import Foundation
import AVFAudio
import CoreGraphics
import MediaPlayer
import UIKit
import RPMKit
import RPMRadio
import os

/// Playback outside the app: the lock screen, the control centre, a car's steering
/// wheel controls and headset buttons.
///
/// Separate from `Player` because it does not play anything. It keeps the system's
/// copy of what is playing and handles the commands the system sends back. The player
/// has one job and this type has the other, so the player can also build and run on a
/// Mac without the `MediaPlayer` framework.
///
/// The interruption and route rules are the two parts here that are easy to get wrong,
/// and a mistake shows only when a user meets that case. Both are explained at
/// `interrupted` and `routeChanged`.
@MainActor
public final class RemoteControl {
    private static let log = Logger(subsystem: "com.rpm.player", category: "audio")

    private let player: Player

    /// Used for the one thing this fetches: a station's logo for the lock screen. It goes
    /// through the app's own gate with no default, because it is the least important
    /// request the app makes and must not keep running after the network is gone.
    private let wire: Gated

    private var listening: [NSObjectProtocol] = []

    public init(player: Player, reach: NetworkReach) {
        self.player = player
        self.wire = Gated(reach: reach)
    }

    /// Claims the audio session and wires the commands. Call it before anything is
    /// played, every time: the session is released at the end of a sitting, so "claimed
    /// once before" does not mean "held now".
    ///
    /// Callers must `await` it, because taking the session is **not instant**. It is a
    /// synchronous round trip to the media daemon, which has to take the session from
    /// its current holder and settle the route before it answers. On the main actor
    /// that would freeze the screen for that time, and the system treats a main thread
    /// that does not answer as an app that has stopped responding to gestures.
    public func begin() async {
        // Only once. `addTarget` appends, so a second pass would add a second handler to
        // every command and a second observer to every notification, and a pause pressed
        // on the lock screen would arrive twice.
        if !wired {
            wired = true
            wireCommands()
            watchTheSession()
        }

        await (held ?? takeTheSession()).value
    }

    private var wired = false

    /// The claim on the session, or nil once it has been let go of.
    ///
    /// **This is a task and not a flag.** Taking the session is not instant, so a flag
    /// would be true from the moment the request starts. A second track tapped shortly
    /// after would read it, go to the engine, and start in a session that nobody holds
    /// yet. With a task, both callers wait on the same work.
    private var held: Task<Void, Never>?

    /// Puts the session into `.playback` and turns it on, off the main thread.
    ///
    /// `AVAudioSession` is documented as safe to call from any thread. That is the only
    /// reason this may leave the main actor.
    @discardableResult
    private func takeTheSession() -> Task<Void, Never> {
        // Read here and not inside the closure: the class is main-actor, so its static is
        // too, and the work below runs off the main actor. `Logger` is a value, so the
        // local copy can cross over.
        let log = Self.log

        let task = onTheSession {
            let began = Date()
            let session = AVAudioSession.sharedInstance()

            do {
                // `.playback` marks this app as a music player: audio continues when the
                // screen locks and the ring switch does not silence it.
                try session.setCategory(.playback, mode: .default)
                try session.setActive(true)
            } catch {
                // Ignored on purpose. Audio still plays through whatever session the
                // system provides.
            }

            // Logged because the cost of this call is why it runs off the main actor. The
            // time is only meaningful on a device: the simulator's daemon answers at
            // once.
            let took = Date().timeIntervalSince(began)
            log.notice("took the audio session in \(took, format: .fixed(precision: 3))s")
        }

        held = task
        return task
    }

    /// The last request made to the session. The next request waits for it.
    ///
    /// **Releasing and taking the session are opposites, and both are slow.** Releasing
    /// at the end of a queue and taking it again for a track tapped soon after are each
    /// a round trip to the media daemon, made off the main thread. Starting them in
    /// order does not make them finish in order. If they finish the wrong way round, the
    /// track plays into a session that was switched off after it started, and the user
    /// hears nothing. So each request waits for the one before it.
    private var lastly: Task<Void, Never>?

    @discardableResult
    private func onTheSession(_ body: @escaping @Sendable () -> Void) -> Task<Void, Never> {
        let before = lastly

        let next = Task {
            await before?.value
            await Task.detached(priority: .userInitiated) { body() }.value
        }

        lastly = next
        return next
    }

    /// The sitting is over: remove the lock screen card and release the session.
    ///
    /// **Setting `nowPlayingInfo = nil` is not enough.** While the session is active,
    /// the system still treats this app as the one playing, so clearing the entry leaves
    /// an empty card on the lock screen: no cover, no title, and keys that do nothing.
    /// The card goes away only when the session becomes inactive, which tells the system
    /// that this app is no longer playing.
    ///
    /// `.notifyOthersOnDeactivation` tells any app that was interrupted to play this
    /// (a podcast, a game's music) that it can take the route back. Without it, that app
    /// stays silent.
    private func theSittingIsOver() {
        hand(nil)

        guard held != nil else { return }
        held = nil

        let log = Self.log

        onTheSession {
            do {
                try AVAudioSession.sharedInstance()
                    .setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                // Logged and not ignored: this fails when something is still running
                // through the session, and the result is the empty lock screen card
                // that this method exists to remove.
                let why = error.localizedDescription
                log.notice("the audio session would not go: \(why, privacy: .public)")
            }
        }
    }

    /// **Every handler here runs on a background thread**, and none of them may touch
    /// the player from there.
    ///
    /// `MPRemoteCommand.addTarget` is imported without any isolation, so a closure
    /// written inside this main-actor method is compiled as a main-actor closure. Swift
    /// then checks that when the system calls it, from whatever thread the media daemon
    /// uses. The check is a dispatch queue assertion. It traps in libdispatch, on a
    /// thread with none of this app's code on the stack, and the message only says
    /// that a block ran on an unexpected queue.
    ///
    /// So each handler is explicitly `@Sendable`, does no work itself, and passes the
    /// work to the main actor. The system needs an acknowledgement, not a result.
    private func wireCommands() {
        let commands = MPRemoteCommandCenter.shared()
        let player = self.player

        // **The session is claimed again before playback starts.** These commands come
        // from the lock screen, where an app that has been in the background is asked to
        // play. By then the route may belong to another app, and an audio node started
        // in a session that is not ours advances the position with no sound. Taking the
        // session again is safe to repeat and costs one round trip to the media daemon.
        commands.playCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in
                await self?.takeTheSession().value
                player.resume()
            }
            return .success
        }
        commands.pauseCommand.addTarget { @Sendable _ in
            Task { @MainActor in player.pause() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
            Task { @MainActor in
                if !player.wantsToPlay { await self?.takeTheSession().value }
                player.toggle()
            }
            return .success
        }
        commands.nextTrackCommand.addTarget { @Sendable _ in
            Task { @MainActor in await player.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { @Sendable _ in
            Task { @MainActor in await player.previous() }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { @Sendable event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            let at = event.positionTime
            Task { @MainActor in player.seek(to: .seconds(at)) }
            return .success
        }
    }

    private func watchTheSession() {
        let centre = NotificationCenter.default

        // The values are read from the notification here, and the notification itself
        // does not cross to the main actor: a `Notification` is not `Sendable`, and only
        // a `UInt` is needed there.
        //
        // **Pass no queue, and hop with a task.** Passing `OperationQueue.main` to a
        // notification centre runs the block on the main THREAD, which is not the same
        // as the main dispatch QUEUE. The main-actor check is a dispatch queue
        // assertion, so it fails with a trap in libdispatch, and the app cannot report
        // it. The session posts these from its own thread, so a hop is needed anyway.
        listening.append(centre.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { [weak self] note in
            let what = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt

            Task { @MainActor in self?.interrupted(what, options) }
        })

        // **The audio server can be lost and then restarted.** When that happens, every
        // object that was using it holds a dead handle, and the session's category is
        // lost too. Apple's guidance is to stop and release everything when the server
        // is lost, and to set everything up again when it is reset. An app that ignores
        // the pair stays silent until it is force quit, with no visible cause.
        listening.append(centre.addObserver(
            forName: AVAudioSession.mediaServicesWereLostNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in self?.player.pause() }
        })

        listening.append(centre.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.takeTheSession().value
                await self?.player.pickUpWhereItStopped()
            }
        })

        listening.append(centre.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
        ) { [weak self] note in
            let why = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt

            Task { @MainActor in self?.routeChanged(why) }
        })
    }

    /// Handles an interruption: a call, another app, Siri.
    ///
    /// **Use the `.shouldResume` flag to decide.** Resuming on `.began` because "we were
    /// playing" would start the music over a phone call. Resuming on `.ended` without
    /// checking `.shouldResume` would start it in the middle of a voice memo.
    private func interrupted(_ raw: UInt?, _ said: UInt?) {
        guard let raw, let what = AVAudioSession.InterruptionType(rawValue: raw) else { return }

        switch what {
        case .began:
            player.pause()

        case .ended:
            let options = said.map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []

            guard options.contains(.shouldResume) else { return }

            // Taking the session is slow, so it must not block the main thread (see
            // `begin`). Playback resumes only after the session is ours again.
            Task { [weak self] in
                await self?.takeTheSession().value
                self?.player.resume()
            }

        @unknown default:
            break
        }
    }

    /// Handles an audio route change, such as unplugging headphones.
    ///
    /// Only a device **going away** pauses playback. A route change also arrives when
    /// headphones are plugged IN, and stopping the music then would be wrong.
    private func routeChanged(_ raw: UInt?) {
        guard let raw,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
        else { return }

        player.pause()
    }

    // ── what the system shows ──

    /// The entry last handed to the system. It is kept here and never read back from the
    /// system.
    ///
    /// **Do not rely on reading `MPNowPlayingInfoCenter.nowPlayingInfo` back.** Apple's
    /// guidance is to keep your own copy and assign the whole dictionary. The getter can
    /// return nil while this app is not the one the system is showing, which can happen
    /// exactly when the lock screen is visible. Updating from that getter would skip the
    /// update, so a pause pressed with the screen locked would change nothing: neither
    /// the rate nor the playback state.
    private var entry: [String: Any]?

    /// Hands the entry to the system. On iOS this is **the only way the system is told
    /// the playback state**.
    ///
    /// `MPNowPlayingInfoCenter.playbackState` does not work on iOS. It is a macOS API.
    /// On iOS the system ignores it unless the app has a private entitlement, and logs:
    ///
    /// > `[MRNowPlaying] Ignoring setPlaybackState because application does not contain`
    /// > `entitlement com.apple.mediaremote.set-playback-state for platform`
    ///
    /// The lock screen would then keep showing a pause key for a paused track. iOS reads
    /// only `MPNowPlayingInfoPropertyPlaybackRate` in the dictionary, together with the
    /// elapsed time.
    private func hand(_ info: [String: Any]?) {
        entry = info
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // **Logged when the state changes.** A log line is the only way to confirm what
        // the app told iOS. It logs once per change, so a playing track logs only once.
        let saying = info == nil ? "nothing"
                   : (player.wantsToPlay ? "playing" : "paused")

        if saying != told {
            told = saying
            Self.log.notice("told iOS: \(saying, privacy: .public)")
        }
    }

    private var told: String?

    /// Puts the current track on the lock screen. Call it whenever the track changes,
    /// and again when its cover arrives.
    public func show(_ track: CloudTrack?, artwork: CGImage?) {
        guard let track else {
            // **No current track does not mean nothing is left to play.** This argument
            // carries only the first fact. `isOver` is the second, and it is asked of the
            // player at the moment the answer is needed, not inferred from the call that
            // arrived. When a station is tuned, a call with no track arrives just before
            // the station is announced. When a track is removed from a queue that still
            // has tracks, the rest of the queue is still waiting to play.
            guard player.isOver else {
                // A station's card belongs to `show(station:)`, which has just set it.
                // Clearing it here would blank the lock screen for radio.
                if player.station == nil { hand(nil) }
                return
            }

            theSittingIsOver()
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title ?? "",
            MPMediaItemPropertyArtist: track.artist ?? "",
            MPMediaItemPropertyAlbumTitle: track.album ?? "",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position.seconds,
            MPNowPlayingInfoPropertyPlaybackRate: player.wantsToPlay ? 1.0 : 0.0,
        ]

        if player.duration > .zero {
            info[MPMediaItemPropertyPlaybackDuration] = player.duration.seconds
        }

        if let artwork {
            let picture = UIImage(cgImage: artwork)

            // `@Sendable` for the same reason as the commands above: the system asks for
            // the picture from its own thread, and a closure written here would otherwise
            // be compiled as main-actor isolated.
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: picture.size) {
                @Sendable _ in picture
            }
        }

        hand(info)
        offer(theQueuesKeys: true)
    }

    /// Puts a station on the lock screen.
    ///
    /// A station has its own entry and does not reuse a track's. A station is **live**,
    /// so it carries no duration and no elapsed time, because the system draws a
    /// scrubber for anything that reports one. The current announcement goes in the
    /// artist field, which the lock screen shows as the second line.
    public func show(station: RadioStation?) {
        guard let station else {
            // Removed and not emptied, for the reason given in `show(_:artwork:)`.
            hand(nil)
            fetching = nil
            logo = nil
            return
        }

        // Fetched once per station. The logo arrives after this entry is posted, so the
        // fetch posts the entry again when it lands. Many logo links in a station
        // directory are dead; a dead link means a station with no logo, not an error.
        if fetching != station.uuid { fetch(theLogoOf: station) }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: station.display,
            MPMediaItemPropertyArtist: player.announced.isEmpty ? Loc.get("Rpm_NowPlaying_Radio") : player.announced,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: player.wantsToPlay ? 1.0 : 0.0,
        ]

        if let logo { info[MPMediaItemPropertyArtwork] = logo }

        hand(info)
        offer(theQueuesKeys: false)
    }

    /// The station whose logo has been requested, and the logo itself once it arrives.
    private var fetching: String?
    private var logo: MPMediaItemArtwork?

    /// Fetches the station's logo for the lock screen.
    ///
    /// This does not use `ArtworkStore`. That store belongs to the cloud library and is
    /// keyed by album and shelf. A station's logo is an arbitrary URL from a directory,
    /// with nothing in the library behind it.
    private func fetch(theLogoOf station: RadioStation) {
        fetching = station.uuid
        logo = nil

        guard let said = station.favicon, let url = URL(string: said),
              url.scheme?.hasPrefix("http") == true
        else { return }

        Task { [weak self] in
            // Goes through the app's own gate, so a dead network costs nothing. A lock
            // screen logo is the least important request the app makes.
            guard let (data, _) = try? await self?.wire.fetch(URLRequest(url: url),
                                                              method: "GET"),
                  let picture = UIImage(data: data)
            else { return }

            // The user may have tuned another station while this request was running, and
            // a logo under the wrong station's name is worse than no logo.
            guard let self, self.fetching == station.uuid, self.player.station?.uuid == station.uuid
            else { return }

            self.logo = MPMediaItemArtwork(boundsSize: picture.size) { @Sendable _ in picture }
            self.show(station: station)
        }
    }

    /// Enables or disables the commands that only make sense with a queue.
    ///
    /// **A station has no queue and no length**, so next, previous and the scrubber
    /// are disabled. The lock screen draws an enabled key whether or not the app
    /// answers it, and a key that does nothing looks like a bug. The Uno head disables
    /// the same three.
    private func offer(theQueuesKeys yes: Bool) {
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = yes
        commands.previousTrackCommand.isEnabled = yes
        commands.changePlaybackPositionCommand.isEnabled = yes
    }

    /// The cheap update: refreshes the position and rate without rebuilding the whole
    /// entry or re-wrapping the cover.
    ///
    /// **It reports intent, not state** (`wantsToPlay`, not `isPlaying`). While a track
    /// is opening, no sound is coming out for about a second, so `isPlaying` is false.
    /// The lock screen would then show a play button for a track that is already
    /// starting, and pressing it would send `play`, which does nothing. The position
    /// may run slightly ahead of the sound for that second, but a wrong key on the lock
    /// screen is worse.
    public func showPosition() {
        // **The end of a sitting is a fact about the player, not a message that callers
        // must remember to send.** It happens in four ways: the stop key, the last track
        // of a queue finishing, the last track being removed from a queue, and a station
        // being switched off. All of them end at `playbackChanged`, which leads here. It
        // is asked and not told, so a fifth way is covered without changes.
        if player.isOver {
            theSittingIsOver()
            return
        }

        // **Our own copy, not the system's.** See ``entry``: the system's getter can
        // return nil. If nothing has been put up yet, there is no card to correct, and
        // the next `show` will carry the rate.
        guard var info = entry else { return }

        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.position.seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.wantsToPlay ? 1.0 : 0.0

        hand(info)
    }
}
#endif
