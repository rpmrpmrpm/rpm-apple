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
        return !dolby.contains { said.contains($0) }
    }

    /// Words in a codec text that name AC-3 or E-AC-3. Tag readers name them in several ways:
    /// "MPEG-4 Audio (ec-3)", "E-AC-3", "Dolby Digital Plus", "Enhanced AC-3", "ATSC A/52".
    static let dolby = ["ac-3", "ac3", "ac 3", "ec-3", "eac3", "dolby", "enhanced ac", "a/52", "a52"]

    /// Whether this device decodes a cloud track's original file. The extension is the
    /// catalogue's, or the one in the file's path when the catalogue has none.
    ///
    /// It reads only the catalogue. A track that this device has already found it cannot decode
    /// is in ``FoundUndecodable``, which ``AudioLadder/asked(_:for:found:)`` reads as well.
    public static func decodes(_ track: CloudTrack) -> Bool {
        let catalogued = track.tags?.extension.flatMap { $0.isEmpty ? nil : $0 }
        let fromPath = track.relativePath.map { ($0 as NSString).pathExtension }
        return decodes(extension: catalogued ?? fromPath, codec: track.tags?.codecDescription)
    }
}

/// Tracks whose original file this device was given and could not decode, by `rpmId`, for as
/// long as the app runs.
///
/// ``PlaysHere`` decides from the catalogue, and the catalogue can be silent or wrong. A track
/// uploaded before its codec was recorded has no codec text, so an E-AC-3 file in an `.m4a`
/// looks like AAC, and its original is asked for. The decoder (`StreamedPcm`) finds out from the
/// bytes, and a download finds out from the file. Both note the track here. Then
/// ``AudioLadder/asked(_:for:found:)`` asks for the AAC copy of it, so every later request for
/// that track (a play, the look-ahead, a download) asks for the copy at once.
///
/// It is kept in memory only. After the app starts again, the first play of the track finds out
/// again, which costs one short request.
public final class FoundUndecodable: @unchecked Sendable {
    /// The one list the app uses. Tests make their own.
    public static let shared = FoundUndecodable()

    private let gate = NSLock()
    private var found: Set<String> = []

    public init() {}

    /// Notes that this device cannot decode the original of `rpmId`. Returns whether it was not
    /// noted before.
    @discardableResult
    public func note(_ rpmId: String) -> Bool {
        guard !rpmId.isEmpty else { return false }
        return gate.withLock { found.insert(rpmId).inserted }
    }

    /// Whether this device has found that it cannot decode the original of `rpmId`.
    public func contains(_ rpmId: String) -> Bool {
        gate.withLock { found.contains(rpmId) }
    }
}
