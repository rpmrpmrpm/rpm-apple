import Foundation
@testable import RPMAudio

/// Silent audio files. A whole queue can play through in a test without making any sound.
///
/// **Silence, not an empty source.** These are real files with a real header and a real
/// length. The engine compares the header with what the decoder reads, to decide whether
/// a record ended or was cut off (see ``Ending``). An empty source would end the wrong way
/// and prove nothing.
///
/// Written by hand as RIFF, not with `AVAudioFile`, for two reasons. The streaming parser
/// reads RIFF with no format hint, which CAF needs. And every byte is set here, so a file
/// of thirty seconds holds exactly thirty seconds. An ending can then be checked against an
/// exact number, not a tolerance.
enum SilentRecord {

    static let rate = 44_100
    static let channels = 2
    static let bytesPerFrame = 4                       // 16-bit stereo

    /// `seconds` of digital silence, as a WAV.
    static func of(seconds: Double) -> Data {
        let frames = Int(seconds * Double(rate))
        let audio = frames * bytesPerFrame

        var wav = Data(capacity: 44 + audio)

        func four(_ text: String) { wav.append(contentsOf: Array(text.utf8)) }
        func long(_ value: Int) { withUnsafeBytes(of: UInt32(value).littleEndian) { wav.append(contentsOf: $0) } }
        func short(_ value: Int) { withUnsafeBytes(of: UInt16(value).littleEndian) { wav.append(contentsOf: $0) } }

        four("RIFF"); long(36 + audio); four("WAVE")

        four("fmt "); long(16)
        short(1)                                       // LPCM
        short(channels)
        long(rate)
        long(rate * channels * 2)                      // bytes a second
        short(channels * 2)                            // bytes a frame
        short(16)                                      // bits a sample

        four("data"); long(audio)
        wav.append(Data(count: audio))                 // zeroed: silence

        return wav
    }

    /// A source the engine will take, holding `seconds` of silence.
    static func source(seconds: Double) throws -> StreamedPcm {
        let source = StreamedPcm()
        try source.take(of(seconds: seconds))
        source.finish(.theFileRanOut)
        return source
    }
}
