import Testing
@testable import RPMRadio

/// Tests for the dial's layout and tuning arithmetic. The desktop draws the dial but has no
/// tests for it, so the arithmetic lives in `DialCard`, where it can be checked without
/// looking at a screen.

private func signs(_ count: Int, _ caption: String = "ABC") -> [String] {
    Array(repeating: caption, count: count)
}

@Test func aShortListFitsTheGlass() {
    let card = DialCard.of(captions: signs(6), glass: 350)
    #expect(card.scaleWidth == 350, "a card of six names asked for \(card.scaleWidth)")
}

/// The card is drawn wider than the glass and slides under it. A crowded list then keeps
/// every sign, not only the first few.
@Test func aCrowdedListMakesTheCardLonger() {
    let card = DialCard.of(captions: signs(120), glass: 350)
    #expect(card.scaleWidth > 350)
}

/// A search with a thousand stations must not lay out a thousand signs to show twenty of
/// them, so the card is capped at six glasses wide.
@Test func theCardIsNeverLongerThanSixGlasses() {
    let card = DialCard.of(captions: signs(4000, "WWWW"), glass: 350)
    #expect(card.scaleWidth <= 350 * 6)
}

/// Each station is printed once, and no two signs on the same row overlap.
@Test func noTwoSignsOnOneRowOverlap() {
    let card = DialCard.of(captions: signs(40, "KEXP"), glass: 390)

    for row in 0..<max(card.nameRows, 1) {
        let onRow = card.printed.filter { $0.row == row }
        for (a, b) in zip(onRow, onRow.dropFirst()) {
            #expect(b.nameLeft >= a.markX + DialCard.squareSize / 2,
                    "row \(row): \(b.caption) starts before \(a.caption) ends")
        }
    }
}

/// The square sits on the station's position, so the needle crosses its centre when tuned.
/// The sign is set right against the left edge of the square.
@Test func theSignIsSetHardAgainstItsSquare() {
    let card = DialCard.of(captions: signs(8), glass: 350)
    let first = card.printed[0]

    #expect(first.nameLeft + first.width
            == first.markX - DialCard.squareSize / 2 - DialCard.squareGap)
}

/// A sign that fits beside its neighbours on no row keeps its graduation mark and loses its
/// caption, so no two captions overlap.
@Test func aSignThatClearsNoRowIsLeftOff() {
    let card = DialCard.of(captions: signs(300, "WWWW"), glass: 320)

    #expect(card.printed.count < 300)
    #expect(card.ticks.count == 300, "a station that lost its caption kept its graduation")
}

/// When the stations are too close together for each to have its own graduation, the card
/// prints evenly spaced graduations and no captions.
@Test func aCardTooCrowdedForGraduationsPrintsNoSignsEither() {
    let card = DialCard.of(captions: signs(5000, "W"), glass: 320)

    #expect(card.printed.isEmpty)
    #expect(card.ticks.count >= 8)
}

@Test func anEmptyDialPrintsNothingAndDoesNotDivideByZero() {
    let card = DialCard.of(captions: [], glass: 350)

    #expect(card.printed.isEmpty)
    #expect(card.nearest(to: 100, of: 0) == nil)
}

// ── tuning ──

/// With detents, the dial snaps to the nearest station on release, so it never stops between
/// two.
@Test func aPointOnTheCardDetentsOntoTheNearestStation() {
    let card = DialCard.of(captions: signs(10), glass: 350)

    for station in 0..<10 {
        #expect(card.nearest(to: card.markOf(station, of: 10), of: 10) == station)
    }
}

@Test func aPointPastEitherEndDetentsOntoTheEndStation() {
    let card = DialCard.of(captions: signs(10), glass: 350)

    #expect(card.nearest(to: -900, of: 10) == 0)
    #expect(card.nearest(to: 90_000, of: 10) == 9)
}

/// The slide is clamped, so the card cannot be dragged past either end. That would leave
/// blank glass in view.
@Test func theCardCannotBeSlidPastItsOwnEnds() {
    let card = DialCard.of(captions: signs(120), glass: 350)

    #expect(card.slide(bringing: 0, to: 300, glass: 350) == 0, "slid the left end inwards")
    #expect(card.slide(bringing: card.scaleWidth, to: 0, glass: 350)
            == -(card.scaleWidth - 350), "slid past the right end")
}

@Test func aCardNoLongerThanTheGlassDoesNotSlideAtAll() {
    let card = DialCard.of(captions: signs(4), glass: 350)
    #expect(card.slide(bringing: 100, to: 300, glass: 350) == 0)
}

// ── where the block sits ──

/// The instrument is centred as one block in the space below the readout. It is not pinned to
/// the top, which would leave the lower half of the dial empty.
@Test func theInstrumentIsCentredInTheRoomBelowTheReadout() {
    let card = DialCard.of(captions: signs(6), glass: 350, height: 176, readoutBottom: 54)

    #expect(card.namesTop > 54)
    #expect(card.scaleBottom <= 176)
    #expect(card.scaleBottom - card.scaleTop == DialCard.scaleSpan)
}

@Test func moreRowsOfSignsPushTheGraduationsDown() {
    let few = DialCard.of(captions: signs(6), glass: 350)
    let many = DialCard.of(captions: signs(60), glass: 350)

    #expect(many.nameRows > few.nameRows)
    #expect(many.scaleTop > few.scaleTop)
}

/// A sign is printed to the left of its square. The first station must sit far enough in that
/// its sign is still on the card, because there is nothing to scroll to off the left end.
@Test func theFirstSignIsOnTheCard() {
    for captions in [signs(8, "WWWW"), signs(80, "KEXP"), signs(3, "A")] {
        let card = DialCard.of(captions: captions, glass: 390)
        for mark in card.printed {
            #expect(mark.nameLeft >= 0,
                    "\(mark.caption) starts at \(mark.nameLeft) on a card of \(captions.count)")
        }
    }
}
