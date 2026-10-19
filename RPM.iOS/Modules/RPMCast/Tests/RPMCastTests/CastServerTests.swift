import Foundation
import Testing
@testable import RPMCast

/// The ring, and the server that reads from it.
@Suite("Somewhere for the audio to wait")
struct PcmRingTests {

    @Test func whatGoesInComesOutInOrder() {
        let ring = PcmRing(seconds: 1)
        ring.write([1, 2, 3, 4, 5])

        #expect(ring.read(upTo: 3) == [1, 2, 3])
        #expect(ring.read(upTo: 10) == [4, 5])
        #expect(ring.read(upTo: 10).isEmpty)
    }

    /// An empty ring is the normal answer while the engine is between buffers. It does not mean that anything is wrong.
    @Test func anEmptyRingIsNotAnError() {
        #expect(PcmRing(seconds: 1).read(upTo: 100).isEmpty)
    }

    /// **The oldest audio is dropped, and the audio thread never waits.** A speaker that stops reading must not be able to
    /// stop the phone from rendering. A render callback may not block at all.
    @Test func aFullRingDropsTheOldestRatherThanWaiting() {
        let ring = PcmRing(seconds: 0.5, rate: 10, channels: 1, bits: 16)
        let room = ring.capacity

        ring.write(Array(repeating: UInt8(1), count: room))
        ring.write([9, 9])

        #expect(ring.dropped == 2)
        #expect(ring.held == room)

        let out = ring.read(upTo: room)
        #expect(out.suffix(2) == [9, 9], "the newest audio was thrown away instead of the oldest")
    }

    @Test func itWrapsAroundTheEnd() {
        let ring = PcmRing(seconds: 0.5, rate: 10, channels: 1, bits: 16)
        let room = ring.capacity

        ring.write(Array(repeating: UInt8(7), count: room - 2))
        _ = ring.read(upTo: room - 2)
        ring.write([1, 2, 3, 4])

        #expect(ring.read(upTo: 10) == [1, 2, 3, 4])
    }
}

/// The 44 bytes at the start of an endless WAV. The receiver reads them once.
@Suite("The header on an endless WAV")
struct WavHeaderTests {

    @Test func itIsAWavAndItSaysWhatIsInIt() {
        let header = WavHeader.of(rate: 44100, channels: 2, bits: 16)

        #expect(header.count == 44)
        #expect(String(decoding: header.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: header[8..<12], as: UTF8.self) == "WAVE")
        #expect(String(decoding: header[36..<40], as: UTF8.self) == "data")
    }

    @Test func theRateAndTheChannelsAreOnTheWireLittleEndian() {
        let header = WavHeader.of(rate: 44100, channels: 2, bits: 16)

        func read(_ at: Int, _ wide: Int) -> Int {
            header[at..<(at + wide)].reversed().reduce(0) { ($0 << 8) | Int($1) }
        }

        #expect(read(20, 2) == 1, "not linear PCM")
        #expect(read(22, 2) == 2)
        #expect(read(24, 4) == 44100)
        #expect(read(28, 4) == 44100 * 4, "the byte rate does not match the format")
        #expect(read(32, 2) == 4)
        #expect(read(34, 2) == 16)
    }

    /// **Not the largest number that the field can hold.** A receiver that reads the size as signed sees a negative length,
    /// and it refuses the stream.
    @Test func theLengthIsAPromiseNobodyKeepsAndStillReadsAsPositive() {
        let header = WavHeader.of()

        func read(_ at: Int) -> UInt32 {
            header[at..<(at + 4)].reversed().reduce(0) { ($0 << 8) | UInt32($1) }
        }

        #expect(read(40) > 1_000_000_000, "the stream would end in minutes")
        #expect(read(40) < UInt32(Int32.max), "a signed reader would see this as negative")
        #expect(read(4) == read(40) + 36)
    }
}

/// Reading into memory that the caller already has.
///
/// **This exists for the audio thread.** The reader is on the other side of the ring's lock, so it must not allocate while
/// holding that lock. A `malloc` there is a pause that the audio thread inherits. A pause on the audio thread is heard as
/// distortion. A reader that allocates its result inside the lock causes exactly this.
@Suite("Somewhere for the audio to wait, read without allocating")
struct PcmRingReadTests {

    @Test func itFillsWhatItIsGivenAndSaysHowMuch() {
        let ring = PcmRing(seconds: 1)
        ring.write([1, 2, 3, 4, 5])

        var pail = [UInt8](repeating: 0, count: 3)
        let took = pail.withUnsafeMutableBytes { ring.read(into: $0) }

        #expect(took == 3)
        #expect(pail == [1, 2, 3])
        #expect(ring.held == 2)
    }

    /// A pail that is bigger than the audio held is only partly filled. **The rest of it is not touched.** The caller sends
    /// only `took` bytes. Anything written past that would be heard as whatever was in memory.
    @Test func aPailBiggerThanWhatIsHeldIsOnlyPartFilled() {
        let ring = PcmRing(seconds: 1)
        ring.write([9, 9])

        var pail = [UInt8](repeating: 0xEE, count: 6)
        let took = pail.withUnsafeMutableBytes { ring.read(into: $0) }

        #expect(took == 2)
        #expect(pail == [9, 9, 0xEE, 0xEE, 0xEE, 0xEE])
    }

    /// Audio in the ring is one run or two. A reader that handles only one run loses everything past the seam.
    @Test func itReadsAcrossTheSeam() {
        let ring = PcmRing(seconds: 0.5, rate: 10, channels: 1, bits: 16)
        let room = ring.capacity

        ring.write(Array(repeating: UInt8(7), count: room - 2))
        _ = ring.read(upTo: room - 2)
        ring.write([1, 2, 3, 4])

        var pail = [UInt8](repeating: 0, count: 4)
        let took = pail.withUnsafeMutableBytes { ring.read(into: $0) }

        #expect(took == 4)
        #expect(pail == [1, 2, 3, 4])
    }

    @Test func anEmptyRingFillsNothing() {
        var pail = [UInt8](repeating: 0, count: 8)
        #expect(PcmRing(seconds: 1).read(into: UnsafeMutableRawBufferPointer(start: &pail, count: 8)) == 0)
    }
}
