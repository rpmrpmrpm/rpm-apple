import Foundation

/// The audio the visualisers read: a 512-wide, two-row picture of the music, where the
/// first row is the frequency spectrum and the second is the raw waveform.
///
/// Ported from `RPM.Core/Audio/ShaderAudioTexture.cs`. It is ShaderToy's audio texture,
/// which is the shape all three looks were written against. On the desktop it is uploaded
/// as an R8 texture and read with `texture(channel, float2(x, 0.25))`. Nothing here
/// uploads anything: the three looks in the iOS app do their arithmetic on the CPU and
/// read these rows as arrays. The shape is kept because the figures that read it are kept.
///
/// **Loudness, not magnitude.** A decibel window is mapped onto 0 to 1, so a quiet
/// bin sits near the floor and a full-scale tone near the top. Raw magnitude read as a
/// level puts everything in the bottom tenth of the range and the picture never moves.
public final class ShaderAudio {
    /// Texels across each row. ShaderToy's audio texture is 512 wide.
    public static let width = 512

    /// The decibel window mapped onto the range.
    private static let dbFloor = -84.0, dbCeiling = -20.0

    /// How much of the previous spectrum frame carries over, so the bars settle instead of
    /// strobing.
    private static let smoothing: Float = 0.5

    private let frameSize: Int
    private let window: [Float]
    private var re: [Double]
    private var im: [Double]

    /// The smoothed spectrum, 0 to 1, held between frames.
    public private(set) var spectrum = [Float](repeating: 0, count: ShaderAudio.width)

    /// The waveform, -1 to 1 across the row.
    public private(set) var wave = [Float](repeating: 0, count: ShaderAudio.width)

    /// - Parameter frameSize: samples an analysis frame, a power of two and at least twice
    ///   the width, so the spectrum has a texel a column.
    public init(frameSize: Int = 2048) {
        precondition(frameSize >= Self.width * 2 && frameSize & (frameSize - 1) == 0,
                     "a frame is a power of two and at least \(Self.width * 2) samples")

        self.frameSize = frameSize
        window = Spectrum.hann(frameSize)
        re = [Double](repeating: 0, count: frameSize)
        im = [Double](repeating: 0, count: frameSize)
    }

    /// Reads a frame of played samples. An empty frame is silence, which is a resting
    /// picture rather than a blank one: the spectrum eases down from wherever it was and
    /// the waveform lies flat.
    public func listen(_ frame: [Float]) {
        readTheSpectrum(frame)
        readTheWave(frame)
    }

    private func readTheSpectrum(_ frame: [Float]) {
        // **No samples means no transform.** The looks feed an empty frame every frame
        // while paused or buffering, and the resting picture is the held spectrum easing
        // down, which is what the smoothing below gives for a level of 0. A transform of
        // two thousand zeros, sixty times a second, would only produce that same answer.
        guard !frame.isEmpty else {
            for x in 0..<Self.width { spectrum[x] *= Self.smoothing }
            return
        }

        let n = frameSize
        let take = min(frame.count, n)

        for i in 0..<take { re[i] = Double(frame[i] * window[i]); im[i] = 0 }
        for i in take..<n { re[i] = 0; im[i] = 0 }

        Spectrum.transform(&re, &im)

        // Linear bins, one texel each: bin k spans k·rate/n Hz. The first 512 of the n/2
        // bins reach about 11 kHz at 44.1 kHz, above which a music spectrum has very little
        // energy.
        for x in 0..<Self.width {
            let power = (re[x] * re[x] + im[x] * im[x]) / (Double(n) * Double(n))
            let db = 10 * log10(power + 1e-12)
            let level = Float(min(1, max(0, (db - Self.dbFloor) / (Self.dbCeiling - Self.dbFloor))))

            // Peak fast, fall slow: a rising bin jumps, a falling one eases down.
            spectrum[x] = level > spectrum[x]
                ? level
                : spectrum[x] * Self.smoothing + level * (1 - Self.smoothing)
        }
    }

    private func readTheWave(_ frame: [Float]) {
        let take = min(frame.count, frameSize)

        for x in 0..<Self.width {
            // Decimated across the row. Silence, and no samples at all, lie flat.
            guard take > 0 else { wave[x] = 0; continue }

            wave[x] = min(1, max(-1, frame[x * take / Self.width]))
        }
    }
}
