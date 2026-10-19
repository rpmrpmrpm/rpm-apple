import Foundation

/// Bass, middle and air, for the marched visualisers.
///
/// Ported from `MarchedStage.Listen` in the desktop. Read off the spectrum row rather than
/// the raw bins, so the lighting follows loudness the way the ear does, and enveloped fast
/// up and slow down: a hit should arrive on the frame it happens and leave over the next few.
///
/// **Not ``RoomBands``**, which uses the same three names for a different measurement. That
/// one folds a hundred and twenty-eight log-spaced bands out of three windows, for a spectrum
/// that people look AT. This one is three numbers from one window, for lighting a picture,
/// and the desktop keeps the two apart for the same reason.
public final class MarchBands {
    private let audio: ShaderAudio

    public private(set) var bass: Float = 0
    public private(set) var middle: Float = 0
    public private(set) var air: Float = 0

    /// The spectrum row itself, 0 to 1 a bin.
    ///
    /// Exposed for the one look that draws the reading rather than being lit by it: the
    /// butterfly is the spectrum, mirrored into four, and it needs the whole row.
    public var spectrum: [Float] { audio.spectrum }

    public init(frameSize: Int = 2048) { audio = ShaderAudio(frameSize: frameSize) }

    /// Reads a frame of played samples. Empty for silence, which lets the three fall away
    /// rather than cutting them.
    public func listen(_ frame: [Float]) {
        audio.listen(frame)

        let heard = audio.spectrum

        func band(_ from: Int, _ to: Int) -> Float {
            var sum: Float = 0
            for x in from..<to { sum += heard[x] }

            return sum / Float(to - from)
        }

        bass = max(band(0, 24), bass * 0.86)
        middle = max(band(24, 140), middle * 0.90)
        air = max(band(140, 400), air * 0.92)
    }
}
