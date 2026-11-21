import Testing
import CoreGraphics
@testable import RPMDesign

/// Which way the tabs' pages slide. The tabs are counted from the left of the bar.
@Suite("The tabs slide")
struct TabSlideTests {
    @Test("a tab on the right comes in from the right")
    func toTheRight() {
        #expect(TabSlide.entry(from: 0, to: 3) == 1)
    }

    @Test("a tab on the left comes in from the left")
    func toTheLeft() {
        #expect(TabSlide.entry(from: 4, to: 1) == -1)
    }

    @Test("the same tab does not move")
    func sameTab() {
        #expect(TabSlide.entry(from: 2, to: 2) == 0)
    }

    /// Going right, the page that was shown leaves to the left, and the other way round.
    @Test("the page left behind goes out on the side away from the new tab")
    func leaving() {
        #expect(TabSlide.place(of: 0, shown: 2) == -1)
        #expect(TabSlide.place(of: 4, shown: 2) == 1)
    }

    @Test("the page shown stands on the screen")
    func shown() {
        #expect(TabSlide.place(of: 3, shown: 3) == 0)
    }

    @Test("a page far from the shown one waits just past the edge, never further")
    func neverFurther() {
        #expect(TabSlide.place(of: 0, shown: 4) == -1)
        #expect(TabSlide.place(of: 4, shown: 0) == 1)
    }

    /// The page coming in starts where it would stand if the old tab were still shown, so both
    /// rules agree on the side.
    @Test("the side a page comes in from is where it stood")
    func entryMatchesPlace() {
        for from in 0..<5 {
            for to in 0..<5 {
                #expect(TabSlide.entry(from: from, to: to) == TabSlide.place(of: to, shown: from))
            }
        }
    }
}
