import Foundation

/// The profile page's calls: the banner, what is playing, a page's feed, posts, replies, votes,
/// friends, notifications and blocks. Reads of a page work without a token; everything else needs
/// one.
extension RPMCommunityClient {
    // Profile

    /// The address of somebody's banner, as an absolute URL, with the stamp in it as for
    /// ``avatar(for:)``. Nil when they have none.
    public func banner(for profile: RPMProfile) -> URL? {
        guard profile.hasBanner, !profile.userId.isEmpty else { return nil }

        var path = "profiles/\(escaped(profile.userId))/banner"
        if profile.bannerUpdatedAt > 0 { path += "?v=\(profile.bannerUpdatedAt)" }

        return URL(string: path, relativeTo: transport.base)?.absoluteURL
    }

    /// The address of a person's photo when only their id is known, as on a reply or a
    /// notification. Without the stamp, so the server's short cache applies. Nil when they have none.
    public func avatar(userId: String, hasAvatar: Bool) -> URL? {
        guard hasAvatar, !userId.isEmpty else { return nil }
        return URL(string: "profiles/\(escaped(userId))/avatar", relativeTo: transport.base)?.absoluteURL
    }

    /// Sets the caller's photo. JPEG, PNG or WebP, at most 512 KB.
    @discardableResult
    public func setAvatar(_ bytes: Data, contentType: String) async throws -> RPMProfile {
        try await transport.upload("POST", "profile/avatar", bytes: bytes, contentType: contentType,
                                   as: RPMProfile.self)
    }

    public func deleteAvatar() async throws {
        try await transport.sendVoid("DELETE", "profile/avatar")
    }

    /// Sets the caller's banner. JPEG, PNG or WebP, at most 2 MB.
    @discardableResult
    public func setBanner(_ bytes: Data, contentType: String) async throws -> RPMProfile {
        try await transport.upload("POST", "profile/banner", bytes: bytes, contentType: contentType,
                                   as: RPMProfile.self)
    }

    public func deleteBanner() async throws {
        try await transport.sendVoid("DELETE", "profile/banner")
    }

    /// Turns sharing of what is playing on or off for every device of this account. Off also
    /// clears what is shown now.
    public func setSharesListening(_ on: Bool) async throws {
        struct Body: Encodable { let sharesListening: Bool }
        try await transport.sendVoid("PUT", "profile/sharing", body: Body(sharesListening: on))
    }

    /// What the caller is playing now. The server ignores it while sharing is off.
    public func setListening(_ song: RPMSong) async throws {
        try await transport.sendVoid("PUT", "profile/listening", body: song)
    }

    public func clearListening() async throws {
        try await transport.sendVoid("DELETE", "profile/listening")
    }

    /// What the caller's page is drawn on. See ``RPMPageGround``.
    public func setPageGround(_ ground: RPMPageGround) async throws {
        struct Body: Encodable { let ground: String }
        try await transport.sendVoid("PUT", "profile/ground", body: Body(ground: ground.wire))
    }

    /// Where the caller's banner comes from: a photo of the artist they are playing, or their banner photo.
    public func setBannerSource(listening: Bool) async throws {
        struct Body: Encodable { let source: String }
        try await transport.sendVoid("PUT", "profile/banner-source", body: Body(source: listening ? "listening" : "photo"))
    }

    /// Sends the badges this phone worked out (``RPMProfileBadges/unlocked(albums:tracks:genreAlbums:)``) and the
    /// one to show. The server adds `unlocked` to what it holds, never removes one, and notifies the caller of each
    /// one it did not hold yet.
    @discardableResult
    public func setBadges(_ unlocked: [String], badge: String, badgeColour: String) async throws -> RPMProfile {
        struct Body: Encodable { let unlocked: [String]; let badge: String; let badgeColour: String }
        return try await transport.send("PUT", "profile/badges",
                                        body: Body(unlocked: unlocked, badge: badge, badgeColour: badgeColour),
                                        as: RPMProfile.self)
    }

    /// The size of the caller's collection, for the counts on their page.
    public func setCounts(albums: Int, tracks: Int) async throws {
        struct Body: Encodable { let albums: Int; let tracks: Int }
        try await transport.sendVoid("PUT", "profile/counts", body: Body(albums: albums, tracks: tracks))
    }

    // Feed and posts

    /// A page of a person's feed: their posts and reviews, newest first.
    ///
    /// - Parameter before: the `next` of the page before; nil for the first page.
    public func feed(userId: String, before: Int64? = nil, limit: Int = 20) async throws -> RPMFeedPage {
        var path = "profiles/\(escaped(userId))/feed?limit=\(limit)"
        if let before { path += "&before=\(before)" }
        return try await transport.get(path, as: RPMFeedPage.self)
    }

    /// A page of everyone's posts and album reviews, newest first: the Feed tab. A page can come back empty
    /// while `next` is set, when everything on it was by someone blocked: keep reading.
    ///
    /// - Parameter before: the `next` of the page before; nil for the first page.
    public func everyone(before: Int64? = nil, limit: Int = 20) async throws -> RPMFeedPage {
        var path = "feed?limit=\(limit)"
        if let before { path += "&before=\(before)" }
        return try await transport.get(path, as: RPMFeedPage.self)
    }

    /// Posts on the caller's own page.
    @discardableResult
    public func post(_ body: String, song: RPMSong?) async throws -> RPMPost {
        struct Body: Encodable { let body: String; let song: RPMSong? }
        return try await transport.send("POST", "profile/posts", body: Body(body: body, song: song),
                                        as: RPMPost.self)
    }

    public func deletePost(_ postId: String) async throws {
        try await transport.sendVoid("DELETE", "profile/posts/\(escaped(postId))")
    }

    /// - Parameter value: 1 up, -1 down, 0 to take the vote back.
    @discardableResult
    public func vote(on post: RPMPost, value: Int) async throws -> RPMPost {
        struct Body: Encodable { let value: Int }
        return try await transport.send(
            "POST", "\(postPath(post.ownerId, post.postId))/vote", body: Body(value: value), as: RPMPost.self)
    }

    // Replies

    /// Every reply under a post, oldest first. See ``RPMReplyTree`` for the thread.
    public func replies(ownerId: String, postId: String) async throws -> [RPMReply] {
        try await transport.get("\(postPath(ownerId, postId))/replies", as: RPMRepliesPage.self).items
    }

    /// - Parameter parentId: the reply this answers; nil for a reply to the post itself.
    @discardableResult
    public func reply(ownerId: String, postId: String, parentId: String?, body: String) async throws -> RPMReply {
        struct Body: Encodable { let body: String; let parentId: String? }
        return try await transport.send(
            "POST", "\(postPath(ownerId, postId))/replies", body: Body(body: body, parentId: parentId),
            as: RPMReply.self)
    }

    public func deleteReply(ownerId: String, postId: String, replyId: String) async throws {
        try await transport.sendVoid("DELETE", "\(postPath(ownerId, postId))/replies/\(escaped(replyId))")
    }

    @discardableResult
    public func vote(ownerId: String, on reply: RPMReply, value: Int) async throws -> RPMReply {
        struct Body: Encodable { let value: Int }
        return try await transport.send(
            "POST", "\(postPath(ownerId, reply.postId))/replies/\(escaped(reply.replyId))/vote",
            body: Body(value: value), as: RPMReply.self)
    }

    private func postPath(_ ownerId: String, _ postId: String) -> String {
        "profiles/\(escaped(ownerId))/posts/\(escaped(postId))"
    }

    // Friends

    /// Asks to be friends. If that person already asked the caller, this accepts instead.
    public func requestFriend(_ userId: String) async throws {
        try await transport.sendVoid("POST", "friends/\(escaped(userId))")
    }

    public func acceptFriend(_ userId: String) async throws {
        try await transport.sendVoid("POST", "friends/\(escaped(userId))/accept")
    }

    /// Cancels the caller's request, declines theirs, or ends a friendship.
    public func removeFriend(_ userId: String) async throws {
        try await transport.sendVoid("DELETE", "friends/\(escaped(userId))")
    }

    public func friends() async throws -> RPMFriends {
        try await transport.get("friends", as: RPMFriends.self)
    }

    // Notifications

    /// A page of the caller's notifications, newest first.
    public func notifications(before: String? = nil) async throws -> RPMNotificationPage {
        var path = "notifications"
        if let before { path += "?before=" + escaped(before) }
        return try await transport.get(path, as: RPMNotificationPage.self)
    }

    public func unreadNotifications() async throws -> Int {
        try await transport.get("notifications/unread", as: RPMUnread.self).unread
    }

    /// Marks this notification and every older one as read.
    public func markNotificationsRead(upTo id: String) async throws {
        struct Body: Encodable { let upTo: String }
        try await transport.sendVoid("POST", "notifications/read", body: Body(upTo: id))
    }

    // Blocks

    /// Blocks a person. It also ends a friendship or a request between the two.
    public func block(_ userId: String) async throws {
        try await transport.sendVoid("POST", "blocks/\(escaped(userId))")
    }

    public func unblock(_ userId: String) async throws {
        try await transport.sendVoid("DELETE", "blocks/\(escaped(userId))")
    }

    public func blocked() async throws -> [RPMPerson] {
        try await transport.get("blocks", as: RPMPeople.self).items
    }
}

/// The replies of one post as a tree, built from each reply's `parentId`.
///
/// The server sends every reply of a post in one flat list, oldest first. A reply whose parent is
/// missing from the list (deleted with nothing under it) is shown at the top level, so no reply
/// is lost.
public struct RPMReplyTree: Sendable {
    /// One reply and how deep it is: 0 for a reply to the post.
    public struct Line: Sendable, Identifiable {
        public let reply: RPMReply
        public let depth: Int
        public var id: String { reply.replyId }
    }

    /// Every reply in reading order: each one followed by the replies under it.
    public let lines: [Line]

    public init(postId: String, replies: [RPMReply]) {
        let known = Set(replies.map(\.replyId))
        var children: [String: [RPMReply]] = [:]
        for reply in replies {
            let parent = known.contains(reply.parentId) ? reply.parentId : postId
            children[parent, default: []].append(reply)
        }

        var lines: [Line] = []
        // An explicit stack and not recursion: a thread can be deep.
        var stack: [(RPMReply, Int)] = (children[postId] ?? []).reversed().map { ($0, 0) }
        var seen = Set<String>()
        while let (reply, depth) = stack.popLast() {
            guard seen.insert(reply.replyId).inserted else { continue }
            lines.append(Line(reply: reply, depth: depth))
            for child in (children[reply.replyId] ?? []).reversed() {
                stack.append((child, depth + 1))
            }
        }
        self.lines = lines
    }
}
