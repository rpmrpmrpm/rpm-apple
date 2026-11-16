import Foundation

// The profile page's wire types: what a person is playing, their posts and the replies under them,
// friends, and notifications. Times are Unix MILLISECONDS, as everywhere in the community API.
//
// Every field that is not an id is read with a default, as the other community types are, so a
// field that a server leaves out does not stop a whole page from reading.

/// A song, as a post carries it and as "listening to" shows it.
public struct RPMSong: Codable, Hashable, Sendable {
    public let artist: String
    public let title: String
    public let album: String

    /// The album's RPM id, when the playing app knew it. The page opens the album with it.
    public let albumId: String?

    public init(artist: String, title: String, album: String, albumId: String?) {
        self.artist = artist
        self.title = title
        self.album = album
        self.albumId = albumId
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist  = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        title   = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        album   = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
        albumId = try c.decodeIfPresent(String.self, forKey: .albumId)
    }
}

/// What a person is playing now, and since when.
public struct RPMListening: Codable, Hashable, Sendable {
    public let artist: String
    public let title: String
    public let album: String
    public let albumId: String?
    public let at: Int64

    public var song: RPMSong { RPMSong(artist: artist, title: title, album: album, albumId: albumId) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artist  = try c.decodeIfPresent(String.self, forKey: .artist) ?? ""
        title   = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        album   = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
        albumId = try c.decodeIfPresent(String.self, forKey: .albumId)
        at      = try c.decodeIfPresent(Int64.self, forKey: .at) ?? 0
    }
}

/// The size of a person's collection, as their app last reported it.
public struct RPMCounts: Codable, Hashable, Sendable {
    public let albums: Int
    public let tracks: Int
    public let updatedAt: Int64

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albums    = try c.decodeIfPresent(Int.self, forKey: .albums) ?? 0
        tracks    = try c.decodeIfPresent(Int.self, forKey: .tracks) ?? 0
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }
}

/// Where the caller stands with another person. A word this build does not know reads as `.none`,
/// so the page offers Add friend and the server answers with the real state.
public enum RPMFriendship: String, Codable, Hashable, Sendable {
    /// The caller's own page. Not named `self`: `RPMFriendship.self` is the type itself.
    case own = "self"
    case none

    /// The caller asked; the other person has not answered.
    case requested

    /// The other person asked the caller.
    case incoming
    case friends

    public init(from decoder: any Decoder) throws {
        let word = try decoder.singleValueContainer().decode(String.self)
        self = RPMFriendship(rawValue: word) ?? .none
    }
}

/// A post on a person's page. The author is always the page's owner.
public struct RPMPost: Codable, Hashable, Sendable, Identifiable {
    public let ownerId: String
    public let postId: String
    public let authorName: String
    public let hasAvatar: Bool
    public let body: String
    public let song: RPMSong?
    public let createdAt: Int64
    public let ups: Int
    public let downs: Int
    public let score: Int

    /// How the caller voted: 1, -1 or 0.
    public let myVote: Int
    public let replyCount: Int
    public let authorDeleted: Bool

    /// The author supports rpm: their name is drawn in gold.
    public let authorSupporter: Bool

    public var id: String { postId }
    public var written: Date { Date(timeIntervalSince1970: Double(createdAt) / 1000) }
    public var authorShown: String { authorDeleted ? Loc.get("Community_DeletedUser") : authorName }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ownerId       = try c.decode(String.self, forKey: .ownerId)
        postId        = try c.decode(String.self, forKey: .postId)
        authorName    = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        hasAvatar     = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        body          = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        song          = try c.decodeIfPresent(RPMSong.self, forKey: .song)
        createdAt     = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        ups           = try c.decodeIfPresent(Int.self, forKey: .ups) ?? 0
        downs         = try c.decodeIfPresent(Int.self, forKey: .downs) ?? 0
        score         = try c.decodeIfPresent(Int.self, forKey: .score) ?? 0
        myVote        = try c.decodeIfPresent(Int.self, forKey: .myVote) ?? 0
        replyCount    = try c.decodeIfPresent(Int.self, forKey: .replyCount) ?? 0
        authorDeleted = try c.decodeIfPresent(Bool.self, forKey: .authorDeleted) ?? false
        authorSupporter = try c.decodeIfPresent(Bool.self, forKey: .authorSupporter) ?? false
    }

    private init(_ post: RPMPost, ups: Int, downs: Int, myVote: Int, ownerId: String, authorName: String,
                 hasAvatar: Bool, authorSupporter: Bool) {
        self.ownerId = ownerId
        self.postId = post.postId
        self.authorName = authorName
        self.hasAvatar = hasAvatar
        self.body = post.body
        self.song = post.song
        self.createdAt = post.createdAt
        self.ups = ups
        self.downs = downs
        self.score = ups - downs
        self.myVote = myVote
        self.replyCount = post.replyCount
        self.authorDeleted = post.authorDeleted
        self.authorSupporter = authorSupporter
    }

    /// The same post with the reader's vote counted here only: on the sample feed, so the keys can be tried.
    public func voted(_ value: Int) -> RPMPost {
        let ups = self.ups + (value == 1 ? 1 : 0) - (myVote == 1 ? 1 : 0)
        let downs = self.downs + (value == -1 ? 1 : 0) - (myVote == -1 ? 1 : 0)
        return RPMPost(self, ups: ups, downs: downs, myVote: value, ownerId: ownerId, authorName: authorName,
                       hasAvatar: hasAvatar, authorSupporter: authorSupporter)
    }

    /// The same post as written by someone else: the reader's own sample posts carry the reader.
    public func by(ownerId: String, name: String, hasAvatar: Bool, supporter: Bool) -> RPMPost {
        RPMPost(self, ups: ups, downs: downs, myVote: myVote, ownerId: ownerId, authorName: name,
                hasAvatar: hasAvatar, authorSupporter: supporter)
    }
}

/// A reply under a post, or under another reply.
public struct RPMReply: Codable, Hashable, Sendable, Identifiable {
    public let postId: String
    public let replyId: String

    /// The post id for a reply to the post itself, or the id of the reply it answers.
    public let parentId: String
    public let userId: String
    public let authorName: String
    public let hasAvatar: Bool
    public let body: String
    public let createdAt: Int64
    public let ups: Int
    public let downs: Int
    public let score: Int
    public let myVote: Int
    public let authorDeleted: Bool

    /// The author supports rpm: their name is drawn in gold.
    public let authorSupporter: Bool

    /// The reply was deleted but has replies under it. It keeps its place in the thread with no text.
    public let deleted: Bool

    public var id: String { replyId }
    public var written: Date { Date(timeIntervalSince1970: Double(createdAt) / 1000) }
    public var authorShown: String { authorDeleted ? Loc.get("Community_DeletedUser") : authorName }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        postId        = try c.decode(String.self, forKey: .postId)
        replyId       = try c.decode(String.self, forKey: .replyId)
        parentId      = try c.decodeIfPresent(String.self, forKey: .parentId) ?? postId
        userId        = try c.decodeIfPresent(String.self, forKey: .userId) ?? ""
        authorName    = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        hasAvatar     = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        body          = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        createdAt     = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        ups           = try c.decodeIfPresent(Int.self, forKey: .ups) ?? 0
        downs         = try c.decodeIfPresent(Int.self, forKey: .downs) ?? 0
        score         = try c.decodeIfPresent(Int.self, forKey: .score) ?? 0
        myVote        = try c.decodeIfPresent(Int.self, forKey: .myVote) ?? 0
        authorDeleted = try c.decodeIfPresent(Bool.self, forKey: .authorDeleted) ?? false
        deleted       = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
        authorSupporter = try c.decodeIfPresent(Bool.self, forKey: .authorSupporter) ?? false
    }
}

/// A review as a profile's feed carries it: the review, and the album it is about.
public struct RPMFeedReview: Hashable, Sendable {
    public let review: RPMReview
    public let albumArtist: String
    public let albumTitle: String
    public let albumYear: Int

    public init(review: RPMReview, albumArtist: String, albumTitle: String, albumYear: Int) {
        self.review = review
        self.albumArtist = albumArtist
        self.albumTitle = albumTitle
        self.albumYear = albumYear
    }
}

extension RPMFeedReview: Decodable {
    private enum CodingKeys: String, CodingKey { case albumArtist, albumTitle, albumYear }

    /// The review's own fields and the album's sit side by side in one object.
    public init(from decoder: any Decoder) throws {
        review = try RPMReview(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        albumArtist = try c.decodeIfPresent(String.self, forKey: .albumArtist) ?? ""
        albumTitle  = try c.decodeIfPresent(String.self, forKey: .albumTitle) ?? ""
        albumYear   = try c.decodeIfPresent(Int.self, forKey: .albumYear) ?? 0
    }
}

/// One entry in a profile's feed.
public enum RPMFeedItem: Hashable, Sendable, Identifiable {
    case post(RPMPost)
    case review(RPMFeedReview)

    public var id: String {
        switch self {
        case .post(let post): "post:" + post.postId
        // The author is part of the key: on the Feed tab two people's reviews of one record stand side by side.
        case .review(let shown): "review:" + shown.review.userId + ":" + shown.review.albumId
        }
    }

    public var createdAt: Int64 {
        switch self {
        case .post(let post): post.createdAt
        case .review(let shown): shown.review.createdAt
        }
    }
}

/// A page of a profile's feed. Entries of a kind this build does not know are left out.
public struct RPMFeedPage: Decodable, Sendable {
    public let items: [RPMFeedItem]

    /// The `before` for the next page; nil at the end.
    public let next: Int64?

    private enum CodingKeys: String, CodingKey { case items, next }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decodeIfPresent([RPMFeedEntry].self, forKey: .items)?.compactMap(\.item) ?? []
        next = try c.decodeIfPresent(Int64.self, forKey: .next)
    }

    public init(items: [RPMFeedItem], next: Int64?) {
        self.items = items
        self.next = next
    }
}

/// One entry of a feed as the server sends it; ``item`` is nil for a kind this build does not know.
struct RPMFeedEntry: Decodable, Sendable {
    let kind: String?
    let post: RPMPost?
    let review: RPMFeedReview?

    var item: RPMFeedItem? {
        switch kind {
        case "post": post.map(RPMFeedItem.post)
        case "review": review.map(RPMFeedItem.review)
        default: nil
        }
    }
}

struct RPMRepliesPage: Decodable, Sendable {
    let items: [RPMReply]
}

/// A person in a list: friends, requests, blocked people.
public struct RPMPerson: Codable, Hashable, Sendable, Identifiable {
    public let userId: String
    public let displayName: String
    public let hasAvatar: Bool
    public let avatarUpdatedAt: Int64

    /// When the friendship, request or block began.
    public let since: Int64

    public var id: String { userId }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId          = try c.decode(String.self, forKey: .userId)
        displayName     = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        hasAvatar       = try c.decodeIfPresent(Bool.self, forKey: .hasAvatar) ?? false
        avatarUpdatedAt = try c.decodeIfPresent(Int64.self, forKey: .avatarUpdatedAt) ?? 0
        since           = try c.decodeIfPresent(Int64.self, forKey: .since) ?? 0
    }
}

public struct RPMFriends: Decodable, Sendable {
    public let friends: [RPMPerson]
    public let incoming: [RPMPerson]
    public let requested: [RPMPerson]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        friends   = try c.decodeIfPresent([RPMPerson].self, forKey: .friends) ?? []
        incoming  = try c.decodeIfPresent([RPMPerson].self, forKey: .incoming) ?? []
        requested = try c.decodeIfPresent([RPMPerson].self, forKey: .requested) ?? []
    }

    private enum CodingKeys: String, CodingKey { case friends, incoming, requested }
}

/// What a notification is about. A word this build does not know is kept as `.other`, and the
/// list leaves it out.
public enum RPMNotificationKind: Hashable, Sendable {
    case reply, vote, friendRequest, friendAccepted, friendReview

    /// The reader unlocked a badge (``RPMNotification/badgeId``).
    case badge
    case other(String)

    init(_ word: String) {
        switch word {
        case "reply": self = .reply
        case "vote": self = .vote
        case "friendRequest": self = .friendRequest
        case "friendAccepted": self = .friendAccepted
        case "friendReview": self = .friendReview
        case "badge": self = .badge
        default: self = .other(word)
        }
    }
}

public struct RPMNotification: Decodable, Hashable, Sendable, Identifiable {
    public let id: String
    public let kind: RPMNotificationKind
    public let fromUserId: String
    public let fromName: String
    public let fromHasAvatar: Bool
    public let ownerId: String?
    public let postId: String?
    public let replyId: String?
    public let albumId: String?
    public let albumTitle: String?

    /// The badge unlocked, on a badge notification. See ``RPMProfileBadges``.
    public let badgeId: String?

    /// How many votes a vote entry stands for. 1 for the other kinds.
    public let count: Int
    public let createdAt: Int64
    public let read: Bool

    public var written: Date { Date(timeIntervalSince1970: Double(createdAt) / 1000) }

    private enum CodingKeys: String, CodingKey {
        case id, kind, fromUserId, fromName, fromHasAvatar, ownerId, postId, replyId,
             albumId, albumTitle, badgeId, count, createdAt, read
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self, forKey: .id)
        kind          = RPMNotificationKind(try c.decodeIfPresent(String.self, forKey: .kind) ?? "")
        fromUserId    = try c.decodeIfPresent(String.self, forKey: .fromUserId) ?? ""
        fromName      = try c.decodeIfPresent(String.self, forKey: .fromName) ?? ""
        fromHasAvatar = try c.decodeIfPresent(Bool.self, forKey: .fromHasAvatar) ?? false
        ownerId       = try c.decodeIfPresent(String.self, forKey: .ownerId)
        postId        = try c.decodeIfPresent(String.self, forKey: .postId)
        replyId       = try c.decodeIfPresent(String.self, forKey: .replyId)
        albumId       = try c.decodeIfPresent(String.self, forKey: .albumId)
        albumTitle    = try c.decodeIfPresent(String.self, forKey: .albumTitle)
        badgeId       = try c.decodeIfPresent(String.self, forKey: .badgeId)
        count         = try c.decodeIfPresent(Int.self, forKey: .count) ?? 1
        createdAt     = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
        read          = try c.decodeIfPresent(Bool.self, forKey: .read) ?? false
    }
}

public struct RPMNotificationPage: Decodable, Sendable {
    public let items: [RPMNotification]
    public let unread: Int
    public let next: String?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items  = try c.decodeIfPresent([RPMNotification].self, forKey: .items) ?? []
        unread = try c.decodeIfPresent(Int.self, forKey: .unread) ?? 0
        next   = try c.decodeIfPresent(String.self, forKey: .next)
    }

    private enum CodingKeys: String, CodingKey { case items, unread, next }
}

struct RPMUnread: Decodable, Sendable {
    let unread: Int
}

struct RPMPeople: Decodable, Sendable {
    let items: [RPMPerson]
}

/// What a profile page is drawn on, read from ``RPMProfile/pageGround``. A value this build cannot read is
/// ``standard``.
public enum RPMPageGround: Hashable, Sendable {
    /// The app's standard background.
    case standard

    /// A solid colour, as 0xRRGGBB.
    case colour(UInt32)

    /// One of the app's backgrounds, by its id (`vinyl`, `pegasus`, `sheet-music`, `gold`).
    case backdrop(String)

    public init(wire: String) {
        if wire.hasPrefix("color:#"), wire.count == 13, let value = UInt32(wire.dropFirst(7), radix: 16) {
            self = .colour(value)
        } else if wire.hasPrefix("backdrop:"), wire.count > 9 {
            self = .backdrop(String(wire.dropFirst(9)))
        } else {
            self = .standard
        }
    }

    /// The value as the server stores it.
    public var wire: String {
        switch self {
        case .standard: ""
        case .colour(let value): "color:#" + String(format: "%06X", value & 0xFFFFFF)
        case .backdrop(let id): "backdrop:" + id
        }
    }
}

/// The sample page that a test build shows while the server has no profile pages yet (`Samples/profile-sample.json`,
/// the same file as the Android app's `profile_sample.json`). It is read with the real wire types. Every time in it is
/// moved so that the newest entry is from a few minutes ago.
public struct RPMProfileSample: Sendable {
    public let counts: RPMCounts?
    public let listening: RPMListening?

    /// The badge the sample shows while the reader has chosen none, and its colour.
    public let badge: String
    public let badgeColour: String

    /// Other people's sample pages, by user id.
    public let people: [String: RPMProfile]

    /// The sample's Feed tab: everyone's posts and reviews, newest first.
    public let everyone: [RPMFeedItem]

    /// Whose photo each sample person borrows, by user id: an artist's, found as the artist page finds it.
    public let faces: [String: String]

    public let feed: RPMFeedPage
    public let replies: [String: [RPMReply]]
    public let notifications: RPMNotificationPage

    private struct Wire: Decodable {
        struct Profile: Decodable {
            let counts: RPMCounts?
            let listening: RPMListening?
            let badge: String?
            let badgeColour: String?
        }
        let profile: Profile
        let feed: RPMFeedPage
        let replies: [String: [RPMReply]]
        let notifications: RPMNotificationPage
        let people: [String: RPMProfile]?
        let everyone: [RPMFeedEntry]?
        let faces: [String: String]?
    }

    /// The bundled sample, or nil when it cannot be read.
    public static func load(now: Date = Date()) -> RPMProfileSample? {
        guard let url = Bundle.module.url(forResource: "profile-sample", withExtension: "json", subdirectory: "Samples"),
              let data = try? Data(contentsOf: url) else { return nil }
        return parse(data, now: now)
    }

    /// Reads a sample, with every time moved by the difference between `now` and the file's own `now`.
    public static func parse(_ data: Data, now: Date) -> RPMProfileSample? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let then = (object["now"] as? NSNumber)?.int64Value else { return nil }
        let shift = Int64(now.timeIntervalSince1970 * 1000) - then
        let moved = Self.shifted(object, by: shift)
        guard let json = try? JSONSerialization.data(withJSONObject: moved),
              let wire = try? RPMJSON.decoder.decode(Wire.self, from: json) else { return nil }
        return RPMProfileSample(counts: wire.profile.counts, listening: wire.profile.listening,
                                badge: wire.profile.badge ?? "", badgeColour: wire.profile.badgeColour ?? "",
                                people: wire.people ?? [:],
                                everyone: (wire.everyone ?? []).compactMap(\.item).sorted { $0.createdAt > $1.createdAt },
                                faces: wire.faces ?? [:],
                                feed: wire.feed, replies: wire.replies, notifications: wire.notifications)
    }

    /// The times in the sample: these keys hold milliseconds.
    private static let times: Set<String> = ["createdAt", "updatedAt", "at"]

    private static func shifted(_ value: Any, by shift: Int64) -> Any {
        if let object = value as? [String: Any] {
            var out: [String: Any] = [:]
            for (key, inner) in object {
                if times.contains(key), let number = (inner as? NSNumber)?.int64Value {
                    out[key] = NSNumber(value: number + shift)
                } else {
                    out[key] = shifted(inner, by: shift)
                }
            }
            return out
        }
        if let list = value as? [Any] { return list.map { shifted($0, by: shift) } }
        return value
    }
}
