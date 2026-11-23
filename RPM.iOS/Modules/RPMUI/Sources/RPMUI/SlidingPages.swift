import SwiftUI
import RPMDesign

/// Pages that slide across the screen as the app's tabs do: the same direction, duration and
/// curve (``RPMDesign/TabSlide``).
///
/// One page is shown for each value of `shown`. The pages stand in the order of
/// `Choice.allCases`. When `shown` changes to a choice further on, the page shown leaves to the
/// left and the new page comes in from the right; to a choice further back, the reverse. The page
/// that left is taken away when the slide ends, so a page that comes back is built again.
///
/// The slide follows `shown` and is not started by a key, so a change from anywhere slides: a key
/// in a ``PageTabs`` row, a link from the player, a script. The library's views and the settings
/// page's sections use this.
@MainActor
public struct SlidingPages<Choice: Hashable & CaseIterable, Page: View>: View {
    private let shown: Choice
    private let page: (Choice) -> Page

    /// The page on the screen, or sliding onto it. It follows `shown`, inside the slide's
    /// animation, so the page that comes in is inserted with its slide.
    @State private var current: Choice

    /// The page shown before the last change: the side the new page comes in from.
    @State private var cameFrom: Choice

    /// The pages still sliding off the screen. They are taken away when the slide ends.
    @State private var leaving: Set<Choice> = []

    /// Counts the changes, so a slide that ends after a newer one began leaves the pages of the
    /// newer one alone.
    @State private var slides = 0

    /// The width the pages slide across.
    @State private var width: CGFloat = 0

    public init(_ shown: Choice, @ViewBuilder page: @escaping (Choice) -> Page) {
        self.shown = shown
        self.page = page
        _current = State(initialValue: shown)
        _cameFrom = State(initialValue: shown)
    }

    public var body: some View {
        ZStack {
            ForEach(onScreen, id: \.self) { which in
                page(which)
                    .offset(x: TabSlide.place(of: place(which), shown: place(current)) * width)
                    .transition(AnyTransition.offset(x: TabSlide.entry(from: place(cameFrom), to: place(which)) * width))
                    .allowsHitTesting(which == current)
                    .accessibilityHidden(which != current)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .onChange(of: shown) { _, next in slide(to: next) }
    }

    /// The pages on the screen: the one shown, and those still sliding away. In their order.
    private var onScreen: [Choice] {
        Choice.allCases.filter { $0 == current || leaving.contains($0) }
    }

    /// The place of a page in the order, counted from the first.
    private func place(_ choice: Choice) -> Int {
        Array(Choice.allCases).firstIndex(of: choice) ?? 0
    }

    /// Shows `next`, sliding both pages the whole width. The page left behind stays until the
    /// slide ends.
    private func slide(to next: Choice) {
        guard next != current else { return }

        slides += 1
        let slide = slides

        // All in one animated change, so the page coming in is inserted with its slide.
        withAnimation(.easeInOut(duration: TabSlide.duration)) {
            cameFrom = current
            leaving.insert(current)
            current = next
        } completion: {
            guard slides == slide else { return }
            leaving = []
        }
    }
}
