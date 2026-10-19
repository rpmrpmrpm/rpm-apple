import Foundation

/// RPM's shared entry for one record.
///
/// The id is minted server-side from what the tags say, so an album has to be
/// resolved before anything else can be asked about it. A client that already
/// holds an id skips straight to the reviews.
public struct RPMAlbum: Codable, Hashable, Sendable, Identifiable {
    public let albumId: String
    public let artist: String
    public let title: String
    public let year: Int
    public let catno: String?
    public let discogsReleaseId: String?
    public let reviewCount: Int
    public let commentCount: Int
    public let averageRating: Double
    public let ratingCount: Int
    public let musicBrainzReleaseId: String?
    public let barcode: String?

    /// Every pressing of one album shares this, which is what "read what people
    /// wrote about every pressing" is asked with.
    public let groupId: String?

    public var id: String { albumId }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albumId              = try c.decode(String.self, forKey: .albumId)
        artist               = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        title                = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        year                 = try c.decodeIfPresent(Int.self, forKey: .year) ?? 0
        catno                = try c.decodeIfPresent(String.self, forKey: .catno)
        discogsReleaseId     = try c.decodeIfPresent(String.self, forKey: .discogsReleaseId)
        reviewCount          = try c.decodeIfPresent(Int.self, forKey: .reviewCount) ?? 0
        commentCount         = try c.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        averageRating        = try c.decodeIfPresent(Double.self, forKey: .averageRating) ?? 0
        ratingCount          = try c.decodeIfPresent(Int.self, forKey: .ratingCount) ?? 0
        musicBrainzReleaseId = try c.decodeIfPresent(String.self, forKey: .musicBrainzReleaseId)
        barcode              = try c.decodeIfPresent(String.self, forKey: .barcode)
        groupId              = try c.decodeIfPresent(String.self, forKey: .groupId)
    }
}

/// One catalogue id an album answers to.
public struct RPMAlbumAlias: Codable, Hashable, Sendable {
    public let namespace: String
    public let value: String
    public let createdAt: Int64
}

/// What somebody wrote about a record.
public struct RPMReview: Codable, Hashable, Sendable {
    public let albumId: String
    public let userId: String
    public let authorName: String
    public let hasAvatar: Bool

    /// Halves of a star, doubled: 1 to 10.
    public let rating: Int

    public let body: String
    public let createdAt: Int64
    public let updatedAt: Int64
    public let ups: Int
    public let downs: Int
    public let score: Int

    /// This reader's own vote: 1 up, -1 down, 0 none.
    public let myVote: Int

    /// The author's account was deleted: the name is empty and ``authorShown`` says
    /// "Deleted user". False when the server does not send the field.
    public let authorDeleted: Bool

    /// The name to draw.
    public var authorShown: String { authorDeleted ? Loc.get("Community_DeletedUser") : authorName }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albumId    = try c.decodeIfPresent(String.self, forKey: .albumId) ?? ""
        userId     = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        hasAvatar  = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        rating     = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        body       = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt  = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        updatedAt  = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
        ups        = try c.decodeIfPresent(Int.self, forKey: .ups) ?? 0
        downs      = try c.decodeIfPresent(Int.self, forKey: .downs) ?? 0
        score      = try c.decodeIfPresent(Int.self, forKey: .score) ?? 0
        myVote     = try c.decodeIfPresent(Int.self, forKey: .myVote) ?? 0
        authorDeleted = try c.decodeIfPresent(Bool.self, forKey: .authorDeleted) ?? false
    }
}

public struct RPMReviewPage: Codable, Sendable {
    public let items: [RPMReview]
    public let page: Int
    public let pageSize: Int
    public let total: Int
    public let sort: String

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items    = try c.decodeIfPresent([RPMReview].self, forKey: .items) ?? []
        page     = try c.decodeIfPresent(Int.self, forKey: .page) ?? 0
        pageSize = try c.decodeIfPresent(Int.self, forKey: .pageSize) ?? 0
        total    = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        sort     = try c.decodeIfPresent(String.self, forKey: .sort) ?? ""
    }
}

public struct RPMComment: Codable, Hashable, Sendable, Identifiable {
    public let albumId: String
    public let commentId: String
    public let userId: String
    public let authorName: String
    public let hasAvatar: Bool
    public let body: String
    public let createdAt: Int64

    /// As on ``RPMReview/authorDeleted``.
    public let authorDeleted: Bool

    /// The name to draw.
    public var authorShown: String { authorDeleted ? Loc.get("Community_DeletedUser") : authorName }

    public var id: String { commentId }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albumId    = try c.decodeIfPresent(String.self, forKey: .albumId) ?? ""
        commentId  = try c.decode(String.self, forKey: .commentId)
        userId     = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        hasAvatar  = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        body       = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt  = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        authorDeleted = try c.decodeIfPresent(Bool.self, forKey: .authorDeleted) ?? false
    }
}

public struct RPMProfile: Codable, Hashable, Sendable {
    public let userId: String
    public let displayName: String
    public let hasAvatar: Bool
    public let avatarUpdatedAt: Int64

    /// MILLISECONDS, not seconds. The rest of this API stamps in unix seconds
    /// and this one field does not: a fresh account reads 1787870345843.
    /// Treating it as seconds dates every profile to the year 58,600.
    public let createdAt: Int64

    /// Whether this person supports rpm, for the mark beside their name.
    /// Defaults to false, so a profile without the field reports nobody and does
    /// not fail to parse. The server omits it entirely on a fresh profile.
    public let supporter: Bool

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId          = try c.decode(String.self, forKey: .userId)
        displayName     = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        hasAvatar       = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        avatarUpdatedAt = try c.decodeIfPresent(Int64.self, forKey: .avatarUpdatedAt) ?? 0
        createdAt       = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        supporter       = try c.decodeIfPresent(Bool.self, forKey: .supporter) ?? false
    }
}

/// How a review list is ordered. The values are the sort tabs on the album page.
public enum RPMReviewSort: String, Sendable, CaseIterable {
    case votes, date, length, positive, negative
}

/// `cloud/devices` answers `{"devices":[...]}`, not a bare array.
struct DevicesResponse: Decodable {
    let devices: [CloudDevice]?
}
