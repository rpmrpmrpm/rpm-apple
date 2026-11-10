import Foundation

/// Which audio files this device decodes as they are, without a copy made by the cloud.
///
/// The iPhone and the Apple TV decode with Core Audio's stream parser (`AudioFileStream`, in
/// `StreamedPcm`) and its converters. iOS and tvOS have no Ogg container and no Vorbis decoder,
/// and they do not read WMA, APE, WavPack, Musepack or DSD files either. Those files play only
/// from the cloud's AAC copy. AC-3 and E-AC-3 inside an MPEG-4 file are refused too, because the
/// converter does not decode them.
///
/// It is a list of what plays and not of what does not. A format that is not on it is played from
/// the AAC copy, and the AAC copy always plays.
public enum PlaysHere {
    /// File types Core Audio's stream parser reads: lower case, without the dot.
    public static let containers: Set<String> = ["flac", "mp3", "m4a", "m4b", "mp4", "aac", "wav",
                                                 "aif", "aiff"]

    /// Whether this device decodes a file with this extension and this codec.
    ///
    /// - Parameters:
    ///   - extension: the file's extension, with or without the dot, in any case. Nil when it is
    ///     not known, and then the answer is no.
    ///   - codec: what the tag reader said the stream is, for example "MPEG-4 Audio (ec-3)". Nil
    ///     when it is not known.
    public static func decodes(extension file: String?, codec: String?) -> Bool {
        var ext = (file ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if ext.hasPrefix(".") { ext.removeFirst() }
        guard containers.contains(ext) else { return false }

        let said = (codec ?? "").lowercased()
        return !["ac-3", "ac3", "ec-3", "eac3"].contains { said.contains($0) }
    }

    /// Whether this device decodes a cloud track's original file. The extension is the
    /// catalogue's, or the one in the file's path when the catalogue has none.
    public static func decodes(_ track: CloudTrack) -> Bool {
        let catalogued = track.tags?.extension.flatMap { $0.isEmpty ? nil : $0 }
        let fromPath = track.relativePath.map { ($0 as NSString).pathExtension }
        return decodes(extension: catalogued ?? fromPath, codec: track.tags?.codecDescription)
    }
}
