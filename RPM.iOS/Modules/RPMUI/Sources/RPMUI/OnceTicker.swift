import SwiftUI

/// One line of text that scrolls through once and stops when it is wider than its space.
///
/// **It ends where it started.** The text is drawn twice, with the second copy one gap after the
/// first. The pair slides left by exactly one text width plus one gap. At the end the second copy
/// is where the first one was, so setting the offset back to zero changes nothing on screen.
///
/// **Once per text.** The run is keyed on the text, so a new song or a new station announcement
/// scrolls once, and nothing else does. Text that fits never moves. With Reduce Motion on,
/// nothing moves at all.
///
/// Text that does not fit fades out at its trailing edge instead of ending in an ellipsis, so the
/// line looks the same before, during and after the run. The leading edge also fades while the
/// text moves.
struct OnceTicker: View {
    private let text: String
    private let font: Font
    private let ink: Color

    init(_ text: String, font: Font, ink: Color) {
        self.text = text
        self.font = font
        self.ink = ink
    }

    /// How long a line stays still before it moves. This is long enough to read the start of it.
    private static let wait: Duration = .seconds(2)

    /// Points per second. Slow enough to read while the text moves.
    private static let speed: Double = 30

    /// The space between the end of the text and the copy that follows it.
    private static let gap: CGFloat = 32

    private static let fade: CGFloat = 14

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var moving = false

    private var overflows: Bool { boxWidth > 0 && textWidth > boxWidth + 0.5 }

    var body: some View {
        // The box: one line of this font tall, and as wide as the space offered. It is never drawn.
        Text(verbatim: text)
            .font(font)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { boxWidth = $0 }
            .overlay(alignment: .leading) { run }
            .mask { edges }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            .task(id: Run(text: text, overflows: overflows, still: reduceMotion)) { await tick() }
    }

    /// The text at its full width, and a second copy after it where it does not fit.
    private var run: some View {
        HStack(spacing: Self.gap) {
            line
                .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { textWidth = $0 }

            if overflows {
                line
            }
        }
        .fixedSize()
        .offset(x: offset)
    }

    private var line: some View {
        Text(verbatim: text)
            .font(font)
            .foregroundStyle(ink)
            .lineLimit(1)
            .fixedSize()
    }

    @ViewBuilder
    private var edges: some View {
        if overflows {
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                    .frame(width: moving ? Self.fade : 0)
                Rectangle()
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: Self.fade)
            }
        } else {
            Rectangle()
        }
    }

    /// What starts a run: a new text, the text being found to overflow after it is measured, or
    /// Reduce Motion being turned on or off.
    private struct Run: Equatable {
        let text: String
        let overflows: Bool
        let still: Bool
    }

    private func tick() async {
        var now = Transaction()
        now.disablesAnimations = true
        withTransaction(now) {
            offset = 0
            moving = false
        }

        guard overflows, !reduceMotion else { return }

        try? await Task.sleep(for: Self.wait)
        guard !Task.isCancelled else { return }

        let distance = textWidth + Self.gap
        let time = Double(distance) / Self.speed
        withAnimation(.easeOut(duration: 0.25)) { moving = true }
        withAnimation(.linear(duration: time)) { offset = -distance }

        try? await Task.sleep(for: .seconds(time))
        guard !Task.isCancelled else { return }

        // The second copy is now where the first one was, so this reset is not visible.
        withTransaction(now) { offset = 0 }
        withAnimation(.easeOut(duration: 0.25)) { moving = false }
    }
}
