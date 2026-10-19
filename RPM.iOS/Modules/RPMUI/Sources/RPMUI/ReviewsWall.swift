import SwiftUI
import RPMKit

/// One review, as a page draws it.
///
/// The wire type with the two things a row needs added: whether it is the reader's own, and when
/// it was written, in words a person would use.
public struct ReviewFace: Identifiable, Sendable {
    public let review: RPMReview
    public let mine: Bool

    public var id: String { review.userId }

    public init(review: RPMReview, mine: Bool) {
        self.review = review
        self.mine = mine
    }
}

/// What everybody else made of the same record.
///
/// The Uno app has the same footer in `RPM.Mobile/Presentation/AlbumPage.xaml`. **It loads
/// after the tracks and fills in underneath them**. Nothing here is needed to play the album, so
/// nothing here holds it up.
public struct ReviewsWall: View {
    private let average: Double
    private let ratingCount: Int
    private let myStars: Double
    private let reviews: [ReviewFace]
    private let sort: RPMReviewSort
    private let reading: Bool
    private let hasMore: Bool
    private let trouble: String?

    private let onSort: (RPMReviewSort) -> Void
    private let onRate: (Double) -> Void
    private let onWrite: () -> Void
    private let onVote: (RPMReview, Int) -> Void
    private let onMore: () -> Void

    public init(average: Double, ratingCount: Int, myStars: Double,
                reviews: [ReviewFace], sort: RPMReviewSort,
                reading: Bool, hasMore: Bool, trouble: String?,
                onSort: @escaping (RPMReviewSort) -> Void,
                onRate: @escaping (Double) -> Void,
                onWrite: @escaping () -> Void,
                onVote: @escaping (RPMReview, Int) -> Void,
                onMore: @escaping () -> Void) {
        self.average = average
        self.ratingCount = ratingCount
        self.myStars = myStars
        self.reviews = reviews
        self.sort = sort
        self.reading = reading
        self.hasMore = hasMore
        self.trouble = trouble
        self.onSort = onSort
        self.onRate = onRate
        self.onWrite = onWrite
        self.onVote = onVote
        self.onMore = onMore
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)

            heading
            mine

            if let trouble {
                Text(trouble)
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0x99 / 255))
            } else if reviews.isEmpty && !reading {
                Text(Loc.get("Album_NoReviews"))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
            }

            // Rows and not a list: a scrolling list inside a scrolling page is two scrolls
            // competing for one finger. The page is what scrolls.
            ForEach(reviews) { face in
                row(face)
            }

            // Pages, as a phone shows them: one key that adds the next batch underneath, and not
            // a row of page numbers to tap.
            if hasMore {
                Button(Loc.get("Rpm_Album_MoreReviews"), action: onMore)
                    .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 40, size: 13))
            }
        }
        .padding(.horizontal, RPMLayout.margin)
        .padding(.top, 22)
        .padding(.bottom, 28)
    }

    private var heading: some View {
        HStack {
            Text(headingSaid).rpmKicker()

            Spacer(minLength: 8)

            // Two orders and no more: what people rated highest, and what came in last. The
            // desktop's five orders are too many for a touch screen.
            HStack(spacing: 6) {
                chip(Loc.get("Album_SortVotes"), .votes)
                chip(Loc.get("Album_SortDate"), .date)
            }
        }
    }

    private var headingSaid: String {
        guard ratingCount > 0 else { return Loc.get("Album_ReviewsHeading") }
        return Loc.get("Rpm_Album_ReviewsRated",
                       average.formatted(.number.precision(.fractionLength(0...1))), ratingCount)
    }

    private func chip(_ said: String, _ order: RPMReviewSort) -> some View {
        Button(said) { onSort(order) }
            .buttonStyle(RPMGlassButton(sort == order ? .primary : .ghost,
                                        radius: 15, height: 30,
                                        stretches: false, inset: 12, size: 12))
    }

    /// The reader's own verdict, which is also how one is given: the stars take a tap, and the
    /// key underneath opens the sheet for the words.
    private var mine: some View {
        VStack(spacing: 10) {
            HStack {
                Text(Loc.get("Album_YourRating"))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0xCC / 255))

                Spacer(minLength: 8)

                StarRating(myStars, size: 20, onPick: onRate)
            }

            Button(myStars > 0 ? Loc.get("Rpm_Album_EditReview") : Loc.get("AlbumMenu_WriteReview"), action: onWrite)
                .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 40, size: 14))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            let card = RoundedRectangle(cornerRadius: 14, style: .continuous)
            card.fill(RPMInk.white(0x14 / 255))
                .overlay { card.strokeBorder(RPMInk.glassEdge, lineWidth: 1) }
        }
    }

    private func row(_ face: ReviewFace) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                // The letter that their name starts with. The desktop draws the avatar where
                // there is one, but that is one fetch per row on a page whose purpose is the
                // record above it.
                Text(face.review.authorDeleted ? "?" : initial(face.review.authorName))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(RPMInk.white(0xDD / 255))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(RPMInk.white(0x26 / 255)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(face.review.authorShown)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        StarRating(Double(face.review.rating) / 2, size: 11)

                        Text(when(face.review))
                            .font(RPMFont.display(11))
                            .foregroundStyle(RPMInk.white(0x77 / 255))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Somebody else's review can be voted on; the reader's own cannot.
                // **Never both**, because the wall does not allow voting on your own review.
                if !face.mine {
                    HStack(spacing: 2) {
                        vote("\u{f077}", face, 1)
                        Text("\(face.review.score)")
                            .font(RPMFont.display(13))
                            .foregroundStyle(RPMInk.white(0xAA / 255))
                            .frame(minWidth: 16)
                        vote("\u{f078}", face, -1)
                    }
                }
            }

            if !face.review.body.isEmpty {
                Text(face.review.body)
                    .font(RPMFont.display(14))
                    .foregroundStyle(RPMInk.white(0xE6 / 255))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(RPMInk.white(0x12 / 255))
        }
    }

    private func vote(_ glyph: String, _ face: ReviewFace, _ value: Int) -> some View {
        Button { onVote(face.review, value) } label: {
            Text(glyph)
                .font(RPMFont.icon(13))
                .foregroundStyle(RPMInk.white(0xE6 / 255))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(face.review.myVote == value ? 1 : 0.4)
        .accessibilityLabel(value > 0 ? Loc.get("Album_VoteUp") : Loc.get("Album_VoteDown"))
    }

    private func initial(_ name: String) -> String {
        guard let first = name.first, first.isLetter || first.isNumber else { return "?" }
        return String(first).uppercased()
    }

    /// When it was written, in words a person would use.
    private func when(_ review: RPMReview) -> String {
        let stamp = review.updatedAt > 0 ? review.updatedAt : review.createdAt
        guard stamp > 0 else { return "" }

        let said = Date(timeIntervalSince1970: Double(stamp) / 1000)
            .formatted(.relative(presentation: .named))

        return review.updatedAt > review.createdAt ? Loc.get("Rpm_Album_Edited", said) : said
    }
}
