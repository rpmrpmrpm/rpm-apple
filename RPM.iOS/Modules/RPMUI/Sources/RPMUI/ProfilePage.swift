import SwiftUI
import RPMKit

/// What a key on someone else's page does to the friendship.
public enum FriendStep: Sendable {
    case add, cancel, accept, decline, remove
}

/// What the profile page asks its owner to do. Every action starts as one that does nothing, and
/// the caller sets the ones that apply: the own page has no Add friend, another person's page has
/// no post box.
public struct ProfileActions {
    /// Nil when the page has no back key.
    public var onBack: (() -> Void)?
    public var onNotifications: () -> Void = {}
    public var onEditPage: () -> Void = {}
    public var onFriend: (FriendStep) -> Void = { _ in }
    public var onBlock: () -> Void = {}
    public var onUnblock: () -> Void = {}
    public var onSend: () -> Void = {}
    public var onVote: (RPMPost, Int) -> Void = { _, _ in }
    public var onVoteReview: (RPMReview, Int) -> Void = { _, _ in }
    /// Opens a post with its replies.
    public var onOpenPost: (RPMPost) -> Void = { _ in }
    public var onDeletePost: (RPMPost) -> Void = { _ in }
    public var onReportPost: (RPMPost) -> Void = { _ in }
    /// Opens a review whole: Read full review.
    public var onReadReview: (RPMFeedReview) -> Void = { _ in }
    /// Reads the next page of the feed.
    public var onMore: () -> Void = {}
    public var onRefresh: () async -> Void = {}

    public init() {}
}

/// A person's page: their banner and photo, name, badge, collection counts, what they are playing, and their posts
/// and reviews, newest first. The same page is the reader's own (``isOwn``) and the page of anyone else, opened from
/// a name. It is the Android app's `ProfileScreen`.
///
/// Every entry in the feed is the page owner's own: only the owner posts on their page, and the
/// reviews are the ones they wrote. So every row uses the owner's name and photo.
public struct ProfilePage: View {
    private let profile: RPMProfile?
    private let isOwn: Bool
    private let photo: URL?
    private let banner: URL?
    private let feed: [RPMFeedItem]
    private let answered: Bool
    private let trouble: String?
    private let hasMore: Bool
    private let unread: Int
    private let playing: RPMSong?
    private let sending: Bool
    @Binding private var draft: String
    @Binding private var withSong: Bool
    private let coverFor: ReviewCoverSource
    private let actions: ProfileActions

    /// The page shows the sample posts of a test build. See ``RPMProfileSample``.
    private let isSample: Bool

    /// Whether the owner wears the supporter's mark: the gold name, the heart, the gold ring and the glow. The caller
    /// decides, because the reader's own profile does not say; their plan does.
    private let supporter: Bool

    @State private var confirmingBlock = false

    /// - Parameters:
    ///   - profile: nil while it is being read.
    ///   - banner: the banner to show: the owner's photo, or the playing artist's when they chose that.
    ///   - answered: whether the feed has been read. False while it is read and after a failed read,
    ///     so a feed that could not be read is not shown as an empty one.
    ///   - playing: the song playing on this phone, for the post box's switch. Nil when nothing is.
    ///   - coverFor: finds a reviewed record's cover.
    public init(profile: RPMProfile?, isOwn: Bool, photo: URL?, banner: URL?,
                feed: [RPMFeedItem], answered: Bool, trouble: String?, hasMore: Bool,
                unread: Int, playing: RPMSong?, sending: Bool,
                draft: Binding<String>, withSong: Binding<Bool>,
                coverFor: @escaping ReviewCoverSource,
                actions: ProfileActions, isSample: Bool = false, supporter: Bool = false) {
        self.profile = profile
        self.isOwn = isOwn
        self.photo = photo
        self.banner = banner
        self.feed = feed
        self.answered = answered
        self.trouble = trouble
        self.hasMore = hasMore
        self.unread = unread
        self.playing = playing
        self.sending = sending
        self._draft = draft
        self._withSong = withSong
        self.coverFor = coverFor
        self.actions = actions
        self.isSample = isSample
        self.supporter = supporter
    }

    /// The height of the banner, under the status bar too.
    private static let bannerTall: CGFloat = 190
    private static let photoSize: CGFloat = 120

    /// How far the photo's centre stands above the banner's foot.
    private static let photoLift: CGFloat = 14

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                top
                    .padding(.bottom, 16)

                VStack(alignment: .leading, spacing: 12) {
                    if isOwn { box }
                    if isSample { Text(Loc.get("Rpm_Profile_SampleNote")).rpmKicker() }
                    rows
                }
                .padding(.horizontal, RPMLayout.margin)
                .padding(.bottom, RPMLayout.foot)
            }
        }
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .top)
        .refreshable { await actions.onRefresh() }
        .background { PageGroundView(wire: profile?.pageGround ?? "") }
        .overlay(alignment: .top) { keys }
        .confirmationDialog(Loc.get("Rpm_Profile_BlockConfirm", profile?.displayName ?? ""),
                            isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button(Loc.get("Rpm_Profile_Block"), role: .destructive, action: actions.onBlock)
            Button(Loc.get("Common_Cancel"), role: .cancel) {}
        }
    }

    // ── the top: banner, photo, name and the lines under it ──

    private var top: some View {
        VStack(spacing: 0) {
            // The height is on the stack and not on the banner: a page without a banner has no
            // banner view, and a frame on no view takes no room, which would lift the photo
            // under the status bar.
            ZStack(alignment: .bottom) {
                // The banner is an overlay on an empty view, so it takes the stack's size and gives
                // none of its own. A filled picture reports its scaled size: a wide photo would be
                // wider than the screen and make the whole page wider.
                Color.clear
                    .overlay { bannerPicture }
                    .clipped()

                // A supporter's photo has a gold ring and a glow that lights up around it.
                PersonPicture(photo, name: profile?.displayName ?? "", size: Self.photoSize)
                    .overlay {
                        Circle().strokeBorder(supporter ? RPMInk.gold : RPMInk.white(0x33 / 255),
                                              lineWidth: supporter ? 3 : 2)
                    }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.bannerTall + Self.photoSize / 2 - Self.photoLift, alignment: .bottom)

            if let profile {
                HStack(spacing: 8) {
                    // A supporter's name is in gold, with the supporter's heart beside it.
                    Text(profile.displayName)
                        .font(RPMFont.display(22))
                        .foregroundStyle(supporter ? RPMInk.gold : .white)
                        .lineLimit(1)

                    if supporter {
                        Text(Glyph.heart)
                            .font(RPMFont.icon(16))
                            .foregroundStyle(RPMInk.gold)
                            .accessibilityLabel(Loc.get("Rpm_Profile_PlanSupporter"))
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
                // The name sits close under the photo.
                .padding(.top, 8)

                if let badge = RPMProfileBadges.byId(profile.badge) {
                    BadgePill(badge: badge, colour: profile.badgeColour)
                        .padding(.top, 6)
                }

                // The counts and the date as one block of two lines, close together.
                VStack(spacing: 0) {
                    if let counts = counts(profile) {
                        Text(counts).rpmKicker()
                    }

                    if profile.createdAt > 0 {
                        Text(Loc.get("Rpm_Profile_MemberSince", since(profile.createdAt)))
                            .font(RPMFont.display(12))
                            .foregroundStyle(RPMInk.white(0x88 / 255))
                    }
                }
                .padding(.top, 6)

                if let listening = profile.listening {
                    HStack(spacing: 10) {
                        Text(Glyph.play).font(RPMFont.icon(11))
                        Text(Loc.get("Rpm_Profile_NowPlaying", listening.title, listening.artist))
                            .font(RPMFont.display(14))
                            .lineLimit(1)
                    }
                    .foregroundStyle(RPMInk.white(0xEE / 255))
                    .padding(.horizontal, RPMLayout.margin)
                    .padding(.vertical, 4)
                    .padding(.top, 12)
                }

                if !isOwn {
                    friendKey(profile).padding(.top, 12)
                }
            }
        }
        // The glow is laid over the lines under the photo too, so it can drift over the name.
        .overlay(alignment: .top) {
            if supporter {
                SupporterSparkles(photo: Self.photoSize)
                    .offset(y: Self.bannerTall - Self.photoLift - Self.photoSize * SupporterSparkles.above)
            }
        }
    }

    /// The banner, as the artist page's photograph: sharp at the top, blurred towards its foot,
    /// and faded out into the page's own background, so it has no lower edge. Nothing without a
    /// banner: the page's background shows.
    @ViewBuilder
    private var bannerPicture: some View {
        if let banner {
            RemotePicture(banner) { image in
                ZStack {
                    filled(image)

                    // The same picture blurred, taking over from the middle down. `opaque` keeps
                    // the blurred edges from going transparent.
                    filled(image)
                        .blur(radius: 24, opaque: true)
                        .mask {
                            LinearGradient(stops: [.init(color: .clear, location: 0.3),
                                                   .init(color: .black, location: 0.75)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                }
                .mask {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: .black, location: 0.45),
                                           .init(color: .clear, location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
            }
        }
    }

    /// The picture filling the banner and cut to it, so the masks run over the banner's height and
    /// not over the picture's own height.
    private func filled(_ image: Image) -> some View {
        Color.clear
            .overlay { image.resizable().scaledToFill() }
            .clipped()
    }

    private func counts(_ profile: RPMProfile) -> String? {
        guard let counts = profile.counts, counts.albums > 0 else { return nil }
        // Grouped as the phone's language groups thousands: "1,610".
        let records = counts.albums == 1 ? Loc.get("Stats_AlbumsOne") : Loc.get("Stats_Albums", counts.albums.formatted())
        let tracks = counts.tracks == 1 ? Loc.get("Rpm_Profile_TracksOne") : Loc.get("Rpm_Queue_Count", counts.tracks.formatted())
        return Loc.get("Rpm_Library_CountsJoin", records, tracks)
    }

    private func since(_ millis: Int64) -> String {
        Date(timeIntervalSince1970: Double(millis) / 1000)
            .formatted(.dateTime.month(.wide).year())
    }

    /// The friendship key under someone else's name. What it says follows the state; the menu key
    /// has the other actions.
    @ViewBuilder
    private func friendKey(_ profile: RPMProfile) -> some View {
        switch profile.friendship {
        case .none:
            key(Loc.get("Rpm_Profile_AddFriend"), .primary) { actions.onFriend(.add) }
        case .requested:
            key(Loc.get("Rpm_Profile_Requested"), .ghost) { actions.onFriend(.cancel) }
        case .incoming:
            HStack(spacing: 10) {
                key(Loc.get("Rpm_Profile_Accept"), .primary) { actions.onFriend(.accept) }
                key(Loc.get("Rpm_Profile_Decline"), .ghost) { actions.onFriend(.decline) }
            }
        case .friends:
            key(Loc.get("Rpm_Profile_Friends"), .ghost) {}
                .allowsHitTesting(false)
        case .own:
            EmptyView()
        }
    }

    private func key(_ title: String, _ weight: RPMGlassButton.Weight,
                     action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(RPMGlassButton(weight, radius: 16, height: 34, stretches: false, inset: 18, size: 13))
    }

    // ── the round keys over the banner ──

    private var keys: some View {
        HStack {
            if let onBack = actions.onBack {
                round(Glyph.back, label: Loc.get("Rpm_Profile_Back"), action: onBack)
            }
            Spacer()
            menu
        }
        .padding(.horizontal, RPMLayout.margin)
        .padding(.top, 4)
    }

    private func round(_ glyph: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { roundFace(glyph) }
            .buttonStyle(.plain)
            .rpmGlass(Circle())
            .accessibilityLabel(label)
    }

    private func roundFace(_ glyph: String) -> some View {
        Text(glyph)
            .font(RPMFont.icon(16))
            .foregroundStyle(RPMInk.white(0xE6 / 255))
            .frame(width: 40, height: 40)
            .contentShape(Circle())
    }

    /// The round menu key: on the reader's own page the notifications and the edit page; on anyone else's the
    /// friendship and the block.
    private var menu: some View {
        Menu {
            if isOwn {
                Button(Loc.get("Rpm_Notify_Title"), action: actions.onNotifications)
                Button(Loc.get("Rpm_Profile_EditPage"), action: actions.onEditPage)
            } else if let profile {
                switch profile.friendship {
                case .requested:
                    Button(Loc.get("Rpm_Profile_CancelRequest")) { actions.onFriend(.cancel) }
                case .friends:
                    Button(Loc.get("Rpm_Profile_RemoveFriend"), role: .destructive) { actions.onFriend(.remove) }
                default:
                    EmptyView()
                }
                if profile.blocked {
                    Button(Loc.get("Rpm_Profile_Unblock"), action: actions.onUnblock)
                } else {
                    Button(Loc.get("Rpm_Profile_Block"), role: .destructive) { confirmingBlock = true }
                }
            }
        } label: {
            roundFace(isOwn ? Glyph.menu : Glyph.more)
                .rpmGlass(Circle())
                .overlay(alignment: .topTrailing) {
                    if isOwn && unread > 0 {
                        Text(unread > 99 ? "99+" : "\(unread)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Capsule().fill(RPMInk.red))
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .accessibilityLabel(Loc.get("Rpm_Profile_Menu"))
        .accessibilityValue(isOwn && unread > 0 ? Loc.get("Rpm_Profile_UnreadCount", unread) : "")
    }

    // ── the post box, on the own page ──

    private var canSend: Bool {
        !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("", text: $draft,
                          prompt: Text(Loc.get("Rpm_Profile_PostPrompt"))
                              .foregroundStyle(RPMInk.white(0x66 / 255)),
                          axis: .vertical)
                    .lineLimit(1...6)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(.vertical, 6)
                    // The server takes no more than this, so a long post is not refused after it
                    // was typed.
                    .onChange(of: draft) { _, typed in
                        if typed.count > RPMCommunityClient.longestWallPost {
                            draft = String(typed.prefix(RPMCommunityClient.longestWallPost))
                        }
                    }

                Button(action: actions.onSend) {
                    if sending {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Text(Loc.get("Rpm_Profile_Post"))
                    }
                }
                .buttonStyle(RPMGlassButton(.primary, radius: 15, height: 32,
                                            stretches: false, inset: 14, size: 13))
                .disabled(!canSend)
            }

            // Only while something plays: there is nothing to add otherwise.
            if let playing {
                Toggle(isOn: $withSong) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Loc.get("Rpm_Profile_WithSong"))
                            .font(RPMFont.display(12))
                            .foregroundStyle(RPMInk.white(0xB3 / 255))
                        Text(songLine(playing))
                            .font(RPMFont.display(11))
                            .foregroundStyle(RPMInk.white(0x77 / 255))
                            .lineLimit(1)
                    }
                }
                .rpmControlTint()
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background {
            let card = RoundedRectangle(cornerRadius: 14, style: .continuous)
            card.fill(RPMInk.white(0x14 / 255))
                .overlay { card.strokeBorder(RPMInk.glassEdge, lineWidth: 1) }
        }
    }

    // ── the feed ──

    @ViewBuilder
    private var rows: some View {
        if profile?.blocked == true {
            VStack(alignment: .leading, spacing: 10) {
                quiet(Loc.get("Rpm_Profile_Blocked"))
                key(Loc.get("Rpm_Profile_Unblock"), .ghost, action: actions.onUnblock)
            }
        } else if let trouble {
            quiet(trouble)
        } else if answered && feed.isEmpty {
            quiet(Loc.get(isOwn ? "Rpm_Profile_FeedEmptyOwn" : "Rpm_Profile_FeedEmpty"))
        } else {
            // Rows and not a list: the page is what scrolls.
            ForEach(feed) { item in
                switch item {
                case .post(let post):
                    PostCard(post: post, photo: photo, isOwn: isOwn,
                             gold: post.authorSupporter || supporter,
                             onVote: { actions.onVote(post, $0) },
                             onOpen: { actions.onOpenPost(post) },
                             onDelete: isOwn ? { actions.onDeletePost(post) } : nil,
                             onReport: isOwn ? nil : { actions.onReportPost(post) })
                case .review(let shown):
                    ReviewCard(shown: shown, isOwn: isOwn, coverFor: coverFor,
                               onVote: { actions.onVoteReview(shown.review, $0) },
                               onRead: { actions.onReadReview(shown) })
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

/// A post as a card, on a profile page and on the Feed tab. It is the Android app's `PostRow`.
///
/// The thumbs start where the text starts and the replies end at the card's inner edge, where the corner key's dots
/// end too. The corner key stands level with the name.
struct PostCard: View {
    let post: RPMPost
    let photo: URL?

    /// The reader's own post: its votes are shown and cannot be pressed.
    let isOwn: Bool

    /// The author's name in gold: a supporter.
    let gold: Bool
    let onVote: (Int) -> Void
    let onOpen: () -> Void
    var onPerson: (() -> Void)?

    /// What the corner menu offers; with neither, the card has no corner key, as on the Feed tab.
    var onDelete: (() -> Void)?
    var onReport: (() -> Void)?

    var body: some View {
        let hasMenu = onDelete != nil || onReport != nil

        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 10) {
                PersonPicture(photo, name: post.authorShown, size: 40)
                    .onTapGesture { (onPerson ?? onOpen)() }

                VStack(alignment: .leading, spacing: 6) {
                    Byline(name: post.authorShown, millis: post.createdAt, gold: gold)
                        .padding(.trailing, hasMenu ? 24 : 0)
                        .contentShape(Rectangle())
                        .onTapGesture { (onPerson ?? onOpen)() }

                    Text(post.body)
                        .font(RPMFont.display(14))
                        .foregroundStyle(RPMInk.white(0xE6 / 255))
                        .fixedSize(horizontal: false, vertical: true)

                    if let song = post.song {
                        HStack(spacing: 6) {
                            Text(Glyph.play).font(RPMFont.icon(9))
                            Text(songLine(song)).font(RPMFont.display(12)).lineLimit(1)
                        }
                        .foregroundStyle(RPMInk.white(0xAA / 255))
                    }

                    HStack(spacing: 0) {
                        VoteKeys(ups: post.ups, downs: post.downs, mine: post.myVote, enabled: !isOwn, onVote: onVote)
                        Spacer(minLength: 0)
                        ReplyKey(count: post.replyCount, action: onOpen)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            // The vote keys are 32 points tall with their marks in the middle, so the foot needs little room of its own.
            .padding(.leading, 14)
            .padding(.trailing, 14)
            .padding(.top, 12)
            .padding(.bottom, 2)

            if hasMenu {
                Menu {
                    if let onDelete {
                        Button(Loc.get("Rpm_Profile_DeletePost"), role: .destructive, action: onDelete)
                    }
                    if let onReport {
                        Button(Loc.get("Artists_WallReport"), action: onReport)
                    }
                } label: {
                    MoreKey()
                }
                .accessibilityLabel(Loc.get("Common_MoreOptions"))
                .padding(.top, 8)
                .padding(.trailing, 3)
            }
        }
        .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RPMInk.white(0x12 / 255)) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

/// "Title by Artist", for a post's song and the post box's switch, as the line under the name says it.
func songLine(_ song: RPMSong) -> String {
    song.artist.isEmpty ? song.title : Loc.get("Rpm_Profile_NowPlaying", song.title, song.artist)
}

/// Thumbs up with the likes beside it, thumbs down with the dislikes: on a post, a review and a
/// reply. The reader's own vote is lit, and a tap on it takes the vote back. On the reader's own
/// post or reply the counts are shown and cannot be pressed: nobody votes on their own. The first
/// thumb starts at the row's own start, where the text above it starts.
struct VoteKeys: View {
    let ups: Int
    let downs: Int
    let mine: Int
    let enabled: Bool
    let onVote: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            key(Glyph.like, ups, 1, Loc.get("Rpm_Profile_Likes", ups), first: true)
            key(Glyph.dislike, downs, -1, Loc.get("Rpm_Profile_Dislikes", downs), first: false)
        }
    }

    private func key(_ glyph: String, _ count: Int, _ value: Int, _ label: String, first: Bool) -> some View {
        let lit = mine == value
        return Button { onVote(lit ? 0 : value) } label: {
            HStack(spacing: 6) {
                Text(glyph).font(RPMFont.icon(13))
                Text("\(count)").font(RPMFont.display(12))
            }
            .foregroundStyle(RPMInk.white(lit ? 0xEE / 255 : 0x99 / 255))
            .padding(.leading, first ? 0 : 8)
            .padding(.trailing, 8)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityAddTraits(lit ? .isSelected : [])
    }
}

/// The speech bubble with how many replies there are, or the word Reply when there are none. Its own end is the
/// row's end.
struct ReplyKey: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(Glyph.comment).font(RPMFont.icon(13)).foregroundStyle(RPMInk.white(0x99 / 255))
                Text(count == 0 ? Loc.get("Rpm_Profile_Reply") : "\(count)")
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0xCC / 255))
            }
            .padding(.leading, 8)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(count == 0 ? Loc.get("Rpm_Profile_Reply")
                            : count == 1 ? Loc.get("Rpm_Profile_RepliesOne")
                            : Loc.get("Rpm_Profile_Replies", count))
    }
}

/// The three dots in a row's corner.
struct MoreKey: View {
    var body: some View {
        Text(Glyph.more)
            .font(RPMFont.icon(13))
            .foregroundStyle(RPMInk.white(0xAA / 255))
            .frame(width: 34, height: 28)
            .contentShape(Rectangle())
    }
}
