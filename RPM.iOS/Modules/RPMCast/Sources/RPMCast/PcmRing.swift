import Foundation
import os

/// A place for audio to wait between the engine that makes it and the speaker that asks for it.
///
/// **Two clocks, and neither of them is ours.** The engine renders in real time on the audio thread. The receiver pulls
/// over the network at whatever rate its own buffer needs. The ring lets each side run at its own rate, without either one
/// waiting for the other. Its size is the main tuning value. It must be large enough to cover a short network stall. It
/// must be small enough that a pause is heard when it is pressed, not several seconds later.
///
/// When the ring is full, a write **drops the oldest audio**. This is deliberate. The audio thread must not wait for anything,
/// and a speaker that stops reading must not be able to stop the phone from rendering.
///
/// ## One side of this is the audio thread
///
/// The audio thread is a real-time thread with a deadline every few milliseconds. Everything here follows from that:
///
/// - **`os_unfair_lock`, not `NSLock`.** A pthread mutex does not pass on priority. The other side of this lock is a normal
///   networking thread, which the scheduler may not run soon. The audio thread would then wait on a low-priority thread. That
///   is priority inversion, and it is heard as distortion. `os_unfair_lock` gives the waiter's priority to the thread that holds the lock.
/// - **Raw memory, not `[UInt8]`.** Writing into a Swift array checks whether its storage is uniquely referenced. If it is not,
///   the whole array may be copied. Copying a megabyte inside the lock would hold up the audio thread for far too long.
/// - **Nothing allocates while the lock is held**, on either side. The reader copies into memory that the caller already owns.
///   See ``read(into:)``.
public final class PcmRing: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.rpm.player", category: "cast")

    /// Allocated, not stored as a property. `os_unfair_lock` must not be copied or moved, and a Swift struct field
    /// does not guarantee either.
    private let gate: UnsafeMutablePointer<os_unfair_lock>

    private let store: UnsafeMutableRawPointer
    private let room: Int

    private var readAt = 0
    private var count = 0
    private var lost = 0

    public init(seconds: Double = 6, rate: Int = 44100, channels: Int = 2, bits: Int = 16) {
        perSecond = rate * channels * (bits / 8)
        room = max(1, Int(seconds * Double(perSecond)))

        store = UnsafeMutableRawPointer.allocate(byteCount: room, alignment: 16)

        gate = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
        gate.initialize(to: os_unfair_lock())
    }

    deinit {
        store.deallocate()
        gate.deinitialize(count: 1)
        gate.deallocate()
    }

    /// How many bytes one second of audio takes, in the format that this ring was made for.
    public let perSecond: Int

    public var capacity: Int { room }

    public var held: Int { locked { count } }

    /// How many bytes have been dropped because there was no room. A count that keeps rising means that the receiver has stopped reading.
    public var dropped: Int { locked { lost } }

    private func locked<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(gate)
        defer { os_unfair_lock_unlock(gate) }
        return body()
    }

    /// Adds audio. It never waits and never fails. When there is no room, the oldest audio is dropped.
    ///
    /// **Two copies, not sixteen thousand assignments.** The audio tap calls this on the audio thread. Copying the input one
    /// byte at a time, with a modulo on each byte, overruns the render deadline for a 16 KB buffer.
    /// An overrun is heard as distortion, not as a small dropout. The ring has at most two contiguous parts, so two
    /// `memcpy` calls copy it.
    public func write(_ data: UnsafeRawBufferPointer) {
        guard !data.isEmpty, let source = data.baseAddress else { return }

        locked {
            // More than the whole ring holds. Only the end of it could survive anyway.
            let taking = min(data.count, room)
            let skipped = data.count - taking
            if skipped > 0 { lost += skipped }

            // Drop the oldest audio first. Then the copies below cannot overwrite bytes that have not been moved yet.
            let over = max(0, count + taking - room)
            if over > 0 {
                readAt = (readAt + over) % room
                count -= over
                lost += over
            }

            let writeAt = (readAt + count) % room
            let first = min(taking, room - writeAt)

            store.advanced(by: writeAt)
                .copyMemory(from: source.advanced(by: skipped), byteCount: first)

            if taking > first {
                store.copyMemory(from: source.advanced(by: skipped + first),
                                 byteCount: taking - first)
            }

            count += taking
        }
    }

    /// The same as `write(_:)` above, for a caller that has an array instead of a pointer. This is used mostly by tests.
    /// The audio tap already has a pointer, and it should keep using that.
    public func write(_ data: [UInt8]) {
        data.withUnsafeBytes { write($0) }
    }

    /// Copies what fits into `pail`, and returns how many bytes were copied.
    ///
    /// **The caller provides the memory.** The reader holds a lock that the audio thread waits on, so it must not allocate
    /// while the lock is held. A `malloc` here would make the audio thread wait. Zero is the normal answer while the engine
    /// is between buffers. It does not mean that anything is wrong.
    public func read(into pail: UnsafeMutableRawBufferPointer) -> Int {
        guard let into = pail.baseAddress else { return 0 }

        return locked {
            let taking = min(pail.count, count)
            guard taking > 0 else { return 0 }

            let first = min(taking, room - readAt)

            into.copyMemory(from: store.advanced(by: readAt), byteCount: first)
            if taking > first {
                into.advanced(by: first).copyMemory(from: store, byteCount: taking - first)
            }

            readAt = (readAt + taking) % room
            count -= taking
            return taking
        }
    }

    /// The same as ``read(into:)``, for a caller that wants an array back. This is used by tests.
    /// A server that writes to a socket already has a buffer, and it should use ``read(into:)``.
    public func read(upTo most: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: max(0, most))
        let took = out.withUnsafeMutableBytes { read(into: $0) }

        out.removeLast(out.count - took)
        return out
    }

    /// Throws away everything except the newest `bytes`.
    ///
    /// **This sets the start-up buffer that a receiver needs.** A receiver does not start playing until it has some audio
    /// buffered. Audio rendered in real time can never get ahead to fill that buffer. At normal speed, the buffer fills only
    /// as fast as it drains, so the speaker would wait forever. What is already in the ring is the head start. Anything older
    /// is only a delay between the phone's playhead and what the room hears.
    public func keepNewest(_ bytes: Int) {
        locked {
            let extra = count - max(0, bytes)
            guard extra > 0 else { return }

            readAt = (readAt + extra) % room
            count -= extra
        }
    }

    public func empty() {
        locked {
            readAt = 0
            count = 0
            lost = 0
        }
    }
}
