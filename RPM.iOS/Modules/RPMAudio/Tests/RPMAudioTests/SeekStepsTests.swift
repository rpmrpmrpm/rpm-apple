import Testing
@testable import RPMAudio

/// The same seek steps as the Android TV app's tests, in seconds.
@Suite struct SeekStepsTests {
    private let fourMinutes = 240.0

    @Test func aPressMovesTenSeconds() {
        #expect(SeekSteps.next(from: 60, way: 1, held: false, since: 5, duration: fourMinutes) == 70)
        #expect(SeekSteps.next(from: 60, way: -1, held: false, since: 5, duration: fourMinutes) == 50)
    }

    /// On a short track a held key moves at the minimum rate, 30 seconds a second.
    /// A 50 ms step moves 1.5 seconds.
    @Test func aHeldKeyOnAShortTrackMovesThirtySecondsASecond() {
        #expect(abs(SeekSteps.next(from: 60, way: 1, held: true, since: 0.05, duration: 120) - 61.5) < 1e-9)
    }

    /// On a long track a held key crosses the whole track in 6 seconds. A one-hour track moves
    /// 600 seconds a second, so a 50 ms step moves 30 seconds.
    @Test func aHeldKeyOnALongTrackCrossesItInSixSeconds() {
        #expect(abs(SeekSteps.next(from: 60, way: 1, held: true, since: 0.05, duration: 3600) - 90) < 1e-9)
    }

    /// A step after a long gap counts at most 0.25 seconds of time.
    @Test func aLongGapCountsAQuarterOfASecondAtMost() {
        #expect(abs(SeekSteps.next(from: 60, way: 1, held: true, since: 0.4, duration: 120) - 67.5) < 1e-9)
    }

    @Test func theStepStopsAtEitherEnd() {
        #expect(SeekSteps.next(from: 235, way: 1, held: false, since: 0, duration: fourMinutes) == fourMinutes)
        #expect(SeekSteps.next(from: 4, way: -1, held: false, since: 0, duration: fourMinutes) == 0)
    }

    /// A step time earlier than the previous step moves nothing. It never steps backwards.
    @Test func aStepWithNoTimeSinceMovesNothing() {
        #expect(SeekSteps.next(from: 60, way: 1, held: true, since: -0.02, duration: fourMinutes) == 60)
    }
}
