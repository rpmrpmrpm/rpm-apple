import Testing
import Foundation
@testable import RPMKit

private let api = URL(string: "https://api.example.com")!

private func community(
    _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> RPMCommunityClient {
    RPMCommunityClient(transport: Transport(
        base: api, tokens: FixedTokens(token: "t"), reach: openLine(),
        session: stubbedSession(handler)))
}

/// Keeps the last request a stubbed session saw.
private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var kept: URLRequest?
    var request: URLRequest? { lock.withLock { kept } }
    func keep(_ request: URLRequest) { lock.withLock { kept = request } }
}

// ── reading ──

@Test func aProfileReadsThePageFields() throws {
    let profile = try fixture("profile-page", as: RPMProfile.self)
    #expect(profile.hasBanner)
    #expect(profile.bannerUpdatedAt == 1_790_000_000_456)
    #expect(profile.listening?.song.title == "Once in a Lifetime")
    #expect(profile.listening?.albumId == "a-remain")
    #expect(profile.counts?.albums == 1610)
    #expect(profile.counts?.tracks == 23329)
    #expect(profile.friendship == .incoming)
    #expect(!profile.blocked)
    #expect(profile.sharesListening)
}

/// A profile from a server without the page still reads, with nothing to show.
@Test func anOldProfileReadsWithoutThePageFields() throws {
    let json = #"{"userId":"u1","displayName":"ana","hasAvatar":false,"avatarUpdatedAt":0,"createdAt":1}"#
    let profile = try RPMJSON.decoder.decode(RPMProfile.self, from: Data(json.utf8))
    #expect(!profile.hasBanner)
    #expect(profile.listening == nil)
    #expect(profile.counts == nil)
    #expect(profile.friendship == .none)
}

@Test func aFriendshipWordFromANewerServerReadsAsNone() throws {
    let json = #"{"userId":"u1","friendship":"following"}"#
    let profile = try RPMJSON.decoder.decode(RPMProfile.self, from: Data(json.utf8))
    #expect(profile.friendship == .none)

    let own = try RPMJSON.decoder.decode(RPMProfile.self, from: Data(#"{"userId":"u1","friendship":"self"}"#.utf8))
    #expect(own.friendship == .own)
}

@Test func theFeedReadsPostsAndReviewsAndSkipsUnknownKinds() throws {
    let page = try fixture("profile-feed", as: RPMFeedPage.self)
    #expect(page.items.count == 2)
    #expect(page.next == 1_790_000_100_000)

    guard case .post(let post) = page.items[0] else { Issue.record("first item is not a post"); return }
    #expect(post.body == "New speakers today.")
    #expect(post.song?.artist == "Talking Heads")
    #expect(post.myVote == 1)
    #expect(post.replyCount == 4)
    #expect(post.written == Date(timeIntervalSince1970: 1_790_000_300))

    guard case .review(let shown) = page.items[1] else { Issue.record("second item is not a review"); return }
    #expect(shown.review.rating == 9)
    #expect(shown.albumTitle == "Remain in Light")
    #expect(shown.albumYear == 1980)
    #expect(page.items[0].id != page.items[1].id)
}

@Test func repliesBecomeATreeInReadingOrder() throws {
    let replies = try fixture("post-replies", as: RPMRepliesPage.self).items
    let tree = RPMReplyTree(postId: "p1", replies: replies)

    #expect(tree.lines.map(\.reply.replyId) == ["r1", "r2", "r3", "r4", "r5"])
    #expect(tree.lines.map(\.depth) == [0, 1, 2, 0, 0])
    #expect(tree.lines[1].reply.deleted)
    #expect(tree.lines[3].reply.authorShown == Loc.get("Community_DeletedUser"))
}

/// A reply whose parent is not in the list is shown at the top, not lost.
@Test func aReplyWithAMissingParentStaysInTheThread() throws {
    let replies = try fixture("post-replies", as: RPMRepliesPage.self).items
    let tree = RPMReplyTree(postId: "p1", replies: replies)
    #expect(tree.lines.contains { $0.reply.replyId == "r5" && $0.depth == 0 })
}

@Test func notificationsReadEveryKindAndKeepUnknownOnesApart() throws {
    let page = try fixture("notifications", as: RPMNotificationPage.self)
    #expect(page.unread == 2)
    #expect(page.next == nil)
    #expect(page.items.map(\.kind) == [.vote, .reply, .friendReview, .friendRequest, .friendAccepted,
                                       .other("mention")])
    #expect(page.items[0].count == 3)
    #expect(page.items[2].albumTitle == "Remain in Light")
}

// ── writing ──

@Test func aPostGoesToTheCallersOwnPage() async throws {
    let seen = Seen()
    let client = community { request in
        seen.keep(request)
        return ok(request, #"{"ownerId":"u1","postId":"p9","body":"Hi"}"#)
    }

    let song = RPMSong(artist: "A", title: "T", album: "L", albumId: nil)
    let post = try await client.post("Hi", song: song)
    #expect(post.postId == "p9")

    let request = try #require(seen.request)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/profile/posts")
    let body = try #require(JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any])
    #expect(body["body"] as? String == "Hi")
    #expect((body["song"] as? [String: Any])?["title"] as? String == "T")
}

@Test func aReplyNamesItsPostAndParent() async throws {
    let seen = Seen()
    let client = community { request in
        seen.keep(request)
        return ok(request, #"{"postId":"p1","replyId":"r9","parentId":"r1"}"#)
    }

    let reply = try await client.reply(ownerId: "u 1", postId: "p1", parentId: "r1", body: "Yes")
    #expect(reply.parentId == "r1")

    let request = try #require(seen.request)
    #expect(request.url?.absoluteString.hasSuffix("/profiles/u%201/posts/p1/replies") == true)
    let body = try #require(JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any])
    #expect(body["parentId"] as? String == "r1")
}

@Test func aBannerIsSentAsBytesWithItsType() async throws {
    let seen = Seen()
    let client = community { request in
        seen.keep(request)
        return ok(request, #"{"userId":"u1","hasBanner":true,"bannerUpdatedAt":5}"#)
    }

    let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0])
    let profile = try await client.setBanner(bytes, contentType: "image/jpeg")
    #expect(profile.hasBanner)

    let request = try #require(seen.request)
    #expect(request.url?.path == "/profile/banner")
    #expect(request.value(forHTTPHeaderField: "Content-Type") == "image/jpeg")
    #expect(request.bodyData == bytes)
}

@Test func theBannerAddressCarriesItsStamp() throws {
    let client = community { ok($0, "") }
    let profile = try fixture("profile-page", as: RPMProfile.self)
    let url = try #require(client.banner(for: profile))
    #expect(url.absoluteString == "https://api.example.com/profiles/u-ana/banner?v=1790000000456")
}

@Test func theFeedAsksForTheNextPage() async throws {
    let seen = Seen()
    let client = community { request in
        seen.keep(request)
        return ok(request, #"{"items":[],"next":null}"#)
    }

    let page = try await client.feed(userId: "u-ana", before: 42)
    #expect(page.items.isEmpty)
    #expect(page.next == nil)
    #expect(seen.request?.url?.query == "limit=20&before=42")
}

// ── the sample page ──

/// The bundled sample reads with the real wire types, and its newest entry is moved to just before now.
@Test func theBundledSampleReadsAndIsRecent() throws {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    let sample = try #require(RPMProfileSample.load(now: now))
    #expect(sample.feed.items.count == 6)
    #expect(sample.counts?.albums == 1610)
    #expect(sample.replies["s-1"]?.count == 4)
    #expect(sample.notifications.unread == 2)
    let newest = try #require(sample.feed.items.map(\.createdAt).max())
    #expect(newest < 2_000_000_000_000)
    #expect(newest > 2_000_000_000_000 - 3 * 3_600_000)
}

/// The sample's other people, the Feed tab's posts and reviews, and the photos the people borrow.
@Test func theSampleHasPeopleAndEveryonesFeed() throws {
    let sample = try #require(RPMProfileSample.load(now: Date(timeIntervalSince1970: 2_000_000_000)))
    #expect(Set(sample.people.keys) == ["u-mara", "u-jonas", "u-ines"])
    #expect(sample.everyone.count == 7)
    #expect(sample.everyone.contains { if case .review = $0 { true } else { false } })
    #expect(sample.everyone.map(\.createdAt) == sample.everyone.map(\.createdAt).sorted(by: >))
    #expect(sample.faces["u-jonas"] == "Radiohead")
    #expect(sample.badge == "music-connoisseur")
}

/// Two people's reviews of one record are two entries on the Feed tab.
@Test func aReviewsFeedIdHoldsItsAuthor() throws {
    let json = #"{"items":[{"kind":"review","review":{"albumId":"a1","userId":"u1","createdAt":2}},{"kind":"review","review":{"albumId":"a1","userId":"u2","createdAt":1}}]}"#
    let page = try RPMJSON.decoder.decode(RPMFeedPage.self, from: Data(json.utf8))
    #expect(page.items.map(\.id) == ["review:u1:a1", "review:u2:a1"])
}

/// The page's look and the supporter's gold read from the wire, with defaults when a server leaves them out.
@Test func theLookAndTheGoldNamesRead() throws {
    // Two pound signs: the colour's "#2 would close a raw string that has one.
    let json = ##"{"userId":"u1","bannerSource":"listening","badges":["first-spin"],"badge":"first-spin","badgeColour":"#2563EB"}"##
    let profile = try RPMJSON.decoder.decode(RPMProfile.self, from: Data(json.utf8))
    #expect(profile.bannerFollowsListening)
    #expect(profile.badges == ["first-spin"])
    #expect(profile.badge == "first-spin")
    #expect(profile.badgeColour == "#2563EB")
    let post = try RPMJSON.decoder.decode(RPMPost.self, from: Data(#"{"ownerId":"u1","postId":"p1","authorSupporter":true}"#.utf8))
    #expect(post.authorSupporter)
    let plain = try RPMJSON.decoder.decode(RPMPost.self, from: Data(#"{"ownerId":"u1","postId":"p1"}"#.utf8))
    #expect(!plain.authorSupporter)
}

/// A badge notification names its badge.
@Test func aBadgeNotificationReads() throws {
    let json = #"{"id":"n1","kind":"badge","badgeId":"crate-digger","createdAt":1}"#
    let note = try RPMJSON.decoder.decode(RPMNotification.self, from: Data(json.utf8))
    #expect(note.kind == .badge)
    #expect(note.badgeId == "crate-digger")
}

/// Everyone's feed is read from `feed`, and the badges are sent as `unlocked` with the badge and its colour.
@Test func everyonesFeedAndTheBadgesUseTheirRoutes() async throws {
    let seen = Seen()
    let client = community { request in
        seen.keep(request)
        let body = request.url?.path == "/profile/badges" ? #"{"userId":"u1","badges":["first-spin"]}"# : #"{"items":[]}"#
        return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
    }
    _ = try await client.everyone(before: 7)
    #expect(seen.request?.url?.path == "/feed")
    #expect(seen.request?.url?.query == "limit=20&before=7")
    let stored = try await client.setBadges(["first-spin"], badge: "first-spin", badgeColour: "#7A1FD1")
    #expect(stored.badges == ["first-spin"])
    #expect(seen.request?.httpMethod == "PUT")
}

@Test func aPageGroundReadsAndWritesItsWire() {
    #expect(RPMPageGround(wire: "color:#2A0A5E") == .colour(0x2A0A5E))
    #expect(RPMPageGround(wire: "backdrop:sheet-music") == .backdrop("sheet-music"))
    #expect(RPMPageGround(wire: "") == .standard)
    #expect(RPMPageGround(wire: "color:red") == .standard)
    #expect(RPMPageGround.colour(0x2A0A5E).wire == "color:#2A0A5E")
}
