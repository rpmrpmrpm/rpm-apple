import Testing
import Foundation
@testable import RPMLibrary

/// Where a face must not be placed on the banner's card, and the layout numbers that decide it.
///
/// The numbers have edge cases that are easy to miss, so they are calculated here and not in a layout
/// pass. The card's width comes from the strip, so it is not tested here.
struct HomeBannerTests {
    /// The cover and the text at the foot of the plate cover that part. The clear band is the area above
    /// them. A face placed below it would be behind the title.
    @Test func theClearBandIsAboveTheSleeveAndTheWriting() {
        let clear = HomeBannerMetrics.clearBottom

        #expect(clear > 0.2)
        #expect(clear < 1)
    }

    /// The clear band also stops short of the right edge, so a face is not cut by it.
    @Test func theClearBandStopsShortOfTheEdge() {
        let clear = HomeBannerMetrics.clearRight(plate: 390)

        #expect(clear < 1)
        #expect(clear > 0.9)
    }

    /// A plate no wider than its margins has no clear band left. The result must still be between 0 and
    /// 1. A negative value would be read as an invalid crop.
    @Test func aPlateTooNarrowToHaveABandStillAnswers() {
        let clear = HomeBannerMetrics.clearRight(plate: 10)

        #expect(clear > 0)
        #expect(clear <= 1)
    }

    // ── the card that runs up behind the heading ──

    /// The overhang is added on top of the plate. Nothing else moves: the plate keeps its own height, and
    /// the extra height is above it.
    @Test func theOverhangMakesTheCardTallerByExactlyItself() {
        #expect(HomeBannerMetrics.height(above: 120) == HomeBannerMetrics.height + 120)
        #expect(HomeBannerMetrics.height(above: 0) == HomeBannerMetrics.height)
    }

    /// A negative inset can come from a reading taken before the window exists. The card is never shorter
    /// than the plate.
    @Test func anOverhangReadBeforeThereWasAWindowIsNoOverhang() {
        #expect(HomeBannerMetrics.height(above: -40) == HomeBannerMetrics.height)
    }

    /// **The clear band grows with the card.** The cover and the text keep the same size at the foot, so
    /// on a taller card they cover a smaller share. A crop that used the short card's fraction would place
    /// the face too high, where it can sit behind the status bar.
    @Test func theClearBandGrowsWhenTheCardRunsUpBehindTheHeading() {
        let short = HomeBannerMetrics.clearBottom
        let tall = HomeBannerMetrics.clearBottom(above: 150)

        #expect(tall > short)
        #expect(tall < 1)
    }

    /// With no overhang the result is the plain value. Both paths use one formula, so they cannot
    /// drift apart.
    @Test func theClearBandWithNoOverhangIsThePlainOne() {
        #expect(HomeBannerMetrics.clearBottom == HomeBannerMetrics.clearBottom(above: 0))
    }

    // ── how deep the reflection runs ──

    /// The reflection must reach below the bottom of the first row's covers. Otherwise the picture ends on
    /// the row instead of under it.
    @Test func theReflectionEndsBelowTheFirstRowOfSleeves() {
        let art = 132.0
        let toTheSleeve = HomeBannerMetrics.dotsBand(cards: 3)
            + HomeBannerMetrics.rowsApart + HomeBannerMetrics.rowHeading + art

        #expect(HomeBannerMetrics.reflection(cards: 3, rowArt: art) > toTheSleeve)
    }

    /// A single card has no dots, so the row below starts higher and the reflection is shorter by the
    /// dots band.
    @Test func oneCardHasNoDotsToReachPast() {
        #expect(HomeBannerMetrics.reflection(cards: 1, rowArt: 132)
                + HomeBannerMetrics.dotsBand(cards: 2)
                == HomeBannerMetrics.reflection(cards: 2, rowArt: 132))
        #expect(HomeBannerMetrics.dotsBand(cards: 1) == 0)
    }

    /// The cover edge depends on the row's art size, so a larger row gives a deeper reflection.
    @Test func aDeeperRowIsADeeperReflection() {
        #expect(HomeBannerMetrics.reflection(cards: 2, rowArt: 180)
                > HomeBannerMetrics.reflection(cards: 2, rowArt: 132))
    }

    /// A row with a negative size is treated as size zero, so the depth is never negative.
    @Test func aRowOfNoSizeStillLeavesTheReflectionItsOwnRoom() {
        #expect(HomeBannerMetrics.reflection(cards: 1, rowArt: -50)
                == HomeBannerMetrics.reflection(cards: 1, rowArt: 0))
    }

    // ── the status bar over the card ──

    /// The card runs up behind the status bar, so the bar covers the top of the card. The result is the
    /// bar's height as a share of the whole card.
    @Test func theStatusBarCoversTheTopOfTheCard() {
        let covered = HomeBannerMetrics.clearTop(statusBar: 59, above: 120)

        #expect(abs(covered - 59 / HomeBannerMetrics.height(above: 120)) < 0.0001)
    }

    /// Without an overhang the card starts below the status bar, so nothing covers it.
    @Test func aCardWithNoOverhangHasNothingOverItsTop() {
        #expect(HomeBannerMetrics.clearTop(statusBar: 59, above: 0) == 0)
    }

    /// A negative inset can come from a reading taken before the window exists. It covers nothing.
    @Test func aNegativeStatusBarCoversNothing() {
        #expect(HomeBannerMetrics.clearTop(statusBar: -10, above: 120) == 0)
    }
}
