import Testing
import Foundation
import CoreGraphics
@testable import RPMDesign

@Test func aBoxDrawnFourWaysIsTheSameBox() {
    let byLines = VectorPath.parse("M0 0L10 0L10 10L0 10Z")
    let byShorthand = VectorPath.parse("M0 0H10V10H0Z")

    #expect(byLines.boundingBoxOfPath == byShorthand.boundingBoxOfPath)
    #expect(byLines.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 10))
}

@Test func numbersRunTogetherByTheirSignsAreStillTwoNumbers() {
    // Drawing programs write "M109 -143H102" with no comma. The minus sign separates the numbers.
    let path = VectorPath.parse("M109 -143H102V-100")
    #expect(path.boundingBoxOfPath == CGRect(x: 102, y: -143, width: 7, height: 43))
}

@Test func aCommandRepeatsWhileTheNumbersLast() {
    // One L command followed by three points.
    let path = VectorPath.parse("M0 0L5 0 10 0 10 5")
    #expect(path.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 5))
}

@Test func relativeCommandsMoveFromWhereThePenIs() {
    let absolute = VectorPath.parse("M10 10L20 10L20 20")
    let relative = VectorPath.parse("m10 10l10 0l0 10")

    #expect(absolute.boundingBoxOfPath == relative.boundingBoxOfPath)
}

@Test func closingAPathPutsThePenBackWhereItStarted() {
    // Without the return to the start, the second line would start at (10,10).
    let path = VectorPath.parse("M0 0H10V10ZL0 -5")
    #expect(path.boundingBoxOfPath.minY == -5)
}

@Test func aCurveIsPartOfTheOutline() {
    let path = VectorPath.parse("M0 0C0 -10 10 -10 10 0")
    #expect(path.boundingBoxOfPath.minY < 0)
}

/// Arcs are not drawn. The parser stops at such a command rather than guessing the pen position.
/// A guessed position would put a stray line across a letter.
@Test func aCommandThisDoesNotDrawStopsRatherThanGuesses() {
    let path = VectorPath.parse("M0 0H10A5 5 0 0 1 20 20")
    #expect(path.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 10, height: 0))
}

@Test func nothingIsAnEmptyPath() {
    #expect(VectorPath.parse("").isEmpty)
    #expect(VectorPath.parse("   ").isEmpty)
}

// ── fitting it into a box ──

@Test func aGlyphFillsTheBoxItIsGiven() {
    let square = VectorPath.parse("M0 0H10V10H0Z")
    let fitted = VectorPath.fitted(square, in: CGRect(x: 0, y: 0, width: 100, height: 100))

    #expect(fitted.boundingBoxOfPath == CGRect(x: 0, y: 0, width: 100, height: 100))
}

/// It keeps its proportions, and is centred in the room left over.
@Test func aWideGlyphIsCentredInATallBox() {
    let wide = VectorPath.parse("M0 0H20V10H0Z")
    let fitted = VectorPath.fitted(wide, in: CGRect(x: 0, y: 0, width: 100, height: 100))
        .boundingBoxOfPath

    #expect(fitted.width == 100)
    #expect(fitted.height == 50)
    #expect(fitted.minY == 25)
}

/// **The wordmark uses SVG coordinates, not a font's.** y grows downward, as on a screen. The
/// letters sit above the baseline at negative y, and the descender of the p hangs below it at
/// positive y. Fitting must not flip the path. Negative y is normal in these coordinates and does
/// not mean a font, so the path keeps its orientation.
@Test func aGlyphIsFittedAsItWasDrawn() {
    // Wide across the top, narrow at the bottom, in the wordmark's own coordinates.
    let heavyOnTop = VectorPath.parse("M0 -100H100V-90H0ZM0 -10H20V0H0Z")
    let fitted = VectorPath.fitted(heavyOnTop, in: CGRect(x: 0, y: 0, width: 100, height: 100))

    #expect(widestRun(of: fitted) < 50, "the wide bar ended up in the bottom half")
}

/// Where the widest part of the path sits: the smallest y at which it reaches full width.
private func widestRun(of path: CGPath) -> CGFloat {
    var highest = CGFloat.greatestFiniteMagnitude
    path.applyWithBlock { element in
        let point = element.pointee.points[0]
        if point.x > 90 { highest = Swift.min(highest, point.y) }
    }
    return highest
}

@Test func fittingNothingIsNotACrash() {
    let empty = VectorPath.parse("")
    #expect(VectorPath.fitted(empty, in: CGRect(x: 0, y: 0, width: 10, height: 10)).isEmpty)

    let square = VectorPath.parse("M0 0H10V10H0Z")
    #expect(!VectorPath.fitted(square, in: .zero).isEmpty)
}
