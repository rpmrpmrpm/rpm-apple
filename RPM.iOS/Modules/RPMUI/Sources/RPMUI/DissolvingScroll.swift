import SwiftUI
import UIKit
import Observation
import os
import RPMDesign

/// A scroller whose content fades out at its top edge instead of being cut off in a straight
/// line.
///
/// A `ScrollView` clips at its own bounds, so a wall under a heading loses its rows on an
/// invisible line: a cover is whole in one frame and gone in the next. The desktop solves this
/// in two places, `PegasusChrome.RecordFade` at the ends of an open record's running order and
/// `PhotoFootFade` at the foot of the track info pane. This is the same solution on the phone.
///
/// **The band is a mask, not a scrim.** There is no single colour to fade to, because the app
/// is drawn on the vinyl plate. A gradient with one colour would look like a shadow over the
/// top of the wall. So the pixels are removed instead, as the desktop's `CompositionMaskBrush`
/// does and as `.mask` does here.
///
/// **The depth grows with the scroll**, so a wall at rest is not changed at all: see
/// ``RPMDesign/EdgeFade``.
public struct DissolvingScroll<Content: View>: View {
    private let content: Content

    /// How far the content has scrolled off the top. It is held in a separate observable object,
    /// and this view's body never reads it.
    ///
    /// It changes on every frame of a scroll. If this body read it, the scroller and all its
    /// content would be rebuilt 60 times a second. Only the mask reads it, so a scroll redraws
    /// the band and nothing else. The needle strip is a separate view for the same reason (see
    /// ``PlayerNeedle``).
    @State private var reach = ScrollReach()

    /// The height of the page's own chrome over the scroller's top, for a scroller that starts at
    /// the top of the screen with no header bar over it: the status bar and a floating title or
    /// back key. Zero for a scroller under a header bar. See ``TopEdge``.
    private let under: Double

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.under = 0
    }

    /// A scroller that starts at the top of the screen, under `under` points of the status bar and
    /// the page's floating title or back key, with no header bar. Content that scrolls up there
    /// fades into the page's own background: see ``TopBand``.
    public init(under: Double, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.under = under
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Inside the content, because the probe finds the scroller from there. It is
                // zero by zero, so it only reads the offset and takes no space.
                ScrollProbe(reach: reach)
                    .frame(width: 0, height: 0)

                content
            }
        }
        // Passed down so a view in the content can read the pull without the page reading it.
        // See ``SwiftUI/View/growsWithPull(plate:anchor:)``.
        .environment(\.scrollReach, reach)
        .modifier(TopEdge(reach: reach, under: under))
    }
}

/// What a scroller does with its top edge.
///
/// - **Under a header bar**, the system's soft scroll edge is used (see
///   ``SwiftUI/View/scrollsUnder(_:)``). The system draws it only under a bar that has visible
///   content. An empty or transparent bar gets no edge.
/// - **With no header bar**, there are `under` points of the page's own chrome at the top of the
///   screen. The content fades into the page's background over that strip: ``TopBand``. Home
///   uses this too, although its title is a header. The system edge fades to a colour that it
///   samples from behind the page, and home's background changes with the banner, so the
///   sampled colour would be wrong.
/// - **Neither**, which is only a scroller under a header before iOS 26: the same fade over
///   ``RPMDesign/EdgeFade/depth`` points.
private struct TopEdge: ViewModifier {
    let reach: ScrollReach
    let under: Double

    @Environment(\.scrollsUnderBar) private var underBar

    func body(content: Content) -> some View {
        if under > 0 {
            content.mask { TopBand(reach: reach, height: under) }
        } else if underBar {
            content
        } else {
            content.mask { TopBand(reach: reach, height: EdgeFade.depth) }
        }
    }
}

private struct ScrollsUnderBarKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True where a `safeAreaBar` is over the scroller's top edge and the system draws the
    /// scroll edge under it. See ``SwiftUI/View/scrollsUnder(_:)``.
    var scrollsUnderBar: Bool {
        get { self[ScrollsUnderBarKey.self] }
        set { self[ScrollsUnderBarKey.self] = newValue }
    }
}

// ── the same fade on a `List` ──

extension View {
    /// Fades this `List`'s top edge in the same way as ``DissolvingScroll/init(under:content:)``
    /// does for a scroll view: `under` points of the status bar and the page's floating back key.
    ///
    /// For pages that must be a `List` (for swipe and reorder) and so cannot use
    /// ``DissolvingScroll``. One row in the list must use ``scrollProbe()``, which reads the
    /// offset.
    func dissolvesAtTop(under: Double) -> some View { modifier(DissolvesAtTop(under: under)) }

    /// Reads the offset of the list this row is in, for ``dissolvesAtTop(under:)``.
    ///
    /// **Use it on a row that stays on screen during the first ``RPMDesign/EdgeFade/depth``
    /// points of scrolling.** The head of a page does this for hundreds of points. A list removes
    /// a row once it has scrolled past, and the probe stops reading. Its last reading is then
    /// deeper than the ramp, and every offset past the ramp gives the same full band, so the old
    /// value still draws the correct result. When the person scrolls back, the row returns and
    /// the probe reads the offset again.
    func scrollProbe() -> some View { modifier(ScrollProbeHost()) }
}

private struct DissolvesAtTop: ViewModifier {
    let under: Double

    /// Held here and passed to the probe, for the same reason as in ``DissolvingScroll``: only
    /// the mask reads it, so a scroll redraws the band and nothing else.
    @State private var reach = ScrollReach()

    func body(content: Content) -> some View {
        content
            .environment(\.scrollReach, reach)
            .mask { TopBand(reach: reach, height: under) }
    }
}

private struct ScrollProbeHost: ViewModifier {
    @Environment(\.scrollReach) private var reach

    func body(content: Content) -> some View {
        content.background(alignment: .topLeading) {
            if let reach {
                ScrollProbe(reach: reach).frame(width: 0, height: 0)
            }
        }
    }
}

// ── the pull ──

extension View {
    /// Scales this view up about `anchor` by how far the enclosing ``DissolvingScroll`` is pulled
    /// down past its top, so a picture `plate` points tall keeps its top at the top of the screen.
    /// With `grows` false the view keeps its own size. This is for a view beside the one in front:
    /// if it grew about its own centre, it would reach sideways over its neighbour.
    ///
    /// **Only this modifier reads the pull.** If the page held the pull as state, the whole page
    /// body would run again on every frame of an over-pull, and the zoom would stutter.
    func growsWithPull(plate: Double, anchor: UnitPoint, grows: Bool) -> some View {
        modifier(GrowsWithPull(plate: plate, anchor: anchor, grows: grows))
    }
}

private struct GrowsWithPull: ViewModifier {
    let plate: Double
    let anchor: UnitPoint
    let grows: Bool

    @Environment(\.scrollReach) private var reach

    func body(content: Content) -> some View {
        let pulled = grows ? (reach?.pulled ?? 0) : 0
        return content.scaleEffect(1 + pulled / max(1, plate), anchor: anchor)
    }
}

private struct ScrollReachKey: EnvironmentKey {
    static let defaultValue: ScrollReach? = nil
}

extension EnvironmentValues {
    var scrollReach: ScrollReach? {
        get { self[ScrollReachKey.self] }
        set { self[ScrollReachKey.self] = newValue }
    }
}

/// How far the scroller has moved, in points below its own top. It is kept where only the band
/// can read it.
@MainActor
@Observable
final class ScrollReach {
    /// Negative while the list is pulled past its top. ``EdgeFade`` treats that as no band at
    /// all.
    var by: Double = 0

    /// How far the list is pulled down past its top, and zero otherwise. Written only when it
    /// changes, so an ordinary scroll, where it stays zero, does not update anything that reads
    /// it.
    var pulled: Double = 0

    /// Whether the content is at its top: scrolled down by less than a point, or pulled past it.
    /// Written only when it changes, like ``pulled``, so a scroll updates its readers at most
    /// twice: when it leaves the top and when it returns. The home banner reads it to keep its
    /// cards still.
    var atTop = true
}

/// The mask: content is removed at the top of a band `height` points tall, less and less further
/// down, and all content is kept from the foot of the band. The removed content shows the
/// page's own background, whatever it is, and not a fixed colour.
///
/// **The grading matches the system's soft edge**: nearly all content is removed behind the
/// chrome, easing to nothing ``RPMDesign/EdgeFade/depth`` points below the foot of the chrome,
/// as the system edge continues past its header. A gentler grading, with no blur to soften what
/// is left, would make the rows behind the title look unfaded.
///
/// **No effect at rest, full effect after ``RPMDesign/EdgeFade/depth`` points of scrolling**, so
/// a picture that runs up behind the clock at rest is whole, and the band appears as the person
/// scrolls.
private struct TopBand: View {
    let reach: ScrollReach
    let height: Double

    /// How much is removed at each stop down the band, at full strength.
    private static let taken: [(at: Double, amount: Double)] = [(0, 1), (0.45, 0.95), (0.75, 0.6), (1, 0)]

    var body: some View {
        GeometryReader { area in
            let strength = EdgeFade.head(scrolled: reach.by, viewport: area.size.height,
                                         depth: EdgeFade.depth) / EdgeFade.depth

            VStack(spacing: 0) {
                LinearGradient(stops: Self.taken.map {
                                   .init(color: .black.opacity(1 - strength * $0.amount), location: $0.at)
                               },
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: height + EdgeFade.depth)

                Color.black
            }
        }
        // Start from the top of the screen. A list that ignores the top safe area still gives
        // that area to its mask. Without this, the band would start under the status bar, which
        // is 62 points lower than on a page that ignores the safe area.
        .ignoresSafeArea(edges: .top)
        // Solid below the foot as well. The scroller's frame ends at the top of the tab bar,
        // but its content scrolls on under the bar. A mask the size of the frame would hide
        // that content and cut rows off in a straight line above the glass.
        .overlay(alignment: .bottom) {
            Color.black
                .frame(height: RPMSafeArea.window.height)
                .offset(y: RPMSafeArea.window.height)
        }
    }
}

// ── reading the offset ──

/// Reads the scroller's offset from the `UIScrollView` underneath, not from the geometry of a
/// marker view.
///
/// **The desktop does the same**: `RecordScroll_ViewChanged` reads `VerticalOffset` from the
/// scroller. A SwiftUI marker measured in a coordinate space depends on more things being true:
/// which space the scroller publishes, and whether the value the marker reports is available
/// outside the scroller at all. A `UIScrollView` is under every `ScrollView` on the phone, it
/// holds the real offset, and the offset changes on the main thread on every frame of a scroll.
private struct ScrollProbe: UIViewRepresentable {
    let reach: ScrollReach

    func makeUIView(context: Context) -> ProbeView { ProbeView() }

    func updateUIView(_ probe: ProbeView, context: Context) { probe.reach = reach }
}

/// An invisible view that finds the scroller it is inside and watches its offset.
@MainActor
private final class ProbeView: UIView {
    private static let log = Logger(subsystem: "com.rpm.player", category: "scroll")

    var reach: ScrollReach? {
        didSet { report() }
    }

    private var watching: NSKeyValueObservation?

    /// The scroller is searched for when the view has a window, because only then is this view
    /// in the hierarchy under the scroller. The search runs again on every move to a window,
    /// because a row can be removed from the tree and added to another one.
    override func didMoveToWindow() {
        super.didMoveToWindow()

        watching = nil
        guard window != nil, let scroller = enclosingScroller() else {
            if window != nil { Self.log.error("no scroll view over the fade probe") }
            return
        }

        // `.initial` means a wall that is already scrolled (for example when the person returns
        // to the tab) gets its band at once, not after the first touch.
        watching = scroller.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.report() }
        }

    }

    private func report() {
        guard let scroller = enclosingScroller() else { return }

        // The inset that the system keeps clear at the top counts as part of the top: an offset
        // of zero under a content inset is still a list at rest.
        let by = scroller.contentOffset.y + scroller.adjustedContentInset.top
        reach?.by = by

        let pulled = max(0, -by)
        if reach?.pulled != pulled { reach?.pulled = pulled }

        let atTop = by < 1
        if reach?.atTop != atTop { reach?.atTop = atTop }

        announce(by)
    }

    /// Logs the offset at most four times a second when `RPM_FADE_DIAG` is set. A missing band
    /// and a band drawn with zero strength look the same on screen, and this log shows which it
    /// is.
    private static let saying = ProcessInfo.processInfo.environment["RPM_FADE_DIAG"] != nil
    private var said = Date.distantPast

    private func announce(_ by: Double) {
        guard Self.saying, Date().timeIntervalSince(said) > 0.25 else { return }

        said = Date()
        Self.log.notice("scrolled \(by, format: .fixed(precision: 1)) points off the top")
    }

    private func enclosingScroller() -> UIScrollView? {
        var next = superview
        while let view = next {
            if let scroller = view as? UIScrollView { return scroller }
            next = view.superview
        }
        return nil
    }
}

extension View {
    /// Puts a page's header over the top of this content, which scrolls under it.
    ///
    /// On iOS 26 and later the header is a `safeAreaBar`: the scroll view below extends under
    /// it, its first row starts below it, and the system's soft scroll edge (a gradual blur and
    /// fade) is drawn under the header instead of ``DissolvingScroll``'s own fade. Glass in the
    /// header then has the content behind it. Before iOS 26 the header is placed above the
    /// content, and the content fades at its own top edge.
    func scrollsUnder<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(ScrollsUnder(bar: bar()))
    }
}

private struct ScrollsUnder<Bar: View>: ViewModifier {
    let bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .environment(\.scrollsUnderBar, true)
                .scrollEdgeEffectStyle(.soft, for: .top)
                .safeAreaBar(edge: .top, spacing: 0) { bar }
        } else {
            VStack(spacing: 0) {
                bar
                content
            }
        }
    }
}
