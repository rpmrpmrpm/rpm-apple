import Foundation
import Testing
@testable import RPMStages

/// The travel between two readings: what is drawn on the frames where nothing was measured.
///
/// **A ramp can be wrong without looking wrong.** A ramp that overshoots, never arrives, or
/// starts from the wrong end still draws a plausible row of bars that answers the music. It is
/// just not the reading any more, and the screen does not show that.
@Suite("The room between two readings")
struct RoomRampTests {

    func reading(_ level: Float, bands: Int = 4) -> RoomReading {
        RoomReading(run: [Float](repeating: level, count: bands),
                    bass: level, middle: level * 0.5, air: level * 0.25)
    }

    /// A ramp from silence to `level`, landing at ten on the clock, over a 25 ms beat.
    func ramp(to level: Float, bands: Int = 4) -> RoomRamp {
        RoomRamp(from: reading(0, bands: bands), to: reading(level, bands: bands),
                 at: 10, over: 0.025)
    }

    // ── the two ends ──

    @Test func itStandsAtTheEarlierReadingWhereTheTravelBegins() {
        let run = ramp(to: 1).read(10).run

        #expect(run.allSatisfy { $0 == 0 })
    }

    @Test func itHasArrivedByTheEndOfTheBeat() {
        let there = ramp(to: 1).read(10.025)

        #expect(there.run.allSatisfy { $0 == 1 })
        #expect(there.bass == 1)
    }

    @Test func itIsHalfwayAtHalfABeat() {
        let half = ramp(to: 1).read(10 + 0.0125)

        for band in half.run { #expect(abs(band - 0.5) < 0.001) }
        #expect(abs(half.middle - 0.25) < 0.001)
    }

    // ── and never past them ──

    /// A beat that overran is a bar holding still. **This is the difference between
    /// interpolating and extrapolating**: if the ramp ran on past the end, a run answering a
    /// transient would draw a level that nothing measured.
    @Test func itDoesNotCarryOnPastWhatWasMeasured() {
        let late = ramp(to: 1).read(10 + 1)

        #expect(late.run.allSatisfy { $0 == 1 })
        #expect(late.air == 0.25)
    }

    /// A clock that has gone backwards. A monotonic clock never does this, but a wall clock
    /// can.
    @Test func itDoesNotTravelBackwardsBeforeTheReadingLanded() {
        #expect(ramp(to: 1).read(9).run.allSatisfy { $0 == 0 })
    }

    // ── the awkward ones ──

    /// The first reading after the engine names its rate: there is no earlier run of the same
    /// width to travel from, and half of one is not a spectrum.
    @Test func itTakesANewRunWholeWhenTheOldOneWasADifferentLength() {
        let grown = RoomRamp(from: reading(0, bands: 2), to: reading(1, bands: 128),
                             at: 10, over: 0.025)

        let mid = grown.read(10 + 0.0125)
        #expect(mid.run.count == 128)
        #expect(mid.run.allSatisfy { $0 == 1 })
    }

    /// A beat of zero would cause a division by zero.
    @Test func itIsTheLaterReadingWhenThereIsNoBeatToTravelOver() {
        let none = RoomRamp(from: reading(0), to: reading(1), at: 10, over: 0)

        #expect(none.read(10).run.allSatisfy { $0 == 1 })
    }

    @Test func aRoomAtRestIsSilentAtEveryInstant() {
        #expect(RoomRamp.still.read(0).run.isEmpty)
        #expect(RoomRamp.still.read(1_000).bass == 0)
    }

    /// Falling is the same arithmetic as rising, and the fall is the half that gives the run
    /// its shape: a bar caught halfway down and never reaching the floor is what the ease in
    /// `RoomBands` is tuned against.
    @Test func itTravelsDownwardsJustAsFar() {
        let falling = RoomRamp(from: reading(1), to: reading(0), at: 10, over: 0.025)

        for band in falling.read(10 + 0.0125).run { #expect(abs(band - 0.5) < 0.001) }
    }
}
