import Foundation

/// Which album has a cover in the store, and which version of it.
///
/// Not a wire type: the store answers `cloud/art` with two different shapes and
/// this is the one answer both collapse to. See `AlbumArtIndex.covers`.
public struct StoredCover: Hashable, Sendable {
    public let albumKey: String

    /// The store's stamp for this cover. Every cover cache is keyed on it: a
    /// person can replace a cover, and a client with the old one cached has
    /// nothing else to tell them apart. Zero means the server did not say, which
    /// reads as "no version known" and not as "new".
    public let updatedAt: Int64

    public let url: String?

    public init(albumKey: String, updatedAt: Int64 = 0, url: String? = nil) {
        self.albumKey = albumKey; self.updatedAt = updatedAt; self.url = url
    }
}

/// What `cloud/art` actually sends.
///
/// Two shapes, because an older API answers with bare keys and no stamps.
/// Both fields are optional and exactly one of them arrives. A client that
/// read only `albums` would draw no covers at all against an older store,
/// which is a worse failure than drawing stale ones.
public struct AlbumArtIndex: Codable, Sendable {
    public let albumKeys: [String]?
    public let albums: [AlbumArtIndexEntry]?

    /// The stamped list where the server sends one, and the bare keys where it
    /// does not. Read the index through this and the two shapes stop existing
    /// above this line.
    public var covers: [StoredCover] {
        if let albums, !albums.isEmpty {
            return albums.map { StoredCover(albumKey: $0.albumKey, updatedAt: $0.updatedAt) }
        }
        return (albumKeys ?? []).map { StoredCover(albumKey: $0, updatedAt: 0) }
    }
}

public struct AlbumArtIndexEntry: Codable, Sendable {
    public let albumKey: String
    public let updatedAt: Int64

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albumKey  = try c.decode(String.self, forKey: .albumKey)
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }
}

/// Which picture of a stored cover to ask `cloud/art/{albumKey}` for.
///
/// Stated at every call, with no default: the original is many times the bytes of a copy, and a
/// copy is a JPEG laid on black, which loses a disc label's transparent corners.
public enum CoverSize: Hashable, Sendable {
    /// The file the desktop uploaded, at its own size and in its own format.
    case original

    /// A copy the API cuts so its longer side is this many pixels. The API rounds the number up to
    /// 256, 512 or 1024 (`CoverSizes.Edges`) and serves the original past 1024, for an original no
    /// larger than the copy, and when a copy cannot be made. A copy is a JPEG with any transparency
    /// laid on black. An API that makes no copies ignores `size` and serves the original.
    case edge(Int)

    /// The query parameter that asks for this picture, or nil for the original.
    var parameter: String? {
        switch self {
        case .original: return nil
        case .edge(let pixels): return "size=\(pixels)"
        }
    }
}

/// One album's cover, signed.
public struct AlbumArtUrlResponse: Codable, Sendable {
    public let url: String
    public let updatedAt: Int64

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url       = try c.decode(String.self, forKey: .url)
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }
}
