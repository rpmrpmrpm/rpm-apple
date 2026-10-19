import Testing
@testable import RPMArt

/// Whether a square, filled into the home banner card from the top, puts its face behind the
/// status bar and the Dynamic Island. This is arithmetic on face boxes, with no Vision.
struct CoveredFaceTests {
    /// A banner card: a little taller than wide, running 59 points up behind the status bar.
    private let card = ArtScene.forClearLeft(width: 390, height: 470, clearTop: 59.0 / 470,
                                             clearRight: 0.94, clearBottom: 0.62)

    /// A square read in a 512 by 512 working space. Filled into the card, it keeps its full height,
    /// so a fraction down the square is the same fraction down the card.
    private let edge = 512

    private func face(down top: Int, size: Int = 60, across left: Int = 226) -> FaceBox {
        FaceBox(x: left, y: top, width: size, height: size)
    }

    /// The whole face is in the top eighth of the square. Once the card runs up behind the status
    /// bar, the face is behind the Dynamic Island.
    @Test func aFaceAtTheVeryTopIsCovered() {
        #expect(ArtFrame.coversFace([face(down: 4)], width: edge, height: edge, for: card))
    }

    @Test func aFaceBelowTheStatusBarIsClear() {
        #expect(!ArtFrame.coversFace([face(down: 120)], width: edge, height: edge, for: card))
    }

    /// The test measures at the eyes, not at the middle of the box. A face whose box only grazes
    /// the line with its forehead still has its eyes in view.
    @Test func aForeheadUnderTheBarIsNotACoveredFace() {
        // Box top at 50 of 512 (about 46 points down a 470-point card), eyes at 74 (68 points),
        // below the 59-point bar.
        #expect(!ArtFrame.coversFace([face(down: 50)], width: edge, height: edge, for: card))
    }

    /// Nothing found is nothing hidden.
    @Test func noFaceIsNotCovered() {
        #expect(!ArtFrame.coversFace([], width: edge, height: edge, for: card))
    }

    /// The largest face is the one that counts. A small face in the corner does not decide.
    @Test func theLargestFaceDecides() {
        let small = face(down: 2, size: 20, across: 20)
        let main = face(down: 200, size: 120)

        #expect(!ArtFrame.coversFace([small, main], width: edge, height: edge, for: card))
    }

    /// A face outside the card's width counts as covered.
    @Test func aFaceOutsideTheWindowIsCovered() {
        // The card keeps about 83% of the square's width, centred. About 8.5% is cut from each side.
        #expect(ArtFrame.coversFace([face(down: 200, size: 20, across: 2)],
                                    width: edge, height: edge, for: card))
    }

    /// With no clear area at the top, nothing covers the top of the picture, so a high face is clear.
    @Test func withNothingOverTheTopAHighFaceIsClear() {
        let under = ArtScene.forClearLeft(width: 390, height: 470, clearTop: 0,
                                          clearRight: 0.94, clearBottom: 0.62)

        #expect(!ArtFrame.coversFace([face(down: 4)], width: edge, height: edge, for: under))
    }
}
