import Testing
import Foundation
import CoreGraphics
import RPMDesign
@testable import RPMArt

/// The ground a transparent station logo stands on, as the desktop's `TransparentMark` makes it.
struct StationGroundTests {
    /// A square of `edge` with a filled rectangle of `colour` in the middle, `share` of the side,
    /// and nothing around it.
    private func mark(_ colour: RGB, share: Double = 0.5, edge: Int = 120) -> CGImage {
        let context = CGContext(data: nil, width: edge, height: edge, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: edge, height: edge))
        context.setFillColor(Pictures.colour(colour))
        let side = Double(edge) * share
        let at = (Double(edge) - side) / 2
        context.fill(CGRect(x: at, y: at, width: side, height: side))
        return context.makeImage()!
    }

    /// An opaque square with its corners cut, the shape of an apple-touch icon.
    private func roundedTile(_ colour: RGB, edge: Int = 120) -> CGImage {
        let context = CGContext(data: nil, width: edge, height: edge, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.clear(CGRect(x: 0, y: 0, width: edge, height: edge))
        context.setFillColor(Pictures.colour(colour))
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: edge, height: edge),
                               cornerWidth: Double(edge) * 0.12, cornerHeight: Double(edge) * 0.12,
                               transform: nil))
        context.fillPath()
        return context.makeImage()!
    }

    private func brightness(_ image: CGImage) -> Double {
        let square = Thumbnail.square(image)!
        var sum = 0.0
        for at in stride(from: 0, to: square.count, by: 4) {
            sum += 0.2126 * Double(square[at]) + 0.7152 * Double(square[at + 1]) + 0.0722 * Double(square[at + 2])
        }
        return sum / Double(square.count / 4) / 255
    }

    @Test func aMarkOnNothingStandsAlone() {
        #expect(StationGround.standsAlone(mark(RGB(255, 255, 255))))
    }

    /// Opaque along every edge and see-through only at the corners: a tile, not a mark.
    @Test func aRoundedTileDoesNotStandAlone() {
        #expect(StationGround.standsAlone(roundedTile(RGB(20, 60, 200))) == false)
    }

    @Test func anOpaquePictureDoesNotStandAlone() {
        #expect(StationGround.standsAlone(Pictures.drawn(field: RGB(200, 30, 30), edge: 60)) == false)
    }

    @Test func theInkIsWhatIsReallyThere() {
        let ink = StationGround.ink(mark(RGB(250, 250, 250)))

        // Allow a small error. The drawing passes through a colour space first.
        #expect(ink.map { abs(Int($0.r) - 250) <= 2 && abs(Int($0.b) - 250) <= 2 } == true)
    }

    @Test func tooLittleOfAMarkHasNoInk() {
        #expect(StationGround.ink(mark(RGB(250, 250, 250), share: 0.04)) == nil)
    }

    /// A light mark gets a dark ground, so the mark stays visible on it.
    @Test func aLightMarkStandsOnADarkGround() throws {
        let ground = try #require(StationGround.ground(for: mark(RGB(240, 240, 230)), identity: "s1"))

        #expect(brightness(ground) < 0.35)
    }

    /// A dark mark gets a ground that is brighter than the mark, but not necessarily pale. The lifted
    /// colours are snapped to the palette and lit at 72%, as on the desktop, which takes back most of
    /// the lift. Only one property is checked here: the ground is brighter than the mark.
    @Test func aDarkMarkStandsOnAPalerGround() throws {
        let dark = mark(RGB(20, 30, 120), share: 0.9)
        let ground = try #require(StationGround.ground(for: dark, identity: "s1"))

        #expect(brightness(ground) > brightness(dark))
    }

    @Test func theGroundIsASquareTheDesktopsSize() throws {
        let ground = try #require(StationGround.ground(for: mark(RGB(240, 240, 230)), identity: "s1"))

        #expect(ground.width == 320 && ground.height == 320)
    }

    /// The same station is the same square every time.
    @Test func theSameIdentityDrawsTheSameGround() throws {
        let one = try #require(StationGround.tile([RGB(200, 40, 40), RGB(40, 40, 200)], identity: "Radio One"))
        let two = try #require(StationGround.tile([RGB(200, 40, 40), RGB(40, 40, 200)], identity: "Radio One"))

        #expect(Thumbnail.square(one) == Thumbnail.square(two))
    }

    /// FNV-1a hash of the lowercased name, computed as the desktop's `SoftFigure.Seed` does. A name
    /// lays out its blobs the same way on every platform.
    @Test func theSeedIsTheDesktops() {
        #expect(StationGround.seed("Radio One") == 3_701_906_720)
        #expect(StationGround.seed("RADIO ONE") == StationGround.seed("radio one"))
    }
}
