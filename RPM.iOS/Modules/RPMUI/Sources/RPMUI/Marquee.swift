import SwiftUI
import RPMDesign

/// A line of text that scrolls sideways when it does not fit.
///
/// **A title cut off with an ellipsis cannot be read.** This line rests for ten seconds,
/// scrolls at reading pace and comes back. The travel is calculated by ``MarqueeWalk``,
/// where it is tested; this view measures the line and draws it.
///
/// An edge fades out while letters are hidden past it, which shows that the line does not
/// fit. The fade is a mask on the letters' alpha, not a colour drawn over them, because
/// the line sits on a picture that changes colour with every cover. The depth of each band
/// comes from ``RPMDesign/EdgeFade/head(scrolled:viewport:depth:)``. It grows with the
/// amount of text hidden past that edge, so the trailing band goes as the end of the line
/// arrives and the leading band appears as the line moves away from its start. A line that
/// fits has no band at either end.
public struct Marquee: View {
    private let text: String
    private let font: Font
    private let ink: Color

    /// How tall one line of this font is.
    ///
    /// **The caller passes it in because it cannot be measured here.** The line is drawn
    /// inside a `GeometryReader`, which fills whatever space it is offered. A height taken
    /// from the text would depend on the column the text is being fitted to.
    private let height: CGFloat

    public init(_ text: String, font: Font, height: CGFloat, ink: Color) {
        self.text = text
        self.font = font
        self.height = height
        self.ink = ink
    }

    @State private var line: CGFloat = 0
    @State private var column: CGFloat = 0

    /// When this line started. Reset whenever the text changes, so a new title rests for
    /// ten seconds instead of continuing the previous title's scroll.
    @State private var from = Date()

    private struct Measured: PreferenceKey {
        static let defaultValue: CGFloat = 0
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = max(value, nextValue())
        }
    }

    public var body: some View {
        let travel = MarqueeWalk.travel(text: line, column: column)

        return GeometryReader { column in
            TimelineView(.animation(paused: travel <= 0)) { timeline in
                let at = MarqueeWalk.offset(at: timeline.date.timeIntervalSince(from),
                                            travel: travel)

                Text(text)
                    .font(font)
                    .foregroundStyle(ink)
                    .lineLimit(1)
                    // Unlimited width to the right, so the whole line is drawn and the
                    // clip, not the layout, decides which part is visible.
                    .fixedSize(horizontal: true, vertical: false)
                    .background {
                        GeometryReader { line in
                            Color.clear.preference(key: Measured.self, value: line.size.width)
                        }
                    }
                    .offset(x: at)
                    .frame(width: column.size.width, alignment: .leading)
                    .clipped()
                    .mask { dissolve(at: at, travel: travel, width: column.size.width) }
            }
            .onPreferenceChange(Measured.self) { line = $0 }
            .onAppear { self.column = column.size.width }
            .onChange(of: column.size.width) { self.column = $1 }
        }
        .frame(height: height)
        .onChange(of: text) { from = Date() }
    }

    /// The mask for a line at offset `at`: opaque in the middle, transparent at an edge that
    /// has letters hidden past it. Each band is limited to half the column, so the two bands
    /// never cross on a narrow column.
    private func dissolve(at: Double, travel: Double, width: Double) -> LinearGradient {
        guard width > 0 else { return LinearGradient(colors: [.black], startPoint: .leading, endPoint: .trailing) }

        let half = width / 2
        let lead = EdgeFade.head(scrolled: -at, viewport: half, depth: EdgeFade.depth)
        let trail = EdgeFade.head(scrolled: MarqueeWalk.hiddenAfter(offset: at, travel: travel),
                                  viewport: half, depth: EdgeFade.depth)

        return LinearGradient(stops: [
            .init(color: .black.opacity(lead > 0 ? 0 : 1), location: 0),
            .init(color: .black, location: lead / width),
            .init(color: .black, location: 1 - trail / width),
            .init(color: .black.opacity(trail > 0 ? 0 : 1), location: 1),
        ], startPoint: .leading, endPoint: .trailing)
    }
}
