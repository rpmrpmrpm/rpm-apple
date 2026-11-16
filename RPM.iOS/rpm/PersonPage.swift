import Foundation
import Observation
import RPMKit
import RPMUI

/// One person's page: their profile, their feed, and the thread that is open on it. The reader's own page opens from
/// the Feed tab's profile key; a name tapped on a post or a review opens one for that person.
///
/// **The newest read wins, not the last one to answer**, as on ``ArtistPosts``: each read of the
/// page takes a number, and its answer is used only while no newer read has started.
@MainActor
@Observable
final class PersonPage: Identifiable {
    private let community: RPMCommunityClient
    let userId: String
    let isOwn: Bool

    nonisolated var id: String { userId }

    /// The sample page for a server that has no profile pages yet; nil in a listener's build.
    private let sample: (() -> RPMProfileSample?)?

    init(community: RPMCommunityClient, userId: String, isOwn: Bool,
         sample: (() -> RPMProfileSample?)? = nil) {
        self.community = community
        self.userId = userId
        self.isOwn = isOwn
        self.sample = sample
    }

    /// Whether the page shows the sample: read from a server that has no feed route yet, the reader's own page with
    /// the sample's posts, or a sample person's page. Writes then fail as they would, except the page's look (the
    /// banner's source, the background and the badge), which is kept here so it can be tried.
    private(set) var isSample = false
    private var sampled: RPMProfileSample?

    /// Whether an error means the server has no such route: 404, or the 401 the live server
    /// answers for a route it does not have, even to a caller whose own profile was just read.
    static func isMissingRoute(_ error: any Error) -> Bool {
        switch error as? RPMError {
        case .unauthorized: true
        case .refused(status: 404, _): true
        default: false
        }
    }

    private(set) var profile: RPMProfile?
    private(set) var feed: [RPMFeedItem] = []

    /// The `before` of the next feed page; nil when there is no more.
    private(set) var next: Int64?

    /// Whether the feed has been read. False while it is read and after a failed read.
    private(set) var answered = false
    private(set) var trouble: String?
    private(set) var sending = false
    var draft = ""
    var withSong = false

    /// A post to open with its replies once the page is read: a post tapped on the Feed tab.
    var pendingPost: RPMPost?

    private var newest = 0
    private var readingMore = false

    var photo: URL? { profile.flatMap(community.avatar(for:)) }
    var banner: URL? { profile.flatMap(community.banner(for:)) }

    // ── reading ──

    /// Reads the profile and the first page of the feed.
    func read() async {
        newest += 1
        let ticket = newest
        do {
            async let first = community.feed(userId: userId)
            let found: RPMProfile?
            if isOwn {
                found = try await community.profile()
            } else {
                found = try await community.publicProfile(userId: userId)
            }
            let page: RPMFeedPage
            do {
                page = try await first
            } catch let missing where Self.isMissingRoute(missing) {
                guard let shown = sampled ?? sample?() else { throw missing }
                sampled = shown
                guard ticket == newest else { return }
                if !isOwn {
                    // A sample person's page: their sample profile, and their posts and reviews from the sample feed.
                    guard let person = shown.people[userId] else { throw missing }
                    isSample = true
                    profile = person
                    feed = shown.everyone.filter { item in
                        switch item {
                        case .post(let post): post.ownerId == userId
                        case .review(let review): review.review.userId == userId
                        }
                    }
                    next = nil
                    answered = true
                    trouble = nil
                    return
                }
                isSample = true
                // What was chosen on the sample page stays: the server cannot keep it yet.
                let kept = profile
                profile = found.map { own in
                    own.filled(from: shown).with(
                        pageGround: kept.map(\.pageGround).flatMap { $0.isEmpty ? nil : $0 },
                        bannerSource: kept.map(\.bannerSource).flatMap { $0.isEmpty ? nil : $0 },
                        badges: kept?.badges,
                        badge: kept.flatMap { $0.badgeColour.isEmpty ? nil : $0.badge },
                        badgeColour: kept.map(\.badgeColour).flatMap { $0.isEmpty ? nil : $0 })
                }
                feed = shown.feed.items
                next = nil
                answered = true
                trouble = nil
                return
            }
            guard ticket == newest else { return }
            isSample = false
            profile = found
            feed = page.items
            next = page.next
            answered = true
            trouble = nil
        } catch {
            guard ticket == newest else { return }
            trouble = message(error)
        }
    }

    func more() async {
        guard let next, !readingMore else { return }
        readingMore = true
        defer { readingMore = false }
        let ticket = newest
        guard let page = try? await community.feed(userId: userId, before: next), ticket == newest else { return }
        // A post written while the page was read can appear on two pages; keep the first.
        let known = Set(feed.map(\.id))
        feed += page.items.filter { !known.contains($0.id) }
        self.next = page.next
    }

    // ── the owner's posts ──

    func post(song: RPMSong?) async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isOwn, !body.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        do {
            try await community.post(body, song: withSong ? song : nil)
            // Only the text that was sent is removed. Anything typed while it was on its way stays.
            if draft.trimmingCharacters(in: .whitespacesAndNewlines) == body { draft = "" }
            withSong = false
        } catch {
            editTrouble = message(error)
            return
        }
        await read()
    }

    func delete(_ post: RPMPost) async {
        do { try await community.deletePost(post.postId) } catch { editTrouble = message(error); return }
        feed.removeAll { $0.id == RPMFeedItem.post(post).id }
        if openPost?.postId == post.postId { closeThread() }
    }

    func vote(_ post: RPMPost, _ value: Int) async {
        guard let changed = try? await community.vote(on: post, value: value) else { return }
        replace(.post(changed))
        if openPost?.postId == changed.postId { openPost = changed }
    }

    func voteReview(_ review: RPMReview, _ value: Int) async {
        guard let changed = try? await community.vote(albumId: review.albumId, userId: review.userId, value: value),
              let index = feed.firstIndex(where: {
                  if case .review(let shown) = $0 { shown.review.albumId == review.albumId && shown.review.userId == review.userId } else { false }
              }),
              case .review(let shown) = feed[index]
        else { return }
        feed[index] = .review(RPMFeedReview(review: changed, albumArtist: shown.albumArtist,
                                            albumTitle: shown.albumTitle, albumYear: shown.albumYear))
    }

    private func replace(_ item: RPMFeedItem) {
        if let index = feed.firstIndex(where: { $0.id == item.id }) { feed[index] = item }
    }

    /// Returns why the report failed, or nil when it was sent.
    func report(_ post: RPMPost, note: String) async -> String? {
        do {
            try await community.report(.post(ownerId: post.ownerId, postId: post.postId),
                                       reason: "post", note: note.isEmpty ? nil : note)
            return nil
        } catch {
            return message(error)
        }
    }

    // ── the person ──

    func friend(_ step: FriendStep) async {
        do {
            switch step {
            case .add: try await community.requestFriend(userId)
            case .accept: try await community.acceptFriend(userId)
            case .cancel, .decline, .remove: try await community.removeFriend(userId)
            }
        } catch {
            editTrouble = message(error)
            return
        }
        await read()
    }

    func block() async {
        do { try await community.block(userId) } catch { editTrouble = message(error); return }
        await read()
    }

    func unblock() async {
        do { try await community.unblock(userId) } catch { editTrouble = message(error); return }
        await read()
    }

    // ── the owner's page ──

    /// Why the last change failed: a post, a delete, a friend step, a block, the photo, the banner
    /// or the name. The page shows it in an alert. ``trouble`` is only for a page that could not be
    /// read, and takes the place of the feed.
    var editTrouble: String?
    private(set) var saving = false

    /// Saves everything changed on the edit page: the name, the photo, the banner and where it comes from, the
    /// background, and the badge with its colour. Each part is sent only when it changed. Returns true when all of it
    /// was saved; otherwise ``editTrouble`` says why, and the edit page stays open with the changes, to try again.
    ///
    /// On the sample page the banner's source, the background and the badge are kept here only, as the server cannot
    /// keep them yet; ``read()`` keeps them over the sample.
    ///
    /// - Parameter ownBadges: the badges this phone worked out, sent with the badge so one unlocked since the last
    ///   send can be chosen at once.
    func save(_ edit: ProfileEdit, ownBadges: [String]) async -> Bool {
        guard let shown = profile, !saving else { return false }
        saving = true
        defer { saving = false }
        do {
            if edit.trimmedName != edit.nameAtStart { try await community.setDisplayName(edit.trimmedName) }
            if let photo = edit.photo {
                try await community.setAvatar(photo, contentType: "image/jpeg")
            } else if edit.dropPhoto {
                try await community.deleteAvatar()
            }
            if let banner = edit.banner {
                try await community.setBanner(banner, contentType: "image/jpeg")
            } else if edit.dropBanner {
                try await community.deleteBanner()
            }
            var badges = shown.badges
            for id in ownBadges where !badges.contains(id) { badges.append(id) }
            if isSample {
                profile = profile?.with(pageGround: edit.ground.wire, bannerSource: edit.follows ? "listening" : "photo",
                                        badges: badges, badge: edit.badge, badgeColour: edit.colour)
            } else {
                if edit.follows != edit.followsAtStart { try await community.setBannerSource(listening: edit.follows) }
                if edit.ground != edit.groundAtStart { try await community.setPageGround(edit.ground) }
                if edit.badge != edit.badgeAtStart || edit.colour != edit.colourAtStart {
                    try await community.setBadges(badges, badge: edit.badge, badgeColour: edit.colour)
                }
            }
            editTrouble = nil
        } catch {
            editTrouble = message(error)
            return false
        }
        await read()
        return true
    }

    /// Sends the badges this phone worked out when the server does not hold them all yet. The server notifies the
    /// reader of each new one. Only on the reader's own page, once it is read: the badge shown and its colour go with
    /// them. Returns true when the server took new badges, so the caller reads the notification count again.
    @discardableResult
    func reportBadges(_ unlocked: [String]) async -> Bool {
        guard let shown = profile, isOwn, !isSample, !unlocked.allSatisfy(shown.badges.contains) else { return false }
        guard let stored = try? await community.setBadges(unlocked, badge: shown.badge, badgeColour: shown.badgeColour)
        else { return false }
        profile = profile?.with(badges: stored.badges)
        return true
    }

    // ── the open thread ──

    private(set) var openPost: RPMPost?
    private(set) var replies: [RPMReply] = []
    private(set) var threadAnswered = false
    private(set) var threadTrouble: String?
    private(set) var replying = false
    var replyDraft = ""

    /// The reply the box answers; nil for the post itself.
    var replyingTo: RPMReply?

    private var threadTicket = 0

    var replyLines: [RPMReplyTree.Line] {
        guard let openPost else { return [] }
        return RPMReplyTree(postId: openPost.postId, replies: replies).lines
    }

    func open(_ post: RPMPost) async {
        openPost = post
        replies = []
        threadAnswered = false
        threadTrouble = nil
        replyingTo = nil
        await readThread()
    }

    func closeThread() {
        openPost = nil
        replies = []
        replyingTo = nil
    }

    private func readThread() async {
        guard let post = openPost else { return }
        if isSample {
            replies = sampled?.replies[post.postId] ?? []
            threadAnswered = true
            return
        }
        threadTicket += 1
        let ticket = threadTicket
        do {
            let said = try await community.replies(ownerId: post.ownerId, postId: post.postId)
            guard ticket == threadTicket, openPost?.postId == post.postId else { return }
            replies = said
            threadAnswered = true
            threadTrouble = nil
        } catch {
            guard ticket == threadTicket else { return }
            threadTrouble = message(error)
        }
    }

    func sendReply() async {
        guard let post = openPost, !replying else { return }
        let body = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        replying = true
        defer { replying = false }
        do {
            try await community.reply(ownerId: post.ownerId, postId: post.postId,
                                      parentId: replyingTo?.replyId, body: body)
            if replyDraft.trimmingCharacters(in: .whitespacesAndNewlines) == body { replyDraft = "" }
            replyingTo = nil
        } catch {
            threadTrouble = message(error)
            return
        }
        await readThread()
        refreshFeed()
    }

    func voteReply(_ reply: RPMReply, _ value: Int) async {
        guard let post = openPost,
              let changed = try? await community.vote(ownerId: post.ownerId, on: reply, value: value),
              let index = replies.firstIndex(where: { $0.replyId == changed.replyId })
        else { return }
        replies[index] = changed
    }

    func deleteReply(_ reply: RPMReply) async {
        guard let post = openPost else { return }
        do {
            try await community.deleteReply(ownerId: post.ownerId, postId: post.postId, replyId: reply.replyId)
        } catch {
            threadTrouble = message(error)
            return
        }
        await readThread()
        refreshFeed()
    }

    func reportReply(_ reply: RPMReply, note: String) async -> String? {
        guard let post = openPost else { return nil }
        do {
            try await community.report(.reply(ownerId: post.ownerId, postId: post.postId, replyId: reply.replyId),
                                       reason: "reply", note: note.isEmpty ? nil : note)
            return nil
        } catch {
            return message(error)
        }
    }

    /// Reads the page again after a reply was added or removed, so the post's count is right. The
    /// feed has no read of a single post, so the first page is read again.
    private func refreshFeed() {
        Task { await read() }
    }

    private func message(_ error: any Error) -> String {
        (error as? RPMError)?.userMessage(refused: Loc.get("Rpm_Profile_Offline"))
            ?? Loc.get("Rpm_Profile_Offline")
    }
}

/// The reader's notifications, and the count on the badge.
@MainActor
@Observable
final class Notices {
    private let community: RPMCommunityClient
    private let sample: (() -> RPMProfileSample?)?

    init(community: RPMCommunityClient, sample: (() -> RPMProfileSample?)? = nil) {
        self.community = community
        self.sample = sample
    }

    private(set) var unread = 0
    private(set) var items: [RPMNotification] = []
    private(set) var next: String?
    private(set) var answered = false
    private(set) var trouble: String?

    /// Whether the sample's notifications were shown: its count then stays read, as real ones do.
    private var sampleSeen = false

    /// Reads the count for the badge. A failure keeps the last count.
    func readUnread() async {
        do {
            unread = try await community.unreadNotifications()
        } catch let missing where PersonPage.isMissingRoute(missing) {
            // A server with no notifications yet: the sample's count, so the badge can be seen.
            if let shown = sample?() { unread = sampleSeen ? 0 : shown.notifications.unread }
        } catch {
            // The last count stays.
        }
    }

    /// Reads the first page, then marks everything on it as read: the list is on screen.
    func read() async {
        do {
            let page: RPMNotificationPage
            do {
                page = try await community.notifications()
            } catch let missing where PersonPage.isMissingRoute(missing) {
                guard let shown = sample?() else { throw missing }
                items = shown.notifications.items
                next = nil
                answered = true
                trouble = nil
                unread = 0
                sampleSeen = true
                return
            }
            items = page.items
            next = page.next
            answered = true
            trouble = nil
            if let newest = page.items.first, page.unread > 0 {
                try? await community.markNotificationsRead(upTo: newest.id)
                unread = 0
            }
        } catch {
            trouble = (error as? RPMError)?.userMessage(refused: Loc.get("Rpm_Profile_Offline"))
                ?? Loc.get("Rpm_Profile_Offline")
        }
    }

    private var readingMore = false

    func more() async {
        guard let next, !readingMore else { return }
        readingMore = true
        defer { readingMore = false }
        guard let page = try? await community.notifications(before: next) else { return }
        let known = Set(items.map(\.id))
        items += page.items.filter { !known.contains($0.id) }
        self.next = page.next
    }

    func answer(_ userId: String, accept: Bool) async {
        if accept { try? await community.acceptFriend(userId) } else { try? await community.removeFriend(userId) }
        items.removeAll { $0.kind == .friendRequest && $0.fromUserId == userId }
    }
}

/// Sends what is playing to the reader's profile, as "listening to".
///
/// At most one send a minute: a song that changes faster waits, and only the newest one is sent.
/// The same song noted again within 20 minutes is not sent again. After that it is, because the
/// server stops showing a song 30 minutes after it was sent.
@MainActor
final class ListeningShare {
    private let community: RPMCommunityClient
    private var sentKey: String?
    private var sentAt: Date?
    private var waiting: Task<Void, Never>?

    init(community: RPMCommunityClient) { self.community = community }

    func note(_ track: CloudTrack?) {
        waiting?.cancel()
        waiting = nil

        guard let track, let title = track.title, !title.isEmpty else {
            guard sentKey != nil else { return }
            sentKey = nil
            sentAt = nil
            Task { try? await community.clearListening() }
            return
        }

        let song = RPMSong(artist: track.artist ?? "", title: title, album: track.album ?? "", albumId: nil)
        let key = song.artist + "\u{1F}" + song.title
        let now = Date()
        if key == sentKey, let sentAt, now.timeIntervalSince(sentAt) < 20 * 60 { return }

        let wait = sentAt.map { max(0, 60 - now.timeIntervalSince($0)) } ?? 0
        waiting = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled, let self else { return }
            self.sentKey = key
            self.sentAt = Date()
            try? await self.community.setListening(song)
        }
    }
}
