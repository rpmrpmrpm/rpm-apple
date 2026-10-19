import Foundation
import Testing
@testable import RPMStages

/// What the room hears.
///
/// The run is a picture, and a picture cannot be asserted, but **every property that makes it a
/// spectrum and not a wall can be**: a kick lights the bass and not the air, a range does not
/// draw its own boundary as a step, silence eases down and does not drop out, and a quiet
/// passage still looks quiet.
@Suite("What the room hears")
struct RoomBandsTests {

    /// A tap that always hands back the same tone, as if the record never changed.
    func tone(_ hz: Double, rate: Int = 44100, at level: Float = 1)
    -> (inout [Float]) -> Bool {
        // A running phase, so that successive frames join up and do not each start at zero.
        // That would be a click every frame, and it would add broadband noise.
        let box = Phase()

        return { frame in
            for at in 0..<frame.count {
                frame[at] = level * Float(sin(box.at + 2 * Double.pi * hz * Double(at) / Double(rate)))
            }
            box.at += 2 * Double.pi * hz * Double(frame.count) / Double(rate)
            return true
        }
    }

    final class Phase { var at: Double = 0 }

    /// Runs the room for `ticks` at sixty a second and answers where it ended up.
    @discardableResult
    func settle(_ room: RoomBands, ticks: Int = 120, playing: Bool = true) -> [Float] {
        for tick in 0..<ticks {
            room.update(now: Double(tick) / 60, playing: playing)
        }
        return room.run
    }

    // ── the envelopes ──

    /// **A kick lights the room and a cymbal does not.** The three envelopes light the figures.
    /// If they all followed the same thing, there would be no reason to have three.
    @Test func theLowEndLightsTheRoomAndTheTopEndDoesNot() {
        let low = RoomBands(rate: 44100)
        low.tap = tone(60)
        settle(low)

        let high = RoomBands(rate: 44100)
        high.tap = tone(9000)
        settle(high)

        #expect(low.bass > high.bass, "60Hz lit \(low.bass), 9kHz lit \(high.bass)")
        #expect(high.air > low.air, "9kHz aired \(high.air), 60Hz aired \(low.air)")
    }

    /// The middle envelope is separate from the bass on purpose: two families driven by one
    /// envelope would breathe as one body.
    @Test func theMiddleAnswersToTheMiddle() {
        let room = RoomBands(rate: 44100)
        room.tap = tone(900)
        settle(room)

        #expect(room.middle > room.bass, "900Hz read \(room.middle) mid against \(room.bass) bass")
    }

    /// **Silence eases down and does not cut.** A spectrum that drops to zero the moment the
    /// music stops looks like the picture breaking, not like the room going quiet.
    @Test func silenceEasesTheRunDownRatherThanCuttingIt() {
        let room = RoomBands(rate: 44100)
        room.tap = tone(440)
        settle(room)

        let loud = room.run.reduce(0, +)
        #expect(loud > 0, "nothing was drawn in the first place")

        // One tick of silence: down, but far from zero.
        room.update(now: 120 / 60, playing: false)
        let after = room.run.reduce(0, +)

        #expect(after < loud, "it did not fall at all")
        #expect(after > loud * 0.3, "it fell off a cliff: \(loud) to \(after)")

        // And given long enough, all the way down.
        for tick in 121..<400 { room.update(now: Double(tick) / 60, playing: false) }
        #expect(room.run.reduce(0, +) < loud * 0.05, "it never settled")
    }

    // ── the run ──

    @Test func itDrawsAsManyBandsAsThereAreBars() {
        let room = RoomBands(rate: 44100)
        room.tap = tone(440)

        #expect(settle(room, ticks: 4).count == RoomBands.bands)
    }

    @Test func everyBandStaysInRange() {
        for hz in [40.0, 440.0, 3000.0, 12000.0] {
            let room = RoomBands(rate: 44100)
            room.tap = tone(hz, at: 4)          // deliberately hot

            #expect(settle(room).allSatisfy { $0 >= 0 && $0 <= 1 }, "\(Int(hz))Hz went out of range")
        }
    }

    /// **The run is not a wall.** A straight log scale would spend half the run below 480 Hz,
    /// so every kick would draw a solid block across the left of the screen, and everything
    /// above 2 kHz would be crushed into the last inch. A tone must move the part of the run it
    /// belongs to and leave the rest alone.
    @Test(arguments: [(60.0, 0.0, 0.45), (900.0, 0.45, 0.80), (9000.0, 0.80, 1.0)])
    func aToneMovesItsOwnPartOfTheRun(hz: Double, from: Double, upto: Double) {
        let room = RoomBands(rate: 44100)
        room.tap = tone(hz)
        let run = settle(room)

        let first = Int(from * Double(RoomBands.bands))
        let last = min(RoomBands.bands, Int(upto * Double(RoomBands.bands)))

        let mine = run[first..<last].max() ?? 0
        let loudest = run.enumerated().max { $0.element < $1.element }?.offset ?? -1

        #expect(loudest >= first && loudest < last,
                "\(Int(hz))Hz peaked at band \(loudest), outside \(first)..<\(last)")
        #expect(mine > 0.25, "\(Int(hz))Hz only reached \(mine) in its own stretch")
    }

    /// **No range draws its own boundary.** The gain is measured per range but eased between
    /// their centres. A step at a crossover is what to watch for: without the easing it would
    /// draw a line straight down the picture at exactly 5 kHz.
    @Test func thereIsNoStepWhereOneRangeHandsOverToTheNext() {
        let room = RoomBands(rate: 44100)

        // Broadband, so every range has something to measure itself against.
        var seed: UInt64 = 0x5eed
        room.tap = { frame in
            for at in 0..<frame.count {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                frame[at] = Float(Int32(truncatingIfNeeded: seed >> 33)) / Float(Int32.max) * 0.3
            }
            return true
        }

        let run = settle(room, ticks: 240)

        // The biggest jump between neighbours, against the typical one. A seam shows up
        // as one step far larger than the rest.
        let steps = (1..<run.count).map { abs(run[$0] - run[$0 - 1]) }
        let worst = steps.max() ?? 0
        let usual = steps.reduce(0, +) / Float(steps.count)

        #expect(worst < usual * 8 + 0.05,
                "a step of \(worst) against a usual \(usual) — that is a seam")
    }

    /// **A quiet passage still looks quiet.** At full adaptation every passage would be drawn
    /// at the same height, because each range is always measured against itself. That is a
    /// meter pinned at the top, not a spectrum.
    @Test func aQuietPassageIsStillVisiblyQuiet() {
        let loud = RoomBands(rate: 44100)
        loud.tap = tone(440, at: 0.9)

        let soft = RoomBands(rate: 44100)
        soft.tap = tone(440, at: 0.02)

        let big = settle(loud, ticks: 240).max() ?? 0
        let small = settle(soft, ticks: 240).max() ?? 0

        #expect(small < big, "loud peaked \(big), quiet peaked \(small)")
    }

    // ── the delays, which turned out not to exist ──

    /// **Pinned: there are no delays between the three windows.**
    ///
    /// The desktop app (C#) holds its long window back through three ticks because its tap
    /// fills forward from the playhead, so a change appears there before it is heard. This tap
    /// trails: every window ends at the present moment, so a change appears in all three
    /// windows at the instant it is heard, whatever their lengths. Any added wait would make
    /// that end of the run late, so the delays must not be copied over.
    ///
    /// Both ends of the run must move on the same tick. Measured: with waits of 0/4/5 the top
    /// arrives four ticks after the bottom, with 0/2/2 it arrives two ticks after, and with no
    /// waits both move together.
    @Test func bothEndsOfTheRunMoveOnTheSameTick() {
        let room = RoomBands(rate: 44100)

        var ticks = 0
        let sound = tone(440)
        room.tap = { frame in
            defer { ticks += 1 }
            guard ticks >= 30 else {
                for at in 0..<frame.count { frame[at] = 0 }
                return true
            }
            return sound(&frame)
        }

        var lowMoved = -1, highMoved = -1

        for tick in 0..<120 {
            room.update(now: Double(tick) / 60, playing: true)
            let run = room.run

            let half = RoomBands.bands / 2
            if lowMoved < 0, (run[0..<half].max() ?? 0) > 0.02 { lowMoved = tick }
            if highMoved < 0, (run[half...].max() ?? 0) > 0.02 { highMoved = tick }
        }

        #expect(lowMoved >= 0, "the bottom of the run never moved at all")
        #expect(highMoved >= 0, "the top of the run never moved at all")
        #expect(lowMoved == highMoved,
                "the run arrived in pieces: bottom at \(lowMoved), top at \(highMoved)")
    }

    /// **A tap that cannot fill the frame is silence, not a fault.** This is the normal state
    /// during the first fraction of a second of a track, when the playhead does not yet have a
    /// full window behind it. A room that read it as anything else would flash at the start of
    /// every record.
    @Test func aTapThatCannotFillTheFrameIsSilence() {
        let room = RoomBands(rate: 44100)
        room.tap = { _ in false }

        #expect(settle(room).allSatisfy { $0 < 0.001 })
    }

    /// The rate decides what every bin means, so it is asked for rather than assumed.
    @Test func theRateIsAskedForRatherThanAssumed() {
        let at48 = RoomBands(rate: 48000)
        at48.tap = tone(60, rate: 48000)
        settle(at48)

        #expect(at48.bass > 0.1, "a 60Hz tone at 48k did not light the room")
    }
}
