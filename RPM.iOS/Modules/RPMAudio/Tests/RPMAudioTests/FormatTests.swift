import Foundation
import AVFAudio
import Testing
@testable import RPMAudio

/// Records whose sample rate or channel count differs from the engine's format.
///
/// **A compressed file at another sample rate must be decoded in two steps.** An
/// `AVAudioConverter` from a compressed format straight to PCM at a different sample rate is not
/// created. It returns nil without throwing, and the log only says that nothing can decode `flac`.
/// A 48 kHz record is common, so this case matters.
@Suite("A record at any rate, and any format")
struct FormatTests {

    func decoded(_ name: String, _ ext: String) throws
    -> (frames: Int, peak: Float, source: AVAudioFormat?, out: AVAudioFormat?) {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: ext))
        let source = StreamedPcm()

        try source.take(try Data(contentsOf: url))
        source.finish(.theFileRanOut)

        var frames = 0
        var peak: Float = 0
        var out: AVAudioFormat?

        while let buffer = try source.read() {
            out = buffer.format
            frames += Int(buffer.frameLength)
            guard let samples = buffer.floatChannelData?[0] else { continue }
            for at in 0..<Int(buffer.frameLength) { peak = max(peak, abs(samples[at])) }
        }

        return (frames, peak, source.format, out)
    }

    @Test func aacAtTheEnginesOwnRateNeedsNoResample() throws {
        let (frames, peak, source, out) = try decoded("tone", "m4a")

        #expect(source?.sampleRate == 44100)
        #expect(out?.sampleRate == 44100)
        #expect(abs(Double(frames) - 44100 * 3) < 44100 * 0.1)
        #expect(peak > 0.2)
    }

    @Test func flacDecodes() throws {
        let (frames, peak, source, _) = try decoded("tone", "flac")

        #expect(source?.sampleRate == 44100)
        #expect(frames > 44100 * 2, "only \(frames) frames")
        #expect(peak > 0.2)
    }

    /// **Two converters are used, not one.** The input is 48 kHz and the output is 44.1 kHz.
    /// The frame count must match that ratio. A resample that drops frames plays the record at
    /// the wrong pitch, and nothing here would throw an error.
    @Test func aFortyEightKilohertzStereoRecordArrivesAtTheEnginesRate() throws {
        let (frames, peak, source, out) = try decoded("tone-48-stereo", "flac")

        #expect(source?.sampleRate == 48000)
        #expect(source?.channelCount == 2)

        #expect(out?.sampleRate == 44100, "it did not come out at the engine's rate")
        #expect(out?.channelCount == 2)

        // Two seconds at 48 kHz is two seconds at 44.1 kHz, allowing for packet rounding.
        let expected = 44100.0 * 2
        #expect(abs(Double(frames) - expected) < 44100 * 0.15,
                "got \(frames) frames, wanted about \(Int(expected)): the pitch would be wrong")
        #expect(peak > 0.2, "it resampled to silence")
    }
}

/// Surround records are folded down to stereo.
///
/// `AVAudioFormat(standardFormatWithSampleRate:channels:)` returns nil for more than two
/// channels. A six channel record then has no PCM format to decode into. The log only says that
/// nothing can decode `flac`. Stereo FLAC files play normally, so the fault looks like a codec
/// problem.
extension FormatTests {

    @Test func aFivePointOneRecordIsFoldedDownRatherThanRefused() throws {
        let (frames, peak, source, out) = try decoded("tone-51", "flac")

        #expect(source?.channelCount == 6, "the fixture is not surround")

        #expect(out?.channelCount == 2, "it did not come down to stereo")
        #expect(out?.sampleRate == 44100)

        let expected = 44100.0 * 2
        #expect(abs(Double(frames) - expected) < 44100 * 0.15, "got \(frames) frames")
        #expect(peak > 0.1, "it folded down to silence")
    }
}

/// The same records, arriving in pieces as they do over a network.
///
/// **Handing over a whole file at once is not the failing case.** Data arrives from a socket in
/// chunks of any size. A header can be split across two chunks, and that is a normal case.
extension FormatTests {

    /// Feeds the file in chunks, as a socket does.
    func streamed(_ name: String, _ ext: String, chunk: Int) throws
    -> (frames: Int, source: AVAudioFormat?, out: AVAudioFormat?) {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: ext))
        let data = try Data(contentsOf: url)
        let source = StreamedPcm()

        var frames = 0
        var out: AVAudioFormat?

        var at = 0
        while at < data.count {
            let end = min(at + chunk, data.count)
            try source.take(data[at..<end])
            at = end

            while let buffer = try source.read() {
                out = buffer.format
                frames += Int(buffer.frameLength)
            }
        }

        source.finish(.theFileRanOut)
        while let buffer = try source.read() {
            out = buffer.format
            frames += Int(buffer.frameLength)
        }

        return (frames, source.format, out)
    }

    @Test(arguments: [("tone-51", 44100.0), ("tone-51-centre", 48000.0)])
    func aSurroundRecordArrivingInPiecesStillOpens(name: String, rate: Double) throws {
        let (frames, source, out) = try streamed(name, "flac", chunk: 4096)

        #expect(source?.sampleRate == rate)
        #expect(source?.channelCount == 6, "\(name) never got a format")
        #expect(out?.channelCount == 2)
        #expect(frames > 44100, "only \(frames) frames out of \(name)")
    }
}

/// A surround record with no channel layout tag.
///
/// **This is a common case.** A FLAC stores its channel layout in a
/// `WAVEFORMATEXTENSIBLE_CHANNEL_MASK` comment. ffmpeg leaves that comment out when the channel
/// order is the usual one for that channel count. CoreAudio then reports no layout, and
/// `AVAudioFormat` cannot be created. The record cannot be played.
///
/// The fixture is a real 5.1 file with that comment removed, and its sound is in the centre
/// channel only. The test covers both problems. The missing layout must not stop playback, and
/// the centre channel must still be heard.
extension FormatTests {

    @Test func aSurroundRecordThatNeverSaysWhereItsChannelsGoIsStillPlayed() throws {
        let (frames, _, source, out) = try decoded("tone-51-centre", "flac")

        #expect(source?.channelCount == 6, "it never got a format at all")
        #expect(out?.channelCount == 2, "it did not come down to stereo")
        #expect(out?.sampleRate == 44100)

        let expected = 44100.0 * 2
        #expect(abs(Double(frames) - expected) < 44100 * 0.15, "got \(frames) frames")
    }

    /// **The centre channel must be mixed in, not dropped.** By default an `AVAudioConverter`
    /// keeps the first channels and drops the rest, unless it is told to mix. On a live album the
    /// centre channel carries the vocals. The fixture is silent except in the centre, so any
    /// conversion that does not mix the centre gives silence.
    @Test func theCentreOfASurroundRecordSurvivesTheFoldToStereo() throws {
        let (_, peak, _, _) = try decoded("tone-51-centre", "flac")

        #expect(peak > 0.1, "the centre channel was dropped rather than mixed in")
    }
}
