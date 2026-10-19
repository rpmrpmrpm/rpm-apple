import Foundation

/// How good a photograph looks, in the abstract.
///
/// This is the `Look` part of `RPM.Core/Art/BackdropRanker.cs`. It is the part the phone uses. **What
/// makes a photograph good is not a property of the screen showing it.** The rest of the judgement
/// depends on the frame, and is measured elsewhere.
///
/// All of it is read from a thumbnail one hundred pixels across. This is for ranking, not for drawing.
public struct BackdropFeatures: Hashable, Sendable {
    /// Average brightness, from 0 (black) to 1 (white).
    public let meanLuma: Double

    /// Spread of brightness, from 0 (flat) to 1 (full range). A washed-out or murky photograph scores low.
    public let contrast: Double

    /// How much colour it has, from 0 (grey) to 1 (vivid).
    public let colourfulness: Double

    /// The shorter side of the source, in pixels. It is a guide to how sharp the picture will look when it
    /// is enlarged to fill a screen. Zero when the size is not known.
    public let sourceMinDim: Int
}

public enum BackdropLook {
    // The weights of the four parts.
    private static let brightness = 0.30, contrast = 0.28, colour = 0.22, resolution = 0.20

    /// The ideal brightness. A backdrop should be mid-dark. It should not be a black bar, and it should not
    /// be glare under the words.
    private static let idealLuma = 0.45

    /// Above this short side, more resolution adds nothing to the score.
    private static let sharpEnough = 720.0

    /// How good the photograph looks, from 0 to 1.
    public static func score(_ f: BackdropFeatures) -> Double {
        brightness * brightnessScore(f.meanLuma)
            + contrast * min(max(f.contrast, 0), 1)
            + colour * min(max(f.colourfulness, 0), 1)
            + resolution * resolutionScore(f.sourceMinDim)
    }

    /// The score for a photograph that nobody could measure. It is in the middle, so a candidate that could
    /// not be measured neither wins nor loses for that reason.
    public static let unmeasured = 0.5

    /// Highest at ``idealLuma``. It falls to 0 at black and at near-white.
    private static func brightnessScore(_ meanLuma: Double) -> Double {
        let d = abs(min(max(meanLuma, 0), 1) - idealLuma)
        // Use the larger distance to the edge, so that both ends reach 0.
        let reach = max(idealLuma, 1 - idealLuma)

        return min(max(1 - d / reach, 0), 1)
    }

    private static func resolutionScore(_ shortSide: Int) -> Double {
        shortSide <= 0 ? unmeasured : min(max(Double(shortSide) / sharpEnough, 0), 1)
    }

    /// Reads a thumbnail. `rgba` holds four bytes per pixel, row by row.
    ///
    /// - Parameters:
    ///   - sourceWidth: the real width of the photograph in pixels, for the sharpness term. Zero when it is
    ///     not known, and then that term returns ``unmeasured``.
    public static func measure(rgba: [UInt8], width: Int, height: Int,
                               sourceWidth: Int, sourceHeight: Int) -> BackdropFeatures {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else {
            return BackdropFeatures(meanLuma: 0, contrast: 0, colourfulness: 0, sourceMinDim: 0)
        }

        var sum = 0.0, sumSq = 0.0
        var sumRg = 0.0, sumRgSq = 0.0, sumYb = 0.0, sumYbSq = 0.0
        let n = width * height

        for i in 0..<n {
            let r = Double(rgba[i * 4]), g = Double(rgba[i * 4 + 1]), b = Double(rgba[i * 4 + 2])
            let l = 0.299 * r + 0.587 * g + 0.114 * b
            sum += l
            sumSq += l * l

            // The cheap version of Hasler and Süsstrunk's colourfulness measure, which uses opponent colour channels.
            let rg = r - g
            let yb = 0.5 * (r + g) - b
            sumRg += rg; sumRgSq += rg * rg
            sumYb += yb; sumYbSq += yb * yb
        }

        let mean = sum / Double(n)
        let lumaStd = (max(0, sumSq / Double(n) - mean * mean)).squareRoot()

        let rgStd = std(sumRg, sumRgSq, n), ybStd = std(sumYb, sumYbSq, n)
        let rgMean = sumRg / Double(n), ybMean = sumYb / Double(n)
        let colourfulness = (rgStd * rgStd + ybStd * ybStd).squareRoot()
            + 0.3 * (rgMean * rgMean + ybMean * ybMean).squareRoot()

        return BackdropFeatures(
            meanLuma: mean / 255,
            // 64 is about the spread of a well-exposed photograph. A good photograph then lands near 1, and a hard
            // clip does not flatten everything above it.
            contrast: min(max(lumaStd / 64, 0), 1),
            colourfulness: min(max(colourfulness / 110, 0), 1),
            sourceMinDim: sourceWidth > 0 && sourceHeight > 0 ? min(sourceWidth, sourceHeight) : 0)
    }

    private static func std(_ sum: Double, _ sumSq: Double, _ n: Int) -> Double {
        let mean = sum / Double(n)
        return (max(0, sumSq / Double(n) - mean * mean)).squareRoot()
    }
}
