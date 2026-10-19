import AVFAudio

/// Applies the levelling gain to the samples as they leave the pump. The gain slides to a new
/// value and does not jump.
///
/// Port of `AudioEngine.ApplyGain` in the desktop app. The gain is applied in the pump, before
/// the audio is split between the handset and a speaker, so a cast is levelled exactly like the
/// handset. It is also applied before the visualiser's copy, so what is drawn is what is heard.
///
/// A jump in gain makes a click. This happens at a gapless join from a -6 dB record into a +3 dB
/// one, and when the setting changes while a record plays. An outright start (a tap or a seek)
/// uses its gain directly, because there is no earlier sound to join.
struct GainSlide {
    /// How far the gain moves per frame while it slides: one unit of linear gain in 20 ms. This
    /// must match the desktop (`GainStepPerFrame`).
    static let stepPerFrame = Float(1 / (StreamedPcm.engineFormat.sampleRate / 50))

    /// The gain the last frame was scaled by. Nil before the first block, which uses its target
    /// directly.
    private(set) var now: Float?

    /// Scales `buffer` in place, moving from the current gain towards `target`.
    ///
    /// Each output sample is clamped to full scale. When the track's peak is known, the gain is
    /// already limited to stay below the ceiling (see `ReplayGain.clamp`), so this clamp protects
    /// tracks whose peak was not measured.
    mutating func apply(_ target: Float, to buffer: AVAudioPCMBuffer) {
        let from = now ?? target
        now = target

        // Unity gain and not sliding: nothing to do. This is by far the most common case, and it
        // covers every station and every unmeasured track.
        if from == target && abs(target - 1) < 1e-6 { return }

        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)

        if from == target {
            for c in 0..<count {
                let samples = channels[c]
                for f in 0..<frames { samples[f] = min(1, max(-1, samples[f] * target)) }
            }
            return
        }

        // The gain moves once per frame, not per sample, so both channels of a frame use the same
        // value. Different values would shift the stereo image while the gain moves.
        var gain = from
        for f in 0..<frames {
            gain = gain < target ? min(target, gain + Self.stepPerFrame)
                                 : max(target, gain - Self.stepPerFrame)

            for c in 0..<count {
                channels[c][f] = min(1, max(-1, channels[c][f] * gain))
            }
        }

        // A block shorter than the slide ends part way through it. The next block continues from
        // this gain.
        now = gain
    }
}
