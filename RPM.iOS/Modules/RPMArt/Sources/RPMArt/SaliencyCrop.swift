import Foundation

/// A crop window, in the pixels of whatever picture it was measured against.
public struct CropRect: Hashable, Sendable {
    public let x: Int, y: Int, width: Int, height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The window to show, and whether it has the shape of the frame it goes in.
///
/// ``fillsTarget`` is false when the content would not survive a crop to the frame's shape. For example, a face
/// is taller than the band on offer. The window is then left taller and narrower. The screen fills with it anyway
/// and loses the sides. That is the right result on a phone. The desktop's blurred pillarbox exists because its
/// strip has a foot, and nothing outside the window is drawn at all. This stage has neither.
public struct CropChoice: Hashable, Sendable {
    public let rect: CropRect
    public let fillsTarget: Bool

    public init(rect: CropRect, fillsTarget: Bool) {
        self.rect = rect
        self.fillsTarget = fillsTarget
    }
}

/// A face, in the same pixels as the saliency map. It comes from a face detector.
public struct FaceBox: Hashable, Sendable {
    public let x: Int, y: Int, width: Int, height: Int

    public init(x: Int, y: Int, width: Int, height: Int) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// A face box as Vision reports it: normalised from 0 to 1, with the origin at the **bottom** left. This converts
    /// it to the pixels the crop works in, whose origin is the **top** left.
    ///
    /// This is one line of arithmetic, and it is the most important line in the art path. If the flip is wrong, every
    /// face is found at its mirror image lower down the photograph. The crop is then confidently and precisely wrong.
    /// The conversion is kept here, with a test, rather than inline where the detector is called.
    public static func fromNormalizedBottomLeft(x: Double, y: Double,
                                                width: Double, height: Double,
                                                pixelWidth: Int, pixelHeight: Int) -> FaceBox {
        FaceBox(x: Int((x * Double(pixelWidth)).rounded()),
                y: Int(((1 - y - height) * Double(pixelHeight)).rounded()),
                width: Int((width * Double(pixelWidth)).rounded()),
                height: Int((height * Double(pixelHeight)).rounded()))
    }
}

/// Picks the part of a photograph worth showing when it has to be fitted into a frame.
///
/// This is a port of the `Choose` part of `RPM.Core/Art/SaliencyCrop.cs`. It picks a window of the frame's own
/// shape, for a display where the picture continues past the frame. (The desktop's `Fit` is for its header, which
/// has a foot and shows nothing outside its window. A phone has no such frame.)
///
/// "Worth showing" is measured with a **saliency map**: one score per pixel, for how much that part of the picture
/// is what the picture is *about*. The caller passes the map in. On iOS it comes from Vision's attention model. On
/// the desktop it comes from U2-Netp. The models differ, but both give the same kind of number. This arithmetic is
/// shared, and it is tested on both platforms.
///
/// The frame is chosen by **framing the subject**, not by searching for the densest window:
///
/// * **Find the subject's box.** Threshold the map, and take the bounding box of what is left.
/// * **Frame it on its height**, and let the frame's shape supply the width. Height is the scarce axis. The
///   subject's width hardly limits anything, but its height decides whether the picture shows a person or only
///   their nose.
/// * **No subject, no zoom.** A texture, a landscape, or a wall of stage lights has no subject. So show the
///   biggest window there is. A search for the busiest patch of a rock face, then a zoom into it, is exactly the
///   mistake a density search makes.
///
/// Faces override all of this, because a face box is not a hint. It is a measurement.
public enum SaliencyCrop {
    /// How far in the crop may zoom. It is a fraction of the largest window of the frame's shape that fits inside
    /// the photograph.
    ///
    /// The fraction is measured against that window, **not** against the whole picture. With a wide frame and a
    /// fairly tall photograph, even the largest allowed window is only a slice of the image. A floor written as
    /// "keep a third of the photo" would then reject every window.
    public static let minScale = 0.45

    /// Saliency this strong, as a fraction of the picture's peak, is the subject itself. It is not the soft halo
    /// that a detector leaves around it.
    private static let subjectThreshold = 0.5

    /// Below this, the "subject" is a speck: a highlight, a bird, or noise.
    private static let minSubjectFraction = 0.005

    /// A subject spread wider than this is the picture itself: a landscape, a texture, or a wall of stage lights.
    /// The value is high on purpose. A band of four players standing shoulder to shoulder covers most of a
    /// photograph, and is still the subject.
    private static let maxSubjectFraction = 0.85

    /// Space around the subject, as a fraction of its height. A frame that ends right at the edge of the subject looks
    /// like a mistake.
    private static let padding = 0.15

    /// How much taller than the band a faceless subject must be before the picture is pillarboxed instead of banded.
    /// Above this, a band would cut across a head.
    private static let subjectPillarbox = 1.6

    /// How far below a too-tall subject's top edge the band is dropped, as a fraction of the band. The value is small
    /// on purpose. With no face to go on, the safe error is upwards. Losing the top of someone's hair costs little.
    /// A band that has slid down onto a chest has lost the person. A detected face overrides this completely.
    private static let faceDrop = 0.02

    /// How much of the widest possible frame is used. The rest is room to slide the frame sideways. Using the full
    /// width would leave no room to move the frame, so the subject would stay wherever the photographer put it.
    private static let horizontalRoom = 0.85

    // A head has a known shape around a face box, so the frame around it is calculated, not guessed.

    /// Hair and crown above the face box, as a fraction of it.
    private static let hairAbove = 0.45

    /// Neck and shoulders below the face box, as a fraction of it.
    private static let shouldersBelow = 0.8

    /// Space either side of a face, as a fraction of its width.
    private static let besideFace = 0.6

    /// The narrowest a pillarboxed picture may get, as an aspect. Below this it is a small stamp in the middle of a
    /// wide frame. So the frame is cropped tighter instead, and a little more of the shoulders is lost.
    private static let minPillarAspect = 2.8

    /// How far short of the frame's shape a window may be and still count as filling it. Cropping a sliver off an
    /// almost right window is better than letterboxing it.
    private static let fillTolerance = 0.12

    /// Where the eyes sit down a face box, from brow to chin.
    private static let eyesInFace = 0.42

    /// Where the eyes go in a band too short to hold a whole face. They go in the upper third. That leaves room for
    /// the chin below, and the rest goes to hair. Hair and chin can be cut. Eyes cannot.
    private static let eyesInBand = 0.38

    /// Chooses the window of `targetAspect` (width divided by height) to show.
    ///
    /// - Parameters:
    ///   - saliency: one score per pixel, row by row, `width` times `height` values, on any positive scale. A
    ///     downscaled map is enough. The caller scales the result back up.
    ///   - faces: every face found, in the same pixels. An empty list is a real answer, and a common one. It is a
    ///     different answer from a photograph that nobody looked at.
    ///   - scene: what covers the frame. **This is not optional.** Where the subject may go is the whole question
    ///     here. A default would answer it by forgetting to ask.
    public static func choose(saliency: [Double], width: Int, height: Int,
                              targetAspect: Double,
                              faces: [FaceBox], scene: ArtScene) -> CropChoice {
        guard width > 0, height > 0, targetAspect > 0, saliency.count >= width * height else {
            return CropChoice(rect: CropRect(x: 0, y: 0,
                                             width: max(width, 0), height: max(height, 0)),
                              fillsTarget: true)
        }

        let focusAcross = scene.focusAcross

        // Where the subject should sit down the frame. A half means the exact centre. A frame with its controls
        // along the foot needs a smaller number, and the subject moves up by that fraction of the frame's height.
        let downShift = 0.5 - scene.focusDown

        // The largest window of the frame's shape that fits inside the photograph. This is the frame with no zoom.
        let (maxW, maxH) = fitInside(width: width, height: height, aspect: targetAspect)

        guard let subject = findSubject(saliency, width: width, height: height) else {
            // Nothing to frame. Centre the widest window on the saliency that exists, and do not zoom. A photograph
            // with no subject has no detail worth enlarging.
            let (cx, cy) = centroid(saliency, width: width, height: height)
            return CropChoice(rect: place(centreX: cx, centreY: cy, w: maxW, h: maxH,
                                          width: width, height: height),
                              fillsTarget: true)
        }

        // The band that a picture of the frame's own shape gets: the height on offer.
        let band = Int(clamp(Double(maxW) / targetAspect,
                             Double(maxH) * minScale, Double(maxH)).rounded())

        // ── faces ──
        //
        // Grow the face boxes into heads and shoulders, using the known proportions. This gives the smallest frame
        // that shows everybody properly. Zoom to it. A good crop is not "as wide as possible". A wide crop of a
        // portrait is a strip of wall with a face in it.
        if !faces.isEmpty {
            let faceTop = faces.map { Double($0.y) - Double($0.height) * hairAbove }.min()!
            let faceBottom = faces.map { Double($0.y) + Double($0.height) * (1 + shouldersBelow) }.max()!
            let faceLeft = faces.map { Double($0.x) - Double($0.width) * besideFace }.min()!
            let faceRight = faces.map { Double($0.x) + Double($0.width) * (1 + besideFace) }.max()!

            let contentH = max(1, faceBottom - faceTop)
            let contentW = max(1, faceRight - faceLeft)

            // The frame's shape is found by growing whichever side is short. It never crops the other side.
            var frameH = max(contentH, contentW / targetAspect)
            var frameW = frameH * targetAspect

            // Fit it back inside the photograph. If the width runs out first, the frame keeps its height and stops
            // having the frame's shape. That is the pillarbox case.
            if frameW > Double(width) {
                // Keep only the height the content needs. Inflating to the pillarbox floor here would letterbox a
                // frame that only needed a sliver cropped off. The height is capped at that floor. Beyond it, the
                // picture would be a small picture in the middle of a wide frame, so the shoulders and hair are cut
                // instead.
                frameW = Double(width)
                frameH = min(min(Double(height), contentH), frameW / minPillarAspect)
            }
            if frameH > Double(height) {
                frameH = Double(height)
                frameW = min(Double(width), frameH * targetAspect)
            }

            // Close enough to the frame's shape is filling it.
            let fills = frameW >= frameH * targetAspect * (1 - fillTolerance)

            // Across: the faces themselves. They are placed where the scene says the clear part is. Only a
            // frame that reached the shape has any slack to slide in.
            let faceX = (faceLeft + faceRight) / 2
            let acrossAt = fills ? faceX + (0.5 - focusAcross) * frameW : faceX

            // Down: the eyes are the reference point. Hair and chin can be cut off. Eyes cannot.
            let eyesAt = faces.map { Double($0.y) + Double($0.height) * eyesInFace }
                .reduce(0, +) / Double(faces.count)
            let downAt = (frameH >= contentH
                          ? (faceTop + faceBottom) / 2
                          : eyesAt - frameH * eyesInBand + frameH / 2)
                + ride(wanted: downShift * frameH, frameHeight: frameH, contentHeight: contentH)

            return CropChoice(
                rect: place(centreX: acrossAt, centreY: downAt,
                            w: Int(frameW.rounded()), h: Int(frameH.rounded()),
                            width: width, height: height),
                fillsTarget: fills)
        }

        // No face, but a subject far taller than the band, such as a figure seen close, or someone looking down
        // with their back turned. Filling the frame here would put a band across a head twice its height, a giant
        // cropped face. So the picture is pillarboxed instead.
        if Double(subject.height) > Double(band) * subjectPillarbox {
            let tallH = min(Double(height), Double(maxW) / minPillarAspect)
            let tallW = min(Double(width), tallH * targetAspect)

            let acrossSubject = Double(subject.x) + Double(subject.width) / 2
            let downSubject = Double(subject.y) + tallH / 2 + tallH * faceDrop
                + ride(wanted: downShift * tallH, frameHeight: tallH,
                       contentHeight: Double(subject.height))

            return CropChoice(
                rect: place(centreX: acrossSubject, centreY: downSubject,
                            w: Int(tallW.rounded()), h: Int(tallH.rounded()),
                            width: width, height: height),
                fillsTarget: tallW >= tallH * targetAspect * (1 - fillTolerance))
        }

        // Frame the subject on its HEIGHT, and let the frame's shape supply the width. Framing on the width instead
        // gives a standing figure, which is narrow and tall, so the window is a slice of a face.
        var frameH = Double(subject.height) * (1 + 2 * padding)
        var frameW = frameH * targetAspect

        if frameW > Double(width) {
            frameW = Double(width)
            frameH = frameW / targetAspect
        }
        if frameH > Double(height) {
            frameH = Double(height)
            frameW = frameH * targetAspect
        }

        // Leave some slack across, so the subject can be placed, not just included. A frame that is the full width
        // of the photograph has no sideways freedom at all. The subject then ends up wherever the photographer left it.
        frameW = min(frameW, Double(maxW) * horizontalRoom)
        frameH = frameW / targetAspect

        // Never zoom past the floor, and never zoom out past the largest window there is.
        let w = Int(clamp(frameW, Double(maxW) * minScale, Double(maxW)).rounded())
        let h = Int(clamp(frameH, Double(maxH) * minScale, Double(maxH)).rounded())

        let focusX = Double(subject.x) + Double(subject.width) / 2
        let subjectX = focusX + (0.5 - focusAcross) * Double(w)
        let subjectY = bandCentre(subject, band: h)
            + ride(wanted: downShift * Double(h), frameHeight: Double(h),
                   contentHeight: Double(subject.height))

        return CropChoice(rect: place(centreX: subjectX, centreY: subjectY, w: w, h: h,
                                      width: width, height: height),
                          fillsTarget: true)
    }

    // ── the pieces ──

    /// How much of the scene's requested lift the frame can actually pay for.
    ///
    /// A scene asks in fractions of the frame, for example "put them a fifth of the way up, the words are along the
    /// foot". But the subject decides what is on offer. The frame can only rise by the slack between its own height
    /// and the head and shoulders inside it. If the request is larger than that, the top edge of the frame passes
    /// the crown, and the top of somebody's head is cut off.
    private static func ride(wanted: Double, frameHeight: Double, contentHeight: Double) -> Double {
        let slack = max(0, (frameHeight - contentHeight) / 2)
        return clamp(wanted, -slack, slack)
    }

    /// Where the band sits when there is no face. This is a guess, and the code treats it as one.
    ///
    /// The face detector has already run by the time this is called. Heads are at the top of people. A band flush
    /// with the subject's top edge shows hair. A band centred on the subject shows a chest. A band dropped a fraction
    /// of its own height below the top lands about where a face would be.
    private static func bandCentre(_ subject: CropRect, band: Int) -> Double {
        if subject.height <= band {
            return Double(subject.y) + Double(subject.height) / 2
        }

        return Double(subject.y) + Double(band) / 2 + Double(band) * faceDrop
    }

    /// A w by h window centred on a point, moved back inside the photograph's edges if needed.
    private static func place(centreX: Double, centreY: Double, w: Int, h: Int,
                              width: Int, height: Int) -> CropRect {
        let w = min(max(w, 1), width)
        let h = min(max(h, 1), height)

        let x = Int(clamp(centreX - Double(w) / 2, 0, Double(width - w)).rounded())
        let y = Int(clamp(centreY - Double(h) / 2, 0, Double(height - h)).rounded())

        return CropRect(x: x, y: y, width: w, height: h)
    }

    /// The subject's box: the strongly salient pixels, boxed. Nil when there is no real subject. That is when
    /// nothing is salient, the salient area is a speck, or saliency is spread over everything.
    private static func findSubject(_ map: [Double], width: Int, height: Int) -> CropRect? {
        var peak = 0.0
        for i in 0..<(width * height) where map[i] > peak { peak = map[i] }

        guard peak > 0 else { return nil }
        let threshold = peak * subjectThreshold

        var minX = width, minY = height, maxX = -1, maxY = -1, count = 0

        for y in 0..<height {
            let row = y * width
            for x in 0..<width where map[row + x] >= threshold {
                count += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }

        guard maxX >= minX, maxY >= minY else { return nil }

        let area = Double(count) / Double(width * height)
        // A speck, or the whole picture. Either way, there is nothing to frame.
        guard area >= minSubjectFraction, area <= maxSubjectFraction else { return nil }

        return CropRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// The saliency-weighted centre of the picture. This is where to point a frame when there is no subject to
    /// aim at. The middle is used when the map is empty.
    private static func centroid(_ map: [Double], width: Int, height: Int) -> (Double, Double) {
        var total = 0.0, sumX = 0.0, sumY = 0.0

        for y in 0..<height {
            let row = y * width
            for x in 0..<width {
                let v = map[row + x]
                guard v > 0 else { continue }

                total += v
                sumX += v * Double(x)
                sumY += v * Double(y)
            }
        }

        return total <= 0
            ? (Double(width) / 2, Double(height) / 2)
            : (sumX / total, sumY / total)
    }

    /// The largest window of the given aspect that fits inside `width` by `height`.
    private static func fitInside(width: Int, height: Int, aspect: Double) -> (Int, Int) {
        var w = width
        var h = Int((Double(width) / aspect).rounded())

        if h > height {
            h = height
            w = Int((Double(height) * aspect).rounded())
        }

        return (min(max(w, 1), width), min(max(h, 1), height))
    }

    private static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(v, lo), hi)
    }
}
