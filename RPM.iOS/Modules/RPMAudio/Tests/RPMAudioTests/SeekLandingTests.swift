import Foundation
import AVFAudio
import Testing
@testable import RPMAudio

/// Where a seek in a FLAC lands, compared with the second it reports.
///
/// The fixture is 8 kHz mono FLAC: three seconds of silence, then three seconds of white noise.
/// Silence packs into a few bytes per packet and noise into hundreds, so the parser's estimate
/// from the average packet size is far off. Asked for 2 s, `AudioFileStreamSeek` gives a byte
/// near 4 s. The position bar and the lyrics show the second the seek reports, so after a seek
/// to 2 s the noise must begin one second later, not at once.
@Suite("A seek lands on the second it reports")
struct SeekLandingTests {

    /// Where the noise begins in the fixture, in seconds.
    private static let noiseBegins = 3.0

    /// One packet of the fixture is 576 frames at 8 kHz, 72 ms. The seek goes to the start of a
    /// packet, and the resampler adds a few milliseconds.
    private static let allowance = 0.12

    private func fixture() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/quiet-then-noise",
                                                 withExtension: "flac"))
        return try Data(contentsOf: url)
    }

    /// Feeds `bytes` in pieces of `chunk` bytes, so that packets are split across pieces.
    private func feed(_ source: StreamedPcm, _ bytes: Data, chunk: Int) throws {
        var at = bytes.startIndex
        while at < bytes.endIndex {
            let end = min(at + chunk, bytes.endIndex)
            try source.take(bytes[at..<end])
            at = end
        }
    }

    /// Decodes everything held and says how far in the first loud sample is, in seconds.
    private func untilTheNoise(_ source: StreamedPcm) throws -> Double? {
        var frames = 0
        var found: Double?

        while let buffer = try source.read() {
            if found == nil, let samples = buffer.floatChannelData?[0] {
                for at in 0..<Int(buffer.frameLength) where abs(samples[at]) > 0.05 {
                    found = Double(frames + at) / buffer.format.sampleRate
                    break
                }
            }
            frames += Int(buffer.frameLength)
        }
        return found
    }

    /// The whole record has arrived, as it has a few seconds after a record starts, because the
    /// download is not paced. Every chunk size, down to one byte, where every packet is split.
    @Test(arguments: [1, 7, 1000, 100_000])
    func aSeekInWhatHasArrivedLandsOnTheSecondItReports(chunk: Int) throws {
        let bytes = try fixture()
        let source = StreamedPcm()
        try feed(source, bytes, chunk: chunk)
        while try source.read() != nil {}

        let landing = try #require(source.byteToHear(2.0))
        guard case .exactly = landing else {
            Issue.record("the byte was estimated: \(landing)")
            return
        }
        #expect(abs(landing.second - 2.0) < Self.allowance)

        source.expectAJump(to: landing)
        try feed(source, bytes[Int(landing.byte)...], chunk: chunk)
        source.finish(.theFileRanOut)

        let heard = try #require(try untilTheNoise(source), "no noise after the seek")
        let expected = Self.noiseBegins - landing.second
        #expect(abs(heard - expected) < Self.allowance,
                "the noise began \(heard) s after the seek, expected \(expected) s")
    }

    /// A second the download has not reached yet is still the parser's estimate, and says so.
    @Test func aSeekPastWhatHasArrivedIsMarkedAsAnEstimate() throws {
        let bytes = try fixture()
        let source = StreamedPcm()
        try feed(source, bytes.prefix(bytes.count / 2), chunk: 1000)

        let landing = try #require(source.byteToHear(5.5))
        guard case .near = landing else {
            Issue.record("a byte past the download was called exact: \(landing)")
            return
        }
    }

    /// After a seek to a packet the stream has seen, the packets that follow the jump are
    /// mapped too. So the table grows past the place where the first request was replaced.
    @Test func theTableGrowsPastWhereTheFirstRequestStopped() throws {
        let bytes = try fixture()
        let source = StreamedPcm()
        try feed(source, bytes.prefix(bytes.count * 6 / 10), chunk: 1000)

        guard case .near = try #require(source.byteToHear(5.5)) else {
            Issue.record("the first part already reached 5.5 s, so this test checks nothing")
            return
        }

        let landing = try #require(source.byteToHear(1.0))
        source.expectAJump(to: landing)
        try feed(source, bytes[Int(landing.byte)...], chunk: 1000)

        guard case .exactly = try #require(source.byteToHear(5.5)) else {
            Issue.record("the packets after the jump were not mapped")
            return
        }
    }

    /// Bytes from another place than the one the jump announced (for example the last bytes of
    /// a request that was replaced) must not be written into the table. They are compared with
    /// what the table holds, and mapping stops at the first difference.
    @Test func bytesFromTheWrongPlaceAreNotWrittenDown() throws {
        let bytes = try fixture()
        let source = StreamedPcm()
        try feed(source, bytes.prefix(bytes.count * 6 / 10), chunk: 1000)

        let landing = try #require(source.byteToHear(1.0))
        source.expectAJump(to: landing)
        try feed(source, bytes[(Int(landing.byte) + 37)...], chunk: 1000)

        guard case .near = try #require(source.byteToHear(5.5)) else {
            Issue.record("bytes from the wrong place were mapped")
            return
        }
    }
}
