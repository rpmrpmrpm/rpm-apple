import Foundation
import AVFAudio
import os

/// The sound as it is being played, kept for whatever draws it (the visualiser).
///
/// **It is a timeline and not a tail of recent audio**, and that is why a visualiser works
/// while a speaker is connected. The pump writes every block it decodes at the frame
/// where the destination will take it, and a read asks for the window ending *at the
/// playhead*. So what is drawn is what is heard, whether the playhead is the node's own
/// clock or a position that a speaker in another room reported over the network.
///
/// Ported from `AudioEngine.CopyPlayFrame` on the desktop, whose documentation says the
/// same: *"These are the exact samples the sink is playing, so the visualiser is in sync
/// with the sound, including when the sound is coming out of a speaker in another room."*
///
/// This does not use a tap on the graph (`gain.installTap`). `PcmEngine.send(to:)` stops
/// the local graph completely, so a tap would draw a picture that does not move while
/// casting. A tap is also a callback on the render thread, which would send audio to two
/// destinations at once, and that distorts the sound when a speaker is connected. Neither
/// the pump nor the reader runs on an audio thread: the pump is an ordinary async loop and
/// so is the reader.
///
/// The `os_unfair_lock` is kept, as `PcmRing` keeps its own. Both sides are ordinary
/// threads, so it is not strictly required, but it is cheap and correct. There is no
/// allocation on either side, and the index arithmetic works in runs, not with a modulo
/// per sample.
public final class RoomSound: @unchecked Sendable {
    /// Twelve seconds of mono at the engine's rate, which is two megabytes.
    ///
    /// **The size is set by how far the pump may run ahead of the room**, not by the
    /// longest window. `RoomFeed.lead` keeps the decoder at most eight seconds ahead of
    /// what the speaker reports as played, so everything the room has not reached yet is
    /// still stored here when it arrives. On the phone itself the two are a fraction of a
    /// second apart and the rest is spare.
    public static let size = 1 << 19

    /// The longest window (in frames) that any reader asks for.
    public static let window = 8192

    private let gate: UnsafeMutablePointer<os_unfair_lock>
    private let ring: UnsafeMutablePointer<Float>

    /// Frames written, **in the engine's own count**: the same count is used when a run is
    /// opened and when the playhead is read. Nothing here converts between two clocks,
    /// because there is only one.
    private var written: AVAudioFramePosition = 0
    private var heardAt: Double = 0

    /// Returns where the sound has actually got to. It is asked for when needed and is not
    /// pushed.
    ///
    /// **Set once, by the engine that owns this, before anything can read it.** That is
    /// why it is a plain field and not protected by the gate. It is called outside the
    /// lock, because answering takes the engine's own lock, and calling it in the other
    /// order would leave the two locks waiting for each other (deadlock).
    private var clock: (@Sendable () -> AVAudioFramePosition?)?

    public init() {
        ring = UnsafeMutablePointer<Float>.allocate(capacity: Self.size)
        ring.initialize(repeating: 0, count: Self.size)

        gate = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        gate.initialize(to: os_unfair_lock())
    }

    deinit {
        ring.deinitialize(count: Self.size)
        ring.deallocate()
        gate.deinitialize(count: 1)
        gate.deallocate()
    }

    /// Sets where the playhead is read from. The engine calls this once, when it is built.
    public func reads(from clock: @escaping @Sendable () -> AVAudioFramePosition?) {
        self.clock = clock
    }

    private func locked<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(gate)
        defer { os_unfair_lock_unlock(gate) }
        return body()
    }

    /// The engine's sample rate, once anything has been written. The rate decides what
    /// every frequency bin means, so the analysis waits for it and does not assume one.
    public var rate: Double { locked { heardAt } }

    /// Whether enough has been written to fill the longest window.
    public var ready: Bool { locked { written >= Self.window } }

    /// Writes one block, mixed down to mono, at the frame where the destination will take
    /// it.
    ///
    /// - Parameter frame: the engine's `scheduled` count *before* this block is added to
    ///   it. The caller passes it and this method does not count itself, so a missing
    ///   write cannot go unnoticed: if a future destination forgets to write, it leaves a
    ///   gap that the read refuses, and does not shift every later sample by the length
    ///   of the gap.
    public func write(_ buffer: AVAudioPCMBuffer, at frame: AVAudioFramePosition) {
        guard let channels = buffer.floatChannelData else { return }

        let frames = Int(buffer.frameLength)
        let count = Int(buffer.format.channelCount)
        guard frames > 0, count > 0 else { return }

        // Only the newest samples can fit if a block is longer than the whole ring. No
        // caller produces such a block, but taking only the end keeps the arithmetic
        // below correct in that case too.
        let taking = min(frames, Self.size)
        let from = frames - taking
        let scale = 1 / Float(count)

        locked {
            heardAt = buffer.format.sampleRate

            // **A start or a seek is a new timeline, and it is detected here and not
            // announced by the caller.** `begin`, `send(to:)` and `comeHome` all set
            // `scheduled` back to zero. A reset that must be remembered in four places
            // will be forgotten in a fifth. A frame that does not continue the last
            // written one cannot belong to the same run of sound, so everything before it
            // becomes unreadable.
            if frame != written { written = frame }

            var at = Int(written % AVAudioFramePosition(Self.size))
            var done = 0

            // **Copy in at most two runs, not one modulo per sample.** The cast ring does
            // the same.
            while done < taking {
                let room = min(taking - done, Self.size - at)

                for i in 0..<room {
                    var sum: Float = 0
                    for c in 0..<count { sum += channels[c][from + done + i] }
                    ring[at + i] = sum * scale
                }

                at = (at + room) % Self.size
                done += room
            }

            written += AVAudioFramePosition(taking)
        }
    }

    /// Fills a frame with the window **ending at the playhead**, oldest first.
    ///
    /// Returns false whenever the correct answer is "not available": before there is a
    /// window of sound, before the playhead has been reported at all, and when the room
    /// has fallen so far behind that what it is playing has been overwritten. A picture
    /// that stops is better than one drawn from the wrong seconds.
    public func fill(_ frame: inout [Float]) -> Bool {
        let n = frame.count
        guard n > 0, n <= Self.size else { return false }

        // Outside the lock: see ``clock``.
        guard let upto = clock?() else { return false }

        let length = AVAudioFramePosition(n)
        let began = upto - length

        return frame.withUnsafeMutableBufferPointer { into -> Bool in
            locked {
                guard began >= 0, upto <= written, let out = into.baseAddress else {
                    return false
                }

                // Overwritten while the room was still behind it.
                guard written - began <= AVAudioFramePosition(Self.size) else { return false }

                let start = Int(began % AVAudioFramePosition(Self.size))
                let first = min(n, Self.size - start)

                out.update(from: ring + start, count: first)
                if n > first { (out + first).update(from: ring, count: n - first) }

                return true
            }
        }
    }

    /// Discards everything written so far.
    ///
    /// **Do not call it on a track change.** The window follows the playhead, so when the
    /// playhead crosses into the next track the window holds the join between the two
    /// tracks, which is exactly what the speaker is playing. Clearing here would blank the
    /// picture for as long as the room is behind, which can be up to eight seconds of a
    /// track that is still playing.
    public func forget() {
        locked {
            written = 0
            ring.update(repeating: 0, count: Self.size)
        }
    }
}
