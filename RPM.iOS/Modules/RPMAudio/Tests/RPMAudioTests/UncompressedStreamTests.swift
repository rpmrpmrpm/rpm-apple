import Foundation
import AVFAudio
import Testing
@testable import RPMAudio

/// A record stored as uncompressed PCM, such as a WAV. It needs no decoding step.
///
/// **The store serves the original file to a listener who asks for original quality.** An
/// original can be a WAV as easily as a FLAC. Every other format on this path is compressed.
/// Two places assumed that, and this suite checks both. First, the parser hands over packets
/// without describing them, because uncompressed packets are all the same size and need no
/// description. Second, the converter receives those bytes as a compressed buffer. For an
/// uncompressed format that buffer has no packet descriptions, so the converter fails with
/// `8192 bytes of input provided, but packet descriptions (0) only account for 0 bytes`.
///
/// If this fails, the head clip plays and then the stream throws on its first read. The pump
/// removes the stream from the front of the queue, and the record ends. The listener hears only
/// the three-second head clip of each track, and then the next track starts.
@Suite("A record that arrives as PCM")
struct UncompressedStreamTests {

    /// A WAV of `seconds` of a tone, header and all, as the store would serve it.
    private func wav(seconds: Double, rate: Int = 44_100, channels: Int = 2) -> Data {
        let frames = Int(Double(rate) * seconds)
        let bytesPerFrame = 2 * channels
        let audio = frames * bytesPerFrame

        var out = Data()

        func four(_ text: String) { out.append(contentsOf: Array(text.utf8)) }
        func long(_ value: Int) { out.append(contentsOf: withUnsafeBytes(of: UInt32(value).littleEndian, Array.init)) }
        func short(_ value: Int) { out.append(contentsOf: withUnsafeBytes(of: UInt16(value).littleEndian, Array.init)) }

        four("RIFF"); long(36 + audio); four("WAVE")
        four("fmt "); long(16); short(1); short(channels)
        long(rate); long(rate * bytesPerFrame); short(bytesPerFrame); short(16)
        four("data"); long(audio)

        // A quiet tone, not silence. A decoder that returned the right number of empty frames
        // would pass a test that only checks for silence.
        for at in 0..<frames {
            let sample = Int16(sin(Double(at) / Double(rate) * 440 * 2 * .pi) * 8000)
            for _ in 0..<channels {
                out.append(contentsOf: withUnsafeBytes(of: sample.littleEndian, Array.init))
            }
        }

        return out
    }

    private func fed(_ bytes: Data, chunk: Int = 8192) throws -> StreamedPcm {
        let source = StreamedPcm()

        for at in stride(from: 0, to: bytes.count, by: chunk) {
            try source.take(bytes[at..<min(at + chunk, bytes.count)])
        }
        source.finish(.theFileRanOut)

        return source
    }

    /// The header is read, and the format comes from the record itself.
    @Test func aWavIsAFormatThisCanOpen() throws {
        let source = try fed(wav(seconds: 0.5))

        #expect(source.ready, "the header was read and nothing could decode it")
        #expect(source.format?.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM)
    }

    /// **The original fault.** Every read threw. When a decode stops, the pump removes the
    /// record from the playback queue.
    @Test func itDecodes() throws {
        let source = try fed(wav(seconds: 0.5))

        var frames: AVAudioFramePosition = 0
        while let buffer = try source.read(upTo: 4096) {
            frames += AVAudioFramePosition(buffer.frameLength)
        }

        // Half a second at 44.1 kHz. The engine rate is the same here, so no resampling is needed.
        #expect(frames > 20_000, "\(frames) frames of a half-second record")
        #expect(source.produced == frames)
    }

    /// The output is the recording itself, not a count of empty frames.
    @Test func whatComesOutIsTheSound() throws {
        let source = try fed(wav(seconds: 0.5))

        var loudest: Float = 0
        while let buffer = try source.read(upTo: 4096) {
            guard let channel = buffer.floatChannelData?[0] else { continue }
            for at in 0..<Int(buffer.frameLength) { loudest = max(loudest, abs(channel[at])) }
        }

        #expect(loudest > 0.1, "it decoded to silence")
    }

    /// A record at another rate is resampled to the engine's, like every other format.
    @Test func aRecordAtAnotherRateComesOutAtTheEngines() throws {
        let source = try fed(wav(seconds: 0.5, rate: 48_000))

        var frames: AVAudioFramePosition = 0
        while let buffer = try source.read(upTo: 4096) {
            frames += AVAudioFramePosition(buffer.frameLength)
            #expect(buffer.format.sampleRate == StreamedPcm.engineFormat.sampleRate)
        }

        #expect(frames > 20_000, "\(frames) frames")
    }

    /// A mono WAV is the other common layout. The resampler does the channel conversion.
    @Test func aMonoRecordPlaysToo() throws {
        let source = try fed(wav(seconds: 0.5, channels: 1))

        var frames: AVAudioFramePosition = 0
        while let buffer = try source.read(upTo: 4096) { frames += AVAudioFramePosition(buffer.frameLength) }

        #expect(frames > 20_000, "\(frames) frames")
    }

    /// **The original fault for records at original quality.**
    ///
    /// The head start asks the store for the record from the point where the clip ends. That is
    /// a range request, and the parser is told about the jump with
    /// `kAudioFileStreamParseFlag_Discontinuity`. An uncompressed stream answers that flag with
    /// `kAudioFileStreamError_DiscontinuityCantRecover` (`'dsc!'`), and it keeps returning that
    /// error for every later call. So the first bytes after the jump could not be parsed, the
    /// download stopped, and only the head clip was heard. The listener heard a couple of
    /// seconds, then the next track.
    ///
    /// The stream cannot recover, and that is correct. A compressed bitstream can find its next
    /// sync word after a jump. Uncompressed audio has no sync words, because every byte is sound,
    /// so there is nothing to find.
    @Test func aRecordCanBeAskedForFromTheMiddle() throws {
        let all = wav(seconds: 10)

        let source = StreamedPcm()
        try source.take(all.prefix(8192))
        let landing = try #require(source.byteToHear(2.75))

        source.expectAJump(landingAt: landing.second)
        try source.take(all[Int(landing.byte)...])
        source.finish(.theFileRanOut)

        var frames: AVAudioFramePosition = 0
        while let buffer = try source.read(upTo: 4096) {
            frames += AVAudioFramePosition(buffer.frameLength)
        }

        let heard = Double(frames) / StreamedPcm.engineFormat.sampleRate
        #expect(heard > 7, "\(heard)s came back of the 7.25s that was asked for")
        #expect(source.ending.reachedItsEnd, "it read as a record that died at the seam")
    }

    /// The byte returned is exact, not estimated. That is why the seam can be measured from it.
    @Test func theByteIsExactForAFormatWithNothingToGuessAbout() throws {
        let source = StreamedPcm()
        try source.take(wav(seconds: 10).prefix(8192))

        guard case .exactly(let byte, let second)? = source.byteToHear(2.75) else {
            Issue.record("the parser guessed at a byte it can count")
            return
        }

        // 2.75 s at 44.1 kHz, stereo, 16-bit, after the 44-byte header.
        #expect(byte == 485_144)
        #expect(second == 2.75)
    }

    /// Chunk boundaries are where this fails. A block of frames can be split across two reads.
    /// A stream that only works on neat boundaries would pass on a fast connection and fail on
    /// a slow one.
    @Test(arguments: [1000, 4096, 65_536])
    func theBytesMayArriveInAnySize(chunk: Int) throws {
        let source = try fed(wav(seconds: 0.5), chunk: chunk)

        var frames: AVAudioFramePosition = 0
        while let buffer = try source.read(upTo: 4096) { frames += AVAudioFramePosition(buffer.frameLength) }

        #expect(frames > 20_000, "\(frames) frames at \(chunk) bytes a chunk")
    }
}
