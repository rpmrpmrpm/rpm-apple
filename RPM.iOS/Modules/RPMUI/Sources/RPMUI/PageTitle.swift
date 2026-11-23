import SwiftUI

/// The name at the top of a page, in the title face.
///
/// **The part of the font's descent that the word does not use is removed from the bottom.** See
/// ``RPMFont/headerDescentSlack(_:size:)``. The line under the title is then the same distance
/// below the letters on every page. A page whose name has no descender gives the saved space to
/// the content below it.
public struct PageTitle: View {
    private let said: String

    /// Whether the whole descent of the font is removed, with or without a descender. See
    /// ``PageHeading``, which puts its line beside a descender instead of under it.
    private let trimsAllDescent: Bool

    public init(_ said: String) {
        self.said = said
        self.trimsAllDescent = false
    }

    init(_ said: String, trimsAllDescent: Bool) {
        self.said = said
        self.trimsAllDescent = trimsAllDescent
    }

    /// The space between the title and the line under it (the counts, or what the page is).
    /// All pages use this one value, so the headings stay in line when the user switches tabs.
    public static let subtitleGap: Double = 6

    public var body: some View {
        Text(said)
            .font(RPMFont.header())
            .tracking(RPMFont.headerTracking())
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.bottom, -(trimsAllDescent ? RPMFont.headerDescentSlack("")
                                                : RPMFont.headerDescentSlack(said)))
    }
}

/// A library view's title, the line under it, and the keys on the title's line.
///
/// **The same height for every title.** The title is laid out as if it had no descender, and the
/// line sits level with the descenders. A line short enough to end before the first letter that
/// reaches below the baseline is set at the left, under the title. A longer line starts just to
/// the right of the last such letter, so it never runs into one. "playlists" is then as tall as
/// "collection" and "artists", and the tabs under the three headers do not move when the user
/// switches between them.
struct PageHeading<Keys: View>: View {
    private let title: String
    private let line: String
    private let keys: Keys

    init(_ title: String, line: String, @ViewBuilder keys: () -> Keys) {
        self.title = title
        self.line = line
        self.keys = keys()
    }

    /// The space between a descender and the line next to it.
    private static var besideDescender: Double { 6 }

    var body: some View {
        VStack(alignment: .leading, spacing: PageTitle.subtitleGap) {
            // The keys are centred on the title's line, not hung from its top. They are taller
            // than the letters, and hung from the top they reached down into the line under the
            // title, which on a shared collection is long enough to run under them.
            PageTitle(title, trimsAllDescent: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .trailing) { keys }

            LineUnderTitle(start: RPMFont.headerDescenderStart(title),
                           end: RPMFont.headerDescenderEnd(title),
                           gap: Self.besideDescender) {
                Text(line)
                    .rpmKicker()
                    .lineLimit(1)
            }
        }
    }
}

/// Places the line under a title: at the left when it ends a ``gap`` before the first descender
/// (``start``), and otherwise a ``gap`` to the right of the last one (``end``). A title with no
/// descender has an ``end`` of zero, and its line is always at the left.
///
/// A layout and not a padding, because the choice depends on how wide the line is, and only a
/// layout can measure its content before it places it. The Android app's `PageHeading` makes the
/// same choice.
private struct LineUnderTitle: Layout {
    let start: CGFloat
    let end: CGFloat
    let gap: CGFloat

    /// How far from the left the line starts, given its width on one line.
    private func inset(_ natural: CGSize) -> CGFloat {
        guard end > 0, natural.width + gap > start else { return 0 }
        return end + gap
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let line = subviews.first else { return .zero }
        let inset = inset(line.sizeThatFits(.unspecified))
        let room = proposal.width.map { max(0, $0 - inset) }
        let size = line.sizeThatFits(ProposedViewSize(width: room, height: proposal.height))
        return CGSize(width: inset + size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        guard let line = subviews.first else { return }
        let inset = inset(line.sizeThatFits(.unspecified))
        line.place(at: CGPoint(x: bounds.minX + inset, y: bounds.minY), anchor: .topLeading,
                   proposal: ProposedViewSize(width: max(0, bounds.width - inset),
                                              height: bounds.height))
    }
}
