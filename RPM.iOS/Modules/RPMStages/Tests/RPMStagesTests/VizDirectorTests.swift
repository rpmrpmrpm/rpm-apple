import Foundation
import Testing
@testable import RPMStages

/// The director that chooses the shots.
///
/// **The picture must be derived, and a fault there is invisible.** A visualiser that
/// accumulates its camera frame by frame looks the same while it plays, but gives a different
/// picture after a seek, a pause or a dropped frame. The claim here is that the same instant of
/// the same record is the same shot wherever you arrive from.
@Suite("The cutting room")
struct VizDirectorTests {

    /// The stand-in clock, which is the only clock this app has so far.
    func at(_ seconds: Double) -> BeatClock { .free(seconds) }

    // ── derived, not accumulated ──

    /// **The main test.** Asking for the same instant twice gives the same shot, whatever order
    /// the questions come in, so a seek lands where playing through would have.
    @Test func theSameInstantIsTheSameShotHoweverYouArriveAtIt() {
        let straight = (0..<40).map { VizDirector.shot(at(Double($0) * 0.5)) }

        // Now ask backwards, and out of order.
        let scattered = [39, 0, 17, 38, 1, 22].map {
            (index: $0, shot: VizDirector.shot(at(Double($0) * 0.5)))
        }

        for one in scattered {
            #expect(one.shot == straight[one.index], "\(one.index) came back different")
        }
    }

    /// A record played from the middle has flown as far as one played from the start. The
    /// distance is added up over the shots actually flown, never the current speed times the
    /// whole count.
    @Test func theFlightIsAddedUpRatherThanMultiplied() {
        // Straight through, adding each shot's own speed over its own beats.
        var walked = 0.0
        let step = 0.05
        for i in 1...4_000 {
            let beats = Double(i) * step
            walked += Double(VizDirector.shot(.free(beats * 60 / BeatClock.freeBpm)).advance) * step
        }

        let derived = VizDirector.travelled(4_000 * step)

        #expect(abs(Double(derived) - walked) < 1, "flown \(derived), walked \(walked)")
    }

    /// A cut picks a new speed, and the camera must not jump when it does. This is the fault
    /// that the added-up distance prevents: the multiplied form would move the camera tens of
    /// units on every cut.
    @Test func theCameraDoesNotJumpOnACut() {
        let cut = Double(VizDirector.beatsPerCut)

        for boundary in 1...12 {
            let before = VizDirector.travelled(Double(boundary) * cut - 1e-4)
            let after = VizDirector.travelled(Double(boundary) * cut + 1e-4)

            #expect(abs(after - before) < 0.01,
                    "cut \(boundary) jumped the camera from \(before) to \(after)")
        }
    }

    /// It always flies forwards. A camera that went backwards at a cut would look like the
    /// record rewinding.
    @Test func itAlwaysFliesForwards() {
        var last = VizDirector.travelled(0)

        for i in 1...500 {
            let now = VizDirector.travelled(Double(i) * 0.37)
            #expect(now > last, "went backwards at beat \(Double(i) * 0.37)")
            last = now
        }
    }

    /// Before the first bar line the count is negative, and the edit must not mirror around
    /// zero: truncation towards zero would hold the first cut for twice as long as every other,
    /// and then run the edit backwards.
    @Test func theEditDoesNotMirrorAroundTheFirstBarLine() {
        // Two cuts either side of zero, at the same distance from it.
        let before = VizDirector.shot(.init(beats: -4, beatsPerBar: 4, measured: true))
        let after = VizDirector.shot(.init(beats: 4, beatsPerBar: 4, measured: true))

        #expect(before.advance != after.advance, "the shot before the first bar mirrors the one after")
    }

    // ── the beat ──

    /// The pulse falls from one to nought across a beat, and is struck again on the next.
    @Test func thePulseIsStruckOnEveryBeat() {
        func pulse(_ beats: Double) -> Float {
            VizDirector.shot(.init(beats: beats, beatsPerBar: 4, measured: true)).pulse
        }

        #expect(pulse(3.0) > 0.99, "the beat did not land")
        #expect(pulse(3.5) < pulse(3.05), "it did not fall across the beat")
        #expect(pulse(3.99) < 0.01, "it had not fallen away by the next beat")
        #expect(pulse(4.0) > 0.99, "the next beat did not land")
    }

    /// **A constant rate, with no easing.** The lattice's slice and its travel are both the
    /// beat count, so any easing here would show on screen as the picture lurching on the beat.
    @Test func theBeatCountAdvancesEvenlyWithinABeat() {
        func beats(_ at: Double) -> Float {
            VizDirector.shot(.init(beats: at, beatsPerBar: 4, measured: true)).beats
        }

        let justAfter = beats(3.05) - beats(3.0)
        let wellInto = beats(3.95) - beats(3.90)

        #expect(abs(justAfter - wellInto) < 0.001,
                "it travelled \(justAfter) on the beat against \(wellInto) between beats")
    }

    // ── the rooms ──

    /// The eighth phrase of a record is always the same, on any day.
    @Test func aRoomIsTheSameRoomEveryTime() {
        #expect(VizDirector.room(8) == VizDirector.room(8))
        #expect(VizDirector.room(8) != VizDirector.room(9))
    }

    /// **A whole number of repeats.** A fractional fold count leaves a seam where the last
    /// wedge meets the first, running the length of the tunnel.
    @Test func theFoldCountIsAWholeNumberOfRepeats() {
        for section in -20...200 {
            let folds = VizDirector.room(section).folds

            #expect(folds == folds.rounded(), "section \(section) folds \(folds)")
            #expect(folds >= 3 && folds <= 9, "section \(section) folds \(folds)")
        }
    }

    /// Every figure a room hands to a shader is inside the range that shader was written for. A
    /// value out of range does not just give a wrong picture; it can make a shader divide by
    /// zero.
    @Test func everyRoomIsInRange() {
        for section in -50...500 {
            let room = VizDirector.room(section)

            #expect(room.arm > 2 && room.arm < 5)
            #expect(room.twist > 0 && room.twist < 0.4)
            #expect(room.ring > 1.5 && room.ring < 4.5)
            #expect(room.girth > 0.03 && room.girth < 0.12)
            #expect(room.cross > 0.2 && room.cross < 1.25)
        }
    }

    /// The walls slide from one room into the next and do not cut: the first beats of a section
    /// are a blend, and after that it has settled.
    @Test func aChangeOfRoomIsASlideRatherThanACut() {
        let perSection = Double(4 * VizDirector.barsPerSection)

        func blend(_ into: Double) -> Float {
            VizDirector.shot(.init(beats: perSection + into, beatsPerBar: 4, measured: true)).blend
        }

        #expect(blend(0) == 0, "the section opened already settled")
        #expect(blend(1) > 0 && blend(1) < 1, "it did not slide")
        #expect(blend(3) == 1, "it never settled")
    }

    /// A section knows which room it came from, so the slide has a starting point.
    @Test func aSectionRemembersTheRoomBeforeIt() {
        let perSection = Double(4 * VizDirector.barsPerSection)
        let shot = VizDirector.shot(.init(beats: perSection * 5 + 1, beatsPerBar: 4, measured: true))

        #expect(shot.now == VizDirector.room(5))
        #expect(shot.was == VizDirector.room(4))
    }

    /// Every section is lit by one of the four ramps, and the ramps are spread over all four
    /// and do not all land on one.
    @Test func theSectionsAreSpreadOverTheFourPalettes() {
        let perSection = Double(4 * VizDirector.barsPerSection)
        var seen = Set<Int>()

        for section in 0..<40 {
            let shot = VizDirector.shot(.init(beats: Double(section) * perSection + 1,
                                              beatsPerBar: 4, measured: true))
            #expect(shot.palette >= 0 && shot.palette < VizDirector.palettes)
            seen.insert(shot.palette)
        }

        #expect(seen.count == VizDirector.palettes, "only \(seen.count) of the ramps were ever used")
    }

    // ── the drop ──

    /// A drop opens the shot out: the camera stops wandering and looks straight down the
    /// tunnel, and the effect fades over the bars after the drop and does not switch off.
    @Test func aDropOpensTheShotOutAndFades() {
        let clock = BeatClock(beats: 40, beatsPerBar: 4, measured: true)

        let onIt = VizDirector.shot(clock, beatsSinceDrop: 0)
        let after = VizDirector.shot(clock, beatsSinceDrop: 4)
        let over = VizDirector.shot(clock, beatsSinceDrop: 40)
        let none = VizDirector.shot(clock)

        #expect(onIt.drop == 1)
        #expect(after.drop > 0 && after.drop < 1)
        #expect(over.drop == 0)
        #expect(none.drop == 0)

        #expect(onIt.sway == 0, "the aim still wandered through the drop")
        #expect(none.sway > 0, "the aim never wanders at all")
    }

    // ── the clock ──

    /// The stand-in clock is the only clock in this app, and it counts a steady 120.
    @Test func theStandInClockCountsASteadyPace() {
        let clock = BeatClock.free(2)

        #expect(!clock.measured)
        #expect(abs(clock.beats - 4) < 1e-9, "two seconds at 120 is four beats, not \(clock.beats)")
    }

    /// A tempo is used instead when one is available. There is none in this app yet; the hook
    /// exists because the desktop app has one.
    @Test func aKnownTempoIsUsedWhereThereIsOne() {
        #expect(BeatClock.at(bpm: 60, seconds: 3).beats == 3)
        #expect(BeatClock.at(bpm: 0, seconds: 3) == BeatClock.free(3))
    }
}
