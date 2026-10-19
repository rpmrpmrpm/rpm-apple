import Testing
@testable import RPMArt

/// Where to cut a photograph so the artist is the part you can see.
///
/// The picture cannot be checked without a screen. This suite can check it. Every figure below is
/// measured against the stage's own frame: a wide frame with the record on the right and the words
/// along the bottom. A good crop is not a property of a photograph alone. It depends on the
/// photograph and on the opening it goes into.
@Suite("Where to cut a photograph")
struct SaliencyCropTests {
    /// The stage on a modern phone in landscape.
    private let stage = ArtScene.forClearLeft(width: 852, height: 393, clearTop: 0,
                                              clearRight: 0.75, clearBottom: 0.62)

    private var aspect: Double { stage.aspect }

    /// A saliency map: a low floor everywhere, and the subject at the top of the scale. A real
    /// detector's map has this shape. The threshold that finds the subject is a fraction of the peak,
    /// not an absolute value, so the floor matters.
    private func map(_ width: Int, _ height: Int, subject: CropRect? = nil) -> [Double] {
        var map = [Double](repeating: 0.05, count: width * height)

        if let subject {
            for y in subject.y..<(subject.y + subject.height) {
                for x in subject.x..<(subject.x + subject.width) {
                    map[y * width + x] = 1
                }
            }
        }

        return map
    }

    /// Where a point sits across a window: 0 at its left edge and 1 at its right. This is the same
    /// fraction the scene's safe zone uses.
    private func across(_ x: Double, _ rect: CropRect) -> Double {
        (x - Double(rect.x)) / Double(rect.width)
    }

    // ── faces ──

    /// **The main case.** A face is placed where the scene shows the picture: left of the record and
    /// clear of the words.
    @Test func theFaceGoesWhereTheRecordAndTheWordsAreNot() {
        let face = FaceBox(x: 330, y: 100, width: 40, height: 48)

        let choice = SaliencyCrop.choose(
            saliency: map(600, 300, subject: CropRect(x: 300, y: 80, width: 110, height: 160)),
            width: 600, height: 300, targetAspect: aspect,
            faces: [face], scene: stage)

        let middle = Double(face.x) + Double(face.width) / 2
        #expect(abs(across(middle, choice.rect) - stage.focusAcross) < 0.01)
        #expect(choice.fillsTarget)
    }

    /// A face on the far right would be behind the record if the picture were shown as it is. The
    /// window moves in as far as the photograph allows, which is not all the way, because it cannot
    /// slide past the edge of the picture it is cut from. The result is not stretched to make up the
    /// difference.
    @Test func aFaceOutOnTheRightIsBroughtInFromBehindTheRecord() {
        let face = FaceBox(x: 490, y: 100, width: 40, height: 48)
        let middle = Double(face.x) + Double(face.width) / 2

        let choice = SaliencyCrop.choose(
            saliency: map(600, 300, subject: CropRect(x: 460, y: 80, width: 110, height: 160)),
            width: 600, height: 300, targetAspect: aspect,
            faces: [face], scene: stage)

        // Where it would have been if the picture were shown as it came: behind the record.
        #expect(middle / 600 > stage.faceHardRight)

        // Where it is now: on show, and further in than it started.
        #expect(across(middle, choice.rect) < stage.faceHardRight)
        #expect(across(middle, choice.rect) < middle / 600)
    }

    /// **The lift is refused rather than paid for with the top of the head.** The scene asks for the
    /// subject a fifth of the way up, because the words are along the bottom. On a frame this wide,
    /// the window is already the height of the head. There is no spare height to move it up with,
    /// and spending it anyway would cut the top off the head.
    @Test func theCrownIsNotSpentOnTheLift() {
        let face = FaceBox(x: 300, y: 100, width: 40, height: 48)

        let choice = SaliencyCrop.choose(
            saliency: map(600, 300, subject: CropRect(x: 270, y: 80, width: 110, height: 160)),
            width: 600, height: 300, targetAspect: aspect,
            faces: [face], scene: stage)

        // The hair above the brow, which is what the lift would have cut first.
        #expect(Double(choice.rect.y) <= Double(face.y) - Double(face.height) * 0.45 + 1)
        #expect(choice.rect.y + choice.rect.height >= face.y + face.height)
    }

    /// A group is a wide box of faces. There is no group detector, and none is needed. The faces at
    /// either end of the photograph must also be inside the window, or the crop removes part of the
    /// group.
    @Test func everybodyInThePhotographIsInTheWindow() {
        let band = [FaceBox(x: 200, y: 110, width: 36, height: 44),
                    FaceBox(x: 300, y: 100, width: 36, height: 44),
                    FaceBox(x: 400, y: 118, width: 36, height: 44)]

        let choice = SaliencyCrop.choose(
            saliency: map(700, 400, subject: CropRect(x: 180, y: 90, width: 280, height: 200)),
            width: 700, height: 400, targetAspect: aspect,
            faces: band, scene: stage)

        for face in band {
            #expect(face.x >= choice.rect.x)
            #expect(face.x + face.width <= choice.rect.x + choice.rect.width)
            #expect(face.y >= choice.rect.y)
            #expect(face.y + face.height <= choice.rect.y + choice.rect.height)
        }
    }

    // ── no faces ──

    /// **No subject, no zoom.** A texture, a landscape or a wall of stage lights has no subject. The
    /// whole picture is shown, in the biggest window possible. Looking for the busiest patch of a
    /// rock face and zooming into it is the mistake this avoids.
    @Test func aPhotographOfNothingInParticularIsNotZoomedInto() {
        let choice = SaliencyCrop.choose(
            saliency: map(600, 300), width: 600, height: 300, targetAspect: aspect,
            faces: [], scene: stage)

        #expect(choice.rect.width == 600)
        #expect(choice.fillsTarget)
    }

    /// A highlight, a bird or a bit of noise is not a subject. Framing a picture around one is worse
    /// than not framing it at all.
    @Test func aSpeckIsNotASubject() {
        let choice = SaliencyCrop.choose(
            saliency: map(600, 300, subject: CropRect(x: 100, y: 100, width: 4, height: 4)),
            width: 600, height: 300, targetAspect: aspect,
            faces: [], scene: stage)

        #expect(choice.rect.width == 600)
    }

    /// A standing figure with no face to find, for example a person seen from behind or looking
    /// down. Heads are at the top of people, so the window goes at the top of the figure. Centred on
    /// the figure, it would show a band across the chest.
    @Test func aFigureIsFramedOnItsHeadAndNotItsChest() {
        let figure = CropRect(x: 170, y: 30, width: 60, height: 340)

        let choice = SaliencyCrop.choose(
            saliency: map(400, 400, subject: figure),
            width: 400, height: 400, targetAspect: aspect,
            faces: [], scene: stage)

        let windowMiddle = Double(choice.rect.y) + Double(choice.rect.height) / 2
        let figureMiddle = Double(figure.y) + Double(figure.height) / 2

        #expect(windowMiddle < figureMiddle)
        #expect(choice.rect.y < figure.y + 40)
    }

    /// A subject that fits the band is framed on itself, with some margin, rather than shown whole.
    /// The window zooms in, because a frame the full width of the photograph has no room to place
    /// anything.
    @Test func aSubjectThatFitsIsZoomedTo() {
        let choice = SaliencyCrop.choose(
            saliency: map(600, 300, subject: CropRect(x: 240, y: 90, width: 120, height: 120)),
            width: 600, height: 300, targetAspect: aspect,
            faces: [], scene: stage)

        #expect(choice.rect.width < 600)
        #expect(choice.fillsTarget)
    }

    // ── what cannot be measured ──

    /// A map that does not match the picture it describes is not a basis for cropping. Show the
    /// whole photograph.
    @Test func aMapThatDoesNotFitThePictureCropsNothing() {
        let choice = SaliencyCrop.choose(
            saliency: [0.5, 0.5], width: 600, height: 300, targetAspect: aspect,
            faces: [], scene: stage)

        #expect(choice.rect == CropRect(x: 0, y: 0, width: 600, height: 300))
    }

    // ── the flip ──

    /// **The most important line in the art path.** Vision's boxes use an origin at the bottom left.
    /// The crop uses pixels from the top left. If this is wrong, each face is found at its mirror
    /// image down the photograph, and the crop is confidently and precisely wrong.
    @Test func aFaceHighInVisionsFrameIsHighInThePicture() {
        let high = FaceBox.fromNormalizedBottomLeft(
            x: 0.1, y: 0.7, width: 0.2, height: 0.2, pixelWidth: 100, pixelHeight: 100)

        #expect(high == FaceBox(x: 10, y: 10, width: 20, height: 20))

        let low = FaceBox.fromNormalizedBottomLeft(
            x: 0.1, y: 0.1, width: 0.2, height: 0.2, pixelWidth: 100, pixelHeight: 100)

        #expect(low.y == 70)
    }
}
