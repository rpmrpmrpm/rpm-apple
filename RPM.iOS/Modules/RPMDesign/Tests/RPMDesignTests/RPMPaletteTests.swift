import Testing
import Foundation
@testable import RPMDesign

/// Snapping a cover colour to the nearest palette accent makes a wall of thousands of covers look
/// like one set of colours, not many accidents of lighting. These tests check the cases that the
/// comments in `RPMPalette` describe.

// ── the generated set ──

@Test func theAssetsTenAccentsCameAcross() {
    #expect(RPMPalette.accents.count == 10)
    #expect(RPMPalette.accents.map(\.name)
        == ["Vermilion", "Rust", "Gold", "Lime", "Forest",
            "Azure", "Indigo", "Magenta", "Crimson", "Red"])
}

@Test func everyAccentCarriesItsThreeStopRamp() {
    for accent in RPMPalette.accents {
        #expect(accent.gradient.count == 3, "\(accent.name) has \(accent.gradient.count) stops")
    }
}

/// The ramp gets darker from top to foot: each stop is darker than the one before it.
@Test func everyRampGetsDarkerDownIt() {
    for accent in RPMPalette.accents {
        let lightness = accent.gradient.map { RPMPalette.oklab($0).l }
        #expect(lightness == lightness.sorted(by: >),
                "\(accent.name)'s ramp does not dim: \(lightness)")
    }
}

// ── snapping ──

@Test func anAccentSnapsToItself() {
    for accent in RPMPalette.accents {
        #expect(RPMPalette.nearest(to: accent.base)?.name == accent.name)
    }
}

/// **This is the case the distance is built to handle.** A plain distance in Oklab is dominated by
/// lightness for a muted colour. A dark navy press photo came out nearer Forest than Azure. A weak
/// blue and a dark green are both dark, and that is all they have in common. So hue is compared
/// first, and a blue photograph stays blue however it was lit.
@Test func aDarkMutedBlueIsBlueRatherThanDark() {
    let navy = RGB(28, 42, 74)
    let snapped = RPMPalette.nearest(to: navy)?.name

    // The claim is blue, not green. Which blue wins depends on the palette, so this test allows
    // either Azure or Indigo. Requiring one name would test the palette, not the rule.
    #expect(snapped == "Azure" || snapped == "Indigo", "a navy came out \(snapped ?? "nothing")")
    #expect(snapped != "Forest", "the lightness axis is dominating the sum again")
}

/// Lime and Forest are the same hue at very different lightness. Lightness is kept in the
/// distance, at half weight, so light and dark greens stay apart.
@Test func lightAndDarkGreenDoNotCollapseIntoOneAnother() {
    let bright = RPMPalette.nearest(to: RGB(150, 220, 60))?.name
    let deep = RPMPalette.nearest(to: RGB(18, 70, 32))?.name

    #expect(bright == "Lime")
    #expect(deep == "Forest")
}

/// A grey has no hue, so it is not nearer one accent than another. Snapping it anyway would pick
/// whichever accent is least saturated. A monochrome portrait would then come back tinted dark
/// green for no reason.
@Test func aGreyHasNoColourInItToBeNearAnything() {
    #expect(RPMPalette.nearest(to: RGB(128, 128, 128)) == nil)
    #expect(RPMPalette.nearest(to: RGB(20, 20, 20)) == nil)
    #expect(RPMPalette.nearest(to: RGB(240, 240, 240)) == nil)
}

/// A warm grey has a chroma of about 0.015. A photograph with a visible colour cast is above
/// 0.023. The neutral line sits between the two. So a nearly neutral press photo keeps its own
/// tone, and a pale beige cover gets an accent.
@Test func theLineBetweenAGreyAndACastIsWhereTheCommentSaysItIs() {
    let warmGrey = RGB(134, 128, 122)
    let beige = RGB(214, 186, 142)

    #expect(RPMPalette.oklch(warmGrey).chroma < RPMPalette.neutralChroma)
    #expect(RPMPalette.oklch(beige).chroma > RPMPalette.neutralChroma)

    #expect(RPMPalette.nearest(to: warmGrey) == nil)
    #expect(RPMPalette.nearest(to: beige) != nil)
}

/// Hue is circular, so red at 359 degrees and red at 1 degree are neighbours, not opposites.
@Test func hueWrapsRatherThanSplittingTheReds() {
    // Two colours a couple of degrees either side of the wrap.
    let justUnder = RGB(230, 30, 20)
    let justOver = RGB(230, 20, 45)

    #expect(RPMPalette.nearest(to: justUnder) != nil)
    #expect(RPMPalette.nearest(to: justOver) != nil)

    // Whatever they land on, the wrap must not make them far apart.
    let (l, c, h) = RPMPalette.oklch(justUnder)
    let (l2, c2, h2) = RPMPalette.oklch(justOver)
    var dh = abs(h - h2)
    if dh > .pi { dh = 2 * .pi - dh }
    #expect(dh < 0.5, "the reds came out \(dh) radians apart")
    #expect(abs(l - l2) < 0.2 && abs(c - c2) < 0.1)
}

// ── the colour space itself ──

/// Oklab's reference points. A wrong coefficient shows up here, rather than as a wall that snaps
/// oddly.
@Test func whiteAndBlackReadAsTheyShould() {
    let white = RPMPalette.oklab(RGB(255, 255, 255))
    #expect(abs(white.l - 1.0) < 0.001)
    #expect(abs(white.a) < 0.001)
    #expect(abs(white.b) < 0.001)

    let black = RPMPalette.oklab(RGB(0, 0, 0))
    #expect(abs(black.l) < 0.001)
}

/// The sRGB transfer curve is undone before colours are compared. Mid grey is about 0.6 in Oklab
/// lightness, not 0.5. The stored byte is a display encoding, so comparing bytes would compare the
/// encoding, not the light.
@Test func theTransferCurveIsUndone() {
    let mid = RPMPalette.oklab(RGB(128, 128, 128)).l
    #expect(mid > 0.55 && mid < 0.65, "mid grey read \(mid)")
}
