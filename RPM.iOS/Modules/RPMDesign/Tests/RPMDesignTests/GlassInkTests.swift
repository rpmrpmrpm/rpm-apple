import Testing
import Foundation
@testable import RPMDesign

/// The bar under the mini player is drawn in the accent of the record. The accent comes from the
/// cover, not from a fixed choice. These tests check that the bar stays visible.

private func lightness(_ colour: RGB) -> Double { RPMPalette.oklab(colour).l }

private func accent(_ name: String) -> RGB {
    RPMPalette.accents.first { $0.name == name }!.base
}

// ── what passes through untouched ──

@Test func anAccentAlreadyLightEnoughIsDrawnAsItIs() {
    for name in ["Vermilion", "Rust", "Gold", "Lime", "Azure", "Magenta", "Crimson", "Red"] {
        #expect(lightness(accent(name)) >= GlassInk.floor, "\(name) is under the floor")
        #expect(GlassInk(accent(name)).rgb == accent(name), "\(name) was changed")
    }
}

@Test func whiteStaysWhite() {
    #expect(GlassInk.white.rgb == RGB(255, 255, 255))
}

// ── what gets lifted ──

@Test func theTwoDarkAccentsAreLiftedToTheFloor() {
    for name in ["Forest", "Indigo"] {
        let lifted = GlassInk(accent(name)).rgb
        #expect(lifted != accent(name), "\(name) was left dark")
        #expect(lightness(lifted) >= GlassInk.floor - 0.005,
                "\(name) came back at \(lightness(lifted))")
    }
}

@Test func blackIsNotDrawnAsBlack() {
    let ink = GlassInk(RGB(0, 0, 0)).rgb
    #expect(ink != RGB(0, 0, 0))
    #expect(lightness(ink) >= GlassInk.floor - 0.005)
}

@Test func everyAccentIsVisibleOnceCheckedAndNoneIsOverLifted() {
    for entry in RPMPalette.accents {
        let ink = GlassInk(entry.base).rgb
        let l = lightness(ink)
        #expect(l >= GlassInk.floor - 0.005, "\(entry.name) is at \(l)")

        // A colour that is already light enough keeps its lightness. A darker one is lifted to
        // the floor and no further, so the lift is the smallest that works.
        let was = lightness(entry.base)
        #expect(l <= max(was, GlassInk.floor) + 0.005, "\(entry.name) was lifted past the floor")
    }
}

/// The lift mixes in white, rather than changing Oklab's L, because mixing keeps the hue. A
/// lifted Forest must still be a green.
@Test func aLiftKeepsTheHue() {
    for name in ["Forest", "Indigo"] {
        let before = RPMPalette.oklch(accent(name))
        let after = RPMPalette.oklch(GlassInk(accent(name)).rgb)

        var turned = abs(after.hue - before.hue)
        if turned > .pi { turned = (2 * .pi) - turned }

        #expect(turned < 0.09, "\(name) turned \(turned) radians")
        #expect(after.chroma < before.chroma, "\(name) kept all its chroma")
    }
}

/// The floor sits just under Azure, the darkest accent that reads on the glass. If the floor
/// goes above 0.549, Azure would be lifted, and a colour that is already readable would be
/// washed out.
@Test func theFloorSitsUnderTheDarkestAccentThatReads() {
    let azure = accent("Azure")
    #expect(lightness(azure) > GlassInk.floor)
    #expect(lightness(azure) - GlassInk.floor < 0.02)
    #expect(GlassInk(azure).rgb == azure)
}

/// A colour just under the floor is moved only a little.
@Test func aColourJustUnderTheFloorIsBarelyMoved() {
    let under = RGB(3, 108, 200)        // Azure, slightly darker: lightness 0.533, just under the floor
    #expect(lightness(under) < GlassInk.floor)

    let lifted = GlassInk(under).rgb
    #expect(lifted != under)
    #expect(Int(lifted.g) - Int(under.g) < 8)
}
