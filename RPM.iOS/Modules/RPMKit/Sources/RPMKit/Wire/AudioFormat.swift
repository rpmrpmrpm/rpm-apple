import Foundation

/// What a file **is**, in the short form that a record sleeve prints: "FLAC", "24/96", "5.1".
///
/// Two facts, and they are not the same kind of fact. The codec is mostly the
/// extension: a `.flac` is a FLAC and nothing else. There is one real exception:
/// `.m4a` carries either AAC or Apple Lossless, and calling a lossless file "AAC"
/// is wrong. So the codec is decided from the extension **and** from what the
/// decoder said is actually inside, and only the second can tell those two apart.
///
/// The channel count is written as the layout people say (5.1, not "six
/// channels"), and **stereo is omitted**, because a line that says "stereo" on every
/// record says nothing about any of them.
public enum AudioFormat {
    /// The short label for a file, or nil where the extension is not one this knows.
    ///
    /// - Parameters:
    ///   - extension: lower-case and dot-prefixed, as the catalogue holds it.
    ///   - description: what the decoder said the stream is. Consulted only where
    ///     the extension is genuinely ambiguous.
    public static func codec(extension file: String?, description: String? = nil) -> String? {
        let trimmed = (file ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let ext = trimmed.hasPrefix(".") ? trimmed : "." + trimmed

        // The MPEG-4 family is ambiguous in both directions: .m4a is AAC unless it is
        // Apple Lossless, and .mp4 is usually AAC. The decoder names the codec in its
        // description, so the word is what decides.
        if [".m4a", ".m4b", ".mp4", ".aac"].contains(ext) {
            if let said = description, !said.isEmpty {
                if says(said, "alac", "apple lossless") { return "ALAC" }
                // Checked before plain AC-3 because "eac3" contains "ac3", and
                // checked at all because "AAC" is the one thing it certainly is not.
                if says(said, "eac3", "e-ac-3", "ec-3") { return "Dolby Digital Plus" }
                if says(said, "ac3", "ac-3") { return "Dolby Digital" }
            }
            return "AAC"
        }

        switch ext {
        case ".flac": return "FLAC"
        case ".mp3": return "MP3"
        case ".wav": return "WAV"
        case ".aif", ".aiff", ".aifc": return "AIFF"
        case ".ogg", ".oga": return "OGG"
        case ".opus": return "Opus"
        case ".wma": return "WMA"
        case ".ape": return "APE"
        case ".wv": return "WavPack"
        case ".mpc": return "Musepack"
        case ".dsf", ".dff": return "DSD"
        case ".alac": return "ALAC"
        default: return nil
        }
    }

    /// The channel layout as a record sleeve prints it, or nil where there is nothing
    /// worth saying.
    ///
    /// Nil for stereo, which is what almost everything is: a badge that every record
    /// has is not useful. Nil also for a count that has no common name, and no
    /// name is invented.
    public static func channels(_ count: Int) -> String? {
        switch count {
        case 1: return Loc.get("Track_Mono")
        case 3: return "2.1"
        case 4: return "4.0"
        case 5: return "5.0"
        case 6: return "5.1"
        case 7: return "6.1"
        case 8: return "7.1"
        case 10: return "9.1"
        case 12: return "7.1.4"   // Atmos beds arrive as twelve discrete channels
        default: return nil
        }
    }

    /// How good the encode is, asked in the way each kind of format can answer.
    ///
    /// A lossless file is judged by its **resolution**: "24/96" means twenty-four
    /// bits at ninety-six kilohertz, and its bitrate follows from the music and is
    /// not a choice anybody made. A lossy file is the other way round: its bit depth
    /// means nothing and the bitrate is the whole decision.
    public static func quality(codec: String?, bitsPerSample: Int, sampleRate: Int,
                               bitrateKbps: Int) -> String? {
        guard isLossless(codec) else {
            return bitrateKbps > 0 ? "\(bitrateKbps) kbps" : nil
        }

        guard bitsPerSample > 0, sampleRate > 0 else {
            // No depth to report. The codec's name already said the useful part, so
            // return nil and not a bitrate nobody chose.
            return nil
        }

        let khz = Double(sampleRate) / 1000
        // 44.1 keeps its decimal; 48 and 96 do not grow one.
        let said = abs(khz - khz.rounded()) < 0.05
            ? String(format: "%.0f", khz.rounded())
            : String(format: "%.1f", khz)

        return "\(bitsPerSample)/\(said)"
    }

    /// Everything worth saying, in display order, dropping whatever is unknown.
    public static func describe(extension file: String?, channels count: Int,
                                description: String? = nil, bitsPerSample: Int = 0,
                                sampleRate: Int = 0, bitrateKbps: Int = 0) -> [String] {
        var parts: [String] = []

        let name = codec(extension: file, description: description)
        if let name { parts.append(name) }
        if let good = quality(codec: name, bitsPerSample: bitsPerSample,
                              sampleRate: sampleRate, bitrateKbps: bitrateKbps) {
            parts.append(good)
        }
        if let layout = channels(count) { parts.append(layout) }

        return parts
    }

    /// Which codecs keep every sample. Decides how a file's quality is stated.
    private static func isLossless(_ codec: String?) -> Bool {
        ["FLAC", "ALAC", "WAV", "AIFF", "APE", "WavPack", "DSD"].contains(codec ?? "")
    }

    private static func says(_ description: String, _ words: String...) -> Bool {
        words.contains { description.range(of: $0, options: .caseInsensitive) != nil }
    }
}

extension CloudTrackTags {
    /// What a record sleeve would print about this file: "FLAC", "16/44.1", "5.1", leaving out
    /// whatever is unknown, and empty where the row has no format at all.
    public var format: [String] {
        guard hasFormat else { return [] }
        return AudioFormat.describe(
            extension: `extension`, channels: channels, description: codecDescription,
            bitsPerSample: bitsPerSample, sampleRate: sampleRate, bitrateKbps: bitrateKbps)
    }
}
