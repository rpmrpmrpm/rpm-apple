import SwiftUI

/// Lays children out from left to right and starts a new line when the next child does not fit.
///
/// This is the Swift version of the desktop's `WrapRow`, for the same case: a row whose length
/// depends on its content and not on the layout. An entry on the About screen has between one
/// and four links, and one may be "GNU Lesser General Public License v2.1". A phone is 390
/// points wide. An `HStack` would squeeze every child until they all fit, and four links would
/// become four ellipses.
///
/// **The size follows the width it is offered, not its children.** A `Layout` is asked for a
/// size with a proposal, and the proposal's width is nil when a parent asks for the preferred
/// size. If this layout answered with the total width of its children, the parent would offer
/// exactly that width and nothing would ever wrap. So it answers with the width it was given and
/// computes only the HEIGHT, which is what wrapping decides.
struct FlowRow: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    init(spacing: CGFloat = 8, lineSpacing: CGFloat = 4) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = wrap(subviews, into: width)

        let height = lines.reduce(0.0) { $0 + $1.height } +
            lineSpacing * CGFloat(max(0, lines.count - 1))

        // An infinite width must not be returned to the parent as a size. If no width is
        // proposed, use the width of the widest line.
        return CGSize(width: width.isFinite ? width : lines.map(\.width).max() ?? 0,
                      height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        var y = bounds.minY

        for line in wrap(subviews, into: bounds.width) {
            var x = bounds.minX

            for index in line.range {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                                      anchor: .topLeading,
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }

            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var range: Range<Int>
        var width: CGFloat
        var height: CGFloat
    }

    /// The children divided into lines. A child wider than the whole row still gets its own line
    /// and is not dropped. It overflows, which is visible and can be fixed, but a missing link
    /// would not be noticed.
    private func wrap(_ subviews: Subviews, into width: CGFloat) -> [Line] {
        var lines: [Line] = []
        var start = 0
        var x: CGFloat = 0
        var height: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let next = x == 0 ? size.width : x + spacing + size.width

            if next > width, index > start {
                lines.append(Line(range: start..<index, width: x, height: height))
                start = index
                x = size.width
                height = size.height
                continue
            }

            x = next
            height = max(height, size.height)
        }

        if start < subviews.count {
            lines.append(Line(range: start..<subviews.count, width: x, height: height))
        }

        return lines
    }
}
