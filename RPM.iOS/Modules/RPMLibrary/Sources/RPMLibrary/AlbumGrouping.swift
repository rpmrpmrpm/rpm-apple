import Foundation
import RPMKit

/// What one album is, for cloud rows. This is the desktop's rule, ported.
///
/// The rule: **an album is a folder with tracks directly in it.** That is not a guess
/// about tags, it is the shape the library itself is filed in (Artist/Album/track), and
/// it is why the desktop gets the three cases a tag-based grouping cannot:
///
/// - a **compilation**, one record with a different artist on every track: the
///   album belongs to its album artist, and the track artists are the tracks';
/// - a **merged multi-disc set**, every disc in one folder with per-disc track
///   numbers, which is what the default filing mode writes: one record, two discs;
/// - a **deliberately separate** disc, given its own folder and its own decorated
///   name, which is meant to read as two records.
///
/// Grouping by track artist and album name would split the first into as many albums
/// as it has artists, and would not merge what the desktop merges.
public enum AlbumGrouping {
    /// The album a cloud row belongs to, as a key rows can be grouped on. Opaque:
    /// it is an identity to compare, not a name to show.
    public static func key(for track: CloudTrack) -> String {
        key(relativePath: track.relativePath,
            albumArtist: track.tags?.albumArtist,
            artist: track.artist,
            album: track.album)
    }

    public static func key(
        relativePath: String?, albumArtist: String?, artist: String?, album: String?
    ) -> String {
        // The folder wins wherever there is one: it is the desktop's own answer,
        // already decided by how the user's library is filed.
        if let folder = folder(of: relativePath) {
            return "folder:" + folder.lowercased()
        }

        // Tags, then. The album's artist is the album artist where the tag has
        // one. A present but BLANK tag is not an album artist, which is why this
        // is not a nil-coalesce.
        let owner = isBlank(albumArtist) ? artist : albumArtist
        let name = isBlank(album) ? "" : AlbumName.normalized(album!)

        return "tags:\(norm(owner))|\(norm(name))"
    }

    /// The library folder a row sits in: everything ahead of the file name,
    /// '/'-separated, and the empty string for a track loose at the library root,
    /// which is one album on the desktop's wall too. Nil only when the row carries
    /// no path, which is the one case the caller has to fall back on tags for.
    public static func folder(of relativePath: String?) -> String? {
        guard let relativePath, !isBlank(relativePath) else { return nil }

        // The library stores '/' whatever it was filed on; a Windows-shaped path
        // is normalised rather than treated as one long file name.
        var path = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("/") { path.removeFirst() }

        guard let cut = path.lastIndex(of: "/") else { return "" }
        return String(path[path.startIndex..<cut])
    }

    /// The album's name: what its files say it is, and failing that the folder's
    /// own name. The same two sources in the same order the desktop's card uses.
    public static func albumName(for tracks: [CloudTrack], folder: String?) -> String? {
        firstFilled(tracks.map(\.album)) ?? segment(folder, fromEnd: 0)
    }

    /// Whose album it is: the album artist, the track artist where no file carries
    /// one, and the folder's parent name where neither does. Artist/Album/track
    /// means the segment above the album is the artist.
    ///
    /// The album artist, not the track artist, is the point: on a compilation they
    /// are all different and only one of them names the record.
    public static func albumArtist(for tracks: [CloudTrack], folder: String?) -> String? {
        firstFilled(tracks.map { $0.tags?.albumArtist })
            ?? firstFilled(tracks.map(\.artist))
            ?? segment(folder, fromEnd: 1)
    }

    /// Which disc of the set a row is on: untagged is disc 1, the same as an
    /// untagged file on the desktop. Zero here means "not known" and
    /// `AlbumTracklist` is what turns it into 1.
    public static func disc(of track: CloudTrack) -> UInt { position(track.tags?.discNumber) }

    /// Where on its disc a row sits. Zero means "not known", and those sort last.
    public static func track(of track: CloudTrack) -> UInt { position(track.tags?.trackNumber) }

    // ── plumbing ──

    private static func position(_ value: Int?) -> UInt {
        guard let value, value > 0 else { return 0 }
        return UInt(value)
    }

    /// One segment of a '/'-separated folder, counted from the end: 0 is the
    /// folder itself, 1 the one above it. Nil when the path does not go back that
    /// far.
    private static func segment(_ folder: String?, fromEnd: Int) -> String? {
        guard let folder, !isBlank(folder) else { return nil }
        let parts = folder.split(separator: "/").map(String.init)
        guard parts.count > fromEnd else { return nil }
        return parts[parts.count - 1 - fromEnd]
    }

    private static func firstFilled(_ values: [String?]) -> String? {
        values.compactMap { $0 }
            .first { !isBlank($0) }?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func norm(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func isBlank(_ value: String?) -> Bool {
        guard let value else { return true }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Album names as the library compares them.
enum AlbumName {
    /// Strips the per-disc decorations that ripping tools often add ("Album - CD 1",
    /// "Album (Disc 2)"), so multi-disc sets group as ONE album rather than one
    /// per disc.
    ///
    /// A name that is nothing BUT a decoration keeps itself: an album genuinely
    /// called "Disc 2" would otherwise normalise to the empty string and join
    /// every other untitled record.
    static func normalized(_ album: String) -> String {
        let trimmed = album.trimmingCharacters(in: .whitespacesAndNewlines)

        // Not a throwing call, whatever the shape of the rest of NSRegularExpression
        // suggests: only building the pattern can fail, and that is done once below.
        let stripped = discSuffix.stringByReplacingMatches(
            in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed), withTemplate: "")

        let result = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? trimmed : result
    }

    // The desktop's own pattern, character for character.
    private static let discSuffix = try! NSRegularExpression(
        pattern: #"[\s\-–—_:,]*[\(\[]?\s*(cd|disc|disk)\s*[-_ ]?\d+\s*[\)\]]?$"#,
        options: [.caseInsensitive])
}
