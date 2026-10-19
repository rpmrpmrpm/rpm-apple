import Foundation
import CoreGraphics

/// Which of an artist's photographs to show.
///
/// This is a port of `RPM.Mobile/Services/BackdropChooser.cs`.
///
/// The desktop app picks with a cheap heuristic first. It reads brightness, colour, aspect and the
/// position of a face from a small thumbnail. That way the expensive crop runs on one photograph, not
/// ten. **A phone does not have that limit.** Vision runs on the Neural Engine and costs very little.
/// So this code judges each candidate by what its crop would actually look like. It runs the real
/// reading and the real crop, then scores the frame that comes out.
///
/// So the signal that matters most is not "is there a face somewhere in this photograph". It is "does
/// the face land in the clear part of the screen once the picture is cut to fit". A photograph whose
/// face can only end up behind the record scores below a good landscape. The desktop's obstruction
/// penalty makes the same judgement, but here it comes from measurement, not from a proxy.
///
/// The number of candidates is kept small: three, not the artist's whole gallery. Every candidate
/// examined is downloaded, and this can run on cellular data.
public enum BackdropChooser {
    /// How many are examined. The list comes back best first, ordered by the source's own likes, so the
    /// best one is nearly always in the first few. Each extra candidate is another download of about a
    /// megabyte, for a small chance of a better pick.
    public static let maxCandidates = 3

    // The weights of the three parts. Placement counts the most. On a screen of this shape, the other two
    // parts only break ties between photographs that already show the artist clearly.
    private static let weightPlacement = 0.55, weightLook = 0.25, weightSharpness = 0.20

    /// The placement score for a photograph with no face. It is in the middle on purpose. A good landscape
    /// scores above a portrait whose face ends up behind the record. A portrait with a face in the clear part
    /// scores above it.
    private static let facelessPlacement = 0.35

    /// A frame that cannot be made the screen's shape is filled, and its sides are lost. This is not fatal,
    /// but it costs score.
    private static let pillarboxPenalty = 0.85

    /// How well this photograph suits the frame, from 0 to 1, and the picture that would be shown.
    ///
    /// - Parameter needing: how wide the frame is, in real pixels. It is used to check that the crop still
    ///   has enough resolution to fill the frame. Pass zero to skip that check. A caller that asks about one
    ///   photograph, rather than choosing between several, passes zero.
    public static func judge(_ photograph: CGImage, for scene: ArtScene,
                             widest: Int, needing pixels: Int) -> (score: Double, picture: CGImage)? {
        guard let framed = ArtFrame.framed(photograph, for: scene, widest: widest) else { return nil }

        let reading = framed.reading
        let window = framed.choice.rect

        // ── placement: where the best face ends up inside the chosen frame ──
        var placement = facelessPlacement
        if !reading.faces.isEmpty {
            placement = 0
            for face in reading.faces {
                let across = (Double(face.x) + Double(face.width) / 2 - Double(window.x))
                    / Double(max(1, window.width))
                placement = max(placement, scene.facePosition(across))
            }
        }

        // ── look: the brightness, contrast, colour and resolution score that the desktop uses. It is used
        // unchanged, because a good photograph is good on any screen. ──
        let look = reading.thumbWidth > 0
            ? BackdropLook.score(BackdropLook.measure(
                rgba: reading.thumbnail,
                width: reading.thumbWidth, height: reading.thumbHeight,
                sourceWidth: reading.sourceWidth, sourceHeight: reading.sourceHeight))
            : BackdropLook.unmeasured

        // ── sharpness: a portrait crop of a landscape photograph keeps about a third of its width. That third
        // must fill a screen with three device pixels for each point. This is the cost of zooming. ──
        let sharpness = pixels <= 0
            ? 1
            : min(max(Double(framed.window.width) / Double(pixels), 0), 1)

        var score = weightPlacement * placement + weightLook * look + weightSharpness * sharpness
        if !framed.choice.fillsTarget { score *= pillarboxPenalty }

        return (score, framed.picture)
    }
}
