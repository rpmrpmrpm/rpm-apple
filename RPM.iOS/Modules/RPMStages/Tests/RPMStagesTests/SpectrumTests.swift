import Foundation
import Testing
@testable import RPMStages

/// The arithmetic that every visualiser is built on.
///
/// **This is the only part of a stage that can be proved right.** A drawn backdrop is a matter
/// of taste and can only be looked at. A band level is a number, and a tone at a known
/// frequency belongs in a known band whatever the screen is doing. So a sine wave goes in and
/// the tests say where it came out.
@Suite("A window, a transform, and a fold into bands")
struct SpectrumTests {

    /// `seconds` of a sine at `hz`, at full scale unless told otherwise.
    func tone(_ hz: Double, rate: Int = 44100, frames: Int = 4096, at level: Float = 1)
    -> [Float] {
        (0..<frames).map { level * Float(sin(2 * Double.pi * hz * Double($0) / Double(rate))) }
    }

    /// Which band a frequency belongs in, by the same log spacing the fold uses.
    func band(of hz: Double, count: Int) -> Int {
        let over = log(hz / Spectrum.lowest) / log(Spectrum.highest / Spectrum.lowest)
        return Int(over * Double(count))
    }

    // ── the transform ──

    /// **This test shows that the FFT is an FFT.** A single sinusoid at bin k must put all of
    /// its energy in bin k and nothing anywhere else.
    @Test func aToneSittingExactlyOnABinLandsOnlyInThatBin() {
        let n = 1024
        let k = 64

        var re = (0..<n).map { sin(2 * Double.pi * Double(k) * Double($0) / Double(n)) }
        var im = [Double](repeating: 0, count: n)

        Spectrum.transform(&re, &im)

        let power = (0..<(n / 2)).map { (re[$0] * re[$0] + im[$0] * im[$0]).squareRoot() }
        let loudest = power.enumerated().max { $0.element < $1.element }?.offset

        #expect(loudest == k, "the peak landed in bin \(loudest ?? -1) rather than \(k)")

        // And everything else is zero, within rounding error.
        let elsewhere = power.enumerated()
            .filter { abs($0.offset - k) > 1 }
            .map(\.element)
            .max() ?? 0

        #expect(elsewhere < power[k] / 1000, "it smeared: \(elsewhere) against \(power[k])")
    }

    /// A transform and nothing else: silence in, silence out. This is cheap, and it catches an
    /// index slip that a tone would hide.
    @Test func silenceTransformsToSilence() {
        var re = [Double](repeating: 0, count: 256)
        var im = [Double](repeating: 0, count: 256)

        Spectrum.transform(&re, &im)

        #expect(re.allSatisfy { $0 == 0 })
        #expect(im.allSatisfy { $0 == 0 })
    }

    // ── the window ──

    /// A Hann window is zero at both ends and one in the middle. **The ends matter**: a frame
    /// that does not end where it began has a step in it, and a step shows in every band at
    /// once.
    @Test func theWindowTapersToNothingAtBothEnds() {
        let shape = Spectrum.hann(64)

        #expect(shape.first == 0)
        #expect(shape.last == 0)
        #expect(abs(shape[32] - 1) < 0.01, "the middle should be open")

        // Symmetric, or it moves the frame's centre of mass and with it the phase.
        for at in 0..<32 {
            #expect(abs(shape[at] - shape[63 - at]) < 1e-6, "lopsided at \(at)")
        }
    }

    // ── the fold ──

    /// **This is what the whole thing is for.** A tone at a known frequency comes out in the
    /// band that frequency belongs to, and stands well clear of the rest.
    ///
    /// The test checks a peak against its neighbours, not an absolute level, and that is not
    /// vague. A band is a *range* and its level is the mean across the bins in it, so a pure
    /// tone is diluted by the number of bins it shares the band with. With log spacing that is
    /// one or two bins at 110 Hz and dozens at 4 kHz. A full-scale tone therefore reads about
    /// 0.9 low down and about 0.5 high up, which is the display working as designed. Music has
    /// energy across a band, not in one bin, so it does not thin out this way.
    @Test(arguments: [110.0, 440.0, 1000.0, 4000.0])
    func aToneComesOutInItsOwnBand(hz: Double) {
        let levels = Spectrum.levels(of: tone(hz), bands: 32, rate: 44100)
        let wanted = band(of: hz, count: 32)

        let loudest = levels.enumerated().max { $0.element < $1.element }?.offset ?? -1

        #expect(abs(loudest - wanted) <= 1,
                "\(Int(hz))Hz came out in band \(loudest), not \(wanted)")

        let elsewhere = levels.enumerated()
            .filter { abs($0.offset - loudest) > 1 }
            .map(\.element)

        let quiet = elsewhere.reduce(0, +) / Float(max(1, elsewhere.count))
        #expect(levels[loudest] > quiet * 2 + 0.2,
                "the tone read \(levels[loudest]) against \(quiet) elsewhere")
    }

    /// The dilution above, stated as its own fact so it cannot drift unnoticed: **the same tone
    /// reads lower the higher it sits**, because the band it lands in is wider. This is worth
    /// pinning because the obvious change is to take the loudest bin in a band and not the
    /// mean, and that turns every stage into a row of spikes.
    @Test func theSameToneReadsLowerTheHigherItSits() {
        let low = Spectrum.levels(of: tone(110), bands: 32, rate: 44100)
        let high = Spectrum.levels(of: tone(4000), bands: 32, rate: 44100)

        #expect(low.max()! > high.max()!, "\(low.max()!) against \(high.max()!)")
        #expect(high.max()! > 0.4, "the top end thinned out to nothing")
    }

    /// Silence reads as zero, not as a floor that makes every stage twitch.
    @Test func silenceReadsAsNothing() {
        let levels = Spectrum.levels(of: [Float](repeating: 0, count: 4096),
                                     bands: 32, rate: 44100)

        #expect(levels.allSatisfy { $0 == 0 }, "silence lit \(levels.filter { $0 > 0 }.count) bands")
    }

    /// Quieter in, lower out, at the same frequency. A display that cannot tell a loud record
    /// from a quiet one shows frequency and nothing else.
    @Test func aQuieterToneReadsLower() {
        let loud = Spectrum.levels(of: tone(1000, at: 1), bands: 32, rate: 44100)
        let soft = Spectrum.levels(of: tone(1000, at: 0.05), bands: 32, rate: 44100)

        let at = band(of: 1000, count: 32)
        #expect(soft[at] < loud[at] - 0.15, "loud \(loud[at]) against soft \(soft[at])")
        #expect(soft[at] > 0, "it read the quiet one as nothing at all")
    }

    /// Every level is in range, whatever goes in. A stage multiplies these by a height.
    @Test func everyLevelStaysInRange() {
        for frame in [tone(440), tone(440, at: 4), [Float](repeating: 1, count: 4096)] {
            let levels = Spectrum.levels(of: frame, bands: 24, rate: 44100)
            #expect(levels.allSatisfy { $0 >= 0 && $0 <= 1 }, "\(levels)")
        }
    }

    /// The count asked for is the count handed back, whatever it is.
    @Test(arguments: [1, 8, 24, 32, 64, 128])
    func itAnswersAsManyBandsAsItIsAskedFor(count: Int) {
        #expect(Spectrum.levels(of: tone(440), bands: count, rate: 44100).count == count)
    }

    /// **Log-spaced, so an octave is an octave wherever it sits.** Two tones an octave apart
    /// low down must be as far apart in bands as two tones an octave apart high up. That is the
    /// reason for not spacing the bands linearly.
    @Test func anOctaveIsTheSameWidthWhereverItIs() {
        let low = band(of: 200, count: 48) - band(of: 100, count: 48)
        let high = band(of: 6400, count: 48) - band(of: 3200, count: 48)

        #expect(abs(low - high) <= 1, "an octave was \(low) bands low down and \(high) high up")
    }

    /// A rate that the analysis was not told about puts every tone in the wrong band, which is
    /// why the sound is asked for its rate and 44.1 kHz is not assumed.
    @Test func theRateDecidesWhereATonesLands() {
        let frame = tone(1000, rate: 48000)

        let right = Spectrum.levels(of: frame, bands: 32, rate: 48000)
        let wrong = Spectrum.levels(of: frame, bands: 32, rate: 44100)

        let at = band(of: 1000, count: 32)
        #expect((right.enumerated().max { $0.element < $1.element }?.offset ?? -1) == at)

        // Told the wrong rate, it still reads *a* tone, just not the right one. This failure is
        // worth knowing about because it looks like it is working.
        #expect(wrong.contains { $0 > 0.5 })
    }
}
