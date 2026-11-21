import CoreGraphics

/// How the pages of the main tabs slide when the tab changes.
///
/// Both pages move the whole width of the screen, in the order the tabs stand in the bar. To a tab
/// on the right, the page shown leaves to the left and the new page comes in from the right. To a
/// tab on the left, the reverse. The tab bar and the mini player do not move. The Android app slides
/// its tabs the same way (`tabSlide`).
///
/// The tabs are given by their place in the bar, counted from the left.
public enum TabSlide {
    /// How long one slide takes, in seconds.
    public static let duration: Double = 0.28

    /// The side a page comes in from, as a share of the screen's width: 1 from the right, -1 from
    /// the left, and 0 when the tab does not change.
    public static func entry(from: Int, to: Int) -> CGFloat {
        to > from ? 1 : to < from ? -1 : 0
    }

    /// Where the page of the tab at `page` stands while the tab at `shown` is shown, as a share of
    /// the screen's width: 0 on the screen, -1 just past its left edge, 1 just past its right edge.
    ///
    /// A page leaving the screen moves here, so it leaves to the side away from the new tab. Every
    /// page off the screen stands just past the edge, never further, so a slide across three tabs
    /// is as quick as a slide to the next one.
    public static func place(of page: Int, shown: Int) -> CGFloat {
        page < shown ? -1 : page > shown ? 1 : 0
    }
}
