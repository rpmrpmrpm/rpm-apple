import SwiftUI
import RPMKit

/// What the thread page asks its owner to do.
public struct ThreadActions {
    public var onClose: () -> Void = {}
    public var onSend: () -> Void = {}
    /// Chooses what the box answers: a reply, or nil for the post itself.
    public var onReplyTo: (RPMReply?) -> Void = { _ in }
    public var onVotePost: (Int) -> Void = { _ in }
    public var onVote: (RPMReply, Int) -> Void = { _, _ in }
    public var onDelete: (RPMReply) -> Void = { _ in }
    public var onReport: (RPMReply) -> Void = { _ in }
    /// Opens the page of the person with this user id.
    public var onOpenPerson: (String) -> Void = { _ in }

    public init() {}
}

/// One post and every reply under it, as a sheet. Replies are indented by how deep they are, up to
/// ``deepest`` steps, so a long thread still has room for its text on a phone.
public struct ThreadPage: View {
    private let post: RPMPost
    private let lines: [RPMReplyTree.Line]
    private let answered: Bool
    private let trouble: String?
    private let sending: Bool
    @Binding private var draft: String
    private let replyingTo: RPMReply?
    private let readerId: String
    private let isPageOwner: Bool
    private let pictureOf: (String, Bool) -> URL?
    private let ownerPhoto: URL?
    private let actions: ThreadActions

    /// The page owner's chosen background (``RPMProfile/pageGround``), as on the page the thread
    /// belongs to.
    private let ground: String

    /// The post's author wears the supporter's mark: their name is in gold.
    private let ownerSupporter: Bool

    /// - Parameters:
    ///   - readerId: the reader's user id, to tell their own replies from other people's.
    ///   - isPageOwner: the reader owns the page. The owner can delete any reply on it.
    ///   - pictureOf: the address of a person's photo, from their user id and whether they have one.
    public init(post: RPMPost, lines: [RPMReplyTree.Line], answered: Bool, trouble: String?,
                sending: Bool, draft: Binding<String>, replyingTo: RPMReply?,
                readerId: String, isPageOwner: Bool,
                pictureOf: @escaping (String, Bool) -> URL?, ownerPhoto: URL?,
                actions: ThreadActions, ground: String = "", ownerSupporter: Bool = false) {
        self.post = post
        self.lines = lines
        self.answered = answered
        self.trouble = trouble
        self.sending = sending
        self._draft = draft
        self.replyingTo = replyingTo
        self.readerId = readerId
        self.isPageOwner = isPageOwner
        self.pictureOf = pictureOf
        self.ownerPhoto = ownerPhoto
        self.actions = actions
        self.ground = ground
        self.ownerSupporter = ownerSupporter
    }

    /// Replies deeper than this are drawn at this depth.
    private static let deepest = 5
    private static let step: CGFloat = 16

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                CloseKey(action: actions.onClose)
            }
            .padding(.horizontal, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    head

                    if let trouble {
                        quiet(trouble)
                    } else if !answered {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }

                    ForEach(lines) { line in
                        row(line)
                            .padding(.leading, CGFloat(min(line.depth, Self.deepest)) * Self.step)
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            box
        }
        .background { PageGroundView(wire: ground) }
    }

    // ── the post ──

    private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                PersonPicture(ownerPhoto, name: post.authorShown, size: 40)
                    .onTapGesture { actions.onOpenPerson(post.ownerId) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.authorShown)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(post.authorSupporter || ownerSupporter ? RPMInk.gold : .white)
                    Text(post.written.formatted(.relative(presentation: .named)))
                        .font(RPMFont.display(11))
                        .foregroundStyle(RPMInk.white(0x77 / 255))
                }
            }

            Text(post.body)
                .font(RPMFont.display(15))
                .foregroundStyle(RPMInk.white(0xEE / 255))
                .fixedSize(horizontal: false, vertical: true)

            if let song = post.song {
                HStack(spacing: 6) {
                    Text(Glyph.play).font(RPMFont.icon(9))
                    Text(songLine(song)).font(RPMFont.display(12)).lineLimit(1)
                }
                .foregroundStyle(RPMInk.white(0xAA / 255))
            }

            // The thumbs start where the text starts; the replies stand at the right.
            HStack(spacing: 0) {
                VoteKeys(ups: post.ups, downs: post.downs, mine: post.myVote,
                         enabled: post.ownerId != readerId, onVote: actions.onVotePost)
                Spacer(minLength: 0)
                ReplyKey(count: 0) { actions.onReplyTo(nil) }
            }
        }
        .padding(.bottom, 6)
    }

    // ── one reply ──

    private func row(_ line: RPMReplyTree.Line) -> some View {
        let reply = line.reply
        let mine = reply.userId == readerId

        return HStack(alignment: .top, spacing: 8) {
            if line.depth > 0 {
                Rectangle()
                    .fill(RPMInk.white(0x22 / 255))
                    .frame(width: 2)
            }

            VStack(alignment: .leading, spacing: 4) {
                if reply.deleted {
                    Text(Loc.get("Rpm_Profile_ReplyDeleted"))
                        .font(RPMFont.display(13))
                        .italic()
                        .foregroundStyle(RPMInk.white(0x77 / 255))
                } else {
                    HStack(spacing: 8) {
                        PersonPicture(reply.authorDeleted ? nil : pictureOf(reply.userId, reply.hasAvatar),
                                      name: reply.authorShown, size: 26)
                        Byline(name: reply.authorShown, millis: reply.createdAt, gold: reply.authorSupporter)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if !reply.authorDeleted { actions.onOpenPerson(reply.userId) } }

                    Text(reply.body)
                        .font(RPMFont.display(14))
                        .foregroundStyle(RPMInk.white(0xE6 / 255))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 0) {
                        VoteKeys(ups: reply.ups, downs: reply.downs, mine: reply.myVote, enabled: !mine) {
                            actions.onVote(reply, $0)
                        }
                        Spacer(minLength: 0)
                        ReplyKey(count: 0) { actions.onReplyTo(reply) }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !reply.deleted {
                Menu {
                    if mine || isPageOwner {
                        Button(Loc.get("Rpm_Profile_DeleteReply"), role: .destructive) { actions.onDelete(reply) }
                    }
                    if !mine {
                        Button(Loc.get("Rpm_Profile_ReportReply")) { actions.onReport(reply) }
                    }
                } label: {
                    MoreKey()
                }
                .accessibilityLabel(Loc.get("Common_MoreOptions"))
            }
        }
        .padding(.vertical, 6)
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(RPMFont.display(13))
            .foregroundStyle(RPMInk.white(0x88 / 255))
    }

    // ── the reply box ──

    private var canSend: Bool {
        !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var box: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Which reply the box answers, with a cross to answer the post instead.
            if let replyingTo {
                HStack(spacing: 6) {
                    Text(Loc.get("Rpm_Profile_Reply") + ": " + replyingTo.authorShown)
                        .font(RPMFont.display(12))
                        .foregroundStyle(RPMInk.white(0x99 / 255))
                        .lineLimit(1)
                    Button { actions.onReplyTo(nil) } label: {
                        Text(Glyph.close)
                            .font(RPMFont.icon(11))
                            .foregroundStyle(RPMInk.white(0x99 / 255))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Loc.get("Common_Cancel"))
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("", text: $draft,
                          prompt: Text(Loc.get("Rpm_Profile_ReplyPrompt"))
                              .foregroundStyle(RPMInk.white(0x66 / 255)),
                          axis: .vertical)
                    .lineLimit(1...5)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .tint(.white)
                    .padding(.vertical, 6)
                    .onChange(of: draft) { _, typed in
                        if typed.count > RPMCommunityClient.longestWallPost {
                            draft = String(typed.prefix(RPMCommunityClient.longestWallPost))
                        }
                    }

                Button(action: actions.onSend) {
                    if sending {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        Text(Loc.get("Album_Send"))
                    }
                }
                .buttonStyle(RPMGlassButton(.primary, radius: 15, height: 32,
                                            stretches: false, inset: 14, size: 13))
                .disabled(!canSend)
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
        .padding(.horizontal, RPMLayout.margin)
        .padding(.bottom, 8)
    }
}
