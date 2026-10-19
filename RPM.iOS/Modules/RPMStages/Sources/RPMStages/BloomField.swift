import Foundation

/// The reading a flower of light is drawn from: a polar spectrogram, and the swell under it.
///
/// Ported from the analysis half of `RPM.Desktop/Presentation/Viz/Controls/BloomStage.cs`.
///
/// **Angle is frequency and radius is time.** Columns are time with now at column 0,
/// rows are the frequency wheel, bass through treble once around. A petal reads this at its
/// own angle and its own radius. So a beat opens at the heart of the flower and travels
/// outward as a ring, a held note draws a spiral arm, and the whole of the last two and a
/// half seconds is on screen at once, turning slowly.
///
/// This is separate from the drawing, and pure, for the same reason as every other
/// visualiser's arithmetic: the picture cannot be checked without a screen, and this can.
public final class BloomField {
    /// The frequency wheel's resolution.
    public static let bands = 64

    /// Time columns. About two and a half seconds at the forty-hertz analysis tick, which is
    /// how long it takes an instant pushed in at the heart to reach the rim.
    public static let columns = 96

    private let audio: ShaderAudio
    private var spec = [Float](repeating: 0, count: ShaderAudio.width)

    private var swellNow: Float = 0
    private var swellHold: Double = 0
    private var turnedSoFar: Double = 0

    /// The spectrogram, row-major: `history[band * columns + column]`, with column 0 the
    /// newest. Values run from 0 to 1.
    public private(set) var history = [Float](repeating: 0,
                                              count: BloomField.bands * BloomField.columns)

    public init(frameSize: Int = 2048) { audio = ShaderAudio(frameSize: frameSize) }

    /// The broadband swell, fast attack and a held peak before a slow release. It drives the
    /// whole bloom's scale, brightness and turn rate.
    public var swell: Float { swellNow }

    /// How far the bloom has turned, in radians. Integrated rather than read off a clock, so
    /// a change of speed never jumps the angle.
    public var turned: Float { Float(turnedSoFar) }

    /// Turns it on. A loud passage turns it a little faster.
    public func turn(_ dt: Double) {
        turnedSoFar += min(max(dt, 0), 0.1) * (0.085 + Double(swellNow) * 0.22)
    }

    /// Reads the playing block, smooths the spectrum, keeps the swell envelope, and pushes
    /// one new column into the spectrogram: this instant's frequency wheel, at the heart of
    /// the flower.
    public func listen(_ frame: [Float], now: Double) {
        audio.listen(frame)

        let heard = audio.spectrum
        for i in spec.indices {
            // Rise fast, fall slow.
            let k: Float = heard[i] > spec[i] ? 0.42 : 0.12
            spec[i] += (heard[i] - spec[i]) * k
        }

        let lo = 2, hi = 220
        var sum: Float = 0
        for i in lo..<hi { sum += spec[i] }
        let level = sum / Float(hi - lo)

        if level > swellNow {
            swellNow += (level - swellNow) * 0.35
            swellHold = now + 0.30
        } else if now >= swellHold {
            swellNow += (level - swellNow) * 0.012
        }

        scroll()
    }

    /// Every row shifts one column outward, then this instant goes in at column 0.
    ///
    /// Bands are log spaced, so the wheel gives an octave roughly equal room instead of
    /// crowding everything into a sliver.
    private func scroll() {
        for band in 0..<Self.bands {
            let lo = Int(2.0 * pow(210.0, Double(band) / Double(Self.bands)))
            var hi = Int(2.0 * pow(210.0, Double(band + 1) / Double(Self.bands)))
            if hi <= lo { hi = lo + 1 }
            if hi > 460 { hi = 460 }

            var sum: Float = 0
            for i in lo..<hi { sum += spec[i] }

            // A gentle knee: quiet detail stays visible, loud peaks do not simply clip to
            // white. **There is no gain in front of it**: real music fills far more of the
            // wheel than a test tone does, and a boost here would turn the whole flower
            // into one white sheet.
            let v = min(1, pow(sum / Float(hi - lo), 0.85))

            let row = band * Self.columns
            for c in stride(from: Self.columns - 1, to: 0, by: -1) {
                history[row + c] = history[row + c - 1]
            }
            history[row] = v
        }
    }
}
