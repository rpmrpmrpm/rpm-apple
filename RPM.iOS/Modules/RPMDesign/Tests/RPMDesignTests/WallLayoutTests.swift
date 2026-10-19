import Testing
import Foundation
@testable import RPMDesign

/// The desktop tests for this layout are `RPM.Core.Tests/AlbumGridLayoutTests.cs` and
/// `AlbumCaptionTests.cs`. The `AnchorLost` cases are left out. They check that a WinUI repeater
/// keeps its place in its own extent estimate. A `UICollectionView` has no such estimate, so those
/// cases do not apply.

// ── how many columns ──

@Test(arguments: [
    (800.0, 160.0, 5),   // exact fit
    (830.0, 160.0, 5),   // 5.19, nearest is 5, the remainder stretches the cards
    (880.0, 160.0, 6),   // 5.5 rounds up, 6 slightly smaller cards
    (159.0, 160.0, 1),   // narrower than one target still shows one
    (0.0, 160.0, 1),     // not yet measured
    (-5.0, 160.0, 1),    // bogus width
])
func columnsRoundToNearestAndNeverBelowOne(width: Double, target: Double, expected: Int) {
    #expect(WallLayout.columns(for: width, targetStride: target) == expected)
}

@Test func aZeroTargetFallsBackToTheMinimum() {
    #expect(WallLayout.columns(for: 800, targetStride: 0) == 1)
}

// ── how wide each one is ──

@Test(arguments: [
    (800.0, 5, 400.0, 160.0),    // 800 / 5, exact
    (830.0, 5, 400.0, 166.0),    // 830 / 5, exact
    (833.0, 5, 400.0, 166.0),    // 166.6, floored, so the row never wraps
    (1000.0, 1, 280.0, 280.0),   // one card in a wide wall is capped
    (0.0, 5, 280.0, 280.0),      // unmeasured, so the cap: the widest allowed
])
func strideFillsTheRowFlooredAndCapped(
    width: Double, columns: Int, max: Double, expected: Double
) {
    #expect(WallLayout.stride(for: width, columns: columns, maxStride: max) == expected)
}

@Test func aBadColumnCountIsTreatedAsOne() {
    #expect(WallLayout.stride(for: 600, columns: 0, maxStride: 800) == 600)
}

/// The row fills the width edge to edge, with whole cards. It is never wider than the wall.
@Test func aFittedRowNeverOverflowsItsWall() {
    for width in stride(from: 320.0, through: 1400.0, by: 7) {
        let (columns, stride) = WallLayout.fit(
            available: width, targetStride: 180, maxColumns: 4)

        #expect(Double(columns) * stride <= width, "\(columns) x \(stride) overflows \(width)")
        #expect(columns >= 1 && columns <= 4)
    }
}

/// A pinch can ask for covers the size of postage stamps. On a phone, a wall that many albums
/// across is a texture, not a library, so the column count has a limit.
@Test func theColumnCountIsClampedWhereAPinchWouldRunAway() {
    #expect(WallLayout.fit(available: 400, targetStride: 20, maxColumns: 4).columns == 4)
    #expect(WallLayout.fit(available: 400, targetStride: 4000, maxColumns: 4).columns == 1)
}

// ── the writing under the cover ──

private let oneAcross = 360.0
private let twoAcross = 170.0
private let fourAcross = 78.0

/// At exactly the size the wall opens at, the scale factor is 1, so each figure is its base value.
@Test func atTheSizeTheWallOpensAtNothingHasMoved() {
    let caption = AlbumCaption.of(art: twoAcross)
    #expect(caption.album == 15)
    #expect(caption.artist == 14)
    #expect(caption.badge == 13)
    #expect(caption.albumLine == 20)
    #expect(caption.artistLine == 19)
}

@Test func aBiggerCoverCarriesBiggerWriting() {
    #expect(AlbumCaption.of(art: oneAcross).album > AlbumCaption.of(art: twoAcross).album)
}

@Test func aSmallerCoverCarriesSmallerWriting() {
    #expect(AlbumCaption.of(art: fourAcross).album < AlbumCaption.of(art: twoAcross).album)
}

/// If two column counts gave the same size, the scaling would do nothing.
@Test func eachColumnCountReadsDifferentlyFromTheNext() {
    let sizes = [oneAcross, 240.0, twoAcross, 120.0, fourAcross]
        .map { AlbumCaption.of(art: $0).album }
    #expect(Set(sizes).count == sizes.count, "two column counts read the same: \(sizes)")
}

/// Below eleven points, a record's name over a photograph is hard to read at arm's length.
@Test func theWritingNeverGoesBelowWhatCanBeRead() {
    #expect(AlbumCaption.of(art: 8).album >= 11)
}

/// Above twenty points, the writing competes with the cover it belongs to.
@Test func theWritingNeverGrowsIntoAHeading() {
    #expect(AlbumCaption.of(art: 2000).album <= 20)
}

/// The clamp is applied to the factor, not to each figure. So the relation between the two sizes
/// holds at both ends, rather than both collapsing to the floor.
@Test func theArtistStaysSmallerThanTheTitleAtBothEnds() {
    #expect(AlbumCaption.of(art: 8).artist < AlbumCaption.of(art: 8).album)
    #expect(AlbumCaption.of(art: 2000).artist < AlbumCaption.of(art: 2000).album)
}

@Test func aCoverOfNoSizeAnswersTheSizeTheWallOpensAt() {
    #expect(AlbumCaption.of(art: 0) == AlbumCaption.of(art: twoAcross))
}

/// Every card in a row must have the same line height. A fraction of a point that differs between
/// two cards would look wrong, so line heights are whole points.
@Test func aLineHeightIsAWholeNumberOfPoints() {
    for art in stride(from: 40.0, through: 400.0, by: 3.7) {
        let caption = AlbumCaption.of(art: art)
        #expect(caption.albumLine == caption.albumLine.rounded())
        #expect(caption.artistLine == caption.artistLine.rounded())
    }
}

@Test func theSameCoverSizeAlwaysGivesTheSameCaption() {
    #expect(AlbumCaption.of(art: 137.4) == AlbumCaption.of(art: 137.4))
}

@Test func aLineIsTallerThanTheWritingOnIt() {
    for art in stride(from: 40.0, through: 400.0, by: 11.0) {
        let caption = AlbumCaption.of(art: art)
        #expect(caption.albumLine > caption.album)
        #expect(caption.artistLine > caption.artist)
    }
}

@Test func aCardIsTheCoverTheTwoLinesAndTheGaps() {
    let caption = AlbumCaption.of(art: twoAcross)
    #expect(caption.card == twoAcross + AlbumCaption.artGap + caption.albumLine
            + AlbumCaption.lineGap + caption.artistLine + AlbumCaption.below)
}

/// The square root is the whole idea. A cover with four times the area is viewed from the same
/// distance, so its title does not need four times the size, nor even two times.
@Test func writingGrowsBySquareRootRatherThanWithTheCover() {
    // Both inside the unclamped band, which runs from an art edge of about 91 to about 302.
    // Outside that band the clamp decides the size, not the curve.
    let small = AlbumCaption.of(art: 100).album
    let doubleArea = AlbumCaption.of(art: 200).album

    // Twice the area means the square root of two times the edge, so the size grows by about 1.41,
    // not by 2.
    let ratio = doubleArea / small
    #expect(ratio > 1.35 && ratio < 1.48, "the writing scaled by \(ratio)")
}

/// Outside the band the clamp decides the size, and that is intended. The curve alone would give a
/// four-across title about 8 points, and a one-across title about 23 points.
@Test func theClampTakesOverBeforeTheCurveReachesEitherEnd() {
    let curveAtFourAcross = 15 * (fourAcross / AlbumCaption.anchor).squareRoot()
    let curveAtOneAcross = 15 * (oneAcross / AlbumCaption.anchor).squareRoot()

    #expect(curveAtFourAcross < AlbumCaption.smallest, "the floor is not doing anything")
    #expect(curveAtOneAcross > AlbumCaption.largest, "the ceiling is not doing anything")

    #expect(AlbumCaption.of(art: fourAcross).album == AlbumCaption.smallest)
    #expect(AlbumCaption.of(art: oneAcross).album == AlbumCaption.largest)
}

/// A whole row of cards is one height, because they all take the same art edge.
@Test func everyCardInARowIsTheSameHeight() {
    let (_, stride) = WallLayout.fit(available: 393, targetStride: 180, maxColumns: 4)
    let art = stride - 24   // the wall's gutter

    let heights = (0..<4).map { _ in AlbumCaption.of(art: art).card }
    #expect(Set(heights).count == 1)
}

// ── the wall inside its own margins ──

/// The wall's two spacing values, defined on `AlbumWall` in the UI module. The UI module has no
/// tests that run without a device, so the values are copied here for the assertions below.
private let wallEdge: Double = 20
private let wallGutter: Double = 24

/// What a row of `columns` cards occupies: the cards, the gaps between them, and a margin at each
/// end.
private func rowWidth(columns: Int, art: Double) -> Double {
    Double(columns) * art + Double(columns - 1) * wallGutter + 2 * wallEdge
}

/// **The bug this guards against is silent.** A wall sized against the whole screen and then
/// inset lays out cards wider than their columns. SwiftUI gives no warning. On a phone, at one
/// zoom level, it clips the cover. So the row must fit at every width and every zoom.
@Test func aRowOfCoversFitsInsideTheWallsMargins() {
    for screen in [320.0, 375, 390, 393, 402, 430, 744, 1024] {
        for target in [70.0, 120, 194, 260, 400, 900] {
            let (columns, art) = WallLayout.wall(
                available: screen, targetStride: target,
                edge: wallEdge, gutter: wallGutter, maxColumns: 4)

            #expect(rowWidth(columns: columns, art: art) <= screen + 0.5,
                    "\(columns) x \(art) overflows a \(screen) wall at target \(target)")
        }
    }
}

/// And it fills the wall. A wall that fits by leaving half a cover of white down one side is not
/// laid out properly. The row must fill the width.
@Test func aRowOfCoversFillsTheWallItFitsIn() {
    for screen in [375.0, 393, 430] {
        for target in [120.0, 194, 260] {
            let (columns, art) = WallLayout.wall(
                available: screen, targetStride: target,
                edge: wallEdge, gutter: wallGutter, maxColumns: 4)

            // Within one point per column. `stride` rounds each card down, so the last card is
            // never pushed off the edge.
            #expect(rowWidth(columns: columns, art: art) >= screen - Double(columns) - 0.5,
                    "\(columns) x \(art) leaves white on a \(screen) wall at target \(target)")
        }
    }
}

/// The wall a phone opens on, checked at a 393 point screen and the app's starting size. The wall
/// stands at the app's own edge margin of 20 points, the same as the heading above it, so the two
/// line up.
@Test func theWallAPhoneOpensOnStandsWhereTheHeadingDoes() {
    let (columns, art) = WallLayout.wall(available: 393, targetStride: 194,
                                         edge: wallEdge, gutter: wallGutter, maxColumns: 4)

    #expect(columns == 2)
    #expect(art == 164)

    // Two covers, one gap and two margins: the phone's width, less the one point that `stride`
    // rounds away, so the second cover is never pushed off the edge.
    #expect(rowWidth(columns: columns, art: art) == 392)
}

/// A pinch to either end still lays out a wall. The cards are never wider than the screen, and
/// there are never so many that they are a pixel across.
@Test func theMarginsHoldAtBothEndsOfAPinch() {
    let (wide, wideArt) = WallLayout.wall(available: 393, targetStride: 3000,
                                          edge: wallEdge, gutter: wallGutter, maxColumns: 4)
    #expect(wide == 1)
    #expect(rowWidth(columns: wide, art: wideArt) <= 393.5)

    let (small, smallArt) = WallLayout.wall(available: 393, targetStride: 1,
                                            edge: wallEdge, gutter: wallGutter, maxColumns: 4)
    #expect(small == 4)
    #expect(smallArt >= 1)
    #expect(rowWidth(columns: small, art: smallArt) <= 393.5)
}

/// An unmeasured wall answers one column, not nothing. So the first frame is never an empty screen.
@Test func anUnmeasuredWallStillAnswers() {
    let (columns, art) = WallLayout.wall(available: 0, targetStride: 194,
                                         edge: wallEdge, gutter: wallGutter, maxColumns: 4)
    #expect(columns == 1)
    #expect(art >= 1)
}

// ── the space for a playlist tile's name ──

/// A playlist tile is a record card with one piece of text instead of two. So the name takes both
/// lines and the gap between them. The tile is the same height as a record card at the same art
/// edge. Two heights in one grid would make the row jump as the user scrolls.
@Test func aNameGetsBothLinesAndTheGapBetweenThem() {
    let caption = AlbumCaption.of(art: twoAcross)
    #expect(caption.nameRoom == caption.albumLine + 2 + caption.artistLine)
}

@Test func aTileIsTheSameHeightAsARecordCard() {
    for art in [fourAcross, twoAcross, oneAcross] {
        let caption = AlbumCaption.of(art: art)
        let tile = art + AlbumCaption.artGap + caption.nameRoom + AlbumCaption.below
        #expect(tile == caption.card)
    }
}

@Test func theNameRoomGrowsWithTheCover() {
    #expect(AlbumCaption.of(art: oneAcross).nameRoom > AlbumCaption.of(art: fourAcross).nameRoom)
}

/// Every tile in a row shares an art edge, so every tile in a row shares this value.
@Test func theNameRoomIsAWholeNumberOfPoints() {
    for art in stride(from: 40.0, through: 400.0, by: 3.7) {
        let room = AlbumCaption.of(art: art).nameRoom
        #expect(room == room.rounded())
    }
}
