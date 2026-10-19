import AVFAudio
import Testing
@testable import RPMAudio

/// The levelling gain as the pump applies it. The gain multiplies each sample and is clamped at
/// full scale. It slides to a new value over time instead of jumping. The desktop app's
/// `AudioEngine.ApplyGain` uses the same rules and numbers.
@Suite("The levelling gain, applied in the pump")
struct GainSlideTests {
    private func block(_ frames: Int, _ value: Float) -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(pcmFormat: StreamedPcm.engineFormat,
                                      frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for c in 0..<2 {
            for f in 0..<frames { buffer.floatChannelData![c][f] = value }
        }
        return buffer
    }

    private func sample(_ buffer: AVAudioPCMBuffer, _ channel: Int, _ frame: Int) -> Float {
        buffer.floatChannelData![channel][frame]
    }

    @Test func unityLeavesTheSamplesAlone() {
        var slide = GainSlide()
        let audio = block(64, 0.3)

        slide.apply(1, to: audio)

        #expect(sample(audio, 0, 0) == 0.3)
        #expect(sample(audio, 1, 63) == 0.3)
    }

    /// A start or a seek has no earlier sound to slide from. So the first block uses its gain
    /// from its first frame.
    @Test func theFirstBlockLandsOnItsGain() {
        var slide = GainSlide()
        let audio = block(64, 0.8)

        slide.apply(0.5, to: audio)

        #expect(sample(audio, 0, 0) == 0.4)
        #expect(sample(audio, 1, 63) == 0.4)
        #expect(slide.now == 0.5)
    }

    /// A boost can take a sample past full scale when the track's peak is unknown. The output
    /// stops at full scale instead of wrapping.
    @Test func aBoostIsClampedAtFullScale() {
        var slide = GainSlide()
        let up = block(8, 0.8)
        let down = block(8, -0.8)

        slide.apply(2, to: up)
        slide.apply(2, to: down)

        #expect(sample(up, 0, 0) == 1)
        #expect(sample(down, 1, 7) == -1)
    }

    /// The gain moves by one unit of linear gain over 20 ms, one step per frame. Both channels
    /// of a frame get the same value, so the stereo image does not shift.
    @Test func aChangeSlidesAtTheDesktopsRate() {
        var slide = GainSlide()
        slide.apply(1, to: block(16, 1))

        let audio = block(2000, 1)
        slide.apply(0.5, to: audio)

        let step = GainSlide.stepPerFrame
        #expect(abs(step - 1 / 882) < 1e-9)

        #expect(abs(sample(audio, 0, 0) - (1 - step)) < 1e-6)
        #expect(abs(sample(audio, 0, 99) - (1 - 100 * step)) < 1e-5)
        #expect(sample(audio, 0, 99) == sample(audio, 1, 99))

        // Half a unit of change takes 441 frames. After that the gain stays at 0.5.
        #expect(sample(audio, 0, 441) == 0.5)
        #expect(sample(audio, 1, 1999) == 0.5)
        #expect(slide.now == 0.5)
    }

    /// A block shorter than the slide stops part way through. The next block continues from there.
    @Test func aShortBlockLeavesTheSlidePartWay() {
        var slide = GainSlide()
        slide.apply(1, to: block(16, 1))

        slide.apply(0, to: block(100, 1))
        let reached = slide.now ?? -1
        #expect(abs(reached - (1 - 100 * GainSlide.stepPerFrame)) < 1e-5)

        let next = block(10, 1)
        slide.apply(0, to: next)
        #expect(abs(sample(next, 0, 0) - (reached - GainSlide.stepPerFrame)) < 1e-5)
    }
}
