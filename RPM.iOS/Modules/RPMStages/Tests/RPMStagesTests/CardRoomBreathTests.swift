import Testing
import Foundation
@testable import RPMStages

/// What lights a room that has no record playing in it.
///
/// **Held to the desktop's constants.** `CardRoomArt` breathes its three envelopes on cycles so
/// that a card room is never a still picture. If these numbers differ from that file's, the
/// desktop and iOS apps draw different rooms from the same figures.
struct CardRoomBreathTests {
    /// Silence is never sent to the shader. Every envelope stays above zero at every moment, so
    /// the figures are always being swelled by something.
    @Test func theRoomIsNeverSilent() {
        for tick in stride(from: 0.0, to: 60.0, by: 0.25) {
            let breath = CardRoomBreath.at(CardRoomBreath.clock(tick))

            #expect(breath.bass > 0.03, "bass fell to \(breath.bass) at \(tick)s")
            #expect(breath.middle > 0.01, "middle fell to \(breath.middle) at \(tick)s")
            #expect(breath.air > 0.005, "air fell to \(breath.air) at \(tick)s")
        }
    }

    /// And never above what a ground may be: a card is not a display, and the constants were
    /// tuned around the middle values.
    @Test func itStaysLowEnoughToBeAGround() {
        for tick in stride(from: 0.0, to: 60.0, by: 0.25) {
            let breath = CardRoomBreath.at(CardRoomBreath.clock(tick))

            #expect(breath.bass <= 0.37)
            #expect(breath.middle <= 0.31)
            #expect(breath.air <= 0.24)
        }
    }

    /// **The three envelopes do not beat together**, which stops the room pulsing. At this rate
    /// their cycles are 11.9, 8.8 and 17.0 seconds and they start out of phase.
    ///
    /// The test allows rare coincidence. The desktop note says the three cycles have no useful
    /// common multiple, but 0.53 and 0.71 are within 1.4% of the ratio 3 to 4, so bass and
    /// middle come back into step about once a minute. This does not read as a beat because the
    /// third cycle is far from both. So the test limits the SHARE of time when all three are
    /// near their peaks (four instants in five minutes, a coincidence and not a rhythm). It
    /// does not claim that this never happens.
    @Test func theThreeDoNotBeatTogether() {
        var together = 0, taken = 0

        for tick in stride(from: 0.0, to: 300.0, by: 0.1) {
            let breath = CardRoomBreath.at(CardRoomBreath.clock(tick))

            taken += 1
            if breath.bass > 0.35, breath.middle > 0.29, breath.air > 0.22 { together += 1 }
        }

        let share = Double(together) / Double(taken)
        #expect(share < 0.01, "all three sat near their peaks for \(share * 100)% of five minutes")
    }

    /// The clock is sped up as a whole, not each rate in turn, so drift, orbit and wobble keep
    /// the proportions they were tuned with.
    @Test func theClockIsQuickenedAndNotTheRates() {
        #expect(CardRoomBreath.clock(1) == CardRoomBreath.rate)
        #expect(CardRoomBreath.clock(0) == 0)
    }

    /// The same moment gives the same room, on every machine and after every restart. Nothing
    /// is random.
    @Test func oneMomentIsOneRoom() {
        let once = CardRoomBreath.at(12.5)
        let again = CardRoomBreath.at(12.5)

        #expect(once == again)
    }
}
