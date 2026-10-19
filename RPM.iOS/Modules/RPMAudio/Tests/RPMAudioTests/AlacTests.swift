import Foundation
import AVFAudio
import Testing
@testable import RPMAudio

/// Apple Lossless (ALAC) playback.
///
/// Without the magic cookie, the codec returns `kAudioCodecBadDataError` on the first packet and
/// produces no frames. The pump then drops the track and moves on. Many iTunes rips are ALAC, so
/// this affects a common kind of file.
///
/// The magic cookie is a blob that the container carries beside the audio. A stream description
/// alone does not say enough to decode some codecs. `AudioFileStream` reads the cookie from the
/// file header.
///
/// **`AVAudioConverter.magicCookie` does not accept the cookie.** Assigning it reads back nil, and
/// decoding still fails. So the decode uses an `AudioConverterRef`.
@Suite("Apple Lossless")
struct AlacTests {

    private func decoded(_ name: String, chunk: Int = 8192) throws
    -> (seconds: Double, peak: Float) {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)",
                                                 withExtension: "m4a"))
        let bytes = try Data(contentsOf: url)

        let source = StreamedPcm()
        for at in stride(from: 0, to: bytes.count, by: chunk) {
            try source.take(bytes[at..<min(at + chunk, bytes.count)])
        }
        source.finish(.theFileRanOut)

        var frames: AVAudioFramePosition = 0
        var peak: Float = 0

        while let buffer = try source.read(upTo: 4096) {
            frames += AVAudioFramePosition(buffer.frameLength)
            guard let channel = buffer.floatChannelData?[0] else { continue }
            for at in 0..<Int(buffer.frameLength) { peak = max(peak, abs(channel[at])) }
        }

        return (Double(frames) / StreamedPcm.engineFormat.sampleRate, peak)
    }

    /// Decodes a file from Apple's own encoder, the one used for iTunes rips.
    @Test func anAppleLosslessRecordPlays() throws {
        let (seconds, peak) = try decoded("apple-alac")

        #expect(seconds > 2.9, "\(seconds)s of a three second record")
        #expect(peak > 0.05, "it decoded to silence: peak \(peak)")
    }

    /// Decodes a file from a second encoder. The cookie belongs to the format, not to one encoder.
    @Test func soDoesOneFromElsewhere() throws {
        let (seconds, peak) = try decoded("fmt-alac")

        #expect(seconds > 2.9, "\(seconds)s")
        #expect(peak > 0.05, "peak \(peak)")
    }

    /// The stream can split at any byte. The cookie must still work when it arrives in the
    /// middle of a chunk.
    @Test(arguments: [1000, 4096, 65_536])
    func theBytesMayArriveInAnySize(chunk: Int) throws {
        let (seconds, _) = try decoded("apple-alac", chunk: chunk)

        #expect(seconds > 2.9, "\(seconds)s at \(chunk) bytes a chunk")
    }
}
