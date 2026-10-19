import Foundation
import AVFAudio
import Testing
@testable import RPMAudio

/// Decoding a stream that arrives in pieces.
///
/// The fixture is three seconds of a 440 Hz tone, AAC in an MP4, the format the store
/// serves. It is fed in **awkward sizes on purpose**. A decoder fails most often at a chunk
/// boundary, where a packet or the header is split across two reads. A split like that can
/// work on a fast connection and still stutter on a slow one.
@Suite("A stream, decoded as it arrives")
struct StreamedPcmTests {

    private static let rate = 44100.0
    private static let seconds = 3.0

    private func tone() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
        return try Data(contentsOf: url)
    }

    /// Feeds the whole file in pieces of `chunk` bytes and decodes everything that comes out.
    private func decoded(chunk: Int) throws -> (frames: Int, peak: Float, format: AVAudioFormat?) {
        let bytes = try tone()
        let source = StreamedPcm()

        var frames = 0
        var peak: Float = 0

        func drain() throws {
            while let buffer = try source.read() {
                frames += Int(buffer.frameLength)
                guard let samples = buffer.floatChannelData?[0] else { continue }
                for at in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[at])) }
            }
        }

        var at = 0
        while at < bytes.count {
            let end = min(at + chunk, bytes.count)
            try source.take(bytes[at..<end])
            try drain()
            at = end
        }

        source.finish(.theFileRanOut)
        try drain()

        return (frames, peak, source.format)
    }

    /// **The most important case.** One byte at a time splits every packet and the header as
    /// badly as possible.
    @Test(arguments: [1, 7, 512, 4096, 100_000])
    func theSameSoundComesOutWhateverSizeTheBytesArriveIn(chunk: Int) throws {
        let (frames, peak, format) = try decoded(chunk: chunk)

        #expect(format?.sampleRate == Self.rate)

        // AAC adds padding at the start and the end. Within a tenth of a second of the expected
        // length, the whole tone was decoded, not a fragment of it.
        let expected = Self.rate * Self.seconds
        #expect(abs(Double(frames) - expected) < Self.rate * 0.1,
                "got \(frames) frames, wanted about \(Int(expected))")

        // The fixture is a tone at about a third of full scale: not silence, and not noise.
        #expect(peak > 0.2 && peak <= 1.0, "peak was \(peak)")
    }

    @Test func aStreamSaysNothingUntilItHasReadItsHeader() throws {
        let source = StreamedPcm()

        #expect(source.format == nil)
        #expect(!source.ready)
        #expect(try source.read() == nil)
    }

    /// Not having data yet is different from the end of the stream. A player that treated the
    /// first as the second would stop the track early, when the network is slow.
    @Test func nothingYetIsNotTheEnd() throws {
        let source = StreamedPcm()
        try source.take(try tone().prefix(2000))

        #expect(try source.read() != nil || !source.drained)
        #expect(!source.drained)

        source.finish(.theFileRanOut)
        while try source.read() != nil {}
        #expect(source.drained)
    }

    /// HE-AAC in ADTS, the format most internet radio sends. The fixture is a 15 kHz tone. The
    /// AAC-LC base layer runs at 22050 Hz and cannot carry a tone that high, so decoding only
    /// the base layer gives near silence. The SBR layer is needed to reproduce it.
    @Test func heAacDecodesAtItsFullRateWithTheTopOctave() throws {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/high-he", withExtension: "aac"))
        let source = StreamedPcm()
        try source.take(try Data(contentsOf: url))
        source.finish(.theFileRanOut)

        var peak: Float = 0
        while let buffer = try source.read() {
            guard let samples = buffer.floatChannelData?[0] else { continue }
            for at in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[at])) }
        }

        #expect(source.format?.sampleRate == 44100)
        #expect(peak > 0.1, "peak was \(peak)")
    }

    @Test func bytesThatAreNotASoundFileAreRefused() {
        let source = StreamedPcm()
        let rubbish = Data(repeating: 0x7F, count: 4096)

        // Either the take throws, or the source never becomes ready. The caller gets the same
        // answer in both cases, and neither is a crash.
        let threw = (try? source.take(rubbish)) == nil
        #expect(threw || !source.ready)
    }
}
