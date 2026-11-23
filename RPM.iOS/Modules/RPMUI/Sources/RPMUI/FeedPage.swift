import SwiftUI
import RPMKit

/// What the Feed tab asks its owner to do.
public struct FeedActions {
    /// Opens the reader's own profile page: the key at the top right.
    public var onMyProfile: () -> Void = {}
    /// Opens the page of the person with this user id.
    public var onOpenPerson: (String) -> Void = { _ in }
    /// Opens a post on its author's page, with its replies.
    public var onOpenPost: (RPMPost) -> Void = { _ in }
    public var onVote: (RPMPost, Int) -> Void = { _, _ in }
    public var onVoteReview: (RPMFeedReview, Int) -> Void = { _, _ in }
    /// Opens a review whole: Read full review.
    public var onReadReview: (RPMFeedReview) -> Void = { _ in }
    /// Reads the next page.
    public var onMore: () -> Void = {}
    public var onRefresh: () async -> Void = {}

    public init() {}
}

/// The Feed tab: everyone's posts and album reviews, newest first. Its header is the collection's: the title, a line
/// under it, and its key on a glass capsule at the right; the key opens the reader's own profile page, with a dot
/// while notifications wait. It is the Android app's `FeedScreen`.
///
/// A post's name or photo opens that person's page; the post itself opens on their page with its replies. A review
/// opens whole.
public struct FeedPage: View {
    private let items: [RPMFeedItem]
    private let answered: Bool
    private let trouble: String?
    private let hasMore: Bool
    private let isSample: Bool
    private let readerId: String
    private let unread: Int
    private let pictureOf: (String, Bool) -> URL?
    private let coverFor: ReviewCoverSource
    private let actions: FeedActions

    /// - Parameters:
    ///   - readerId: the reader's user id, so their own posts and reviews cannot be voted on.
    ///   - unread: how many notifications wait, for the dot on the profile key.
    ///   - pictureOf: the address of a person's photo, from their user id and whether they have one.
    public init(items: [RPMFeedItem], answered: Bool, trouble: String?, hasMore: Bool, isSample: Bool,
                readerId: String, unread: Int, pictureOf: @escaping (String, Bool) -> URL?,
                coverFor: @escaping ReviewCoverSource, actions: FeedActions) {
        self.items = items
        self.answered = answered
        self.trouble = trouble
        self.hasMore = hasMore
        self.isSample = isSample
        self.readerId = readerId
        self.unread = unread
        self.pictureOf = pictureOf
        self.coverFor = coverFor
        self.actions = actions
    }

    public var body: some View {
        VStack(spacing: 0) {
            DissolvingScroll {
                LazyVStack(alignment: .leading, spacing: 12) {
                    rows
                }
                // The first answer fades in over the waiting wheel, so the page does not change at
                // once some time after it has slid in. A later read, such as a pull to refresh,
                // changes the rows without this.
                .animation(.easeOut(duration: 0.25), value: settled)
                .padding(.horizontal, RPMLayout.margin)
                .padding(.top, 4)
                .padding(.bottom, RPMLayout.foot)
            }
            .refreshable { await actions.onRefresh() }
            .frame(maxHeight: .infinity)
            .scrollsUnder { header }
        }
        .background { VinylGround() }
    }

    private var header: some View {
        PageHeading(Loc.get("Rpm_Tab_Feed"), line: isSample ? Loc.get("Rpm_Profile_SampleNote") : "") {
            Button(action: actions.onMyProfile) {
                Text(Glyph.profile)
                    .font(RPMFont.icon(16))
                    .foregroundStyle(RPMInk.white(0xB8 / 255))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .rpmGlassGroup()
            .overlay(alignment: .topTrailing) {
                if unread > 0 {
                    Circle().fill(RPMInk.red).frame(width: 10, height: 10).offset(x: 2, y: -2)
                }
            }
            .accessibilityLabel(Loc.get("Rpm_Feed_MyProfile"))
            .accessibilityValue(unread > 0 ? Loc.get("Rpm_Profile_UnreadCount", unread) : "")
        }
        .padding(.leading, RPMLayout.margin)
        .padding(.trailing, 16)
        .padding(.bottom, 10)
    }

    /// Whether the first read has ended, with the posts or with trouble.
    private var settled: Bool { answered || trouble != nil }

    @ViewBuilder
    private var rows: some View {
        if let trouble {
            quiet(trouble)
        } else if answered && items.isEmpty {
            quiet(Loc.get("Rpm_Feed_Empty"))
        } else if !answered && items.isEmpty {
            // The first read is not answered yet. The wheel stands where the posts will be.
            ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
        } else {
            ForEach(items) { item in
                switch item {
                case .post(let post):
                    PostCard(post: post, photo: pictureOf(post.ownerId, post.hasAvatar),
                             isOwn: post.ownerId == readerId, gold: post.authorSupporter,
                             onVote: { actions.onVote(post, $0) },
                             onOpen: { actions.onOpenPost(post) },
                             onPerson: { actions.onOpenPerson(post.ownerId) })
                case .review(let shown):
                    let review = shown.review
                    ReviewCard(shown: shown, isOwn: review.userId == readerId, coverFor: coverFor,
                               onVote: { actions.onVoteReview(shown, $0) },
                               onRead: { actions.onReadReview(shown) }) {
                        ReviewAuthor(shown: shown, photo: pictureOf(review.userId, review.hasAvatar)) {
                            actions.onOpenPerson(review.userId)
                        }
                    }
                }
            }

            if hasMore {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .onAppear(perform: actions.onMore)
            }
        }
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(RPMFont.display(13))
            .foregroundStyle(RPMInk.white(0x88 / 255))
            .fixedSize(horizontal: false, vertical: true)
    }
}
