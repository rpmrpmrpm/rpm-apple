import Testing
@testable import RPMArt

/// What is covering the picture.
///
/// The stage is a wide frame with the record on the right and the words along the bottom. Every
/// value here is about one thing: the artist stays in the clear area at the upper left, whatever
/// the size of the phone or its rotation.
@Suite("What is covering the picture")
struct ArtSceneTests {
    /// The stage on a modern phone in landscape. The record covers the right side from half its
    /// diameter in. The column of words covers the bottom third.
    private let stage = ArtScene.forClearLeft(width: 852, height: 393, clearTop: 0,
                                              clearRight: 0.75, clearBottom: 0.62)

    @Test func theRecordIsWhereTheClearBandEnds() {
        #expect(stage.faceHardRight == 0.75)
    }

    /// **Nothing covers the left here**, so the left limit is only a margin. A face against the
    /// very edge of the glass looks like a mistake. The desktop app puts the album cover against
    /// that edge and sets a floor at half the picture. Using that rule here would leave a safe
    /// zone only a few percent wide, pressed against the record, which is the one place a face
    /// must not be.
    @Test func nothingCoversTheLeftSoTheFloorIsOnlyAMargin() {
        #expect(stage.faceHardLeft > 0)
        #expect(stage.faceHardLeft < 0.1)
    }

    /// The artist goes left of centre, because the right is the record.
    @Test func theSubjectGoesLeftOfTheRecord() {
        #expect(stage.focusAcross > stage.faceHardLeft)
        #expect(stage.focusAcross < stage.faceHardRight)
        #expect(stage.focusAcross < 0.5)
    }

    /// The artist also goes above the middle, because the words are along the bottom. Eyes sit
    /// high in a frame, and the space above gives room for hair above the face.
    @Test func theSubjectGoesAboveTheMiddle() {
        #expect(stage.focusDown < 0.5)
        #expect(stage.focusDown > 0)
    }

    /// A frame with nothing over it still keeps its margins, and does not put a face in the exact
    /// centre. This is the portrait player, which does not show a photograph.
    @Test func aClearFrameStillHasMargins() {
        let clear = ArtScene.forClearLeft(width: 393, height: 852, clearTop: 0,
                                          clearRight: 1, clearBottom: 1)

        #expect(clear.faceHardRight == 1)
        #expect(clear.faceHardLeft > 0)
        #expect(clear.focusDown == 0.45)
    }

    /// Values outside the valid range are clamped. They can come from a live layout. A record that
    /// covers the whole picture would otherwise give an invalid result.
    @Test func anImpossibleFrameIsBroughtBackIntoRange() {
        let squashed = ArtScene.forClearLeft(width: 100, height: 100, clearTop: 0,
                                             clearRight: -3, clearBottom: 0)
        let stretched = ArtScene.forClearLeft(width: 100, height: 100, clearTop: 0,
                                              clearRight: 5, clearBottom: 5)

        #expect(squashed.clearRight == 0.2)
        #expect(squashed.focusDown == 0.15)
        #expect(stretched.clearRight == 1)
        #expect(stretched.focusDown == 0.45)

        // The band keeps its right edge to the right of its left edge, even when the record covers
        // all of it. Otherwise the band would have a negative width.
        #expect(squashed.faceHardRight > squashed.faceHardLeft)
    }

    /// A frame measured before layout has no size. A photograph must not be cut for it. The
    /// rectangle would be measured against nothing and then shown as a valid result.
    @Test func aFrameOfNoSizeSaysSo() {
        #expect(!ArtScene.forClearLeft(width: 0, height: 0, clearTop: 0,
                                       clearRight: 0.75, clearBottom: 0.6).isLaidOut)
        #expect(stage.isLaidOut)
    }

    @Test func theShapeIsTheFramesOwn() {
        #expect(abs(stage.aspect - 852.0 / 393.0) < 0.0001)
    }
}
