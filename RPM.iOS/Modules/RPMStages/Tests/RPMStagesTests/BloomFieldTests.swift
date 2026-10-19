import Foundation
import Testing
@testable import RPMStages

/// The polar spectrogram that the flower of light is drawn from.
///
/// **The claim is that the last few seconds are all on screen at once.** If every petal showed
/// the same instant, the bloom would be a wheel that pulses, which is not the visualiser. The
/// centre is now and the rim is two and a half seconds ago, so a beat opens at the centre and
/// travels out.
@Suite("The bloom's reading")
struct BloomFieldTests {
    let rate = 44_100
    let n = 2048

    func tone(_ hz: Double, _ level: Float = 0.9) -> [Float] {
        (0..<n).map { level * Float(sin(2 * .pi * hz * Double($0) / Double(rate))) }
    }

    func music(_ level: Float = 0.6) -> [Float] {
        var roll = Roll(seed: 21)

        return (0..<n).map { _ in level * roll.nudge() * 2 }
    }

    /// One band's row, centre first.
    func row(_ field: BloomField, _ band: Int) -> ArraySlice<Float> {
        field.history[(band * BloomField.columns)..<((band + 1) * BloomField.columns)]
    }

    /// Where the loudest column of a row is: zero at the centre and one at the rim.
    func crest(_ field: BloomField, _ band: Int) -> Double {
        let r = row(field, band)
        let at = r.indices.max { r[$0] < r[$1] } ?? r.startIndex

        return Double(at - r.startIndex) / Double(BloomField.columns - 1)
    }

    // ── the travel ──

    /// **The main test.** A burst goes in at the centre and is further out on every tick, like
    /// a ring on water.
    @Test func aBurstOpensAtTheHeartAndTravelsToTheRim() {
        let field = BloomField(frameSize: n)

        // One loud instant, then quiet.
        field.listen(tone(400), now: 0)
        let born = crest(field, band(for: 400))

        for i in 1...40 { field.listen([], now: Double(i) * 0.025) }
        let later = crest(field, band(for: 400))

        #expect(born < 0.05, "the burst was born at \(born) rather than at the heart")
        #expect(later > 0.3, "forty ticks on it had only reached \(later)")
    }

    /// Which row a frequency lands in, computed the same way the field lays out its rows.
    func band(for hz: Double) -> Int {
        let bin = Double(hz) * Double(n) / Double(rate)

        for b in 0..<BloomField.bands {
            let lo = Int(2.0 * pow(210.0, Double(b) / Double(BloomField.bands)))
            let hi = max(lo + 1, Int(2.0 * pow(210.0, Double(b + 1) / Double(BloomField.bands))))
            if bin >= Double(lo) && bin < Double(hi) { return b }
        }

        return BloomField.bands - 1
    }

    /// The centre always shows the present: a full width of silence pushes the loud passage off
    /// the rim and leaves the middle of the flower dark.
    ///
    /// The row does not drop to zero, and should not: the spectrum eases down and does not cut,
    /// so a width of silence leaves a fading tail. The test checks the centre, which is the
    /// present instant and holds nothing.
    @Test func aWidthOfSilenceLeavesTheHeartDark() {
        let field = BloomField(frameSize: n)
        let at = band(for: 400)

        for i in 0..<(BloomField.columns * 2) { field.listen(tone(400), now: Double(i) * 0.025) }

        let lit = field.history[at * BloomField.columns]
        #expect(lit > 0.3, "the heart never lit: \(lit)")

        for i in 0..<BloomField.columns { field.listen([], now: 10 + Double(i) * 0.025) }

        #expect(field.history[at * BloomField.columns] < 0.01,
                "the heart is still burning at \(field.history[at * BloomField.columns])")
    }

    // ── the wheel ──

    /// **Bass to treble once around**, log spaced, so each octave gets about the same room and
    /// nothing is squeezed into a thin strip.
    @Test func theWheelRunsBassThroughTreble() {
        let low = BloomField(frameSize: n)
        let high = BloomField(frameSize: n)

        low.listen(tone(120), now: 0)
        high.listen(tone(8_000), now: 0)

        func loudest(_ field: BloomField) -> Int {
            (0..<BloomField.bands).max { field.history[$0 * BloomField.columns]
                                       < field.history[$1 * BloomField.columns] } ?? 0
        }

        #expect(loudest(low) < BloomField.bands / 3, "a bass note lit row \(loudest(low))")
        #expect(loudest(high) > BloomField.bands * 2 / 3, "a hi-hat lit row \(loudest(high))")
    }

    /// Every reading is a number a shader can be handed.
    @Test func everyReadingIsInRange() {
        let field = BloomField(frameSize: n)

        for i in 0..<60 { field.listen(music(1.0), now: Double(i) * 0.025) }

        #expect(field.history.count == BloomField.bands * BloomField.columns)
        #expect(field.history.allSatisfy { $0 >= 0 && $0 <= 1 })
    }

    // ── the swell and the turn ──

    /// Fast attack, a held peak, then a slow release. It drives the scale and brightness of the
    /// whole flower, so a twitchy value would make the bloom flicker.
    @Test func theSwellRisesQuicklyAndSettlesSlowly() {
        let field = BloomField(frameSize: n)

        for i in 0..<20 { field.listen(music(), now: Double(i) * 0.025) }
        let up = field.swell
        #expect(up > 0.1, "the bloom never lifted: \(up)")

        for i in 0..<40 { field.listen([], now: 1 + Double(i) * 0.025) }

        #expect(field.swell < up, "it did not settle")
        // A second of silence removes about a third of it. This is the release time tuned in
        // the desktop app. Half is the limit for "eased and not cut".
        #expect(field.swell > up * 0.5, "it cut rather than settled: \(up) to \(field.swell)")
    }

    /// **Integrated, so a change of speed never makes the angle jump.** A loud passage turns
    /// the bloom faster. Multiplying the elapsed time by the current rate would snap the angle
    /// whenever the music changed.
    @Test func theTurnIsIntegratedAndNeverJumps() {
        let quiet = BloomField(frameSize: n)
        let loud = BloomField(frameSize: n)

        for i in 0..<40 { loud.listen(music(0.9), now: Double(i) * 0.025) }

        var last = Float(0)
        for _ in 0..<120 {
            quiet.turn(1.0 / 60)
            loud.turn(1.0 / 60)

            #expect(loud.turned >= last, "the angle went backwards")
            last = loud.turned
        }

        #expect(quiet.turned > 0, "it never turned at all")
        #expect(loud.turned > quiet.turned, "the music did not turn it faster")
    }

    /// A frame that arrives late must not make the flower spin a long way.
    @Test func aLateFrameDoesNotSpinIt() {
        let field = BloomField(frameSize: n)
        field.turn(4)

        #expect(field.turned < 0.02, "a four-second frame turned it \(field.turned)")
    }
}
