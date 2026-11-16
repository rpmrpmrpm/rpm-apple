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

    /// The author supports rpm: their name is drawn in gold. False when the server does not send the field.
    public let authorSupporter: Bool

    /// The name to draw.
    public var authorShown: String { authorDeleted ? Loc.get("Community_DeletedUser") : authorName }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        authorSupporter = try c.decodeIfPresent(Bool.self, forKey: .authorSupporter) ?? false
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

    // The fields below belong to the profile page. Every one is optional on the wire, so a profile
    // from a server without the page still reads, and shows no banner, no song and no counts.

    public let hasBanner: Bool
    public let bannerUpdatedAt: Int64

    /// What this person is playing now. Nil when nothing is, when it is older than the server's
    /// limit, or when they have turned sharing off.
    public private(set) var listening: RPMListening?

    /// How many albums and tracks are in their collection, as their app last reported.
    public private(set) var counts: RPMCounts?

    /// Where the caller stands with this person.
    public let friendship: RPMFriendship

    /// The caller has blocked this person.
    public let blocked: Bool

    /// Whether the person shares what they are listening to. Only the caller's own profile
    /// (`GET profile`) carries it; on anyone else's it reads true.
    public let sharesListening: Bool

    /// What the owner's page is drawn on, as the server stores it. See ``RPMPageGround``.
    public private(set) var pageGround: String

    /// Where the banner comes from: `photo` (the banner photo, or none) or `listening` (a photo of the artist the
    /// owner is playing). Empty reads as `photo`.
    public private(set) var bannerSource: String

    /// The badges unlocked, by id, oldest first. See ``RPMProfileBadges``.
    public private(set) var badges: [String]

    /// The badge shown under the name, or empty.
    public private(set) var badge: String

    /// The badge's colour, `#RRGGBB`, or empty for the first of ``RPMProfileBadges/colours``.
    public private(set) var badgeColour: String

    /// Whether the banner is a photo of the artist the owner is playing.
    public var bannerFollowsListening: Bool { bannerSource == "listening" }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId          = try c.decode(String.self, forKey: .userId)
        displayName     = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        hasAvatar       = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        avatarUpdatedAt = try c.decodeIfPresent(Int64.self, forKey: .avatarUpdatedAt) ?? 0
        createdAt       = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        supporter       = try c.decodeIfPresent(Bool.self, forKey: .supporter) ?? false
        hasBanner       = try c.decodeIfPresent(Bool.self, forKey: .hasBanner) ?? false
        bannerUpdatedAt = try c.decodeIfPresent(Int64.self, forKey: .bannerUpdatedAt) ?? 0
        listening       = try c.decodeIfPresent(RPMListening.self, forKey: .listening)
        counts          = try c.decodeIfPresent(RPMCounts.self, forKey: .counts)
        friendship      = try c.decodeIfPresent(RPMFriendship.self, forKey: .friendship) ?? .none
        blocked         = try c.decodeIfPresent(Bool.self, forKey: .blocked) ?? false
        sharesListening = try c.decodeIfPresent(Bool.self, forKey: .sharesListening) ?? true
        pageGround      = try c.decodeIfPresent(String.self, forKey: .pageGround) ?? ""
        bannerSource    = try c.decodeIfPresent(String.self, forKey: .bannerSource) ?? ""
        badges          = try c.decodeIfPresent([String].self, forKey: .badges) ?? []
        badge           = try c.decodeIfPresent(String.self, forKey: .badge) ?? ""
        badgeColour     = try c.decodeIfPresent(String.self, forKey: .badgeColour) ?? ""
    }

    /// The same profile with the page's look changed: what the sample page keeps, as the server cannot. A nil
    /// value keeps what there is.
    public func with(pageGround: String? = nil, bannerSource: String? = nil, badges: [String]? = nil,
                     badge: String? = nil, badgeColour: String? = nil) -> RPMProfile {
        var copy = self
        if let pageGround { copy.pageGround = pageGround }
        if let bannerSource { copy.bannerSource = bannerSource }
        if let badges { copy.badges = badges }
        if let badge { copy.badge = badge }
        if let badgeColour { copy.badgeColour = badgeColour }
        return copy
    }

    /// The same profile with the sample's counts and song where it has none of its own. See ``RPMProfileSample``.
    public func filled(from sample: RPMProfileSample) -> RPMProfile {
        var copy = self
        if copy.counts == nil { copy.counts = sample.counts }
        if copy.listening == nil { copy.listening = sample.listening }
        if copy.badge.isEmpty { copy.badge = sample.badge }
        if copy.badgeColour.isEmpty { copy.badgeColour = sample.badgeColour }
        return copy
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
