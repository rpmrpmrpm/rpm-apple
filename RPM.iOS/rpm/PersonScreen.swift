import SwiftUI
import RPMKit
import RPMUI
import RPMAudio
import RPMLibrary

/// One person's page with everything that opens from it: a post's thread, a review read in full, the notifications,
/// the edit page, and the report panel. The reader's own page and anyone else's both rise over the app (see
/// `RootView`).
struct PersonScreen: View {
    let page: PersonPage
    let model: AppModel

    /// The reader's notifications; nil on someone else's page.
    let notices: Notices?

    let onBack: () -> Void
    let onOpenPerson: (String) -> Void
    let onOpenAlbum: (CloudAlbum) -> Void

    /// The badges the reader's own collection unlocks, worked out on this phone. Empty on someone else's page.
    var ownBadges: [String] = []

    /// The photos the sample people borrow, by user id. Empty outside a sample.
    var faces: [String: URL] = [:]

    /// Finds a reviewed record's cover.
    let coverFor: ReviewCoverSource

    @State private var showingNotices = false
    @State private var edit: ProfileEdit?
    @State private var readingReview: String?

    /// A photo of the artist the owner is playing, for a banner that follows what they play.
    @State private var playingPhoto: URL?
    @State private var reportingPost: RPMPost?
    @State private var reportingReply: RPMReply?

    var body: some View {
        @Bindable var bound = page

        ProfilePage(profile: page.profile, isOwn: page.isOwn, photo: photo,
                    banner: follows ? playingPhoto : page.banner,
                    feed: page.feed, answered: page.answered, trouble: page.trouble,
                    hasMore: page.next != nil, unread: notices?.unread ?? 0,
                    playing: playing, sending: page.sending,
                    draft: $bound.draft, withSong: $bound.withSong,
                    coverFor: coverFor,
                    actions: actions, isSample: page.isSample, supporter: supporter)
            .task(id: page.profile?.listening?.artist) {
                guard let listening = page.profile?.listening else { playingPhoto = nil; return }
                playingPhoto = try? await model.cloud.artistPictures(artist: listening.artist,
                                                                     album: listening.album).backdrops.first
            }
            .task(id: page.userId) {
                await page.read()
                if let post = page.pendingPost {
                    page.pendingPost = nil
                    await page.open(post)
                }
                // The badges are sent from the root once the page is read (`BadgesAsked` in
                // `RootView`), which reads the count again after them.
                await notices?.readUnread()
                openWhereTheScriptAsked()
            }
            .overlay {
                if let post = reportingPost {
                    ReportSheet(prompt: Loc.get("Album_ReportCommentPrompt"),
                                onSend: { note in await page.report(post, note: note) },
                                onClose: { reportingPost = nil })
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: reportingPost)
            .alert(page.editTrouble ?? "", isPresented: Binding(
                get: { page.editTrouble != nil && edit == nil },
                set: { if !$0 { page.editTrouble = nil } })) {
                Button(Loc.get("Common_Cancel"), role: .cancel) {}
            }
            .sheet(isPresented: Binding(get: { page.openPost != nil },
                                        set: { if !$0 { page.closeThread() } })) {
                thread
            }
            .sheet(isPresented: $showingNotices) { notifications }
            .sheet(isPresented: Binding(get: { readingReview != nil }, set: { if !$0 { readingReview = nil } })) {
                review
            }
            .fullScreenCover(isPresented: Binding(get: { edit != nil }, set: { if !$0 { edit = nil } })) {
                editPage
            }
    }

    /// Opens the notifications or the edit page on the reader's own page, so that a script can show them. The
    /// simulator accepts no taps. Debug only: a release build does not read this.
    private func openWhereTheScriptAsked() {
        #if DEBUG
        guard page.isOwn else { return }
        switch ProcessInfo.processInfo.environment["RPM_PROFILE_OPEN"] {
        case "notifications": showingNotices = true
        case "edit": edit = ProfileEdit(profile: page.profile, isSample: page.isSample)
        default: break
        }
        #endif
    }

    /// The owner's photo: their own, or on a sample person's page the photo they borrow.
    private var photo: URL? { page.photo ?? faces[page.userId] }

    /// Whether the banner is the playing artist's photo: when the owner chose that, and on the sample page unless a
    /// photo was chosen there.
    private var follows: Bool {
        page.profile?.bannerFollowsListening == true || (page.isSample && page.profile?.bannerSource != "photo")
    }

    /// Whether the page's owner wears the supporter's mark. The reader's own profile does not say;
    /// their plan does. The sample page shows it, so the look can be seen.
    private var supporter: Bool {
        page.profile?.supporter == true || (page.isOwn && model.quota?.wearsMark == true) || page.isSample
    }

    /// The song on this phone now, for the post box's switch.
    private var playing: RPMSong? {
        guard let track = model.player.current, let title = track.title, !title.isEmpty else { return nil }
        return RPMSong(artist: track.artist ?? "", title: title, album: track.album ?? "", albumId: nil)
    }

    private var actions: ProfileActions {
        var actions = ProfileActions()
        actions.onBack = onBack
        actions.onNotifications = { showingNotices = true }
        actions.onEditPage = { edit = ProfileEdit(profile: page.profile, isSample: page.isSample) }
        actions.onFriend = { step in Task { await page.friend(step) } }
        actions.onBlock = { Task { await page.block() } }
        actions.onUnblock = { Task { await page.unblock() } }
        actions.onSend = { Task { await page.post(song: playing) } }
        actions.onVote = { post, value in Task { await page.vote(post, value) } }
        actions.onVoteReview = { review, value in Task { await page.voteReview(review, value) } }
        actions.onOpenPost = { post in Task { await page.open(post) } }
        actions.onDeletePost = { post in Task { await page.delete(post) } }
        actions.onReportPost = { reportingPost = $0 }
        actions.onReadReview = { readingReview = RPMFeedItem.review($0).id }
        actions.onMore = { Task { await page.more() } }
        actions.onRefresh = { await page.read() }
        return actions
    }

    // ── the edit page ──

    @ViewBuilder
    private var editPage: some View {
        if let edit {
            EditPage(edit: edit, profile: page.profile, photo: photo, banner: page.banner, playingPhoto: playingPhoto,
                     unlocked: Array(Set(page.profile?.badges ?? []).union(ownBadges)),
                     trouble: page.editTrouble, saving: page.saving,
                     onSave: { Task { if await page.save(edit, ownBadges: ownBadges) { self.edit = nil } } },
                     onClose: {
                         page.editTrouble = nil
                         self.edit = nil
                     })
        }
    }

    // ── a review read in full ──

    @ViewBuilder
    private var review: some View {
        // Looked up in the feed each time, so a vote on it shows at once.
        let found = page.feed.lazy.compactMap { item -> RPMFeedReview? in
            if case .review(let shown) = item, item.id == readingReview { return shown }
            return nil
        }.first
        if let shown = found {
            let album = model.album(for: shown)
            ReviewPage(shown: shown, isOwn: page.isOwn, author: nil, coverFor: coverFor,
                       ground: page.profile?.pageGround ?? "",
                       onVote: { value in Task { await page.voteReview(shown.review, value) } },
                       onOpenAlbum: album.map { found in { readingReview = nil; onOpenAlbum(found) } },
                       onClose: { readingReview = nil })
        }
    }

    // ── the thread ──

    @ViewBuilder
    private var thread: some View {
        @Bindable var bound = page

        if let post = page.openPost {
            ThreadPage(post: post, lines: page.replyLines, answered: page.threadAnswered,
                       trouble: page.threadTrouble, sending: page.replying,
                       draft: $bound.replyDraft, replyingTo: page.replyingTo,
                       readerId: model.who?.userId ?? "", isPageOwner: page.isOwn,
                       pictureOf: { model.community.avatar(userId: $0, hasAvatar: $1) ?? faces[$0] },
                       ownerPhoto: photo, actions: threadActions,
                       ground: page.profile?.pageGround ?? "", ownerSupporter: supporter)
                .overlay {
                    if let reply = reportingReply {
                        ReportSheet(prompt: Loc.get("Album_ReportCommentPrompt"),
                                    onSend: { note in await page.reportReply(reply, note: note) },
                                    onClose: { reportingReply = nil })
                            .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.18), value: reportingReply)
        }
    }

    private var threadActions: ThreadActions {
        var actions = ThreadActions()
        actions.onClose = { page.closeThread() }
        actions.onSend = { Task { await page.sendReply() } }
        actions.onReplyTo = { page.replyingTo = $0 }
        actions.onVotePost = { value in
            if let post = page.openPost { Task { await page.vote(post, value) } }
        }
        actions.onVote = { reply, value in Task { await page.voteReply(reply, value) } }
        actions.onDelete = { reply in Task { await page.deleteReply(reply) } }
        actions.onReport = { reportingReply = $0 }
        actions.onOpenPerson = { userId in
            guard userId != page.userId else { return }
            page.closeThread()
            openAfterSheet(userId)
        }
        return actions
    }

    // ── notifications ──

    @ViewBuilder
    private var notifications: some View {
        if let notices {
            NotificationsPage(items: notices.items, answered: notices.answered, trouble: notices.trouble,
                              hasMore: notices.next != nil,
                              pictureOf: { model.community.avatar(userId: $0, hasAvatar: $1) ?? faces[$0] },
                              actions: noticeActions(notices))
                .task { await notices.read() }
        }
    }

    private func noticeActions(_ notices: Notices) -> NotificationsActions {
        var actions = NotificationsActions()
        actions.onClose = { showingNotices = false }
        actions.onAccept = { userId in Task { await notices.answer(userId, accept: true) } }
        actions.onDecline = { userId in Task { await notices.answer(userId, accept: false) } }
        actions.onMore = { Task { await notices.more() } }
        actions.onOpen = { note in open(note) }
        return actions
    }

    /// Opens a person's page once the sheet that asked for it has gone. SwiftUI shows one sheet at
    /// a time from one place, and a page asked for while another sheet closes is dropped.
    private func openAfterSheet(_ userId: String) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            onOpenPerson(userId)
        }
    }

    /// Opens what a notification is about. A reply or a vote opens the post, when it is on the
    /// part of the page that has been read; a badge opens the edit page, where it can be chosen; everything else
    /// opens the person who caused it.
    private func open(_ note: RPMNotification) {
        showingNotices = false
        switch note.kind {
        case .reply, .vote:
            let found = page.feed.lazy.compactMap { item -> RPMPost? in
                if case .post(let post) = item, post.postId == note.postId { return post }
                return nil
            }.first
            if let found { Task { await page.open(found) } }
        case .badge:
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                edit = ProfileEdit(profile: page.profile, isSample: page.isSample)
            }
        case .friendRequest, .friendAccepted, .friendReview:
            if !note.fromUserId.isEmpty { openAfterSheet(note.fromUserId) }
        case .other:
            break
        }
    }
}
