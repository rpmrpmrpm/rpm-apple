import Foundation

/// RPM's shared entry for one artist: the id of their wall, and the name RPM keeps for them.
///
/// The entry is created by the first person who writes on the wall, not by reading it. So most
/// artists have no entry, and an artist page usually reads an empty wall.
public struct RPMArtist: Codable, Hashable, Sendable, Identifiable {
    public let artistId: String
    public let name: String

    /// MILLISECONDS since 1970, like every stamp on the community routes.
    public let createdAt: Int64

    public var id: String { artistId }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artistId  = try c.decode(String.self, forKey: .artistId)
        name      = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        createdAt = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    }
}

/// One line on an artist's wall: something a listener wrote, or a line the server wrote when a
/// listener reviewed or rated one of the artist's records.
///
/// Read the kind through ``isPost`` and ``isReview``. A kind that a newer server sends and this build
/// does not know is neither, so it is not drawn as a post with no words.
public struct RPMWallEntry: Codable, Hashable, Sendable, Identifiable {
    public let artistId: String
    public let entryId: String

    /// "post" or "review".
    public let kind: String
    public let userId: String
    public let authorName: String
    public let hasAvatar: Bool

    /// What a listener wrote, on a post. Empty on a review line: the album page is where the review
    /// itself is read.
    public let body: String

    /// MILLISECONDS since 1970.
    public let createdAt: Int64

    /// The record a review line is about, as the album entry spells it. Nil on a post.
    public let albumId: String?
    public let albumTitle: String?

    /// Halves of a star, doubled: 1 to 10. Zero on a post.
    public let rating: Int

    /// Whether the review behind a review line has words in it. It decides between "wrote a review"
    /// and "rated".
    public let hasBody: Bool

    /// As on ``RPMReview/authorDeleted``.
    public let authorDeleted: Bool

    public var id: String { entryId }

    public var isPost: Bool { kind.caseInsensitiveCompare("post") == .orderedSame }

    public var isReview: Bool { kind.caseInsensitiveCompare("review") == .orderedSame }

    /// The name to draw.
    public var authorShown: String { authorDeleted ? Loc.get("Community_DeletedUser") : authorName }

    /// The rating in stars, halves included. Zero on a post.
    public var stars: Double { Double(rating) / 2 }

    public var written: Date { Date(timeIntervalSince1970: Double(createdAt) / 1000) }

    /// The string key of a review line's sentence, or nil for a post, whose line is the author's own
    /// words. It is kept apart from ``line`` so a test can read it without the string table.
    public var lineKey: String? {
        guard isReview else { return nil }
        return hasBody ? "Artists_WallWroteReview" : "Artists_WallRated"
    }

    /// What the line says: a post's words, or a sentence about the review with the record's title
    /// in it.
    public var line: String {
        guard let lineKey else { return body }
        return Loc.get(lineKey, albumTitle ?? "")
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artistId      = try c.decodeIfPresent(String.self, forKey: .artistId) ?? ""
        entryId       = try c.decode(String.self, forKey: .entryId)
        kind          = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        userId        = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        authorName    = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        hasAvatar     = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        body          = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt     = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        albumId       = try c.decodeIfPresent(String.self, forKey: .albumId)
        albumTitle    = try c.decodeIfPresent(String.self, forKey: .albumTitle)
        rating        = try c.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        hasBody       = try c.decodeIfPresent(Bool.self, forKey: .hasBody) ?? false
        authorDeleted = try c.decodeIfPresent(Bool.self, forKey: .authorDeleted) ?? false
    }
}

/// What a report is about. Each case carries what the server needs to open the report: the album
/// for the three things on an album page, the artist for a line on an artist's wall. The server
/// refuses a report without them, so the type does not allow one.
public enum RPMReportTarget: Sendable, Equatable {
    case album(albumId: String)
    case review(albumId: String, authorId: String)
    case comment(albumId: String, commentId: String)
    case wallPost(artistId: String, entryId: String)
}
