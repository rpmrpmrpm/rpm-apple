import Testing
import Foundation
import CoreGraphics
@testable import RPMArt
import RPMDesign
import RPMLibrary

/// The generated lists' photographs, as the phone ships them. The desktop's `PlaylistPhotoTests`
/// checks its own table against the same JSON. These tests check the phone's table, so the two
/// apps cannot disagree about which list has which photograph without one of the tests failing.
struct PlaylistPhotosTests {
    // ── the table ──

    /// Every entry in `scripts/playlist-photos.json` is in the phone's table with the same file, and
    /// nothing else is. The table is generated. This test fails when the JSON is edited and
    /// `gen_playlist_photos.py` is not run.
    @Test func theTableIsTheJson() throws {
        let json = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // RPMArtTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // RPMArt
            .deletingLastPathComponent()   // Modules
            .deletingLastPathComponent()   // RPM.iOS
            .deletingLastPathComponent()   // RPM
            .appendingPathComponent("scripts/playlist-photos.json")

        let book = try JSONSerialization.jsonObject(with: Data(contentsOf: json)) as! [String: Any]
        let photos = book["photos"] as! [[String: Any]]

        #expect(PlaylistPhotos.shippedEdge == book["edge"] as? Int)
        #expect(photos.count == PlaylistPhotos.files.count)

        for photo in photos {
            let cut = GeneratedCut(kind: photo["kind"] as! String,
                                   genre: photo["genre"] as? String,
                                   decade: photo["decade"] as! Int)
            #expect(PlaylistPhotos.files[cut] == photo["file"] as? String, "\(cut)")
        }
    }

    /// Every file the table names is in the bundle, decodes, and is returned at the size asked for.
    /// A missing file would otherwise fall back to the store's picture without any warning.
    @Test func everyListInTheTableHasItsPhotograph() {
        for cut in PlaylistPhotos.files.keys {
            let art = PlaylistPhotos.cover(for: cut, edge: 200)
            #expect(art?.image.width == 256, "\(cut)")
            #expect(art?.image.height == 256, "\(cut)")
        }
    }

    /// Most generated lists have no photograph, and a kind this build does not know has none either.
    /// Both return nil, so the caller asks the store instead.
    @Test func aListWithNoEntryHasNoPhotograph() {
        #expect(PlaylistPhotos.cover(for: GeneratedCut(kind: "NeverPlayed", genre: nil, decade: 0),
                                     edge: 200) == nil)
        #expect(PlaylistPhotos.cover(for: GeneratedCut(kind: "Calm", genre: "Polka", decade: 0),
                                     edge: 200) == nil)
        #expect(!PlaylistPhotos.has(GeneratedCut(kind: "SomethingNewer", genre: nil, decade: 0)))
    }

    /// The size is rounded up to the store's buckets and capped at the file's own 640 pixels, so a
    /// large square is never made bigger than the photograph it comes from.
    @Test func theSizeIsABucketAndNeverBiggerThanTheFile() {
        let chill = GeneratedCut(kind: "Calm", genre: nil, decade: 0)

        #expect(PlaylistPhotos.cover(for: chill, edge: 100)?.image.width == 256)
        #expect(PlaylistPhotos.cover(for: chill, edge: 400)?.image.width == 512)
        #expect(PlaylistPhotos.cover(for: chill, edge: 1300)?.image.width == 640)
    }

    // ── the wash ──

    /// A photograph washed in a colour takes that colour's hue. Each pixel is the result of the PDF
    /// `Color` blend at the desktop's strength. Skia's `SKBlendMode.Color` uses the same formula, so
    /// matching it here means matching the desktop's cover.
    @Test func theWashIsThePdfColourBlendAtTheDesktopsStrength() throws {
        let azure = RPMPalette.accents[5].base

        for under in [RGB(128, 128, 128), RGB(40, 180, 90), RGB(230, 210, 30)] {
            let washed = try #require(PlaylistPhotos.washed(Self.flat(under, width: 64, height: 64),
                                                           in: azure, edge: 64))
            let pixel = Self.pixel(of: washed, atX: 32, y: 32)
            let expected = Self.colourBlend(under: under, over: azure, alpha: 0.72)

            #expect(abs(Int(pixel.r) - Int(expected.r)) <= 3, "\(under) red")
            #expect(abs(Int(pixel.g) - Int(expected.g)) <= 3, "\(under) green")
            #expect(abs(Int(pixel.b) - Int(expected.b)) <= 3, "\(under) blue")
        }

        let grey = try #require(PlaylistPhotos.washed(
            Self.flat(RGB(128, 128, 128), width: 64, height: 64), in: azure, edge: 64))
        #expect(abs(Self.hue(Self.pixel(of: grey, atX: 32, y: 32)) - Self.hue(azure)) < 6)
    }

    /// A landscape photograph fills the square, so the corners show the photograph, not black bars.
    @Test func aWidePhotographFillsTheSquare() throws {
        let wide = Self.flat(RGB(255, 255, 255), width: 300, height: 100)

        let washed = try #require(PlaylistPhotos.washed(wide, in: RGB(200, 40, 40), edge: 64))

        #expect(Self.light(Self.pixel(of: washed, atX: 1, y: 1)) > 100)
        #expect(Self.light(Self.pixel(of: washed, atX: 62, y: 62)) > 100)
    }

    // ── helpers ──

    /// Pictures are made and read in sRGB, the space the wash draws in. So the test compares the blend
    /// itself, not a colour conversion. `Pictures.drawn` uses DeviceRGB, which macOS converts.
    private static let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    private static func flat(_ colour: RGB, width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: 0, space: srgb,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(colorSpace: srgb,
                                     components: [CGFloat(colour.r) / 255, CGFloat(colour.g) / 255,
                                                  CGFloat(colour.b) / 255, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private static func pixel(of image: CGImage, atX x: Int, y: Int) -> RGB {
        var bytes: [UInt8] = [0, 0, 0, 0]
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: srgb,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        }
        return RGB(bytes[0], bytes[1], bytes[2])
    }

    /// The PDF specification's non-separable `Color` blend: the backdrop's luminosity with the
    /// source's hue and saturation, mixed with the backdrop by the source's alpha.
    private static func colourBlend(under: RGB, over: RGB, alpha: Double) -> RGB {
        func lum(_ c: [Double]) -> Double { 0.3 * c[0] + 0.59 * c[1] + 0.11 * c[2] }

        func clip(_ c: [Double]) -> [Double] {
            let l = lum(c), n = c.min()!, x = c.max()!
            var out = c
            if n < 0 { out = out.map { l + ($0 - l) * l / (l - n) } }
            if x > 1 { out = out.map { l + ($0 - l) * (1 - l) / (x - l) } }
            return out
        }

        let backdrop = [Double(under.r), Double(under.g), Double(under.b)].map { $0 / 255 }
        let source = [Double(over.r), Double(over.g), Double(over.b)].map { $0 / 255 }
        let shift = lum(backdrop) - lum(source)
        let blended = clip(source.map { $0 + shift })

        let mixed = zip(backdrop, blended).map { (1 - alpha) * $0 + alpha * $1 }
        let bytes = mixed.map { UInt8(clamping: Int(($0 * 255).rounded())) }
        return RGB(bytes[0], bytes[1], bytes[2])
    }

    private static func light(_ c: RGB) -> Double {
        0.2126 * Double(c.r) + 0.7152 * Double(c.g) + 0.0722 * Double(c.b)
    }

    /// Hue in degrees, 0 to 360.
    private static func hue(_ c: RGB) -> Double {
        let r = Double(c.r) / 255, g = Double(c.g) / 255, b = Double(c.b) / 255
        let high = max(r, g, b), low = min(r, g, b), span = high - low
        guard span > 0 else { return 0 }

        let sector: Double
        if high == r { sector = ((g - b) / span).truncatingRemainder(dividingBy: 6) }
        else if high == g { sector = (b - r) / span + 2 }
        else { sector = (r - g) / span + 4 }

        let degrees = sector * 60
        return degrees < 0 ? degrees + 360 : degrees
    }
}
