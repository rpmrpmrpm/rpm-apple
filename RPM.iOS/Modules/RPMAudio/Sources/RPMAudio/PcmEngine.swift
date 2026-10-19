import Foundation
import AVFAudio
import os

/// The engine the sound comes out of.
///
/// One player node into a mixer, fed buffers as the decoder produces them. `AVQueuePlayer`
/// cannot do what this design needs: the pump keeps its own copy of the samples for the
/// visualiser, a second node can act as the other deck, the pump scales the samples (so a quiet
/// record can be turned up, not only down), and a cast is the same pump handing buffers to a
/// speaker.
///
/// Buffers are pushed, not pulled. A render callback would run on the real-time audio thread,
/// where nothing may allocate, lock or wait, and a decoder does all three. Scheduling keeps the
/// decode on a thread that can afford to be slow.
public final class PcmEngine: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.rpm.player", category: "audio")

    public enum Trouble: Error, Equatable {
        /// The stream never said what it was, so there is nothing to connect.
        case noFormat

        /// The engine would not start. On a phone this is the session.
        case wontStart
    }

    /// How many buffers are kept in front of the node. This is about a second and a half.
    ///
    /// Fewer was audible: at the start of a track the decoder is only as far ahead as the network,
    /// so the node reached the end of its buffers again and again and the sound cut in and out for
    /// the first few seconds.
    ///
    /// A deeper queue has no cost at the other end. Pausing a node is immediate however much is
    /// scheduled behind it, and a seek stops the node, which drops everything scheduled.
    private static let ahead = 8

    /// How many frames are scheduled before the node is started (one second at 44.1 kHz).
    ///
    /// Starting on the first buffer makes the start stutter, because the node would run out of
    /// audio before the network could catch up. With a second in hand, the track begins once.
    private static let priming: AVAudioFramePosition = 44100

    /// How many frames are decoded at a time. About a fifth of a second at 44.1 kHz: small enough
    /// to schedule smoothly, large enough that the decoder is not called too often.
    private static let bite: AVAudioFrameCount = 8192

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()

    /// Where the pump puts what it decodes when the destination is not the handset.
    ///
    /// **Swapping this is what casting is.** The engine has one source and one destination, and
    /// moving the destination moves the sound with nothing above it changing. A queue advances
    /// because the engine advances it.
    ///
    /// There is only one destination at a time. Rendering to the device while tapping the graph
    /// for a speaker distorts the sound when the speaker connects.
    private var toTheRoom: RoomFeed?

    /// The only door the destination moves through, so `toTheRoom` and ``Playback/sent``
    /// cannot disagree. The gate is held by every caller.
    private func goingTo(_ room: RoomFeed?) {
        toTheRoom = room
        if room != nil { state.movedToTheRoom() } else { state.cameHome() }
    }

    /// Silence, rendered on the handset for as long as the sound is going somewhere else. See
    /// ``CastKeepAlive``, which explains what iOS does to an app that plays nothing.
    ///
    /// **Private, and used from exactly four places**: the two methods that move the destination
    /// and the two that stop and start the sound. Then no path can move the sound off this phone,
    /// or back onto it, or stop it, without passing a line that turns the silence on or off.
    ///
    /// **The second pair matters.** On iOS the lock screen's key is drawn from whether this app's
    /// session is making audio, so silence left running through a pause shows a pause key over a
    /// paused room for ever. See ``pause()``.
    private let awake = CastKeepAlive()

    /// Whether the silence is fitted. Read-only: the methods listed on `awake` are the only way to
    /// change it.
    var keepingAwake: Bool { awake.wanted }

    /// The sound as it was handed over, kept so that something can draw it.
    ///
    /// **Written by the pump, not by a tap on the graph.** That is why a visualiser keeps drawing
    /// while the sound comes out of a speaker: there is no local graph then, but there are still
    /// samples. It is read at the playhead, so the picture shows what is heard, not what has been
    /// decoded (those can be eight seconds apart in another room). See ``RoomSound``.
    public let played = RoomSound()

    /// What the player is doing and where the sound is going, as one state.
    ///
    /// **It is on the engine, not on the node**, because the node is not the only place the sound
    /// can go. Pausing while a speaker is connected has to stop the pump handing buffers over and
    /// has to reach the receiver; `node.pause()` on a node that is not running does nothing. See
    /// ``Playback``.
    ///
    /// `toTheRoom` is the room itself, because a reference is not a state. The two change together
    /// through ``goingTo(_:)`` and nowhere else.
    private var state = Playback()

    private let gate = NSLock()
    private var inFlight = 0
    /// The thread the pump runs on.
    ///
    /// **A thread of its own, not a task.** A `Task.detached` runs on the Swift cooperative pool:
    /// one thread per core, shared with everything else the app does asynchronously, and nothing
    /// reserves the pump a place in it. If the pump is not scheduled for as long as the node's
    /// buffered audio lasts, the result is silence, heard as a stutter.
    ///
    /// With its own thread, **blocking is allowed**: waiting on a speaker's clock is a real wait
    /// (several seconds when the receiver is well ahead), and it happens here and not on a thread
    /// the rest of the app needs. See ``RoomFeed/take(_:while:)``.
    private var pumping: Thread?

    /// Which run of the pump is the current one.
    ///
    /// **Not `Thread.cancel()`.** A cancelled thread stops only when it next looks, which can be a
    /// sleep later, and in that time it can schedule a buffer onto a node that was just emptied
    /// for a different record. Every turn of the loop reads this number instead, so once a start
    /// or a stop changes it, the old pump is no longer the pump.
    private var pumpRun = 0
    private var connected = false

    /// Whether the node has been told to play. This is false during the priming, before there is
    /// anything to play, so it is not the same as whether sound is coming out.
    private var started = false

    /// Everything handed to the node, which is not the same as everything heard.
    private var scheduled: AVAudioFramePosition = 0

    /// One track's worth of audio in the node's timeline.
    ///
    /// **Scheduled is not heard.** Gapless playback is exactly the distance between the two: the
    /// next record is handed over while the current one is still coming out of the speaker, so the
    /// node holds two tracks and only one is being heard. Which one is a question about where the
    /// node's clock has got to.
    private struct Run {
        /// The caller's number for the record. The caller numbers by position, so an edit to the
        /// running order can change the number of the record that is playing, without stopping it.
        /// See ``rearranged``.
        var id: Int

        /// How many frames the node had been given before this one started.
        let from: AVAudioFramePosition

        /// Where in the track the run begins: zero from the start, or the landing second after a
        /// seek.
        let origin: Double
    }

    private var runs: [Run] = []

    /// Which run was last reported as the one being heard, so that a change is announced once and
    /// not on every poll.
    private var announced: Int?

    /// One source waiting to be played. The queue is in order: the pump takes the first one and
    /// stays on it until it is drained.
    fileprivate struct Next {
        var id: Int
        let source: StreamedPcm
        var origin: Double

        /// What this source is levelled from, settled when it was handed over. See
        /// ``SourceLoudness``.
        let loudness: SourceLoudness
    }

    private var coming: [Next] = []

    /// Told when the track **coming out of the speaker** changes, which is not when it
    /// was handed over. The engine is the only thing that knows the difference.
    public var moved: (@Sendable (Int) -> Void)?

    /// Called when everything given to the engine has played out, **and why it ran out**.
    ///
    /// The reason comes from the source, not from anything worked out here. Without it, the only
    /// thing a listener could check is the position, and a position cannot tell a record that
    /// stopped from a record that is short. See ``Ending``.
    public var ranOut: (@Sendable (Ending) -> Void)?

    /// Why the last source to leave the front left it.
    ///
    /// Kept here because the source it belongs to is gone by the time anyone is told: the pump
    /// removes a drained source, carries on with whatever is behind it, and reports only when
    /// nothing is behind it.
    private var lastEnding: Ending = .theRecordFinished

    /// - Parameter normalize: the listener's levelling setting. **No default**, so that no engine
    ///   is built with a levelling setting by accident.
    public init(normalize: NormalizeContext) {
        setting = normalize

        // **One question, two answers, and `RoomSound` needs to know neither.** Where the sound has
        // got to is the node's own clock on the handset, and a position reported by the speaker
        // over the network while casting. `whereItIs` tells them apart.
        played.reads { [weak self] in self?.whereItIs()?.sample }

        PumpDiag.announce()
    }

    private let diag = PumpDiag()

    /// Seconds of audio in front of the node: everything handed over that the node's clock has not
    /// reached yet.
    ///
    /// **This is the real cushion, and `inFlight` is not.** Eight buffers are a second and a half
    /// only when every one is a full `bite`. `StreamedPcm.read` returns a short buffer whenever
    /// the converter ran out of input, so the count can stay at eight while the audio in front of
    /// the node is a fifth of a second. Scheduled minus heard is true whenever it is asked.
    ///
    /// Nil while there is no clock: paused, casting, or before the node has started.
    private var cushionSeconds: Double? {
        guard let (_, sample, rate) = whereItIs(), rate > 0 else { return nil }
        return gate.withLock { max(0, Double(scheduled - sample) / rate) }
    }

    /// Where in the **track** playback is, in seconds.
    ///
    /// It uses the node's own clock, not a count of what was scheduled: those differ by the audio
    /// sitting in front of the speaker, which a progress bar must not be wrong by. The node's clock
    /// restarts at zero every time the node is stopped (a seek does this), so where the current
    /// run began is added back.
    public var position: Double {
        guard let (run, sample, rate) = whereItIs() else {
            // **A paused node has no clock.** `lastRenderTime` is nil as soon as rendering stops,
            // so reading through to the run's origin would send the position to the start of the
            // track on every pause, and back on every play. The last known position is the right
            // answer while nothing moves.
            //
            // Failing that, the position it is about to have: just after a seek nothing is
            // scheduled yet, and zero there would make the position jump to the start of the track.
            return gate.withLock { held ?? runs.first?.origin ?? coming.first?.origin ?? 0 }
        }

        // **Never before where it was sent.** Just after `play()` the node's time can be negative:
        // the render clock still holds a last render from before this run, and the run has not
        // started. Read directly, that makes the position jump back past the point the user dragged
        // to.
        let at = run.origin + max(0, Double(sample - run.from) / rate)
        gate.withLock { held = at }
        return at
    }

    /// The last position that was read off a running clock, for the times when there is none:
    /// paused, and the moment between a stop and the next start. Cleared by anything that moves
    /// the position somewhere else.
    private var held: Double?

    /// Which track is coming out of the speaker, or about to be if none is yet.
    public var playing: Int? { whereItIs()?.run.id ?? gate.withLock { whatIsAboutToBeHeard() } }

    /// What will be heard first. Asked only when **no clock has reported a position yet**: before
    /// the node has rendered a block, and between a cast starting and the speaker's first status.
    ///
    /// **The oldest thing handed over, not the newest.** `coming.first?.id` is the record being
    /// decoded. On the handset that is right, because nothing is in front of the node while
    /// ``runs`` is empty. While casting it is wrong by however far the pump has run ahead: it
    /// fills the ring as fast as it can, and the room reports nothing until it starts playing, so
    /// by the speaker's first status the pump can have decoded two whole records.
    ///
    /// What the room plays first is the oldest run still in the ring. `runs` is emptied by
    /// ``play(_:id:from:because:)`` and by ``send(to:from:)``, so its head is the first audio of
    /// the stream the room is being handed, and nothing removes it until a clock has reached
    /// something.
    ///
    /// The gate is held by every caller.
    private func whatIsAboutToBeHeard() -> Int? {
        if toTheRoom != nil, let oldest = runs.first?.id { return oldest }
        return coming.first?.id
    }

    /// Which track is being heard, and where the node's clock has got to.
    private func whereItIs() -> (run: Run, sample: AVAudioFramePosition, rate: Double)? {
        // **While casting, the only clock that knows is the speaker's.** What has been handed over
        // is still in a socket and in several seconds of the receiver's own buffer, so the node's
        // clock (which is not running) would put the position wherever the decoder has reached,
        // seconds ahead of the room.
        if let room = gate.withLock({ toTheRoom }) {
            guard let played = room.played else { return nil }

            return gate.withLock {
                guard let run = runs.last(where: { $0.from <= played }) ?? runs.first
                else { return nil }
                return (run, played, StreamedPcm.engineFormat.sampleRate)
            }
        }

        // **This raises when the node has no engine.** `lastRenderTime` is one of the AVAudioNode
        // calls that assert instead of answering then, and the position is read on a timer that
        // starts before anything is connected.
        guard node.engine != nil,
              let heard = node.lastRenderTime,
              let mine = node.playerTime(forNodeTime: heard)
        else { return nil }

        let sample = mine.sampleTime

        return gate.withLock {
            // The last run the clock has reached. Anything after it has been handed
            // over and not yet heard.
            guard let run = runs.last(where: { $0.from <= sample }) ?? runs.first else {
                return nil
            }
            return (run, sample, mine.sampleRate)
        }
    }

    public var isPlaying: Bool {
        if gate.withLock({ toTheRoom != nil }) {
            return gate.withLock { !coming.isEmpty && !state.isPaused }
        }
        return node.engine != nil && node.isPlaying
    }

    /// Something to play, but not yet enough of it to start on.
    ///
    /// Different from ``starved`` because the user is told something different even though both
    /// show a spinner: this is the beginning of a track and that is the middle of it.
    public var priming: Bool { gate.withLock { !started && !coming.isEmpty } }

    /// Asked to play, but with nothing in front of the node to make sound from.
    ///
    /// **This is buffering**, and it is a fact, not a guess: the node is running and every buffer
    /// handed to it has been played. It answers "why is nothing coming out".
    public var starved: Bool {
        // **This is a node fact, and there is no node while casting.** `inFlight` counts buffers
        // the node has not played yet, and nothing increments it when audio goes to a room, so read
        // directly it would say starved for ever (a status line stuck on Buffering and a play key
        // that does not change). What the room is waiting for is reported separately by the
        // receiver.
        guard gate.withLock({ toTheRoom == nil }) else { return false }

        return isPlaying && gate.withLock { inFlight == 0 && !coming.isEmpty }
    }

    /// Takes the finished source off the front, and remembers why it finished.
    ///
    /// Every way a source leaves the queue goes through here: it drained, or its decoder gave up.
    /// The reason is kept because the source it belongs to is gone by the time anybody is told.
    /// See ``lastEnding``.
    private func takeItOffTheFront(_ ending: Ending) {
        gate.withLock {
            guard !coming.isEmpty else { return }

            coming.removeFirst()
            lastEnding = ending
        }
    }

    /// Plays a source now, dropping whatever was already scheduled, and keeps feeding it until the
    /// stream is drained.
    ///
    /// - Parameter loudness: what the source is levelled from. **No default**: a source put on
    ///   without it would play at the gain of the previous source.
    ///   ``SourceLoudness/unmeasured`` is the stated answer for something nobody measured.
    public func play(_ source: StreamedPcm, id: Int = 0, from seconds: Double = 0,
                     loudness: SourceLoudness, because why: Playback.Start) throws {
        try begin(source, id: id, from: seconds, loudness: loudness, because: why)
    }

    private func begin(_ source: StreamedPcm, id: Int, from seconds: Double,
                       loudness: SourceLoudness, because why: Playback.Start) throws {
        guard source.ready else { throw Trouble.noFormat }

        let room = gate.withLock { toTheRoom }

        if let room {
            // **The device is not started while a speaker is connected.** Starting it would put a
            // real-time render thread back on the phone with nothing to render.
            room.begin(at: seconds)
        } else {
            try connect()

            // **Stopped, not paused.** A pause would keep what is already scheduled: after a seek
            // the old audio in front of the node would play for a second before the new position
            // arrived.
            node.stop()
        }

        let mine = gate.withLock { () -> Int in
            pumpRun += 1
            return pumpRun
        }

        gate.withLock {
            inFlight = 0
            scheduled = 0
            runs = []
            announced = nil
            held = nil

            // **A pause outlives the source it was pressed against, unless somebody asked for
            // sound.** A queue advancing by itself and a seek keep the pause. A tap on a track
            // clears it. `startIfThereIsEnough` checks the pause before it starts the node, so a
            // pause left standing cannot produce sound.
            //
            // A pause pressed while this source was on its way is not lost: `Transport.arrives`
            // hands it back, and the caller presses it again as soon as the source is here.
            state.aRecordWentOn(why)

            // Nothing to prime when the destination is a room: it takes what it is
            // given and its own buffer is the cushion.
            started = room != nil
            coming = [Next(id: id, source: source, origin: seconds, loudness: loudness)]
            lastEnding = .theRecordFinished
        }

        // **The node is not told to go here.** It is told once there is a cushion in
        // front of it; see `priming`.
        let thread = Thread { [weak self] in self?.pump(mine) }
        thread.name = "com.rpm.player.pump"

        // **A thread of its own is not a tier of its own.** At `.userInitiated` the pump runs in
        // the same band as every artwork decode and library read in the app, and a fast swipe
        // starts a dozen of those at once. The scheduler can then leave the pump on an efficiency
        // core while the drag holds the performance cores. Only the main thread belongs above this,
        // so the pump uses the top band, and scrolling cannot outrank playback. The node's buffered
        // audio lasts a second and a half, which is how long a stall must be to be heard.
        thread.qualityOfService = .userInteractive

        pumping = thread
        thread.start()
    }

    /// Puts a source behind what is playing, with nothing between them.
    ///
    /// **This is all of gapless.** The node plays what it was given in the order it was given, so
    /// a record handed over before the last one finishes follows it sample to sample. Nothing has
    /// to be timed or faded; the only requirement is to hand it over early enough.
    ///
    /// The source carries its own loudness because the changeover happens on the pump, seconds
    /// from here, with nobody to ask at that moment.
    public func queue(_ source: StreamedPcm, id: Int, loudness: SourceLoudness) {
        gate.withLock {
            coming.append(Next(id: id, source: source, origin: 0, loudness: loudness))
        }
    }

    /// Whether anything is waiting behind what is being scheduled.
    public var hasSomethingNext: Bool { gate.withLock { coming.count > 1 } }

    /// Takes back whatever was handed over behind the record at the front, so the
    /// engine runs out when that record ends. For the sleep timer set to the end of a
    /// track.
    ///
    /// - Returns: whether the record named is still the one at the front. It is not once
    ///   the pump has moved on to the one behind it: that audio is already in front of
    ///   the node and cannot be taken back, and nothing is changed then.
    @discardableResult
    public func dropWhatIsNext(behind playing: Int) -> Bool {
        gate.withLock {
            guard coming.first?.id == playing else { return false }

            if coming.count > 1 { coming.removeSubrange(1...) }
            return true
        }
    }

    /// What each source still being decoded is levelled from, front first. Internal so
    /// a test can ask it.
    var loudnessComing: [SourceLoudness] { gate.withLock { coming.map(\.loudness) } }

    /// The running order was rearranged underneath the record playing.
    ///
    /// **Two facts in one message**, because a queue edit is one event and both answers must land
    /// together:
    ///
    /// - What was handed over to play next was chosen for a running order that no longer exists,
    ///   so it is dropped. Gapless hands over the next record while the current one is still
    ///   coming out of the speaker, so a rearranged list can leave a record already loaded behind
    ///   the playhead, and nothing above this engine can see that.
    /// - The record playing is under a different number now. The ids are the caller's positions,
    ///   and a drag can give the next record the number the current one is already under. Two
    ///   sources under one number would be a run that never opens: a track that is never
    ///   announced and a position that never returns to zero.
    ///
    /// Whoever holds the queue hands the new next record over afterwards, in its own time. This
    /// only removes what the edit made untrue.
    ///
    /// - Returns: whether the record named is still the one at the front. It is not once the pump
    ///   has moved on to the one behind it: that audio is already in front of the node and cannot
    ///   be taken back, and nothing is changed then.
    @discardableResult
    public func rearranged(_ playing: Int, isNow renamed: Int) -> Bool {
        gate.withLock {
            guard coming.first?.id == playing else { return false }

            if coming.count > 1 { coming.removeSubrange(1...) }

            coming[0].id = renamed
            for at in runs.indices where runs[at].id == playing { runs[at].id = renamed }
            if announced == playing { announced = renamed }

            return true
        }
    }

    /// Whether somebody asked for silence, whichever destination is fitted.
    public var isPaused: Bool { gate.withLock { state.isPaused } }

    /// **What the player is doing and where the sound is going**, as one answer.
    ///
    /// Read this instead of rebuilding it from separate questions (is there a source, is it
    /// paused, is it playing, is it priming). Each is answered differently while casting, and one
    /// of them answering for the node would show a key that is the opposite of the truth. See
    /// ``Playback``.
    public var playback: Playback { gate.withLock { state } }

    public func pause() {
        let room = gate.withLock { () -> RoomFeed? in
            state.somebodyPressedPause()
            return toTheRoom
        }

        guard let room else {
            node.pause()
            engine.pause()
            return
        }

        // **Nothing local to pause.** The pump stops handing buffers over and the speaker is told
        // separately; see `Player.apply`. The room is told as well, so that it does not treat a
        // speaker that has stopped moving as a speaker that has gone away.
        room.paused = true

        // **The silence stops too, because on iOS the silence is what says "playing".** The
        // now-playing state is not a field an app sets. `MPNowPlayingInfoCenter.h` says
        // `playbackState` "only applies on macOS, where playback state cannot be determined by the
        // application's audio session". So on a phone the lock screen's key comes from whether this
        // app's session is making audio, and the rate in the dictionary only runs the clock beside
        // it. `CastKeepAlive` makes audio for as long as a speaker is fitted, so without this a
        // paused room would keep a pause key for ever and the record's clock would stop beside it.
        // The silence exists to keep the app from being suspended while audio leaves the phone, and
        // while paused none is leaving.
        awake.stop()
    }

    /// Stops the handset's own device without saying that anybody asked for silence.
    ///
    /// **For the handover only.** Picking up a speaker tears this render graph down and starts
    /// another: the node and the engine stop with buffers still in flight, then a second
    /// `AVAudioEngine` starts for the keep-alive silence. That is two reconfigurations of the
    /// shared audio session back to back under live audio, and it produced an audible stutter at
    /// the moment the user picked a speaker.
    ///
    /// This does not make the change faster, it makes it silent: **audio that is not playing
    /// cannot under-run.** It is not ``pause()``, because a pause is a user request and this is
    /// not. A player that was playing is still playing, in a room, a second later, and the key
    /// over it must not flicker.
    public func hush() {
        node.pause()
        engine.pause()
    }

    public func resume() throws {
        let room = gate.withLock { () -> RoomFeed? in
            state.somebodyPressedPlay()
            return toTheRoom
        }

        guard let room else {
            if !engine.isRunning { try engine.start() }

            // Play pressed during the priming starts with what there is. The user's request
            // outranks the cushion.
            gate.withLock { started = true }
            node.play()
            return
        }

        room.paused = false

        // Audio is leaving the phone again, so the keep-alive silence starts again. See ``pause()``
        // for why it is not left running.
        awake.start()
    }

    /// Releases everything. What was scheduled and not yet heard is dropped, so a stop is
    /// immediate and not a fade.
    public func stop() {
        gate.withLock { pumpRun += 1 }
        pumping = nil

        // Guarded for the same reason as the position read: an `AVAudioNode` with no engine asserts
        // instead of answering, and this can be reached by tuning a station before any track has
        // played.
        if node.engine != nil { node.stop() }
        engine.stop()

        gate.withLock {
            inFlight = 0
            scheduled = 0
            runs = []
            announced = nil
            held = nil
            started = false
            coming = []
        }
    }

    // ── the wiring ──

    private func connect() throws {
        guard !connected else {
            if !engine.isRunning { try engine.start() }
            return
        }

        engine.attach(node)

        // Straight at the mixer. The levelling is not a node on this graph: the pump
        // scales the samples before they are scheduled, because a node here is skipped
        // entirely while a speaker is connected. See ``GainSlide``.
        let format = StreamedPcm.engineFormat
        engine.connect(node, to: engine.mainMixerNode, format: format)

        // Called before starting, because on some routes an engine started without it renders
        // nothing and reports no error.
        engine.prepare()

        do { try engine.start() } catch { throw Trouble.wontStart }
        connected = true
    }

    // ── how loud ──

    /// The listener's levelling setting.
    ///
    /// **Read by the pump for every block it levels**, together with the source's own
    /// ``SourceLoudness``, so a change reaches the record already playing. It is heard
    /// once the audio already handed over has played out: about a second and a half on
    /// the handset, up to ``RoomFeed``'s lead on a speaker.
    public var normalize: NormalizeContext {
        get { gate.withLock { setting } }
        set { gate.withLock { setting = newValue } }
    }

    private var setting: NormalizeContext

    // ── where the sound goes ──

    /// Sends the sound to a speaker instead of to this phone.
    ///
    /// **The device is stopped, not muted.** Muting it would leave a real-time render
    /// thread running with nothing to do but miss deadlines, which is audible on the
    /// way in. Stopping it means there is no audio thread at all while a speaker is
    /// connected: the pump decodes, hands buffers to the room, and waits on the
    /// speaker's own clock.
    ///
    /// What was already scheduled in front of the node goes with it. That audio has
    /// been decoded but not heard, and the room is about to be sent the same seconds
    /// from the source; keeping it would play them twice.
    public func send(to room: RoomFeed, from seconds: Double) {
        gate.withLock { goingTo(room) }

        if node.engine != nil { node.stop() }
        engine.stop()

        // The node's clock is what `runs` are measured against, and it has just been thrown away.
        // Everything still to be played is re-based on where the room is about to start.
        gate.withLock {
            inFlight = 0
            scheduled = 0
            runs = []
            announced = nil
            held = nil
            started = true          // there is no node to prime; the room takes what it is given

            // **The pause is deliberately not cleared here.** Moving the sound to a speaker is not
            // a request to hear it: whoever was playing carries on in the other room, and whoever
            // was paused has asked for nothing yet and waits. Clearing it would be a machinery door
            // changing what the player is doing, which `Playback` exists to prevent.
            if !coming.isEmpty { coming[0].origin = seconds }
        }

        room.begin(at: seconds)

        // Nothing comes out of this phone from here until it comes home. iOS suspends an app that
        // plays nothing as soon as the screen locks, and the server that feeds the speaker would
        // stop with it. The keep-alive silence prevents that.
        awake.start()
    }

    /// Brings the sound back to the handset, carrying on from `seconds`.
    ///
    /// Whatever the room was still holding is gone: it is in a socket and in the
    /// receiver's own buffer, and neither is reachable from here. The caller says
    /// where the room had got to, and the pump goes on from there.
    public func comeHome(at seconds: Double) throws {
        gate.withLock { goingTo(nil) }

        // **After the handset's own device is running**, so the app never plays nothing at all.
        // Also when `connect()` throws: silence that outlives the cast is a render thread nobody
        // can see and a battery drain nobody can explain.
        defer { awake.stop() }

        try connect()

        gate.withLock {
            inFlight = 0
            scheduled = 0
            runs = []
            announced = nil
            held = nil
            started = false
            if !coming.isEmpty { coming[0].origin = seconds }
        }
    }

    /// Whether the sound is going to a speaker.
    public var casting: Bool { gate.withLock { toTheRoom != nil } }

    // ── what everything else listens to ──
    //
    // There is no tap on the graph. A tap would run a callback on the render thread, which is a
    // second destination for the audio, and it would never fire while casting, because
    // `send(to:)` stops that graph. What draws the music reads ``played`` instead: the pump's own
    // timeline at the playhead, which works for the handset and for a speaker.

    /// Whether the phone itself makes a sound.
    ///
    /// **Casting is a sink, not a second player.** The engine keeps rendering in real time, which
    /// keeps the queue advancing and the position moving. The handset just stops being where the
    /// sound comes out. Nothing above here knows the difference.
    public var silenced: Bool {
        get { engine.mainMixerNode.outputVolume == 0 }
        set { engine.mainMixerNode.outputVolume = newValue ? 0 : 1 }
    }

    /// Keeps `ahead` buffers in front of the node, moving on to whatever is behind the current
    /// source when it runs out.
    ///
    /// **Nothing yet is not the end.** A decoder with no PCM in hand means the network has not
    /// caught up. A pump that treated this as the end would stop the track the first time a train
    /// entered a tunnel. Only `drained` ends a source, and only an empty queue ends the pump.
    private func pump(_ mine: Int) {
        // Local to this run of the pump: a new start or a seek is a new pump, and lands
        // on its gain rather than sliding to it from the record before.
        var level = GainSlide()

        while gate.withLock({ pumpRun }) == mine {
            if PumpDiag.on {
                diag.turned(cushion: cushionSeconds, inFlight: gate.withLock { inFlight })
            }

            announceIfItMoved()

            let room = gate.withLock { Self.ahead - inFlight }
            guard room > 0 else {
                Thread.sleep(forTimeInterval: 0.02)
                continue
            }

            guard let next = gate.withLock({ coming.first }) else {
                // Everything has been handed over and is still coming out of the speaker.
                waitToRunOut(mine)
                continue
            }

            // **Before the read, not after it.** Handing more over while paused fills the ring with
            // audio nobody asked for, and the room would play it as soon as it is told to go again.
            // If the check came after the read, a pause that landed while the pump was outside the
            // room's wait would decode and drop a block on every turn: the record would run on
            // unheard, and play would resume further on.
            if gate.withLock({ state.isPaused }), gate.withLock({ toTheRoom != nil }) {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }

            let made: AVAudioPCMBuffer?
            do { made = try next.source.read(upTo: Self.bite) }
            catch {
                Self.log.error("decode stopped: \(error.localizedDescription, privacy: .public)")
                takeItOffTheFront(Ending(why: .theDecoderStopped, reachedItsEnd: false))
                continue
            }

            guard let buffer = made else {
                if next.source.drained {
                    // A record shorter than the cushion is still a record.
                    startIfThereIsEnough(whateverIsThere: true)

                    // On to the next one. **Nothing is stopped here**: what is already
                    // in front of the node carries on playing. The source is asked why
                    // it drained on the way out, because in a moment it will be gone.
                    takeItOffTheFront(next.source.ending)
                    continue
                }

                Thread.sleep(forTimeInterval: 0.02)
                continue
            }

            // **Levelled here, before the fork**, so the handset and a speaker get the
            // same samples and the picture is drawn from what is heard. The setting is
            // read for every block, so a change reaches this record without a restart.
            level.apply(next.loudness.gain(under: normalize).linear, to: buffer)

            // **Every block, whichever destination takes it, at the frame that destination is about
            // to give it.** Both branches below open their runs at `scheduled` and advance it by
            // the same length, so one number serves the node's clock and the speaker's alike. This
            // is before the fork and not inside it, so that the picture cannot work in one room and
            // fail in the other.
            played.write(buffer, at: gate.withLock { scheduled })

            if let room = gate.withLock({ toTheRoom }) {
                // **Waits here**, which is what makes the room the clock: the speaker's own
                // position says whether the decoder may run on. It is a real wait, and the pump has
                // its own thread for it.
                hand(buffer, to: room, as: next.id, from: next.origin, while: mine)
            } else {
                schedule(buffer, as: next.id, from: next.origin, while: mine)
            }
        }
    }

    /// Hands one buffer to the speaker, opening a new run if this is a different track from the
    /// previous one.
    ///
    /// The bookkeeping is the same as in ``schedule``: `runs` are in frames since the destination
    /// began either way. The only difference between the handset and the room is **whose clock
    /// says what has been heard**.
    ///
    /// **Only while this pump is still the current one.** A block decoded before a `stop` or a
    /// `begin` arrives here after it: the pump checks `pumpRun` at the top of its loop, and the
    /// decode in between is most of the work. Without the check, the stale block would open a run
    /// in the `runs` that `stop` had just emptied. A stop leaves the cast standing, so `playing`
    /// would read that run and the player would say it wanted to play after being told to stop.
    /// See ``isCurrent(_:)``.
    private func hand(_ buffer: AVAudioPCMBuffer, to room: RoomFeed,
                      as id: Int, from origin: Double, while mine: Int) {
        let current = gate.withLock { () -> Bool in
            guard isCurrent(mine) else { return false }

            if runs.last?.id != id {
                runs.append(Run(id: id, from: scheduled, origin: origin))
            }
            scheduled += AVAudioFramePosition(buffer.frameLength)
            return true
        }

        guard current else { return }

        _ = room.take(buffer, while: { self.gate.withLock { self.pumpRun } == mine })
    }

    /// Hands one buffer to the node, opening a new run if this is a different track from the
    /// previous one.
    ///
    /// Only while this pump is still the current one, for the reason given in
    /// ``hand(_:to:as:from:while:)``. Here a stale block would also be put in front of a node that
    /// `stop` had just stopped, and enough of them would start the node again.
    private func schedule(_ buffer: AVAudioPCMBuffer, as id: Int, from origin: Double,
                          while mine: Int) {
        let current = gate.withLock { () -> Bool in
            guard isCurrent(mine) else { return false }

            if runs.last?.id != id {
                runs.append(Run(id: id, from: scheduled, origin: origin))
            }
            inFlight += 1
            scheduled += AVAudioFramePosition(buffer.frameLength)
            return true
        }

        guard current else { return }

        node.scheduleBuffer(buffer) { [weak self] in
            self?.gate.withLock { self?.inFlight -= 1 }
        }

        startIfThereIsEnough()
    }

    /// Whether the pump numbered `mine` is still the one this engine is running.
    ///
    /// **Ask under the gate, in the same block as the write it decides.** `stop` and `begin`
    /// change `pumpRun` and then empty `runs`, each under the gate. A write that checks first
    /// either lands before the change (and is emptied with the rest) or sees the change and does
    /// nothing. If the check and the write are in separate blocks, the answer can be stale when
    /// the write happens.
    ///
    /// The gate is held by every caller.
    private func isCurrent(_ mine: Int) -> Bool { pumpRun == mine }

    /// Starts the node once there is a cushion in front of it, or once there is
    /// nothing more coming: a track shorter than the cushion must still play.
    private func startIfThereIsEnough(whateverIsThere: Bool = false) {
        let go = gate.withLock { () -> Bool in
            guard !started else { return false }

            // **Somebody asked for silence, and that outranks having enough to play.**
            //
            // The pump has its own pause check, but it tests `paused && toTheRoom != nil`. That is
            // limited to the cast, because handing buffers to a paused *room* fills a ring with
            // audio nobody asked for, while handing them to a paused *node* just prepares the audio
            // that a resume wants. So the local path has no pause except the node's own.
            //
            // That fails when the node is re-armed. `comeHome` clears `started` and starts the
            // engine, so a cast that was paused and then brought home (the room failed, or the
            // speaker was switched off) would reach here with the pump running and `toTheRoom` nil,
            // and the record would start playing out of the handset while `paused` was still true.
            //
            // `resume` starts the node itself and sets `started`, so nothing waits on this to be
            // let through.
            guard !state.isPaused else { return false }

            guard whateverIsThere || scheduled >= Self.priming else { return false }

            started = true
            return true
        }

        if go { node.play() }
    }

    /// Says so once, when the track coming out of the speaker becomes a different one from the
    /// previous one.
    ///
    /// **Two kinds of answer, and only one may tidy up.** A record that a clock reached is a fact
    /// about what has been heard. A record named because no position has been reported yet is a
    /// statement about what will be heard. Dropping runs on the strength of that would throw away
    /// the description of audio still to be played. Then the clock's own answer would fall
    /// through to `runs.first` and keep naming the same wrong record for the rest of the song.
    private func announceIfItMoved() {
        let reached = whereItIs()?.run.id
        guard let now = reached ?? gate.withLock({ whatIsAboutToBeHeard() }) else { return }

        let changed = gate.withLock { () -> Bool in
            guard announced != now else { return false }
            announced = now

            // Runs the clock has gone past are no longer needed, and would otherwise grow while the
            // app is open. **Only where a clock said so**: see above.
            if reached != nil, let at = runs.firstIndex(where: { $0.id == now }), at > 0 {
                runs.removeFirst(at)
            }
            return true
        }

        if changed { moved?(now) }
    }

    /// Waits for the last of what was handed over to be heard, then says so once.
    private func waitToRunOut(_ mine: Int) {
        var said = false

        while gate.withLock({ pumpRun }) == mine {
            announceIfItMoved()

            guard gate.withLock({ coming.isEmpty }) else { return }

            if !said, gate.withLock({ inFlight == 0 }) {
                said = true
                ranOut?(gate.withLock { lastEnding })
            }

            Thread.sleep(forTimeInterval: 0.05)
        }
    }
}

extension AVAudioPCMBuffer {
    /// The same audio without its first `frames`.
    ///
    /// A copy, not a view, because an `AVAudioPCMBuffer` cannot start part way in. It is used for
    /// a few blocks per record: the one where a head start hands over, and the one or two that an
    /// encoder's priming falls inside.
    func past(_ frames: AVAudioFrameCount) -> AVAudioPCMBuffer? {
        guard frames < frameLength,
              let from = floatChannelData,
              let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength - frames),
              let to = out.floatChannelData
        else { return nil }

        out.frameLength = frameLength - frames

        for channel in 0..<Int(format.channelCount) {
            to[channel].update(from: from[channel] + Int(frames), count: Int(out.frameLength))
        }

        return out
    }
}
