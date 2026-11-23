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
/// in a ``PageTabs`` row, a link from the player, a script. The settings page's sections slide
/// whole. The library's views are held (`holding`), as described below.
///
/// **A held page stands still, and only the part under its header slides.** Each library view
/// draws its own header and its own ``PageTabs`` row, inside its own `NavigationStack`. A view
/// that `holding` names is not moved. The part under its header moves instead
/// (`slidesWhenHeld()`). The header of the view that leaves fades out while the new one fades in
/// (`headerWhenHeld()`). The new row replaces the old one at once, in the same place
/// (`rowWhenHeld()`). So the row seems to stay and its pill moves across, as on the settings page,
/// where one header and one row stand over all the sections. A view with a page pushed on its
/// stack is not held and slides whole, because the pushed page has no row.
///
/// **Held pages stand on top of each other, so they cannot paint a ground of their own.** One
/// ground is drawn behind all of them (`groundBehindHeldPages()`), and each page leaves its own
/// out (`groundUnlessHeld()`). A `NavigationStack` paints an opaque background, and only iOS 18 and
/// later can make it clear. On iOS 17 no page is held, and every page slides whole.
@MainActor
public struct SlidingPages<Choice: Hashable & CaseIterable, Page: View>: View {
    private let shown: Choice
    private let page: (Choice) -> Page

    /// Whether the page of a choice is held now: it stands still and only the part under its
    /// header slides. Nil when every page slides whole.
    private let holding: ((Choice) -> Bool)?

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

    /// Pages that always slide whole.
    public init(_ shown: Choice, @ViewBuilder page: @escaping (Choice) -> Page) {
        self.shown = shown
        self.page = page
        self.holding = nil
        _current = State(initialValue: shown)
        _cameFrom = State(initialValue: shown)
    }

    /// Pages that are held while `holding` says so. See the notes on the type.
    public init(_ shown: Choice, holding: @escaping (Choice) -> Bool,
                @ViewBuilder page: @escaping (Choice) -> Page) {
        self.shown = shown
        self.page = page
        self.holding = holding
        _current = State(initialValue: shown)
        _cameFrom = State(initialValue: shown)
    }

    public var body: some View {
        ZStack {
            ForEach(onScreen, id: \.self) { which in
                placed(which)
            }
        }
        .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
        .onChange(of: shown) { _, next in slide(to: next) }
    }

    /// One page where the slide has it: moved whole, or held still with the part under its header
    /// moved.
    ///
    /// **Every page gets the same modifiers, held or not.** A page is held or not as its stack is
    /// pushed and popped. Modifiers that came and went with it would build the page again, and its
    /// stack with it.
    private func placed(_ which: Choice) -> some View {
        let held = holds(which)
        let away = TabSlide.place(of: place(which), shown: place(current)) * width

        // The header and the row of a held page give way only to those of a held page that comes
        // in. A page that comes in whole covers them as it comes.
        let shows = !held || which == current || !holds(current)
        let behind = mayHold

        return page(which)
            .modifier(SlideMotion(shift: held ? away : 0, presence: shows ? 1 : 0))
            .transformEnvironment(\.pageSlide) { slide in
                slide.rowShows = shows
                slide.groundBehind = behind
            }
            .offset(x: held ? 0 : away)
            .transition(entering(which, held: held))
            // The page shown is in front, so a page that comes in whole covers the header of a
            // held page that leaves.
            .zIndex(which == current ? 1 : 0)
            .allowsHitTesting(which == current)
            .accessibilityHidden(which != current)
    }

    /// How a page comes in: from the side away from the page it replaces. A held page does not
    /// move: the part under its header comes in from that side, and its header fades in.
    private func entering(_ which: Choice, held: Bool) -> AnyTransition {
        let from = TabSlide.entry(from: place(cameFrom), to: place(which)) * width
        guard held else { return AnyTransition.offset(x: from) }
        return AnyTransition.modifier(active: SlideMotion(shift: from, presence: 0),
                                      identity: SlideMotion(shift: 0, presence: 1))
    }

    /// Whether pages may be held here: a `holding` was given, and the system can make a
    /// `NavigationStack`'s own background clear.
    private var mayHold: Bool {
        holding != nil && HeldPages.possible
    }

    /// Whether the page of `which` is held now.
    private func holds(_ which: Choice) -> Bool {
        guard mayHold, let holding else { return false }
        return holding(which)
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

/// Whether ``SlidingPages`` can hold pages on this system.
enum HeldPages {
    /// From iOS 18, where a `NavigationStack`'s own background can be made clear
    /// (`containerBackground(_:for:)` with `.navigation`). A held page needs that, because the
    /// pages under it must show through.
    static var possible: Bool {
        if #available(iOS 18, *) { return true }
        return false
    }
}

// ── what a page is told about the slide ──

/// What a page inside ``SlidingPages`` is told about the slide. Outside one, the defaults hold:
/// nothing moves and everything shows.
struct PageSlide: Equatable {
    /// How far the part under the header of a held page stands from its place, in points.
    var shift: CGFloat = 0

    /// How much of the header shows: 1 all of it, 0 none.
    var presence: Double = 1

    /// Whether the row of tabs under the header shows.
    var rowShows = true

    /// Whether one ground is drawn behind the pages, so the page draws none.
    var groundBehind = false
}

private struct PageSlideKey: EnvironmentKey {
    static let defaultValue = PageSlide()
}

extension EnvironmentValues {
    var pageSlide: PageSlide {
        get { self[PageSlideKey.self] }
        set { self[PageSlideKey.self] = newValue }
    }
}

/// Adds `shift` to how far a held page's content stands from its place, and takes `presence` of
/// its header. It is the page's place in the slide, and also the transition of a held page that
/// comes in, so the two add up.
///
/// It is animatable, so the content follows the slide on every frame. The content is inside the
/// page's `NavigationStack`, where the slide's own offset cannot reach it.
private struct SlideMotion: ViewModifier, Animatable {
    var shift: CGFloat
    var presence: Double

    /// `nonisolated` because `Animatable` is. See `SpectrumRunView.animatableData`.
    nonisolated var animatableData: AnimatablePair<CGFloat, Double> {
        get { AnimatablePair(shift, presence) }
        set {
            shift = newValue.first
            presence = newValue.second
        }
    }

    func body(content: Content) -> some View {
        let moved = self.shift
        let shown = self.presence

        return content.transformEnvironment(\.pageSlide) { slide in
            slide.shift += moved
            slide.presence *= shown
        }
    }
}

// ── the parts of a page that can be held ──

extension View {
    /// The one ground behind the pages of a ``SlidingPages`` that holds them, because held pages
    /// draw none. Nothing on a system where pages are not held. Put it on the `SlidingPages`.
    @MainActor public func groundBehindHeldPages() -> some View {
        background {
            if HeldPages.possible { VinylGround() }
        }
    }

    /// The part of a page under its header. In a held page it slides; elsewhere it does nothing.
    @MainActor func slidesWhenHeld() -> some View {
        modifier(HeldContent())
    }

    /// A page's header, with anything that opens under it, such as the search field. In a held
    /// page that leaves, it fades out, and in one that comes in, it fades in.
    @MainActor func headerWhenHeld() -> some View {
        modifier(HeldHeader())
    }

    /// A page's ``PageTabs`` row. In a held page that leaves, it is hidden at once, because the
    /// row of the page that comes in stands in the same place.
    @MainActor func rowWhenHeld() -> some View {
        modifier(HeldRow())
    }

    /// The page's ground (``VinylGround``), except in a held page: there one ground is drawn
    /// behind all the pages (`groundBehindHeldPages()`). Use it in place of
    /// `.background { VinylGround() }` on a page that ``SlidingPages`` may hold.
    @MainActor func groundUnlessHeld() -> some View {
        modifier(HeldGround())
    }
}

private struct HeldContent: ViewModifier {
    @Environment(\.pageSlide) private var slide

    func body(content: Content) -> some View {
        content.offset(x: slide.shift)
    }
}

private struct HeldHeader: ViewModifier {
    @Environment(\.pageSlide) private var slide

    func body(content: Content) -> some View {
        content.opacity(slide.presence)
    }
}

private struct HeldRow: ViewModifier {
    @Environment(\.pageSlide) private var slide

    func body(content: Content) -> some View {
        content
            .opacity(slide.rowShows ? 1 : 0)
            // At once and not in the slide's animation: two rows half seen in one place look
            // fainter than one row.
            .animation(nil, value: slide.rowShows)
    }
}

private struct HeldGround: ViewModifier {
    @Environment(\.pageSlide) private var slide

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            // The stack's own background is clear in every case. A page that draws its ground
            // covers it anyway, and a held page must let the pages under it show through.
            content
                .background {
                    if !slide.groundBehind { VinylGround() }
                }
                .containerBackground(Color.clear, for: .navigation)
        } else {
            content.background { VinylGround() }
        }
    }
}
