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
        HeaderText(said)
            .foregroundStyle(.white)
            .padding(.bottom, -(trimsAllDescent ? RPMFont.headerDescentSlack("")
                                                : RPMFont.headerDescentSlack(said)))
    }
}

/// One part of a title, in the title face or in the face that stands in for it.
///
/// Thiamine has Latin letters only. For a letter it lacks, such as Chinese, Core Text falls back to
/// another face. That face is drawn at its own ``size``, so its ink is as tall as the title face's
/// letters and not as tall as the title's point size asks, and it is raised by ``lift`` points so
/// an ideograph stands on the baseline. See ``RPMFont/headerRuns(_:size:)``.
public struct HeaderRun: Sendable, Hashable {
    public let text: String
    public let size: CGFloat
    public let lift: CGFloat
    public let inTitleFace: Bool
}

/// A title in the title face, on one line, with the letters the face lacks drawn at their own
/// size (``HeaderRun``).
///
/// **The line box is the title face's own.** A title with a run in another face is laid out in
/// the box that a title of Latin letters has, with the same baseline, so a Chinese page title is
/// as tall as an English one and the pages under it do not move.
struct HeaderText: View {
    private let said: String
    private let size: CGFloat

    init(_ said: String, size: CGFloat = 96) {
        self.said = said
        self.size = size
    }

    var body: some View {
        let runs = RPMFont.headerRuns(said, size: size)
        if runs.allSatisfy(\.inTitleFace) {
            Text(said)
                .font(RPMFont.header(size))
                .tracking(RPMFont.headerTracking(size))
                .lineLimit(1)
        } else {
            TitleFaceLine {
                // The title face's line box, measured from a letter of its own and not drawn.
                Text(verbatim: "x")
                    .font(RPMFont.header(size))
                    .opacity(0)
                    .accessibilityHidden(true)

                runs.reduce(Text(verbatim: "")) { text, run in
                    text + Text(verbatim: run.text)
                        .font(RPMFont.header(run.size))
                        .baselineOffset(run.lift)
                }
                .tracking(RPMFont.headerTracking(size))
                .lineLimit(1)
            }
        }
    }
}

/// Lays out the second view (a title) with its baseline on the baseline of the first (a letter in
/// the title face), and is as tall as the first. See ``HeaderText``.
private struct TitleFaceLine: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return .zero }
        let box = subviews[0].sizeThatFits(.unspecified)
        let title = subviews[1].sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: title.width, height: box.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        guard subviews.count == 2 else { return }
        let box = subviews[0].dimensions(in: .unspecified)
        let room = ProposedViewSize(width: bounds.width, height: nil)
        let title = subviews[1].dimensions(in: room)

        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.minX,
                                      y: bounds.minY + box[.lastTextBaseline] - title[.lastTextBaseline]),
                          anchor: .topLeading, proposal: room)
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
