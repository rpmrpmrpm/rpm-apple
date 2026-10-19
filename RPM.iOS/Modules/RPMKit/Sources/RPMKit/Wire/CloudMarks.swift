import Foundation

/// One record's mark as the store holds it.
public struct CloudAlbumMark: Codable, Hashable, Sendable {
    /// The album hash the desktop stores the record's cover under:
    /// `AlbumArtKey.of(.cover, ...)`, 32 hex characters. The store refuses any
    /// other shape, including `CloudAlbum.key`, which is the wall's own grouping.
    public let albumKey: String
    public let favorite: Bool

    /// When it was marked, in UTC ticks and not unix seconds. The store keeps
    /// what the desktop sends, and the desktop sends .NET ticks, so this is not
    /// the same unit as `updatedAt` beside it. Do not compare the two.
    public let favoritedAt: Int64

    /// The store's own stamp, in unix seconds. Compared against the value this
    /// machine last accepted, server clock against server clock, so whose mark
    /// is newer never depends on two computers agreeing about the time.
    public let updatedAt: Int64

    /// Whether the record is classical, as the listener marked it in the desktop's
    /// album editor. A classical record's tracklist is drawn as works with their
    /// movements under them. Nil when no computer has said, and when the server does
    /// not send the field; both draw an ordinary tracklist.
    public let classical: Bool?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albumKey    = try c.decode(String.self, forKey: .albumKey)
        favorite    = try c.decodeIfPresent(Bool.self, forKey: .favorite) ?? false
        favoritedAt = try c.decodeIfPresent(Int64.self, forKey: .favoritedAt) ?? 0
        updatedAt   = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
        classical   = try c.decodeIfPresent(Bool.self, forKey: .classical)
    }

    public init(albumKey: String, favorite: Bool, favoritedAt: Int64 = 0, updatedAt: Int64 = 0,
                classical: Bool? = nil) {
        self.albumKey = albumKey; self.favorite = favorite
        self.favoritedAt = favoritedAt; self.updatedAt = updatedAt
        self.classical = classical
    }
}

/// Every record this user has marked, in one call. A client with two thousand
/// albums must not ask two thousand times which eleven of them are favourites.
public struct CloudAlbumMarksResponse: Codable, Sendable {
    public let albums: [CloudAlbumMark]

    /// Whose marks these are. Nil when the server does not send the field. A read of
    /// another account's marks checks it, because a server that does not know `?owner=`
    /// answers with the caller's own marks and a 200.
    public let owner: String?
}

/// What a mark write answers with: the store's new stamp for that row.
public struct CloudAlbumMarkStamp: Codable, Sendable {
    public let updatedAt: Int64
}
