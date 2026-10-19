import Foundation
import AVFAudio
import RPMCast
import os

/// The other place the engine's audio can go: a speaker in another room.
///
/// **This is a destination, not a listener.** The engine has one source and one sink
/// (the Uno head's `LpcmCastSink` works the same way). Swapping the sink moves the sound
/// to the speaker, and nothing above it changes. A queue advances because the engine
/// advances it, a station casts because it is a source too, and a DJ set keeps mixing
/// because the mix is the source.
///
/// The audio does not come from a tap on the live render graph. A tap would send audio
/// to two places and distort the sound. It runs on the audio thread, which has a deadline
/// every few milliseconds, and converting, locking and handing over the samples is work
/// that thread must not be slow at. Pointing the pump here means **there is no audio
/// thread at all while casting**: the phone's audio device is stopped, so no deadline
/// can be missed.
///
/// ## Taking is the clock
///
/// A sink must not accept samples faster than they are consumed. It waits instead. That
/// back pressure paces the decoder, so no timer is needed and nothing runs ahead of the
/// audio. Here the sink waits on the **speaker's own reported position**, and on the ring
/// while the speaker has not reported anything yet.
public final class RoomFeed: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.rpm.player", category: "cast")

    /// How far ahead of the speaker the engine may get. Past this, the pump waits.
    ///
    /// The same eight seconds as the Uno head. This is a limit and not a buffer: the ring
    /// holds the audio, and this stops the decoder from filling the ring with a whole
    /// track ahead of playback.
    private static let lead: Double = 8

    /// If the ring is full and the speaker has not played a frame for this long, the
    /// speaker is gone. It is not just buffering.
    private static let gone: Duration = .seconds(30)

    /// How many seconds past the last report ``gotTo()`` will estimate. A status is due
    /// four times a second, and a second without one is too long to estimate over.
    private static let guessFor: Double = 1

    private let ring: PcmRing
    private let rate: Double
    private let channels: Int

    private let gate = NSLock()

    /// Frames handed over. This is not the same as frames heard: they can be seconds
    /// apart, and keeping the two separate is the main job of this type.
    private var written: AVAudioFramePosition = 0

    /// What the **speaker** last said it had played, in frames. Nil until it says.
    private var reported: AVAudioFramePosition?

    /// When that report arrived, so the time between two reports can be estimated.
    ///
    /// It is updated only when the number moves. A room that has stopped keeps sending
    /// the same value, so it gets no new timestamp and the estimate ends by itself.
    private var reportedAt: ContinuousClock.Instant?

    /// The highest value ``gotTo()`` has returned. It is the same one-way ratchet that
    /// ``says(_:)`` applies to the report, one step later: a report that arrives behind an
    /// estimate must not move the position backwards.
    private var handedOut: AVAudioFramePosition = 0

    /// Where the track being sent began, so a reported position can be turned into a
    /// position in the track.
    private var began: Double = 0

    /// Set when the speaker has gone quiet with a full ring for too long.
    public private(set) var lost = false

    /// Whether the user asked for silence.
    ///
    /// **A paused speaker is a speaker whose position does not move**, and that is the
    /// same thing the stall watch uses to decide a speaker has gone away. Without this
    /// flag a paused room would be declared lost after thirty seconds.
    public var paused: Bool {
        get { gate.withLock { isPaused } }
        set { gate.withLock { isPaused = newValue } }
    }

    private var isPaused = false

    /// Nothing more is going to this room, and **any caller still waiting stops now**.
    ///
    /// The pump waits inside ``take(_:while:)`` for the speaker to catch up. Removing the
    /// destination does not reach a caller that is already waiting there: it would keep
    /// waiting for a room that no longer listens, until the stall timeout thirty seconds
    /// later. The user would see half a minute of Buffering after moving the sound back
    /// to the phone.
    public func release() {
        gate.withLock { let_go = true }
    }

    private var let_go = false

    /// Called when the speaker stops taking audio, so the player can move the sound back
    /// to the phone instead of staying on a stalled cast.
    public var failed: (@Sendable (String) -> Void)?

    private let named: String

    public init(ring: PcmRing, named: String,
                rate: Double = StreamedPcm.engineFormat.sampleRate,
                channels: Int = Int(StreamedPcm.engineFormat.channelCount)) {
        self.ring = ring
        self.named = named
        self.rate = rate
        self.channels = channels
    }

    // ── what the speaker says ──

    /// Records the speaker's own clock, in seconds into the stream it is playing.
    ///
    /// **Nothing on this side knows this number.** Audio that has been handed over is
    /// still in a socket and in several seconds of the receiver's own buffer, so only
    /// the room can say where playback is. The value only moves forward, because status
    /// updates arrive with jitter and a position that goes backwards makes a seek bar
    /// twitch.
    public func says(_ seconds: Double) {
        gate.withLock {
            let frames = AVAudioFramePosition(max(0, seconds) * rate)
            if frames > (reported ?? 0) {
                reported = frames
                reportedAt = .now
            }
        }
    }

    /// Where in the track the room has got to, or nil before it has reported anything.
    public var heard: Double? {
        gate.withLock {
            guard let at = gotTo() else { return nil }
            return began + Double(at) / rate
        }
    }

    /// Frames the room has played, counted in the same way as ``written``.
    public var played: AVAudioFramePosition? { gate.withLock { gotTo() } }

    /// Where the room is **in the stream it is playing**. This is the receiver's own
    /// count, not a position in the track.
    ///
    /// ``heard`` adds ``began`` to give the position in the track. A screen in another
    /// room needs the stream position instead: it runs its clock from the media
    /// element's `currentTime`, so an anchor given to it must use that count. Otherwise
    /// the time shown on a television is wrong by the point where the stream started.
    /// See `CastNowPlaying.streamAt`.
    public var inTheStream: Double? {
        gate.withLock {
            guard let at = gotTo() else { return nil }
            return Double(at) / rate
        }
    }

    /// Where the room is now. **This is not the same as the last reported position.**
    ///
    /// A status arrives four times a second, and the speaker plays at normal speed
    /// between reports. Returning the last report on every read would make anything drawn
    /// from it stand still and then jump: a seek bar that moves in steps, and a spectrum
    /// that flashes at four hertz.
    ///
    /// **The estimate is limited in three ways**, and none needs a flag to be set: it
    /// never goes past what has been handed over, it never goes backwards, and it stops
    /// after ``guessFor`` seconds. If no report has arrived for a second, the room may
    /// have stopped, and a position that stands still is the correct answer.
    ///
    /// Every caller must hold the gate.
    private func gotTo() -> AVAudioFramePosition? {
        guard let reported else { return nil }

        var at = reported
        if !isPaused, let since = reportedAt {
            let seconds = min(Self.guessFor, (ContinuousClock.now - since).asSeconds)
            at = min(reported + AVAudioFramePosition(seconds * rate), written)
        }

        handedOut = max(handedOut, at)
        return handedOut
    }

    /// Starts a new stream: a track, or a seek (a receiver sees a seek as a new track).
    public func begin(at seconds: Double) {
        gate.withLock {
            written = 0
            reported = nil
            reportedAt = nil
            handedOut = 0
            began = seconds
            lost = false
        }
        ring.empty()
    }

    /// Our stream has been removed from the receiver, and **nothing stored here describes
    /// real playback** until ``begin(at:)`` starts the next stream.
    ///
    /// The removal and the next `begin` do not happen at the same moment. Between them the
    /// next track is signed and opened, which takes a network round trip. If the state
    /// were kept across that gap, the pacer would keep measuring the lead (how far
    /// ``written`` is ahead of a ``reported`` that stopped moving when the connection was
    /// cut) and treat it as a room that has stopped answering. After thirty seconds of a
    /// slow signature the stall watch would move the music back to the phone, although the
    /// user only pressed next.
    ///
    /// So the numbers are cleared, and the stall watch stops with them. With nothing
    /// reported, the pacer falls back to the ring, which is the right back pressure for a
    /// stream that nobody is reading yet. The ring itself is **not** emptied here. `begin`
    /// does that, because only the caller that starts the new source knows its start
    /// second.
    ///
    /// Reached through `CastSink.handOver`, the only path the removal goes through.
    public func takenBack() {
        gate.withLock {
            reported = nil
            reportedAt = nil

            // **The ratchet must be cleared too, and this is the important part.** If only
            // the report were cleared, ``handedOut`` would stay at the last track's final
            // position, and `gotTo` returns the larger of the two. The next stream's first
            // report is a small number, so it would be ignored. The ratchet normally
            // prevents the position going backwards, but here going back to zero is
            // correct: the next stream starts at its own beginning.
            handedOut = 0

            lost = false
        }
    }

    /// How much audio is in the ring, in seconds.
    public var waiting: Double {
        guard ring.perSecond > 0 else { return 0 }
        return Double(ring.held) / Double(ring.perSecond)
    }

    // ── taking audio ──

    /// Waits until the speaker is within ``lead`` seconds of the engine, then takes the
    /// buffer.
    ///
    /// **This is the clock.** When the speaker pauses, its position stops moving, the
    /// lead fills up, and the engine stands still until the speaker plays again.
    /// Returns false once the sink will take no more.
    ///
    /// **It blocks the calling thread, on purpose.** The only caller is the engine's pump,
    /// which has its own thread for this kind of wait. A wait of several seconds (which
    /// happens whenever the speaker is a little ahead) would take a thread from the
    /// cooperative pool, and the rest of the app could not use it.
    ///
    /// - Parameter carryOn: whether the caller still wants this. It is checked on every
    ///   turn of the wait, because a blocked thread cannot be cancelled and something
    ///   outside must be able to end the wait. `Task.isCancelled` cannot do this: it is
    ///   always false outside a task.
    public func take(_ buffer: AVAudioPCMBuffer, while carryOn: () -> Bool) -> Bool {
        guard paced(while: carryOn) else { return false }
        write(buffer)
        return true
    }

    private func paced(while carryOn: () -> Bool) -> Bool {
        var stalledSince = ContinuousClock.now
        var lastSeen: AVAudioFramePosition = -1

        while carryOn() {
            // Checked first, on every turn: this is how the wait is ended from outside.
            guard !gate.withLock({ let_go }) else { return false }

            let (ahead, seen) = gate.withLock { () -> (Double, AVAudioFramePosition?) in
                guard let reported else { return (0, nil) }
                return (Double(written - reported) / rate, reported)
            }

            guard let seen else {
                // **Nothing reported yet**: the receiver has not fetched anything. The
                // ring is the only back pressure available, and it is enough, because
                // it holds the audio the speaker will start on.
                if ring.held < ring.capacity - ring.perSecond { return true }

                Thread.sleep(forTimeInterval: 0.02)
                continue
            }

            if ahead <= Self.lead { return true }

            if seen != lastSeen {
                // The speaker is moving, so being ahead of it is normal.
                lastSeen = seen
                stalledSince = ContinuousClock.now
            } else if !gate.withLock({ isPaused }), ContinuousClock.now - stalledSince > Self.gone {
                gate.withLock { lost = true }

                // **The state at the time it stopped.** "Stopped playing" alone is not
                // enough to diagnose the fault. The second where it stuck, how far the
                // pump had run past it, and what was left in the ring together tell
                // apart a speaker that went away, a network that stalled, and a status
                // poll that is no longer trusted. These look the same to the user.
                let (at, ahead, held) = gate.withLock {
                    (Double(reported ?? 0) / rate,
                     Double(written - (reported ?? 0)) / rate,
                     Double(ring.held) / Double(max(1, ring.perSecond)))
                }

                failed?("""
                    \(named) stopped playing: stuck at \(String(format: "%.1f", at))s for \
                    \(Self.gone), pump \(String(format: "%.1f", ahead))s ahead, \
                    \(String(format: "%.1f", held))s in the ring
                    """)
                return false
            }

            Thread.sleep(forTimeInterval: 0.02)
        }

        return false
    }

    /// Converts float samples to 16-bit and writes them into the ring.
    ///
    /// **This does not run on the audio thread**, which is the purpose of the whole
    /// design, so it may be ordinary code. It is still written to be cheap: it is called
    /// for every buffer of every track while a speaker is connected.
    private func write(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }

        let frames = Int(buffer.frameLength)
        let count = min(channels, Int(buffer.format.channelCount))
        guard frames > 0, count > 0 else { return }

        var out = [Int16](repeating: 0, count: frames * count)

        out.withUnsafeMutableBufferPointer { into in
            var at = 0
            for frame in 0..<frames {
                for channel in 0..<count {
                    // Clamped before it is scaled. A sample above full scale wraps
                    // around when it is truncated and does not clip, which sounds like
                    // a loud bang.
                    let sample = max(-1, min(1, channelData[channel][frame]))
                    into[at] = Int16(sample * 32767).littleEndian
                    at += 1
                }
            }
        }

        out.withUnsafeBytes { ring.write($0) }
        gate.withLock { written += AVAudioFramePosition(frames) }
    }

    /// Waits until the speaker has taken everything handed over, or until it stops taking.
    ///
    /// **This is the end of the track, not the end of the decode.** When casting they are
    /// seconds apart. Telling them apart lets the queue advance on time without cutting
    /// off the end of the track.
    public func drain() async {
        let until = ContinuousClock.now.advanced(by: Self.gone)

        while ContinuousClock.now < until, !Task.isCancelled {
            let (done, ahead) = gate.withLock { () -> (Bool, Double) in
                guard let reported else { return (false, .infinity) }
                return (reported >= written - AVAudioFramePosition(rate / 2),
                        Double(written - reported) / rate)
            }

            if done { return }
            _ = ahead

            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}


private extension Duration {
    /// Seconds as one number. The attoseconds are included and not dropped, because a
    /// hundredth of a second is already four hundred frames.
    var asSeconds: Double {
        let (seconds, atto) = components
        return Double(seconds) + Double(atto) * 1e-18
    }
}
