import Foundation
import CoreGraphics
import ImageIO
import Testing
import RPMKit
@testable import RPMArt

/// An artist's logo: cut to its lettering, then reduced to the pixels it is drawn at. The reduction
/// does not skip source pixels, darken the edges or add ringing.
@Suite("An artist's logo")
struct LetteringTests {
    /// A transparent canvas with one rectangle of `colour` on it, alpha `alpha`.
    static func canvas(width: Int, height: Int,
                               block: (x: Int, y: Int, width: Int, height: Int),
                               colour: (UInt8, UInt8, UInt8) = (255, 255, 255),
                               alpha: UInt8 = 255) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for y in block.y ..< block.y + block.height {
            for x in block.x ..< block.x + block.width {
                let at = (y * width + x) * 4
                // Premultiplied, as the plane holds it.
                bytes[at] = UInt8(Int(colour.0) * Int(alpha) / 255)
                bytes[at + 1] = UInt8(Int(colour.1) * Int(alpha) / 255)
                bytes[at + 2] = UInt8(Int(colour.2) * Int(alpha) / 255)
                bytes[at + 3] = alpha
            }
        }
        return Plane(width: width, height: height, bytes: bytes).image()!
    }

    /// The canvas as a PNG, the way a catalogue publishes a logo.
    static func png(_ image: CGImage) -> Data {
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return out as Data
    }

    /// An opaque field of one grey with vertical stripes of another.
    private static func stripes(width: Int, height: Int, ground: UInt8, stripe: UInt8,
                                every: Int, wide: Int) -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let at = (y * width + x) * 4
                let grey = x % every < wide ? stripe : ground
                bytes[at] = grey; bytes[at + 1] = grey; bytes[at + 2] = grey
            }
        }
        return Plane(width: width, height: height, bytes: bytes).image()!
    }

    // ── the cut ──

    @Test func theMarginsAreCutOffTheLettering() {
        let logo = Self.canvas(width: 800, height: 310, block: (300, 100, 200, 90))

        let cut = Lettering.trimmed(logo)

        #expect(cut.width == 200)
        #expect(cut.height == 90)
    }

    /// A drop shadow fades to an alpha of one or two well outside the lettering. Those pixels are
    /// not lettering, so the cut must ignore them.
    @Test func aFaintShadowIsNotLettering() {
        var plane = Plane(Self.canvas(width: 400, height: 200, block: (100, 50, 200, 100)))!
        for x in 0..<400 { plane.bytes[(10 * 400 + x) * 4 + 3] = 6 }

        let cut = Lettering.trimmed(plane.image()!)

        #expect(cut.width == 200)
        #expect(cut.height == 100)
    }

    @Test func aPictureWithNoMarginComesBackWhole() {
        let logo = Self.canvas(width: 120, height: 40, block: (0, 0, 120, 40))

        let cut = Lettering.trimmed(logo)

        #expect(cut.width == 120)
        #expect(cut.height == 40)
    }

    @Test func aPictureWithNothingVisibleComesBackWhole() {
        let logo = Self.canvas(width: 120, height: 40, block: (0, 0, 0, 0))

        let cut = Lettering.trimmed(logo)

        #expect(cut.width == 120)
        #expect(cut.height == 40)
    }

    // ── how tall ──

    @Test func theCapStandsWhereTheMarkFitsAcross() {
        let logo = Self.canvas(width: 400, height: 200, block: (0, 0, 400, 200))

        #expect(Lettering.height(of: logo, cap: 150, room: 1000) == 150)
    }

    /// A long name in one word reaches the side first, so the width sets the height.
    @Test func aLongMarkIsAsTallAsTheWidthAllows() {
        let logo = Self.canvas(width: 800, height: 100, block: (0, 0, 800, 100))

        #expect(Lettering.height(of: logo, cap: 150, room: 600) == 75)
    }

    @Test func noWidthYetLeavesTheCap() {
        let logo = Self.canvas(width: 800, height: 100, block: (0, 0, 800, 100))

        #expect(Lettering.height(of: logo, cap: 150, room: 0) == 150)
    }

    // ── the reduction ──

    @Test func aMarkIsReducedToTheHeightAskedAndKeepsItsShape() {
        let logo = Self.canvas(width: 800, height: 310, block: (0, 0, 800, 310))

        let fitted = Lettering.fitted(logo, height: 60)

        #expect(fitted.height == 60)
        #expect(fitted.width == 155)   // 800 × 60 / 310, rounded
    }

    /// Enlarging a mark past its own resolution makes it soft, so it is kept at its own size.
    @Test func aMarkIsNeverEnlarged() {
        let logo = Self.canvas(width: 200, height: 80, block: (0, 0, 200, 80))

        let fitted = Lettering.fitted(logo, height: 150)

        #expect(fitted.width == 200)
        #expect(fitted.height == 80)
    }

    /// Filtered on straight alpha, the black of the transparent pixels bleeds into the edge of white
    /// lettering and draws a dark rim around it. Premultiplied, every pixel with any alpha is still
    /// white, because its colour equals its alpha.
    @Test func whiteLetteringHasNoDarkRim() {
        let logo = Self.canvas(width: 803, height: 311, block: (101, 57, 413, 131))

        let plane = Plane(Lettering.fitted(logo, height: 47))!

        for at in stride(from: 0, to: plane.bytes.count, by: 4) where plane.bytes[at + 3] > 0 {
            #expect(Int(plane.bytes[at]) + 1 >= Int(plane.bytes[at + 3]))
        }
    }

    /// A bicubic filter dips below the ground on either side of a bright stroke. The B-spline only
    /// adds and never subtracts, so no output pixel is darker than the darker of the two greys.
    @Test func aStrokeHasNoDarkLineBesideIt() {
        let logo = Self.stripes(width: 600, height: 300, ground: 100, stripe: 240, every: 20, wide: 3)

        let plane = Plane(Lettering.fitted(logo, height: 160))!

        let darkest = stride(from: 0, to: plane.bytes.count, by: 4).map { plane.bytes[$0] }.min()!
        #expect(darkest >= 99)
    }

    /// A stroke one pixel wide, reduced six times in height, must still show. Four taps read straight
    /// from the full-size picture would hit it in some columns and miss it in others.
    @Test func aThinStrokeIsNotSkipped() {
        let logo = Self.stripes(width: 1200, height: 600, ground: 0, stripe: 255, every: 12, wide: 1)

        let plane = Plane(Lettering.fitted(logo, height: 100))!

        // Each stripe is twelve source pixels apart, so two output pixels apart. Each pair of output
        // columns must carry some of the stripe.
        let row = 50
        for x in stride(from: 0, to: plane.width - 1, by: 2) {
            let left = plane.bytes[(row * plane.width + x) * 4]
            let right = plane.bytes[(row * plane.width + x + 1) * 4]
            #expect(max(left, right) > 10)
        }
    }

    @Test func theFourWeightsAlwaysSumToOne() {
        for step in 0..<10 {
            let t = Float(step) / 10
            let sum = Plane.bSpline(1 + t) + Plane.bSpline(t) + Plane.bSpline(1 - t) + Plane.bSpline(2 - t)
            #expect(abs(sum - 1) < 0.0001)
        }
    }
}
