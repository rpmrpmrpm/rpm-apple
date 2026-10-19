import Foundation
import AVFAudio
import Testing
@testable import RPMAudio

/// Records whose compressed packets are all the same size.
///
/// **The parser gives packet descriptions only for packets of different sizes.** When every
/// packet is the same size, there are no descriptions. The data arrives as a run of packets with
/// no descriptions. If that run is passed to the converter as one packet, decoding stops with an
/// error such as `8192 bytes of input provided, but packet descriptions (0) only account for 0
/// bytes`. This suite guards against that failure.
///
/// Uncompressed PCM needs no packets, and `UncompressedStreamTests` covers it. This suite covers
/// compressed formats whose packets are all one size. µ-law is the simplest example.
@Suite("A record whose packets are all one size")
struct PacketRunTests {

    /// Half a second of a tone as µ-law in a WAV, laid out the way `ffmpeg` lays one
    /// out: an eighteen byte `fmt ` saying format seven, then a `fact`, then the audio.
    private func ulaw(seconds: Double, rate: Int = 44_100, channels: Int = 2) -> Data {
        let frames = Int(Double(rate) * seconds)
        var out = Data()

        func four(_ text: String) { out.append(contentsOf: Array(text.utf8)) }
        func long(_ value: Int) { out.append(contentsOf: withUnsafeBytes(of: UInt32(value).littleEndian, Array.init)) }
        func short(_ value: Int) { out.append(contentsOf: withUnsafeBytes(of: UInt16(value).littleEndian, Array.init)) }

        four("RIFF"); long(46 + frames * channels); four("WAVE")
        four("fmt "); long(18); short(7); short(channels)
        long(rate); long(rate * channels); short(channels); short(8); short(0)
        four("fact"); long(4); long(frames)
        four("data"); long(frames * channels)

        for at in 0..<frames {
            let sample = Int16(sin(Double(at) / Double(rate) * 440 * 2 * .pi) * 8000)
            for _ in 0..<channels { out.append(Self.encoded(sample)) }
        }

        return out
    }

    /// The standard µ-law of one sample: sign, exponent, mantissa, inverted.
    private static func encoded(_ sample: Int16) -> UInt8 {
        var value = Int32(sample)
        let sign: Int32 = value < 0 ? 0x80 : 0
        if sign != 0 { value = -value }

        value = min(value, 32_635) + 132

        var exponent: Int32 = 7
        var mask: Int32 = 0x4000
        while value & mask == 0 && exponent > 0 {
            exponent -= 1
            mask >>= 1
        }

        let mantissa = (value >> (exponent + 3)) & 0x0F
        return UInt8(~(sign | (exponent << 4) | mantissa) & 0xFF)
    }

    private func fed(_ bytes: Data, chunk: Int = 8192) throws -> StreamedPcm {
        let source = StreamedPcm()

        for at in stride(from: 0, to: bytes.count, by: chunk) {
            try source.take(bytes[at..<min(at + chunk, bytes.count)])
        }
        source.finish(.theFileRanOut)

        return source
    }

    @Test func itOpens() throws {
        let source = try fed(ulaw(seconds: 0.5))

        #expect(source.ready, "the header was read and nothing could decode it")
        #expect(source.format?.streamDescription.pointee.mFormatID == kAudioFormatULaw)
    }

    /// Every read threw an error. When a decode stops, the pump drops the record.
    @Test func aRunOfPacketsDecodes() throws {
        let source = try fed(ulaw(seconds: 0.5))

        var frames: AVAudioFramePosition = 0
        while let buffer = try source.read(upTo: 4096) {
            frames += AVAudioFramePosition(buffer.frameLength)
        }

        #expect(frames > 20_000, "\(frames) frames of a half-second record")
    }

    /// The whole run must be decoded. A converter given more data than it asks for keeps what fits
    /// and drops the rest. Dropped data makes the record play several times too fast.
    @Test func theWholeRunIsDecodedRatherThanAsMuchOfItAsFitted() throws {
        let source = try fed(ulaw(seconds: 0.5), chunk: 65_536)

        var frames: AVAudioFramePosition = 0
        var loudest: Float = 0

        while let buffer = try source.read(upTo: 4096) {
            frames += AVAudioFramePosition(buffer.frameLength)
            guard let channel = buffer.floatChannelData?[0] else { continue }
            for at in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(channel[at])) }
        }

        #expect(frames > 20_000, "\(frames) frames at 64 KB a chunk")
        #expect(loudest > 0.1, "it decoded to silence")
    }
}
