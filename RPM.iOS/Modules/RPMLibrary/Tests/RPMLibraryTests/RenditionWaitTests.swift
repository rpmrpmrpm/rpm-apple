import Testing
import Foundation
@testable import RPMLibrary

/// A download waits for the stored rendition instead of starting a live encode. These tests cover how
/// long the wait lasts, how often the store is checked, and what a change of rate does to the wait.
@Suite("Waiting for the store to make a rendition")
struct RenditionWaitTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }

    @Test func aTrackNobodyIsWaitingOnIsDue() {
        let wait = RenditionWait()
        #expect(wait.isDue("t1", kilobits: 320, now: start))
        #expect(!wait.isWaiting("t1"))
        #expect(wait.nextCheck == nil)
    }

    @Test func theFirstLiveAnswerStartsAWaitAndIsNotDueUntilTheFirstGap() {
        var wait = RenditionWait()
        #expect(wait.stillMaking("t1", kilobits: 320, now: start) == .new)

        #expect(wait.isWaiting("t1"))
        #expect(!wait.isDue("t1", kilobits: 320, now: at(RenditionWait.first - 1)))
        #expect(wait.isDue("t1", kilobits: 320, now: at(RenditionWait.first)))
        #expect(wait.nextCheck == at(RenditionWait.first))
    }

    @Test func theGapDoublesAndStopsAtTheLongest() {
        var wait = RenditionWait()
        _ = wait.stillMaking("t1", kilobits: 320, now: start)

        #expect(wait.stillMaking("t1", kilobits: 320, now: at(15)) == .waiting)
        #expect(wait.nextCheck == at(15 + 30))

        #expect(wait.stillMaking("t1", kilobits: 320, now: at(45)) == .waiting)
        #expect(wait.nextCheck == at(45 + 60))

        #expect(wait.stillMaking("t1", kilobits: 320, now: at(105)) == .waiting)
        #expect(wait.nextCheck == at(105 + RenditionWait.longest))
    }

    @Test func aChangeOfRateMakesTheTrackDueAtOnceAndStartsANewWait() {
        var wait = RenditionWait()
        _ = wait.stillMaking("t1", kilobits: 320, now: start)
        wait.asked(["t1"], kilobits: 320)

        #expect(wait.isDue("t1", kilobits: 256, now: at(1)))
        #expect(wait.stillMaking("t1", kilobits: 256, now: at(1)) == .new)

        // The new rate has not been asked for, whatever the old one was.
        #expect(wait.unasked == [256: ["t1"]])
    }

    @Test func waitingTooLongIsOverdueAndAsksTheStoreAgain() {
        var wait = RenditionWait()
        _ = wait.stillMaking("t1", kilobits: 320, now: start)
        wait.asked(["t1"], kilobits: 320)
        #expect(wait.unasked.isEmpty)

        let late = at(RenditionWait.giveUp + 1)
        #expect(wait.stillMaking("t1", kilobits: 320, now: late) == .overdue)

        // The wait starts again from now, and the ask goes out again.
        #expect(wait.unasked == [320: ["t1"]])
        #expect(wait.nextCheck == late.addingTimeInterval(RenditionWait.first))
        #expect(wait.stillMaking("t1", kilobits: 320, now: late.addingTimeInterval(20)) == .waiting)
    }

    @Test func unaskedIsGroupedByRate() {
        var wait = RenditionWait()
        _ = wait.stillMaking("b", kilobits: 320, now: start)
        _ = wait.stillMaking("a", kilobits: 320, now: start)
        _ = wait.stillMaking("c", kilobits: 192, now: start)

        #expect(wait.unasked == [320: ["a", "b"], 192: ["c"]])

        wait.asked(["a", "b"], kilobits: 320)
        #expect(wait.unasked == [192: ["c"]])
    }

    @Test func anAskAtTheOldRateDoesNotMarkAWaitRestartedAtANewOne() {
        var wait = RenditionWait()
        _ = wait.stillMaking("t1", kilobits: 320, now: start)

        // The rate changed while the ask for 320 was out.
        _ = wait.stillMaking("t1", kilobits: 256, now: at(1))
        wait.asked(["t1"], kilobits: 320)

        #expect(wait.unasked == [256: ["t1"]])
    }

    @Test func anAskForATrackNoLongerWaitedOnChangesNothing() {
        var wait = RenditionWait()
        _ = wait.stillMaking("t1", kilobits: 320, now: start)
        wait.forget(["t1"])
        wait.asked(["t1"], kilobits: 320)

        #expect(wait.isEmpty)
        #expect(wait.unasked.isEmpty)
    }

    @Test func forgettingEndsTheWait() {
        var wait = RenditionWait()
        _ = wait.stillMaking("t1", kilobits: 320, now: start)
        _ = wait.stillMaking("t2", kilobits: 320, now: at(5))

        wait.forget(["t1"])
        #expect(!wait.isWaiting("t1"))
        #expect(wait.isDue("t1", kilobits: 320, now: at(6)))
        #expect(wait.nextCheck == at(5 + RenditionWait.first))

        wait.forgetAll()
        #expect(wait.isEmpty)
        #expect(wait.nextCheck == nil)
    }
}
