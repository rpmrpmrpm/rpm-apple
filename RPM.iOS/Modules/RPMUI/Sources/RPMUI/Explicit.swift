import SwiftUI
import RPMKit

/// The E mark for explicit lyrics: a small light square with the letter in the ground's colour, so
/// the letter looks cut out of it.
///
/// `edge` is the side of the square. The letter and the corner follow it. 14 points sits beside a
/// song's title in a list.
///
/// **It goes after the title, never before it**, and in the same row, so a long title is shortened
/// to leave room for the mark and does not run under it. ``MarkedTitle`` does both.
///
/// It is not drawn in the mini player, in the player, or on the home banner's card. Those show
/// what is playing or what is offered, and the mark there would only be noise.
struct ExplicitMark: View {
    var edge: CGFloat = 14

    var body: some View {
        Text(verbatim: "E")
            .font(.system(size: edge * 9 / 14, weight: .bold))
            .foregroundStyle(RPMInk.ground)
            .frame(width: edge, height: edge)
            .background(RoundedRectangle(cornerRadius: edge * 3 / 14).fill(RPMInk.white(0xAA / 255)))
            // Fixed: the title gives way to the mark, never the mark to the title.
            .fixedSize()
            .accessibilityElement()
            .accessibilityLabel(Loc.get("Library_Explicit"))
    }
}

/// A title with the E after it when `explicit` is true. Where it is false this is the plain text.
///
/// The caller styles it as it would style a `Text`: the font, the colour, the line limit and the
/// alignment are read from the environment by the text inside. The mark keeps its own look.
///
/// On one line the title gives way to the mark: a long title is shortened and the mark stays in
/// view. Where more lines are allowed, the mark is part of the text, after the last word and joined
/// to it by a no-break space, so it wraps with that word and never stands alone at the edge of the
/// block. There it is the system's filled square E, drawn in the mark's colour.
struct MarkedTitle: View {
    let text: String
    let explicit: Bool

    /// The side of the mark. By default it suits a title of 14 to 17 points.
    var edge: CGFloat = 14

    init(_ text: String, explicit: Bool, edge: CGFloat = 14) {
        self.text = text
        self.explicit = explicit
        self.edge = edge
    }

    @Environment(\.lineLimit) private var lineLimit

    var body: some View {
        if explicit, lineLimit != 1 {
            Text(text)
                + Text(verbatim: "\u{00A0}")
                + Text(Image(systemName: "e.square.fill")).foregroundStyle(RPMInk.white(0xAA / 255))
        } else if explicit {
            HStack(spacing: 6) {
                Text(text)
                ExplicitMark(edge: edge)
            }
        } else {
            Text(text)
        }
    }
}
