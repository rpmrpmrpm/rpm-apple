import Foundation
import Testing
@testable import RPMStages

/// The plate of sand.
///
/// **The tests check that the sand arrives.** A plate whose grains wander at random has a bug,
/// but on a phone it looks the same as a working plate: a haze of white dots. So the tests ask
/// the physics question: after a while under a steady note, is the sand closer to the lines
/// where the plate stands still than it was at the start?
@Suite("Chladni's plate")
struct ChladniPlateTests {
    let rate = 44_100
    let n = 2048

    /// A chord, so several modes are sounded and the figure has something to be.
    func chord(_ level: Float = 0.7) -> [Float] {
        (0..<n).map { i in
            let t = Double(i) / Double(rate)

            return level * Float(sin(2 * .pi * 110 * t)
                               + sin(2 * .pi * 440 * t)
                               + sin(2 * .pi * 1_760 * t)) / 3
        }
    }

    /// How far the sand is, on average, from the lines where the plate stands still.
    /// Measured as the displacement itself: the sand settles on its zeros.
    func stillness(_ plate: ChladniPlate) -> Float {
        var sum: Float = 0
        for grain in plate.grains { sum += abs(plate.displacement(at: grain)) }

        return sum / Float(plate.grains.count)
    }

    /// Sounds a plate for a while and hands it back.
    func played(_ plate: ChladniPlate, frames: Int, frame: [Float]) -> ChladniPlate {
        for _ in 0..<frames {
            plate.listen(frame)
            plate.settle(1.0 / 40)
        }

        return plate
    }

    // ── the figure ──

    /// **The main test.** Under a steady note the sand ends nearer the still lines than it
    /// started, and keeps getting nearer. Nothing sorts the grains and nothing draws the
    /// figure: the sand collects because arriving is the only absorbing state.
    ///
    /// **A figure takes minutes, not seconds.** This is by design. A hop is a fixed 0.0024 of
    /// the plate per second, so a grain half a plate from a line takes three minutes to reach
    /// it. A hop that scales with how hard the plate shakes the grain would finish in seconds
    /// and then spend minutes making changes too small to see. So this test runs one minute of
    /// music and asks for a clear move, not a finished figure.
    ///
    /// The distance is sampled along the way as well as at the end, because a random walk can
    /// end nearer the lines by chance. A real collecting process makes it fall at every sample.
    @Test func theSandFindsTheLinesWhereThePlateStandsStill() {
        let plate = ChladniPlate(grains: 3_000)
        plate.listen(chord())

        var readings = [stillness(plate)]
        for _ in 0..<5 {
            readings.append(stillness(played(plate, frames: 500, frame: chord())))
        }

        for i in 1..<readings.count {
            #expect(readings[i] < readings[i - 1],
                    "the sand went back out at reading \(i): \(readings)")
        }

        #expect(readings.last! < readings[0] * 0.85,
                "a minute of music moved the sand from \(readings[0]) to \(readings.last!)")
    }

    /// **Silence leaves the sand exactly where it lies.** Nothing breathes, pulses or fades in.
    /// The last figure the music drew stays, and that is what silence looks like. The plate
    /// rings down first (a struck plate does not stop at once), and the test checks what
    /// happens after it has stopped ringing.
    @Test func silenceMovesNothingAtAll() {
        let plate = ChladniPlate(grains: 500)
        _ = played(plate, frames: 60, frame: chord())

        // Let it ring down. The release is slow by design: the sand keeps moving while anything
        // still drives it.
        var rang = 0
        while plate.drive > 0, rang < 2_000 {
            plate.listen([])
            plate.settle(1.0 / 40)
            rang += 1
        }

        #expect(plate.drive == 0, "the plate never stopped ringing")
        #expect(rang > 20, "it stopped dead rather than ringing down")

        let figure = plate.grains

        for _ in 0..<400 {
            plate.listen([])
            plate.settle(1.0 / 40)
        }

        #expect(plate.grains == figure, "the sand moved in silence")
    }

    /// The sand never leaves the plate. A grain thrown off an edge is put back at a random
    /// place, not bounced, because bouncing would build a line of grains along the border that
    /// the physics never put there.
    @Test func everyGrainStaysOnThePlate() {
        let plate = ChladniPlate(grains: 2_000)
        _ = played(plate, frames: 200, frame: chord(1.0))

        #expect(plate.grains.allSatisfy { $0.x >= -1 && $0.x <= 1 && $0.y >= -1 && $0.y <= 1 })
    }

    // ── the note ──

    /// **The figure is the balance of the spectrum, not its loudness.** The modes are
    /// normalised, so the same music played louder draws almost the same figure and throws the
    /// sand harder.
    ///
    /// Almost the same, not exactly: the spectrum is read in decibels over a window 64 dB wide,
    /// so a passage quiet enough to put some bands under the floor has a different balance. Ten
    /// decibels apart is a change of level; forty is a different recording.
    @Test func loudnessThrowsTheSandHarderWithoutChangingTheFigure() {
        let quiet = ChladniPlate(grains: 1)
        let loud = ChladniPlate(grains: 1)

        for _ in 0..<80 {
            quiet.listen(chord(0.3))
            loud.listen(chord(0.9))
        }

        #expect(loud.drive > quiet.drive, "the loud plate is driven no harder")

        for m in 0..<quiet.sounding.count {
            #expect(abs(quiet.sounding[m] - loud.sounding[m]) < 0.08,
                    "mode \(m) came out \(quiet.sounding[m]) against \(loud.sounding[m])")
        }
    }

    /// A bass line and a hi-hat wake different modes. Two spectra give two figures, which is
    /// the claim the visualiser makes.
    @Test func differentMusicSoundsDifferentModes() {
        func under(_ hz: Double) -> [Float] {
            (0..<n).map { 0.8 * Float(sin(2 * .pi * hz * Double($0) / Double(rate))) }
        }

        let low = ChladniPlate(grains: 1)
        let high = ChladniPlate(grains: 1)

        for _ in 0..<120 {
            low.listen(under(80))
            high.listen(under(6_000))
        }

        // The lowest mode answers to the lowest music and the busiest mode to the top end.
        #expect(low.sounding[0] > low.sounding[low.sounding.count - 1],
                "a bass note sounded the top of the plate: \(low.sounding)")
        #expect(high.sounding[high.sounding.count - 1] > high.sounding[0],
                "a hi-hat sounded the bottom of the plate: \(high.sounding)")
    }

    /// A plate cannot change which modes it holds in one frame: one figure dissolves into the
    /// next and does not cut.
    @Test func theFigureDissolvesRatherThanCuts() {
        func under(_ hz: Double) -> [Float] {
            (0..<n).map { 0.8 * Float(sin(2 * .pi * hz * Double($0) / Double(rate))) }
        }

        let plate = ChladniPlate(grains: 1)
        for _ in 0..<120 { plate.listen(under(80)) }

        let before = plate.sounding
        plate.listen(under(6_000))
        let after = plate.sounding

        var moved: Float = 0
        for m in before.indices { moved += abs(after[m] - before[m]) }

        #expect(moved > 0, "the plate did not answer the new note at all")
        #expect(moved < 0.5, "the plate cut to the new figure in one frame: \(moved)")
    }

    // ── the throw ──

    /// The same seed throws the same plate. A listener's plate should be the one they saw
    /// yesterday, and a test of figure formation needs the same throw on every run.
    @Test func theSameSeedThrowsTheSamePlate() {
        let one = ChladniPlate(grains: 300, seed: 7)
        let two = ChladniPlate(grains: 300, seed: 7)
        let other = ChladniPlate(grains: 300, seed: 8)

        #expect(one.grains == two.grains)
        #expect(one.grains != other.grains)
    }

    /// Sand is scattered unevenly, not on a regular grid: it lands thicker in some places than
    /// others. A perfectly even pour looks printed.
    @Test func theSandIsNotPouredEvenly() {
        let plate = ChladniPlate(grains: 20_000)

        var quarters = [Int](repeating: 0, count: 4)
        for grain in plate.grains {
            quarters[(grain.x > 0 ? 1 : 0) + (grain.y > 0 ? 2 : 0)] += 1
        }

        let most = quarters.max()!, fewest = quarters.min()!
        #expect(most > fewest, "the pour was perfectly even, which is not a pour")
        #expect(most < fewest * 3, "the pour is a heap in one corner: \(quarters)")
    }
}
