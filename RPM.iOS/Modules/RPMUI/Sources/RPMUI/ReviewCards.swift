import SwiftUI
import UIKit
import RPMKit

/// Finds a reviewed record's cover at an edge in points: the reader's own copy's, else the catalogue's; nil for none.
public typealias ReviewCoverSource = @MainActor (RPMFeedReview, CGFloat) async -> Image?

/// A review's cover, at the right of its card. The review's text runs beside it and on under it.
let reviewCoverEdge: CGFloat = 120

/// The most lines of a review a card shows; the whole review is a tap away.
let reviewLines = 10

/// A review as a card, on a profile page and on the Feed tab. It is the Android app's `ReviewRow`.
///
/// The record's title, its artist and year, and the stars stand at the left, with the cover at the right; the review
/// follows in quotation marks, beside the cover while there is room and then on under it across the card, as the
/// desktop's conductor box runs text round a picture. A card shows at most ``reviewLines`` lines; Read full review at
/// the foot opens the whole review.
struct ReviewCard<Author: View>: View {
    let shown: RPMFeedReview
    let isOwn: Bool
    let coverFor: ReviewCoverSource
    let onVote: (Int) -> Void
    let onRead: () -> Void

    /// The line with the author's photo and name above the record, on the Feed tab. Without one, on the author's own
    /// page, the time stands beside the stars instead.
    private let author: Author?

    @State private var headHeight: CGFloat = 0

    init(shown: RPMFeedReview, isOwn: Bool, coverFor: @escaping ReviewCoverSource,
         onVote: @escaping (Int) -> Void, onRead: @escaping () -> Void, @ViewBuilder author: () -> Author) {
        self.shown = shown
        self.isOwn = isOwn
        self.coverFor = coverFor
        self.onVote = onVote
        self.onRead = onRead
        self.author = author()
    }

    var body: some View {
        let review = shown.review
        let gap: CGFloat = 12
        let space: CGFloat = 8

        VStack(alignment: .leading, spacing: 0) {
            if let author {
                author.padding(.bottom, 12)
            }

            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: space) {
                    ReviewHead(shown: shown, showTime: Author.self == EmptyView.self)
                        .padding(.trailing, reviewCoverEdge + gap)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { headHeight = $0 }

                    if !review.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // The corner the cover takes, measured from the top of the text.
                        WrappedText(text: quoted(review.body), size: 14, colour: UIColor.white.withAlphaComponent(0xE6 / 255),
                                    maxLines: reviewLines,
                                    corner: CGSize(width: reviewCoverEdge + gap,
                                                   height: max(0, reviewCoverEdge - headHeight - space)))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: reviewCoverEdge, alignment: .topLeading)

                ReviewCover(shown: shown, edge: reviewCoverEdge, coverFor: coverFor)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)
            }

            HStack {
                VoteKeys(ups: review.ups, downs: review.downs, mine: review.myVote, enabled: !isOwn, onVote: onVote)
                Spacer()
                Button(action: onRead) {
                    Text(Loc.get("Rpm_Profile_ReadReview"))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 4)
        .background { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RPMInk.white(0x12 / 255)) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onRead)
    }
}

extension ReviewCard where Author == EmptyView {
    /// A card on the author's own page, with no author line.
    init(shown: RPMFeedReview, isOwn: Bool, coverFor: @escaping ReviewCoverSource,
         onVote: @escaping (Int) -> Void, onRead: @escaping () -> Void) {
        self.shown = shown
        self.isOwn = isOwn
        self.coverFor = coverFor
        self.onVote = onVote
        self.onRead = onRead
        self.author = nil
    }
}

/// A review's text in the language's quotation marks.
func quoted(_ body: String) -> String {
    Loc.get("Rpm_Profile_Quoted", body.trimmingCharacters(in: .whitespacesAndNewlines))
}

/// The record's title, its artist and year, and the stars; when `showTime`, the time beside the stars.
struct ReviewHead: View {
    let shown: RPMFeedReview
    let showTime: Bool

    var body: some View {
        let review = shown.review
        VStack(alignment: .leading, spacing: 0) {
            Text(shown.albumTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
            Text(shown.albumYear > 0 ? "\(shown.albumArtist), \(shown.albumYear)" : shown.albumArtist)
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0x99 / 255))
                .lineLimit(1)
                .padding(.top, 2)
            if review.rating > 0 || showTime {
                HStack(spacing: 10) {
                    if review.rating > 0 { StarRating(Double(review.rating) / 2, size: 15) }
                    if showTime {
                        Text(written(review.createdAt))
                            .font(RPMFont.display(11))
                            .foregroundStyle(RPMInk.white(0x77 / 255))
                            .lineLimit(1)
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}

/// When something was written, in words a person would use: "just now" for the last minute.
func written(_ millis: Int64) -> String {
    guard millis > 0 else { return "" }
    let date = Date(timeIntervalSince1970: Double(millis) / 1000)
    if Date().timeIntervalSince(date) < 60 { return Loc.get("Rpm_Profile_JustNow") }
    return date.formatted(.relative(presentation: .named))
}

/// The record's cover, found by `coverFor`, over the record glyph while it is found or when there is none.
struct ReviewCover: View {
    let shown: RPMFeedReview
    let edge: CGFloat
    let coverFor: ReviewCoverSource
    @State private var image: Image?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        ZStack {
            shape.fill(Color.black.opacity(0x22 / 255))
            Text(Glyph.record)
                .font(RPMFont.icon(28))
                .foregroundStyle(RPMInk.white(0x3A / 255))
            if let image {
                image.resizable().scaledToFill()
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(shape)
        .overlay { shape.strokeBorder(RPMInk.glassEdge, lineWidth: 1) }
        .task(id: shown.review.albumId + shown.albumTitle) { image = await coverFor(shown, edge) }
        .accessibilityHidden(true)
    }
}

/// The author's photo and name over a review on the Feed tab, with when it was written. Opens their page.
struct ReviewAuthor: View {
    let shown: RPMFeedReview
    let photo: URL?
    let onPerson: () -> Void

    var body: some View {
        let review = shown.review
        Button(action: onPerson) {
            HStack(spacing: 10) {
                PersonPicture(review.authorDeleted ? nil : photo, name: review.authorShown, size: 32)
                Byline(name: review.authorShown, millis: review.createdAt, gold: review.authorSupporter)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(review.authorDeleted)
    }
}

/// A name and when it wrote. A supporter's name is in gold.
struct Byline: View {
    let name: String
    let millis: Int64
    var gold = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(gold ? RPMInk.gold : .white)
                .lineLimit(1)
            Text(written(millis))
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x77 / 255))
                .lineLimit(1)
        }
    }
}

/// A whole review, risen over the page from Read full review: the cover beside the record's title, artist, year and
/// stars, then every line of the review, the votes, and Open album when the record is in the reader's collection.
public struct ReviewPage: View {
    private let shown: RPMFeedReview
    private let isOwn: Bool
    private let author: (photo: URL?, onPerson: () -> Void)?
    private let coverFor: ReviewCoverSource
    private let ground: String
    private let onVote: (Int) -> Void
    private let onOpenAlbum: (() -> Void)?
    private let onClose: () -> Void

    /// - Parameters:
    ///   - author: the author's photo and what opens their page, on the Feed tab; nil on the author's own page.
    ///   - ground: what the page under it is drawn on (``RPMProfile/pageGround``); empty for the standard background.
    ///   - onOpenAlbum: nil when the record is not in the reader's collection.
    public init(shown: RPMFeedReview, isOwn: Bool, author: (photo: URL?, onPerson: () -> Void)?,
                coverFor: @escaping ReviewCoverSource, ground: String, onVote: @escaping (Int) -> Void,
                onOpenAlbum: (() -> Void)?, onClose: @escaping () -> Void) {
        self.shown = shown
        self.isOwn = isOwn
        self.author = author
        self.coverFor = coverFor
        self.ground = ground
        self.onVote = onVote
        self.onOpenAlbum = onOpenAlbum
        self.onClose = onClose
    }

    public var body: some View {
        let review = shown.review
        VStack(spacing: 0) {
            HStack {
                Spacer()
                CloseKey(action: onClose)
            }
            .padding(.horizontal, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let author {
                        ReviewAuthor(shown: shown, photo: author.photo, onPerson: author.onPerson)
                    }
                    HStack(alignment: .top, spacing: 14) {
                        ReviewCover(shown: shown, edge: 140, coverFor: coverFor)
                        ReviewHead(shown: shown, showTime: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !review.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(quoted(review.body))
                            .font(RPMFont.display(15))
                            .foregroundStyle(RPMInk.white(0xEE / 255))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        VoteKeys(ups: review.ups, downs: review.downs, mine: review.myVote, enabled: !isOwn, onVote: onVote)
                        Spacer()
                        if let onOpenAlbum {
                            Button(Loc.get("Rpm_Profile_OpenAlbum"), action: onOpenAlbum)
                                .buttonStyle(RPMGlassButton(.ghost, radius: 16, height: 34, stretches: false, inset: 18, size: 13))
                        }
                    }
                }
                .padding(.horizontal, RPMLayout.margin)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .background { PageGroundView(wire: ground) }
    }
}

/// A close key: a cross at the top right of a sheet.
struct CloseKey: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(Glyph.close)
                .font(RPMFont.icon(15))
                .foregroundStyle(RPMInk.white(0xCC / 255))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.get("Common_Cancel"))
    }
}

/// Text that runs round a corner kept free at its top right, as the desktop's conductor box runs text round a
/// picture. UIKit's text layout does this with an exclusion path; SwiftUI's `Text` cannot. Every line that reaches
/// into the corner is shortened to end before it, and the lines under the corner use the whole width.
struct WrappedText: UIViewRepresentable {
    let text: String
    let size: CGFloat
    let colour: UIColor
    let maxLines: Int

    /// The free corner's width and height, from the text's top right.
    let corner: CGSize

    func makeUIView(context: Context) -> CornerTextView {
        let view = CornerTextView()
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.lineBreakMode = .byTruncatingTail
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: CornerTextView, context: Context) {
        view.attributedText = NSAttributedString(string: text, attributes: [.font: RPMFont.displayFace(size),
                                                                            .foregroundColor: colour])
        view.textContainer.maximumNumberOfLines = maxLines
        view.corner = corner
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView view: CornerTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? 300
        return CGSize(width: width, height: view.height(at: width))
    }
}

/// The text view behind ``WrappedText``: it keeps the free corner as an exclusion path at the width it is laid out at.
final class CornerTextView: UITextView {
    var corner: CGSize = .zero {
        didSet { if corner != oldValue { setNeedsLayout() } }
    }

    private var keptFor: (width: CGFloat, corner: CGSize)?

    override func layoutSubviews() {
        keep(at: bounds.width)
        super.layoutSubviews()
    }

    /// The height the text takes at `width`, with the corner kept free.
    func height(at width: CGFloat) -> CGFloat {
        keep(at: width)
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        layoutManager.ensureLayout(for: textContainer)
        return ceil(layoutManager.usedRect(for: textContainer).maxY)
    }

    private func keep(at width: CGFloat) {
        guard width > 0, keptFor?.width != width || keptFor?.corner != corner else { return }
        keptFor = (width, corner)
        textContainer.exclusionPaths = corner.height > 0 && corner.width > 0
            ? [UIBezierPath(rect: CGRect(x: width - corner.width, y: 0, width: corner.width, height: corner.height))]
            : []
    }
}
