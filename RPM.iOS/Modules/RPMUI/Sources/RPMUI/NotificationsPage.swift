import SwiftUI
import RPMKit

/// What the notifications page asks its owner to do.
public struct NotificationsActions {
    public var onClose: () -> Void = {}
    /// Opens what a notification is about: the post, the person, or the album.
    public var onOpen: (RPMNotification) -> Void = { _ in }
    public var onAccept: (String) -> Void = { _ in }
    public var onDecline: (String) -> Void = { _ in }
    public var onMore: () -> Void = {}

    public init() {}
}

/// The caller's notifications, newest first: replies, votes, friend requests, accepted requests,
/// friends' reviews and badges unlocked. Unread ones have a dot. A kind this build does not know is left out.
public struct NotificationsPage: View {
    private let items: [RPMNotification]
    private let answered: Bool
    private let trouble: String?
    private let hasMore: Bool
    private let pictureOf: (String, Bool) -> URL?
    private let actions: NotificationsActions

    public init(items: [RPMNotification], answered: Bool, trouble: String?, hasMore: Bool,
                pictureOf: @escaping (String, Bool) -> URL?, actions: NotificationsActions) {
        self.items = items
        self.answered = answered
        self.trouble = trouble
        self.hasMore = hasMore
        self.pictureOf = pictureOf
        self.actions = actions
    }

    private var shown: [RPMNotification] {
        items.filter { if case .other = $0.kind { false } else { true } }
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                PageTitle(Loc.get("Rpm_Notify_Title"))
                Spacer()
                Button(action: actions.onClose) {
                    Text(Glyph.close)
                        .font(RPMFont.icon(15))
                        .foregroundStyle(RPMInk.white(0xCC / 255))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Loc.get("Common_Cancel"))
            }
            .padding(.horizontal, RPMLayout.margin)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if let trouble {
                        quiet(trouble)
                    } else if answered && shown.isEmpty {
                        quiet(Loc.get("Rpm_Notify_Empty"))
                    } else if !answered {
                        ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 16)
                    }

                    ForEach(shown) { row($0) }

                    if hasMore {
                        ProgressView()
                            .tint(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .onAppear(perform: actions.onMore)
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .background { VinylGround() }
    }

    private func row(_ note: RPMNotification) -> some View {
        HStack(alignment: .top, spacing: 10) {
            PersonPicture(pictureOf(note.fromUserId, note.fromHasAvatar), name: note.fromName, size: 36)

            VStack(alignment: .leading, spacing: 6) {
                Text(said(note))
                    .font(RPMFont.display(14))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)

                Text(note.written.formatted(.relative(presentation: .named)))
                    .font(RPMFont.display(11))
                    .foregroundStyle(RPMInk.white(0x77 / 255))

                if note.kind == .friendRequest {
                    HStack(spacing: 10) {
                        Button(Loc.get("Rpm_Profile_Accept")) { actions.onAccept(note.fromUserId) }
                            .buttonStyle(RPMGlassButton(.primary, radius: 14, height: 30,
                                                        stretches: false, inset: 14, size: 12))
                        Button(Loc.get("Rpm_Profile_Decline")) { actions.onDecline(note.fromUserId) }
                            .buttonStyle(RPMGlassButton(.ghost, radius: 14, height: 30,
                                                        stretches: false, inset: 14, size: 12))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !note.read {
                Circle().fill(RPMInk.red).frame(width: 8, height: 8).padding(.top, 6)
                    .accessibilityHidden(true)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(RPMInk.white(note.read ? 0x10 / 255 : 0x1C / 255))
        }
        .contentShape(Rectangle())
        .onTapGesture { actions.onOpen(note) }
    }

    private func said(_ note: RPMNotification) -> String {
        let who = note.fromName.isEmpty ? Loc.get("Community_DeletedUser") : note.fromName
        switch note.kind {
        case .reply: return Loc.get("Rpm_Notify_Reply", who)
        case .vote: return note.count > 1 ? Loc.get("Rpm_Notify_Votes", note.count) : Loc.get("Rpm_Notify_Vote", who)
        case .friendRequest: return Loc.get("Rpm_Notify_FriendRequest", who)
        case .friendAccepted: return Loc.get("Rpm_Notify_FriendAccepted", who)
        case .friendReview: return Loc.get("Rpm_Notify_FriendReview", who, note.albumTitle ?? "")
        case .badge:
            return note.badgeId.flatMap(RPMProfileBadges.byId).map { Loc.get("Rpm_Notify_Badge", $0.name) } ?? ""
        case .other: return ""
        }
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(RPMFont.display(13))
            .foregroundStyle(RPMInk.white(0x88 / 255))
            .fixedSize(horizontal: false, vertical: true)
    }
}
