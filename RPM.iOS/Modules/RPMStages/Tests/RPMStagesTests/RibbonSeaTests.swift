import Foundation
import Testing
@testable import RPMStages

/// The ribbon sea.
///
/// **The claim under test is that the wrinkles TRAVEL.** If the lines only wobble in place, the
/// picture looks the same at a glance, but it is not the visualiser. The band history makes a
/// crest born at the left edge from this instant's music flow right along the line over the
/// next seconds, so the far end shows the music of a moment ago.
@Suite("The ribbon sea")
struct RibbonSeaTests {
    let rate = 44_100
    let n = 2048

    func tone(_ hz: Double, _ level: Float = 0.8) -> [Float] {
        (0..<n).map { level * Float(sin(2 * .pi * hz * Double($0) / Double(rate))) }
    }

    /// **Broadband, for anything that reads the swell.** The swell is the mean of 200 bins, so
    /// a pure tone, which lights three of them, barely lifts it. That is correct: an ocean
    /// follows a whole mix, not one note.
    func music(_ level: Float = 0.6) -> [Float] {
        var roll = Roll(seed: 4)

        return (0..<n).map { _ in level * roll.nudge() * 2 }
    }

    func trace(_ sea: RibbonSea, at time: Double = 0, aspect: Float = 0.46) -> [SIMD2<Float>] {
        var points = [SIMD2<Float>](repeating: .zero, count: RibbonSea.lines * RibbonSea.columns)
        sea.trace(time, aspect: aspect, into: &points)

        return points
    }

    /// One line out of a trace.
    func line(_ points: [SIMD2<Float>], _ line: Int) -> ArraySlice<SIMD2<Float>> {
        points[(line * RibbonSea.columns)..<((line + 1) * RibbonSea.columns)]
    }

    // ── the wrinkle that travels ──

    /// **The main test.** A burst of music is pushed in at the near end of a line and is
    /// further along it as time passes, like a wave sent down a rope.
    ///
    /// The test reads the band history directly, not the drawn line. A burst also lifts the
    /// SWELL, which raises every point of every line at once, so a line drawn with music
    /// differs from one drawn without it everywhere, and the wrinkle cannot be told from the
    /// lift. The history is the mechanism, so it is where the travel can be shown as a fact.
    @Test func aBurstOfMusicTravelsAlongTheLine() {
        let sea = RibbonSea(frameSize: n)
        sea.listen(tone(3_000), now: 0)

        // The band that a line near the front reads: `fcoord` is 1 − v, so line 2 of fifteen
        // reads near the top of the spectrum.
        let band = Float(1) - 2 / Float(RibbonSea.lines - 1)

        func crestIsAt() -> Float {
            var best: Float = 0, at: Float = 0

            for c in 0..<100 {
                let u = Float(c) / 99
                let here = sea.read(u, band: band)
                if here > best { best = here; at = u }
            }

            return at
        }

        let born = crestIsAt()
        for i in 0..<40 { sea.listen([], now: Double(i) * 0.025) }
        let later = crestIsAt()

        #expect(born < 0.1, "the crest was born at \(born) along the line, not at the near end")
        #expect(later > born + 0.25, "it went from \(born) to \(later), which is not travelling")
    }

    /// The history is the delay line, so the far end of a line shows the music of a moment ago
    /// and the near end shows the music of now.
    @Test func theFarEndOfALineIsOlderMusicThanTheNearEnd() {
        let sea = RibbonSea(frameSize: n)

        // Fill the whole history with loud music, then go quiet.
        for i in 0..<120 { sea.listen(tone(3_000), now: Double(i) * 0.025) }
        for i in 0..<20 { sea.listen([], now: 2 + Double(i) * 0.025) }

        // The near end has just had twenty columns of silence pushed into it; the far end
        // still holds the loud passage.
        #expect(sea.read(0.02, band: 0.9) < sea.read(0.9, band: 0.9),
                "the delay line is not delaying: \(sea.read(0.02, band: 0.9)) at the near end")
    }

    // ── the swell ──

    /// Fast attack, slow settle. An ocean cannot twitch, so a snare makes a wrinkle and does
    /// not lift the whole sea.
    @Test func theSwellRisesQuicklyAndSettlesSlowly() {
        let sea = RibbonSea(frameSize: n)

        for i in 0..<20 { sea.listen(music(), now: Double(i) * 0.025) }
        let up = sea.swell
        #expect(up > 0.1, "the sea never lifted: \(up)")

        // Longer than the hold time.
        for i in 0..<40 { sea.listen([], now: 1 + Double(i) * 0.025) }
        let after = sea.swell

        #expect(after < up, "it did not settle at all")
        #expect(after > up * 0.6, "it dropped from \(up) to \(after), which is a cut rather than a settle")
    }

    /// The front lines lead, and the whole sea lifts when the music does.
    @Test func theFrontLinesAreBrighterAndTheMusicLiftsThemAll() {
        let sea = RibbonSea(frameSize: n)

        #expect(sea.brightness(0) > sea.brightness(RibbonSea.lines - 1))

        let quiet = sea.brightness(0)
        for i in 0..<20 { sea.listen(music(), now: Double(i) * 0.025) }

        #expect(sea.brightness(0) > quiet, "the music did not lift the sea")
    }

    // ── the projection ──

    /// The sea moves whether or not anything is playing: it breathes on its own clock. Silence
    /// is a calm sea, not a flat line.
    @Test func theSeaRollsWithNoMusicAtAll() {
        let sea = RibbonSea(frameSize: n)

        let then = trace(sea, at: 0)
        let later = trace(sea, at: 3)

        var moved: Float = 0
        for i in then.indices { moved += abs(then[i].y - later[i].y) }

        #expect(moved > 0.1, "the sea stood still")
    }

    /// Every point is a number. A NaN anywhere makes a line vanish, and a vanished line looks
    /// like a hole in the sea, not like a fault.
    @Test(arguments: [0.30, 0.46, 1.0, 2.2])
    func everyPointIsANumber(aspect: Double) {
        let sea = RibbonSea(frameSize: n)
        for i in 0..<40 { sea.listen(tone(120), now: Double(i) * 0.025) }

        let points = trace(sea, at: 7, aspect: Float(aspect))

        #expect(points.count == RibbonSea.lines * RibbonSea.columns)
        #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    /// **A wider window gives a longer stretch of sea, not a stretched one.** Scaling by the
    /// height alone puts the line ends inside the edges of a landscape phone, and a line that
    /// tapers away in mid-air looks as if the sea has run out.
    @Test func aWiderWindowGetsMoreOceanRatherThanAStretchedOne() {
        let sea = RibbonSea(frameSize: n)

        // Portrait is taller than it is wide, landscape the other way round.
        let portrait = trace(sea, at: 2, aspect: 2.2)
        let landscape = trace(sea, at: 2, aspect: 0.46)

        func reaches(_ points: [SIMD2<Float>]) -> Float {
            line(points, RibbonSea.lines - 1).map { abs($0.x) }.max() ?? 0
        }

        // Both lines reach beyond the frame, which is -1 to 1 in these coordinates.
        #expect(reaches(portrait) > 1, "the portrait sea stops inside the frame")
        #expect(reaches(landscape) > 1, "the landscape sea stops inside the frame")
    }

    /// The lines recede: the back of the sea is drawn above the front, which makes it look like
    /// a sea and not a stack of ribbons.
    @Test func theBackOfTheSeaIsAboveTheFront() {
        let sea = RibbonSea(frameSize: n)
        let points = trace(sea, at: 0)

        func middle(_ at: Int) -> Float { line(points, at)[at * RibbonSea.columns + RibbonSea.columns / 2].y }

        #expect(middle(RibbonSea.lines - 1) > middle(0),
                "the far line is not above the near one")
    }
}
