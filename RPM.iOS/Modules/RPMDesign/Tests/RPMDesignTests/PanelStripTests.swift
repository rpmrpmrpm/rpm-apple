import Testing
@testable import RPMDesign

/// Panels side by side in a horizontal scroller that comes to rest on a panel. Examples are the
/// quick selection on home and Popular tracks on the artist page.

/// Where the last panel's left edge is on screen when the scroller is as far along as it goes.
private func lastPanelAtTheEnd(_ strip: PanelStrip, screen: Double, panels: Int, apart: Double) -> Double {
    let content = Double(panels) * strip.width + Double(panels - 1) * apart
    let furthest = strip.leading + content + strip.trailing - screen
    let lastLeft = strip.leading + Double(panels - 1) * (strip.width + apart)
    return lastLeft - furthest
}

@Suite struct PanelStripTests {
    @Test func onePanelFillsTheScreenBetweenTheMargins() {
        let strip = PanelStrip(screen: 390, margin: 20, peek: 32, panels: 1)

        #expect(strip.width == 350)
        #expect(strip.leading == 20)
        #expect(strip.trailing == 20)
    }

    @Test func severalPanelsLeaveRoomForTheNextOneToShow() {
        let strip = PanelStrip(screen: 390, margin: 20, peek: 32, panels: 4)

        #expect(strip.width == 318)
        #expect(strip.leading == 20)
    }

    /// The last panel comes to rest at the left margin, like every other panel. With only the
    /// margin after it, the last panel stopped at the margin plus the peek. The rows then looked
    /// indented.
    @Test func theLastPanelRestsAtTheLeftMargin() {
        for panels in 1...5 {
            let strip = PanelStrip(screen: 390, margin: 20, peek: 32, panels: panels)

            #expect(lastPanelAtTheEnd(strip, screen: 390, panels: panels, apart: 16) == 20)
        }
    }

    @Test func aScreenTooNarrowForAPanelGivesNoWidth() {
        #expect(PanelStrip(screen: 50, margin: 20, peek: 32, panels: 3).width == 0)
    }
}
