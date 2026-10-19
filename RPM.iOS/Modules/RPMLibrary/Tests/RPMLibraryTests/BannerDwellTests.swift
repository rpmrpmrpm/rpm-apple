import Testing
import Foundation
@testable import RPMLibrary

/// When the home banner moves to the next card by itself. It uses the desktop's timing.
struct BannerDwellTests {
    private func dwell(at: Int = 0, cards: Int = 5, loops: Bool = true, onScreen: Bool = true,
                       pageAtTop: Bool = true, still: Bool = true) -> BannerDwell {
        BannerDwell(at: at, ring: BannerRing(cards: cards, loops: loops), onScreen: onScreen,
                    pageAtTop: pageAtTop, still: still)
    }

    @Test func countsOnAVisibleStripAtRest() {
        #expect(dwell().counts)
    }

    /// With one card there is nowhere to step to. With none, there is nothing to show.
    @Test func doesNotCountWithFewerThanTwoCards() {
        #expect(!dwell(cards: 1).counts)
        #expect(!dwell(cards: 0).counts)
    }

    /// Home stays built under the other tabs. A countdown there would move a banner nobody can see,
    /// and the reader would come back to a card they never chose.
    @Test func doesNotCountOffScreen() {
        #expect(!dwell(onScreen: false).counts)
    }

    /// The page behind home takes its background from the card in front. When the page is scrolled down,
    /// the reader is looking at the rows, and a step would change the background under them.
    @Test func doesNotCountWhenThePageIsScrolledDown() {
        #expect(!dwell(pageAtTop: false).counts)
    }

    /// A step while the reader is dragging would move the card away from their finger.
    @Test func doesNotCountWhileTheStripIsMoving() {
        #expect(!dwell(still: false).counts)
    }

    /// When the strip comes to rest on the copy of the first card, it moves to the real first card. The
    /// countdown starts from there.
    @Test func doesNotCountOnTheCopyOfTheFirstCard() {
        #expect(!dwell(at: 5, cards: 5).counts)
    }

    @Test func stepsToTheNextCard() {
        #expect(dwell(at: 0).next == 1)
        #expect(dwell(at: 3).next == 4)
    }

    /// A swipe changes the card in front, which changes the task id and restarts the countdown. This works
    /// only because the card in front is part of the value.
    @Test func aSwipeIsADifferentCountdown() {
        #expect(dwell(at: 1) != dwell(at: 2))
        #expect(dwell(still: false) != dwell(still: true))
    }

    /// Back at the top of the page, the countdown starts again from the full hold, not from the point it
    /// had reached when the page was scrolled down.
    @Test func comingBackToTheTopIsANewCountdown() {
        #expect(dwell(pageAtTop: false) != dwell(pageAtTop: true))
    }

    /// The phone holds a card for the same time as the desktop. The test reads the desktop's source, so the
    /// two cannot drift apart without this test failing.
    @Test func holdsACardAsLongAsTheDesktop() throws {
        let rpm = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RPMLibraryTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // RPMLibrary
            .deletingLastPathComponent()   // Modules
            .deletingLastPathComponent()   // RPM.iOS
            .deletingLastPathComponent()   // RPM
        let source = try String(
            contentsOf: rpm.appending(path: "RPM.Desktop/Presentation/Main/Home/HomeBanner.cs"),
            encoding: .utf8)

        let line = try #require(source.split(separator: "\n")
            .first { $0.contains("const int DwellMs") })
        let digits = line.filter(\.isNumber)
        let desktop = try #require(Int(digits))

        #expect(BannerDwell.hold == .milliseconds(desktop))
    }
}

/// The strip as a loop: after the last card comes the first card, entering from the right.
struct BannerRingTests {
    /// The last card steps forward onto the copy of the first card, rather than back across every card to
    /// the first.
    @Test func theLastCardStepsForwardOntoTheCopyOfTheFirst() {
        let ring = BannerRing(cards: 5, loops: true)

        #expect(ring.slots == 6)
        #expect(ring.next(after: 4) == 5)
        #expect(ring.card(at: 5) == 0)
    }

    /// At rest on the copy, the strip moves to the first card itself. On any other card, it stays
    /// where it is.
    @Test func theCopyRestsOnTheFirstCard() {
        let ring = BannerRing(cards: 5, loops: true)

        #expect(ring.rest(at: 5) == 0)
        #expect(ring.rest(at: 4) == nil)
        #expect(ring.rest(at: 0) == nil)
    }

    /// If the strip is rebuilt with fewer cards, the slot in front can be past the end. It then rests on a
    /// card that exists.
    @Test func aSlotPastTheEndRestsOnACard() {
        let ring = BannerRing(cards: 3, loops: true)

        #expect(ring.rest(at: 7) == 1)
    }

    /// One card has nowhere to loop to, so no copy is drawn.
    @Test func oneCardHasNoCopy() {
        #expect(BannerRing(cards: 1, loops: true).slots == 1)
        #expect(BannerRing(cards: 0, loops: true).slots == 0)
    }

    /// Without a loop there is no copy, and the last card steps back to the first.
    @Test func withoutTheCopyTheLastCardStepsToTheFirst() {
        let ring = BannerRing(cards: 5, loops: false)

        #expect(ring.slots == 5)
        #expect(ring.next(after: 4) == 0)
    }
}
