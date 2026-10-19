import Foundation

/// A track's full tag surface and the cover embedded in the user's own file.
///
/// **PascalCase, unlike everything else here.** The sidecar is a blob the
/// uploader wrote and the store hands back untouched, not a Lambda response, so
/// it carries .NET property names rather than the API's camelCase. Decoding it
/// with the shared coder and no keys would silently produce an empty sidecar and
/// a phone with no fallback artwork.
///
/// Only the fields a client reads are here. The blob carries thirty more, and a
/// Swift mirror of all of them would be thirty more places to drift for no
/// reader. `Codable` ignores what it is not asked for.
public struct TagSidecar: Codable, Sendable {
    /// Where the file belongs under the library root, forward slashes.
    public let relativePath: String

    /// Lower-case extension including the dot. Says which container the blob is.
    public let `extension`: String

    public let rpmId: String?
    public let durationSeconds: Double
    public let title: String?
    public let artist: String?
    public let albumArtist: String?
    public let album: String?
    public let genre: String?
    public let trackNumber: Int
    public let trackCount: Int
    public let discNumber: Int
    public let discCount: Int

    /// The picture inside the user's own file. Base64 in the JSON, so a sidecar
    /// is as big as the cover in it: callers cache what they fetch rather than
    /// asking twice.
    public let art: Data?
    public let artMime: String?

    enum CodingKeys: String, CodingKey {
        case relativePath = "RelativePath"
        case `extension` = "Extension"
        case rpmId = "RpmId"
        case durationSeconds = "DurationSeconds"
        case title = "Title"
        case artist = "Artist"
        case albumArtist = "AlbumArtist"
        case album = "Album"
        case genre = "Genre"
        case trackNumber = "TrackNumber"
        case trackCount = "TrackCount"
        case discNumber = "DiscNumber"
        case discCount = "DiscCount"
        case art = "Art"
        case artMime = "ArtMime"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        relativePath    = try c.decodeIfPresent(String.self, forKey: .relativePath) ?? ""
        `extension`     = try c.decodeIfPresent(String.self, forKey: .extension) ?? ""
        rpmId           = try c.decodeIfPresent(String.self, forKey: .rpmId)
        durationSeconds = try c.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 0
        title           = try c.decodeIfPresent(String.self, forKey: .title)
        artist          = try c.decodeIfPresent(String.self, forKey: .artist)
        albumArtist     = try c.decodeIfPresent(String.self, forKey: .albumArtist)
        album           = try c.decodeIfPresent(String.self, forKey: .album)
        genre           = try c.decodeIfPresent(String.self, forKey: .genre)
        trackNumber     = try c.decodeIfPresent(Int.self, forKey: .trackNumber) ?? 0
        trackCount      = try c.decodeIfPresent(Int.self, forKey: .trackCount) ?? 0
        discNumber      = try c.decodeIfPresent(Int.self, forKey: .discNumber) ?? 0
        discCount       = try c.decodeIfPresent(Int.self, forKey: .discCount) ?? 0
        art             = try c.decodeIfPresent(Data.self, forKey: .art)
        artMime         = try c.decodeIfPresent(String.self, forKey: .artMime)
    }
}

/// One track's opening seconds, for a wall that plays a short preview
/// before anything is streamed.
struct HeadClipsResponse: Decodable {
    let clips: [HeadClip]?

    struct HeadClip: Decodable {
        let rpmId: String
        /// Base64 in the JSON. Absent on a track whose clip has not been made.
        let audio: Data?
    }
}

/// The answer to a request to make renditions: `cloud/transcode`.
struct TranscodeResponse: Decodable {
    let kilobits: Int?
    let ready: Int?
    let queued: Int?
}

/// A signed URL, and what the store is actually serving at it.
struct UrlResponse: Decodable {
    let url: String
    let kilobits: Int?

    /// Whether this address is a rendition being encoded as it is sent and not an
    /// object. Absent from stores without the live path, and absent from every answer
    /// that is an object, so nil reads as `.stored`.
    let live: Bool?
}
