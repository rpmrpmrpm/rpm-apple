import SwiftUI

/// A scroller that is only as tall as what is in it, up to a ceiling.
///
/// **SwiftUI's `ScrollView` takes every point it is offered**, so a panel holding two rows would
/// be mostly empty space with two rows at the top.
///
/// The height is worked out from the number of rows and is not measured. A measured height does
/// not work here: a preference read from the content's background does not reach out of a
/// `ScrollView`, or it comes back as the height the scroller was already given. Either way it is
/// a loop that settles on the wrong answer, and the scroller stays at the ceiling. **Counting is
/// safe only because these rows cannot wrap**: every panel that uses this draws one line and one
/// subtitle, both trimmed. A list of wrapping rows must not use it.
public struct ShortScroll<Content: View>: View {
    private let ceiling: CGFloat
    private let rows: Int
    private let each: CGFloat
    private let padding: CGFloat
    private let content: Content

    public init(rows: Int, each: CGFloat, upTo ceiling: CGFloat, padding: CGFloat = 12,
                @ViewBuilder content: () -> Content) {
        self.rows = rows
        self.each = each
        self.ceiling = ceiling
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        ScrollView {
            content
        }
        .scrollIndicators(.hidden)
        .frame(height: min(CGFloat(rows) * each + padding, ceiling))
    }
}
