import Foundation

/// The 44 bytes at the start of a WAV file.
///
/// **For a stream with no end**, which is what casting is. The sizes in a RIFF header give the length of the file.
/// A cast has no length, so the sizes are set to the largest value that the fields can hold. Endless WAV streams
/// are usually written this way. The Default Media Receiver expects it. It reads the format, starts playing, and never
/// reaches the end that the header declares.
public enum WavHeader {
    /// Linear PCM. The receiver decodes it without asking for more data. It is also the format that the engine
    /// already produces.
    private static let pcm: UInt16 = 1

    public static func of(rate: Int = 44100, channels: Int = 2, bits: Int = 16) -> Data {
        let blockAlign = channels * bits / 8
        let byteRate = rate * blockAlign

        // Not `.max`. A receiver that reads the size as signed sees a negative length, and it refuses the stream.
        // This value is the largest that a signed 32-bit reader can hold, less the header. At 44.1 kHz stereo,
        // that is about 3.4 hours of audio.
        let endless = UInt32(Int32.max) - 44

        var out = Data()
        out.append(contentsOf: Array("RIFF".utf8))
        out.append(little: endless + 36)
        out.append(contentsOf: Array("WAVE".utf8))

        out.append(contentsOf: Array("fmt ".utf8))
        out.append(little: UInt32(16))
        out.append(little: pcm)
        out.append(little: UInt16(channels))
        out.append(little: UInt32(rate))
        out.append(little: UInt32(byteRate))
        out.append(little: UInt16(blockAlign))
        out.append(little: UInt16(bits))

        out.append(contentsOf: Array("data".utf8))
        out.append(little: endless)

        return out
    }
}

extension Data {
    fileprivate mutating func append(little value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func append(little value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
