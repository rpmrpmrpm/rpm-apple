import SwiftUI
import RPMKit

/// One line on an artist's wall as the page draws it: the line, and whether the reader wrote it.
public struct WallFace: Identifiable, Sendable {
    public let entry: RPMWallEntry

    /// Whether the reader wrote this line, as a post or as a review. The reader can delete their own
    /// post, and cannot report anything of their own.
    public let mine: Bool

    public var id: String { entry.entryId }

    public init(entry: RPMWallEntry, mine: Bool) {
        self.entry = entry
        self.mine = mine
    }
}

/// What listeners wrote about an artist, at the foot of the artist's page: a box to write in, and
/// the lines, newest first. The phone version of the wall card in
/// `RPM.Desktop/Presentation/Main/Artists/ArtistDetailView.xaml`.
///
/// The box is there from the start, before the wall has been read and when it is empty, because
/// the first post is what creates the artist's entry. Under it is one of three things: nothing
/// while the wall is being read, the empty line once it is read with nothing on it, or ``trouble``
/// when it could not be read. A wall that could not be read is never shown as an empty one.
public struct ArtistWallSection: View {
    private let lines: [WallFace]
    private let answered: Bool
    private let trouble: String?
    private let sending: Bool
    @Binding private var draft: String
    private let onSend: () -> Void
    private let onDelete: (RPMWallEntry) -> Void
    private let onReport: (RPMWallEntry) -> Void

    /// - Parameters:
    ///   - answered: whether the wall has been read. False while it is being read, and after a
    ///     read that failed.
    ///   - trouble: why the wall could not be read or written, or nil.
    ///   - draft: what is typed in the box. It is held by the caller, so a page that is built again
    ///     keeps it.
    public init(lines: [WallFace], answered: Bool, trouble: String?, sending: Bool,
                draft: Binding<String>,
                onSend: @escaping () -> Void,
                onDelete: @escaping (RPMWallEntry) -> Void,
                onReport: @escaping (RPMWallEntry) -> Void) {
        self.lines = lines
        self.answered = answered
        self.trouble = trouble
        self.sending = sending
        self._draft = draft
        self.onSend = onSend
        self.onDelete = onDelete
        self.onReport = onReport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Loc.get("Artists_Wall"))
                .rpmKicker()
                .textCase(.uppercase)

            box

            if let trouble {
                Text(trouble)
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0x99 / 255))
            } else if answered && lines.isEmpty {
                Text(Loc.get("Artists_WallEmpty"))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
            }

            // Rows and not a list, for the reason the album page's reviews give: the page is what
            // scrolls.
            ForEach(lines) { face in
                row(face)
            }
        }
        .padding(.horizontal, RPMLayout.margin)
    }

    // ── the box ──

    private var canSend: Bool {
        !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var box: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("", text: $draft,
                      prompt: Text(Loc.get("Artists_WallPlaceholder"))
                          .foregroundStyle(RPMInk.white(0x66 / 255)),
                      axis: .vertical)
                .lineLimit(1...6)
                .font(RPMFont.display(15))
                .foregroundStyle(.white)
                .tint(.white)
                .padding(.vertical, 6)
                // The server takes no more than this. The box stops there, so a long post is not
                // refused after it was typed.
                .onChange(of: draft) { _, typed in
                    if typed.count > RPMCommunityClient.longestWallPost {
                        draft = String(typed.prefix(RPMCommunityClient.longestWallPost))
                    }
                }

            Button(action: onSend) {
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
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background {
            let card = RoundedRectangle(cornerRadius: 14, style: .continuous)
            card.fill(RPMInk.white(0x14 / 255))
                .overlay { card.strokeBorder(RPMInk.glassEdge, lineWidth: 1) }
        }
    }

    // ── one line ──

    private func row(_ face: WallFace) -> some View {
        let entry = face.entry

        return HStack(alignment: .top, spacing: 10) {
            // The letter their name starts with, as on the album page's reviews.
            Text(initial(entry))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RPMInk.white(0xDD / 255))
                .frame(width: 32, height: 32)
                .background(Circle().fill(RPMInk.white(0x26 / 255)))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(entry.authorShown)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(when(entry))
                        .font(RPMFont.display(11))
                        .foregroundStyle(RPMInk.white(0x77 / 255))
                        .lineLimit(1)
                }

                Text(entry.line)
                    .font(RPMFont.display(14))
                    .foregroundStyle(RPMInk.white(entry.isPost ? 0xE6 / 255 : 0xBB / 255))
                    .fixedSize(horizontal: false, vertical: true)

                // Only on a review line. A post has no rating, and empty stars under a post would
                // read as a rating of zero.
                if entry.isReview && entry.rating > 0 {
                    StarRating(entry.stars, size: 11)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            menu(face)
        }
        .padding(.leading, 14)
        .padding(.trailing, 4)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RPMInk.white(0x12 / 255))
        }
    }

    /// The key in the line's corner: Delete on the reader's own post, Report on anybody else's
    /// line. The reader's own review line has neither. It goes when the review goes, and the album
    /// page is where a review is deleted.
    @ViewBuilder
    private func menu(_ face: WallFace) -> some View {
        let deletable = face.mine && face.entry.isPost

        if deletable || !face.mine {
            Menu {
                if deletable {
                    Button(Loc.get("Artists_WallDelete"), role: .destructive) { onDelete(face.entry) }
                } else {
                    Button(Loc.get("Artists_WallReport")) { onReport(face.entry) }
                }
            } label: {
                Text(Glyph.more)
                    .font(RPMFont.icon(13))
                    .foregroundStyle(RPMInk.white(0xAA / 255))
                    .frame(width: 34, height: 28)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(Loc.get("Common_MoreOptions"))
        }
    }

    private func initial(_ entry: RPMWallEntry) -> String {
        guard !entry.authorDeleted, let first = entry.authorName.first,
              first.isLetter || first.isNumber
        else { return "?" }
        return String(first).uppercased()
    }

    /// When it was written, in words a person would use.
    private func when(_ entry: RPMWallEntry) -> String {
        guard entry.createdAt > 0 else { return "" }
        return entry.written.formatted(.relative(presentation: .named))
    }
}
