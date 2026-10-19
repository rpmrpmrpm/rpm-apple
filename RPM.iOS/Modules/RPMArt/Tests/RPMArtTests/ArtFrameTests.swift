import CoreGraphics
import Testing
import RPMDesign
@testable import RPMArt

/// The three steps together: read the photograph, choose the window, and cut it out.
///
/// The arithmetic is tested in another file, without a screen and without Vision. This suite
/// checks the other part: that the reading and the drawing actually run, and that the output has
/// the shape of the hole it goes into, so the view has nothing left to decide.
/// **Serialised.** `VNImageRequestHandler.perform` is synchronous and holds the thread it is called
/// on for close to a second. If several of these run alongside the rest of the suite, every thread
/// in the cooperative pool can be inside Vision at once. The actor hops that the other tests wait
/// for then have no thread to run on, and the suite hangs instead of failing.
@Suite("A photograph, cut for the screen", .serialized)
struct ArtFrameTests {
    private let stage = ArtScene.forClearLeft(width: 852, height: 393, clearTop: 0,
                                              clearRight: 0.75, clearBottom: 0.62)

    /// A test picture with a subject: a bright shape on a dark field, off to one side. The
    /// attention model needs something to find in it.
    private func photograph(width: Int = 1200, height: Int = 800) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

        context.setFillColor(CGColor(red: 0.06, green: 0.07, blue: 0.11, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(CGColor(red: 0.95, green: 0.86, blue: 0.62, alpha: 1))
        context.fillEllipse(in: CGRect(x: Double(width) * 0.62, y: Double(height) * 0.35,
                                       width: Double(width) * 0.22,
                                       height: Double(height) * 0.42))

        return context.makeImage()!
    }

    @Test func aCutPictureIsTheShapeOfTheFrame() throws {
        let cut = try #require(ArtFrame.cut(photograph(), for: stage, widest: 1400))

        let aspect = Double(cut.width) / Double(cut.height)
        #expect(abs(aspect - stage.aspect) / stage.aspect < 0.02)
    }

    /// The cut is made at the size it will be shown, and no larger. A backdrop is a full-screen
    /// bitmap, so extra pixels only cost memory.
    @Test func aCutPictureIsNoWiderThanTheScreenWantsIt() throws {
        let cut = try #require(ArtFrame.cut(photograph(width: 3000, height: 2000),
                                            for: stage, widest: 1400))

        #expect(cut.width <= 1400)
        #expect(cut.width > 900)
    }

    /// The picture is never enlarged. A window narrower than the screen keeps its own pixels, and
    /// the view scales it up. Scaling up here would use more memory for the same soft picture.
    @Test func aSmallPhotographIsNotBlownUpToFit() throws {
        let cut = try #require(ArtFrame.cut(photograph(width: 400, height: 300),
                                            for: stage, widest: 1400))

        #expect(cut.width <= 400)
    }

    /// A frame measured before layout has no size. Cutting for it would measure a rectangle
    /// against nothing and return a result that looks valid.
    @Test func nothingIsCutForAFrameOfNoSize() {
        let unmeasured = ArtScene.forClearLeft(width: 0, height: 0, clearTop: 0,
                                               clearRight: 0.75, clearBottom: 0.62)

        #expect(ArtFrame.cut(photograph(), for: unmeasured, widest: 1400) == nil)
    }

    // ── a picture already framed on its subject ──

    /// A square in a frame wider than itself keeps its whole width and loses its bottom, never its
    /// top. A cut taken from the middle can remove the top of a face.
    @Test func aSquareInAWideFrameKeepsItsTop() {
        #expect(ArtFrame.topWindow(width: 1000, height: 1000, aspect: 1.4)
                == CropRect(x: 0, y: 0, width: 1000, height: 714))
    }

    /// A square in a frame taller than itself keeps its whole height and loses its sides evenly.
    @Test func aSquareInATallFrameLosesItsSidesEvenly() {
        #expect(ArtFrame.topWindow(width: 1000, height: 1000, aspect: 0.85)
                == CropRect(x: 75, y: 0, width: 850, height: 1000))
    }

    /// A frame with the same shape as the picture takes all of it.
    @Test func aFrameTheShapeOfThePictureTakesAllOfIt() {
        #expect(ArtFrame.topWindow(width: 1000, height: 1000, aspect: 1)
                == CropRect(x: 0, y: 0, width: 1000, height: 1000))
    }

    /// A square filled into the artist page band. The cut has the band's shape and starts at the
    /// top of the square, so a coloured strip along the bottom edge of the square is left out.
    @Test func aFilledSquareIsTheShapeOfTheFrameAndHasNoFoot() throws {
        let band = ArtScene.forClearLeft(width: 393, height: 280, clearTop: 0, clearRight: 0.94, clearBottom: 0.66)
        let square = Pictures.drawn(field: RGB(120, 40, 160), splash: RGB(230, 40, 40),
                                    share: 0.25, edge: 300)

        let cut = try #require(ArtFrame.filled(square, for: band, widest: 1400))

        let aspect = Double(cut.width) / Double(cut.height)
        #expect(abs(aspect - band.aspect) / band.aspect < 0.02)
        #expect(Pictures.rgb(of: cut, atX: cut.width / 2, fromTop: cut.height - 1).r < 180)
    }

    /// Vision reads the picture here, so this test checks that it ran. A reading holds a map the
    /// size of the working space, and the map has values taken from the photograph.
    @Test func thePictureIsActuallyRead() throws {
        let reading = try #require(PhotoVision.read(photograph()))

        #expect(reading.saliency.count == reading.workWidth * reading.workHeight)
        #expect(max(reading.workWidth, reading.workHeight) == PhotoVision.workLongEdge)
        #expect(reading.sourceWidth == 1200)
        #expect(reading.saliency.contains { $0 > 0 })
    }
}
