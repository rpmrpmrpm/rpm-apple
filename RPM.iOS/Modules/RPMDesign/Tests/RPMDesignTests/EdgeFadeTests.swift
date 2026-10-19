import Testing
import Foundation
@testable import RPMDesign

/// Checks the rule that the desktop's `PegasusChrome.RecordFade` uses. The phone's wall is
/// masked with the same numbers, so the two must agree.

@Test(arguments: [
    (0.0, 800.0, 0.0),      // at the top: no band, the first row is drawn whole
    (10.0, 800.0, 10.0),    // the band grows one point for each point scrolled
    (29.0, 800.0, 29.0),
    (30.0, 800.0, 30.0),    // full depth
    (4000.0, 800.0, 30.0),  // and stays at that depth for the rest of the list
    (-40.0, 800.0, 0.0),    // scrolled past the top: still no band
])
func theBandGrowsWithTheScrollAndStopsAtItsDepth(
    scrolled: Double, viewport: Double, expected: Double
) {
    #expect(EdgeFade.head(scrolled: scrolled, viewport: viewport, depth: 30) == expected)
}

@Test func aBandIsNeverDeeperThanTheListItDissolves() {
    #expect(EdgeFade.head(scrolled: 500, viewport: 18, depth: 30) == 18)
}

@Test(arguments: [0.0, -10.0, Double.nan])
func anUnmeasuredViewportAnswersNoBand(viewport: Double) {
    #expect(EdgeFade.head(scrolled: 500, viewport: viewport, depth: 30) == 0)
}

@Test func anUnreadOffsetAnswersNoBand() {
    #expect(EdgeFade.head(scrolled: .nan, viewport: 800, depth: 30) == 0)
}

@Test func theDepthIsTheOneTheDesktopUses() {
    #expect(EdgeFade.depth == 30)
}
