import Foundation
import Testing
@testable import RPMStages

/// The two rows that all three looks read the music through.
///
/// **This decides whether a visualiser moves at all.** A spectrum mapped as raw magnitude puts
/// every bin in the bottom tenth of its range, so the picture drawn from it sits still through
/// a whole record while nothing looks broken.
@Suite("The music as the looks read it")
struct ShaderAudioTests {
    let rate = 44_100
    let n = 2048

    /// A tone at exactly the middle of bin `k`, so the energy lands in one place and the
    /// test is about the mapping rather than about leakage.
    func tone(bin k: Int, level: Float = 1) -> [Float] {
        let hz = Double(k) * Double(rate) / Double(n)

        return (0..<n).map { level * Float(sin(2 * .pi * hz * Double($0) / Double(rate))) }
    }

    // ── the spectrum ──

    /// A full-scale tone reads at the top of the range and its far neighbours read at the
    /// floor. The window is 64 dB wide and a full-scale sine sits above its ceiling, so this
    /// shows that the decibel mapping is the right way up.
    @Test func aFullScaleToneReadsAtTheTopAndNowhereElse() {
        let audio = ShaderAudio(frameSize: n)
        audio.listen(tone(bin: 100))

        #expect(audio.spectrum[100] > 0.95, "the tone read \(audio.spectrum[100])")
        #expect(audio.spectrum[300] < 0.05, "a bin two hundred away read \(audio.spectrum[300])")
    }

    /// A quiet tone reads well below a loud one, rather than both pinning at the top.
    @Test func aQuietToneReadsLowerThanALoudOne() {
        let loud = ShaderAudio(frameSize: n)
        loud.listen(tone(bin: 100))

        let quiet = ShaderAudio(frameSize: n)
        quiet.listen(tone(bin: 100, level: 0.01))

        #expect(quiet.spectrum[100] < loud.spectrum[100] - 0.2,
                "\(quiet.spectrum[100]) against \(loud.spectrum[100])")
    }

    /// **Peak fast, fall slow.** A bin that rises jumps to the new level in one frame; one that
    /// falls eases down. Bars that fell as fast as they rose would strobe on every snare.
    @Test func aBinJumpsUpAndEasesDown() {
        let audio = ShaderAudio(frameSize: n)

        audio.listen(tone(bin: 100))
        let peak = audio.spectrum[100]

        audio.listen([Float](repeating: 0, count: n))
        let after = audio.spectrum[100]

        #expect(after < peak, "it did not fall at all")
        #expect(after > peak * 0.3, "it fell to \(after) from \(peak), which is a cut rather than a fall")
    }

    /// Silence is a resting picture, not a blank one: the held spectrum eases down from
    /// wherever it was.
    ///
    /// **An empty frame is not transformed at all**, which is why this case is separate: the
    /// looks hand one over every frame while paused or buffering, and a two-thousand-point
    /// transform of zeros sixty times a second would only warm the phone to compute a known
    /// answer.
    @Test func anEmptyFrameEasesTheSpectrumDownWithoutMeasuringAnything() {
        let audio = ShaderAudio(frameSize: n)
        audio.listen(tone(bin: 100))

        let peak = audio.spectrum[100]
        audio.listen([])

        #expect(abs(audio.spectrum[100] - peak * 0.5) < 1e-5,
                "an empty frame should halve the held level, not \(audio.spectrum[100]) from \(peak)")
    }

    /// It never runs out of picture: every texel is a number, whatever arrives.
    @Test(arguments: [0, 1, 64, 2048, 8192])
    func everyTexelIsAnswerable(samples: Int) {
        let audio = ShaderAudio(frameSize: n)
        audio.listen((0..<samples).map { Float(sin(Double($0) * 0.05)) })

        #expect(audio.spectrum.count == ShaderAudio.width)
        #expect(audio.wave.count == ShaderAudio.width)
        #expect(audio.spectrum.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(audio.wave.allSatisfy { $0 >= -1 && $0 <= 1 })
    }

    // ── the waveform ──

    /// The second row is the sound itself, decimated across the width, not a spectrum again. A
    /// look that draws it should draw a wave.
    @Test func theWaveRowIsTheSoundItself() {
        let audio = ShaderAudio(frameSize: n)

        // One cycle over the whole frame, so the row is one cycle across.
        audio.listen((0..<n).map { Float(sin(2 * .pi * Double($0) / Double(n))) })

        #expect(audio.wave[ShaderAudio.width / 4] > 0.9, "a quarter in should be the crest")
        #expect(audio.wave[3 * ShaderAudio.width / 4] < -0.9, "three quarters in should be the trough")
    }

    /// Silence is flat and does not sit at an offset, so nothing drawn from it leans.
    @Test func silenceLiesFlat() {
        let audio = ShaderAudio(frameSize: n)
        audio.listen([Float](repeating: 0, count: n))

        #expect(audio.wave.allSatisfy { $0 == 0 })
    }

    /// A frame longer than the analysis window is read only as far as the window goes, not past
    /// its end.
    @Test func aFrameLongerThanTheWindowIsReadAsFarAsItGoes() {
        let audio = ShaderAudio(frameSize: n)
        audio.listen([Float](repeating: 0.5, count: n * 4))

        #expect(audio.wave.allSatisfy { abs($0 - 0.5) < 1e-6 })
    }
}
