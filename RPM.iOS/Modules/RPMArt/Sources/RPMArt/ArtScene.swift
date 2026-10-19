import Foundation

/// What is covering the picture, and where.
///
/// This is a port of the clear-left half of `RPM.Core/Art/ArtScene.cs`, the desktop version of
/// the same type. The iOS app only needs that half. One artist's photograph is shown on one
/// screen, in a wide landscape frame. The record covers the right side from half its diameter in,
/// and the column of words covers the foot. What is left is the upper-left, and that is where the
/// artist goes.
///
/// The desktop's strip has the obstruction on the other side. The album cover sits against its
/// left edge, so a face there has to clear it. That case needs the other constructor and other
/// limits. This file has no strip, so it has no constructor for one.
/// ``forClearLeft(width:height:clearTop:clearRight:clearBottom:)`` is the only way in. A scene
/// can therefore never be built with the wrong side protected.
///
/// **Every value is a fraction of the displayed picture**, not a constant tuned for one phone. A
/// bigger phone or a rotated one moves the whole calculation with it.
public struct ArtScene: Hashable, Sendable {
    /// The frame, in points. The crop is judged for a shape, and the shape is the only thing about
    /// the screen that the arithmetic needs.
    public let width: Double, height: Double

    /// The part of the picture that is on show, as fractions across it. A face outside this range
    /// is behind something opaque and is not seen.
    public let clearLeft: Double, clearRight: Double

    /// How far down the frame its top is covered, as a fraction of the height. On a frame that runs
    /// up behind the status bar and the Dynamic Island, this is their height. On a frame that starts
    /// below them, it is zero. Used when choosing between pictures, so that a face which would sit
    /// behind the Dynamic Island is not the one chosen. See ``ArtFrame/coversFace(_:width:height:for:)``.
    public let clearTop: Double

    /// How far in the obstructions reach at their worst. Nothing covers the left on this shape, so
    /// the floor is only a margin. A face against the very edge of the screen looks like a mistake,
    /// not like a deliberate composition.
    public let safeLeftFloor: Double, safeRightCap: Double

    /// The bounds that ``focusAcross`` is clamped into. These are open. The desktop strip uses a
    /// tight range right of centre, which is the wrong half for this frame. The clamp must not be
    /// what decides which side is safe.
    public let focusAcrossFloor: Double, focusAcrossCeiling: Double

    /// Where a subject should sit down the frame, from 0 (top) to 1 (foot).
    public let focusDown: Double

    /// The shape the picture is cut to.
    public var aspect: Double { width / max(1, height) }

    /// Whether there is a frame at all. A scene measured before layout has none. Judging a
    /// photograph against it would cut a rectangle for nothing.
    public var isLaidOut: Bool { width > 0 && height > 0 }

    private init(width: Double, height: Double,
                 clearLeft: Double, clearRight: Double, clearTop: Double,
                 safeLeftFloor: Double, safeRightCap: Double,
                 focusAcrossFloor: Double, focusAcrossCeiling: Double,
                 focusDown: Double) {
        self.width = width
        self.height = height
        self.clearLeft = clearLeft
        self.clearRight = clearRight
        self.clearTop = clearTop
        self.safeLeftFloor = safeLeftFloor
        self.safeRightCap = safeRightCap
        self.focusAcrossFloor = focusAcrossFloor
        self.focusAcrossCeiling = focusAcrossCeiling
        self.focusDown = focusDown
    }

    /// A frame with nothing covering its left. The status bar covers the top down to `clearTop`.
    /// The record covers from `clearRight` across. The words and the keys cover everything below
    /// `clearBottom`. The upper-left is where the subject goes.
    ///
    /// - Parameter clearTop: has no default. From this function, a frame that runs up behind the
    ///   status bar looks the same as one that starts below it. Only the caller knows which it is.
    public static func forClearLeft(width: Double, height: Double, clearTop: Double,
                                    clearRight: Double, clearBottom: Double) -> ArtScene {
        let right = min(max(clearRight, 0.2), 1)
        let bottom = min(max(clearBottom, 0.2), 1)
        let top = min(max(clearTop, 0), 0.5)

        return ArtScene(
            width: width, height: height,
            clearLeft: 0, clearRight: right, clearTop: top,
            safeLeftFloor: 0.04, safeRightCap: right,
            focusAcrossFloor: 0.05, focusAcrossCeiling: 0.95,
            // Slightly above the middle of the clear band, not at its centre. Eyes read better high in
            // a frame, and the room above the face gives headroom for the hair that the crop adds.
            focusDown: min(max(bottom * 0.45, 0.15), 0.5))
    }

    // ── the safe zone ──
    //
    // The clear band above is measured at the current size. The floor and the cap are the limits
    // that a photograph must stay inside at any size.

    /// The edges of the safe zone. A face at or past these is behind the record, or against the
    /// edge of the glass.
    public var faceHardLeft: Double { max(clearLeft, safeLeftFloor) }

    /// - Note: The `+ 0.02` keeps the two edges in order on a frame too narrow to have a clear band
    ///   at all. Without it the record would reach past the left-hand margin.
    public var faceHardRight: Double { max(faceHardLeft + 0.02, min(clearRight, safeRightCap)) }

    private var safeCentre: Double { (faceHardLeft + faceHardRight) / 2 }
    private var safeHalf: Double { max(0.01, (faceHardRight - faceHardLeft) / 2) }

    /// Where a subject should be placed across the frame: the centre of the safe zone. It is nudged
    /// a little away from the words, so the title and the artist keep their clearance.
    public var focusAcross: Double {
        min(max(safeCentre + safeHalf * 0.15, focusAcrossFloor), focusAcrossCeiling)
    }

    /// The ideal position for a face, either side of the centre of the safe zone. A face in this
    /// range scores full marks.
    public var faceIdealLeft: Double { safeCentre - safeHalf * 0.31 }
    public var faceIdealRight: Double { safeCentre + safeHalf * 0.31 }

    /// How well a face at this position across the picture suits the frame. It is 1 in the ideal
    /// spot, ramps down to 0 at the edges of the safe zone, and is 0 outside them. Outside means
    /// behind the record, or off the edge of the glass.
    ///
    /// This is how one photograph is judged against another. The question is not "is there a face
    /// in it". The question is "does the face land where it can be seen after the picture is cut to
    /// fit".
    public func facePosition(_ across: Double) -> Double {
        guard across > faceHardLeft, across < faceHardRight else { return 0 }

        if across < faceIdealLeft {
            return (across - faceHardLeft) / max(1e-6, faceIdealLeft - faceHardLeft)
        }
        if across > faceIdealRight {
            return (faceHardRight - across) / max(1e-6, faceHardRight - faceIdealRight)
        }

        return 1
    }
}
