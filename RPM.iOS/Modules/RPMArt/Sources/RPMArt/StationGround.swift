import Foundation
import CoreGraphics
import CoreImage
import RPMDesign

/// The picture behind a station's logo, for a logo that was published with nothing behind it. This is a port of
/// the desktop's `TransparentMark`, and of the figure that it draws, `SoftFigure.Tile`. So a station's square looks
/// the same on both platforms.
///
/// **Why a made ground is needed at all.** A mark on nothing looks like a hole in a dark well, not like a badge.
/// The animated rooms behind the banner card and the player are lit from the colours in the square. A transparent
/// mark on black gives them almost nothing to light from.
///
/// **The ground is taken away from the mark's tone.** This is the opposite of the obvious choice, and it is the main
/// part of the desktop's fix. A ground in the mark's own tone would swallow the mark. The hues come from the picture,
/// but the value is pushed the other way: dark under a light mark, pale under a dark one.
public enum StationGround {
    /// Whether the picture is a mark standing on nothing, rather than a tile with rounded corners.
    ///
    /// "Has an alpha channel" is not the test. Nearly every apple-touch icon is an opaque square with its corners cut.
    /// The test is the outer ring. A mark is see-through nearly all the way round it. A rounded tile loses only about
    /// a tenth of its edge to the corners.
    public static func standsAlone(_ picture: CGImage) -> Bool {
        guard picture.width >= 3, picture.height >= 3,
              picture.alphaInfo != .none, picture.alphaInfo != .noneSkipLast,
              picture.alphaInfo != .noneSkipFirst,
              let pixels = rgba(picture)
        else { return false }

        let width = picture.width, height = picture.height
        // Inset by a pixel, because the outermost row of a resampled picture is often a half-covered fringe.
        let left = 1, top = 1, right = width - 2, bottom = height - 2

        var empty = 0, seen = 0
        for i in 0..<borderSamples {
            let t = Double(i) / Double(borderSamples)
            let across = left + Int(t * Double(right - left))
            let down = top + Int(t * Double(bottom - top))

            for (x, y) in [(across, top), (across, bottom), (left, down), (right, down)] {
                seen += 1
                if pixels[(y * width + x) * 4 + 3] < see {
                    empty += 1
                }
            }
        }

        return seen > 0 && Double(empty) / Double(seen) >= mostlyEmpty
    }

    /// The colour the mark is drawn in: the mean of the pixels that are really there. Transparent pixels are skipped,
    /// because a picture that is nine-tenths empty has almost no colour by any ordinary reading. Nil where there is
    /// too little of the mark to judge.
    public static func ink(_ picture: CGImage) -> RGB? {
        guard let pixels = rgba(picture) else { return nil }

        var red = 0, green = 0, blue = 0, drawn = 0
        for at in stride(from: 0, to: pixels.count, by: 4) where pixels[at + 3] >= solid {
            // Premultiplied, and these pixels are almost fully opaque, so the stored colour is the real colour.
            red += Int(pixels[at]); green += Int(pixels[at + 1]); blue += Int(pixels[at + 2])
            drawn += 1
        }

        guard drawn >= enough else { return nil }
        return RGB(UInt8(red / drawn), UInt8(green / drawn), UInt8(blue / drawn))
    }

    /// The ground a transparent mark stands on: the mark's own hues, pushed away from its value.
    /// This is the desktop's `TransparentMark.Ground`.
    ///
    /// - Parameter identity: what the arrangement is drawn from, so a station is the same square every time. Its uuid.
    public static func ground(for mark: CGImage, identity: String) -> CGImage? {
        let seed = identity.isEmpty ? "rpm" : identity

        // Too little of the mark to judge. Use the palette's own three colours, which is what a record with no cover
        // at all gets.
        guard let ink = ink(mark), let square = Thumbnail.square(mark) else {
            return tile(ringColours(seed), identity: seed)
        }

        let light = isLight(ink)
        let read = [CoverColor.dominant(rgba: square), CoverColor.highlight(rgba: square), average(square)]
        let colours = read.compactMap { $0 }.map { light ? dim($0, underALightMark) : lift($0, underADarkMark) }

        return tile(colours.isEmpty ? ringColours(seed) : colours, identity: seed)
    }

    /// The figure itself: six soft blobs in these colours, over the darkest of them, with one shaft of light across.
    /// Then the whole thing is blurred. This is the desktop's `SoftFigure.Tile`, drawn at the same 320 pixels with the
    /// same seed and roll. So the arrangement for a name is the same as on the desktop.
    public static func tile(_ colours: [RGB], identity: String) -> CGImage? {
        guard !colours.isEmpty else { return nil }

        let side = 320
        let edge = Double(side)
        let ink = palette(colours, identity)
        var roll = Roll(seed(identity) ^ UInt32(truncatingIfNeeded: variant &* 0x9E37_79B9))

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Drawn top-down, as Skia draws. This way a seed puts the blobs where the desktop puts them.
        context.translateBy(x: 0, y: edge)
        context.scaleBy(x: 1, y: -1)

        // The ground is the darkest colour. Where no blob reaches, the station's own colour shows, not a hole.
        context.setFillColor(cg(darkest(ink), alpha: 1, in: space))
        context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))

        // The blobs are wide and overlap. At this size they are the picture, and the viewer sees the edge where
        // two colours meet.
        for at in 0..<blobs {
            let colour = ink[at % ink.count]
            let centre = CGPoint(x: roll.between(-0.15, 1.15) * edge, y: roll.between(-0.15, 1.15) * edge)
            let radius = roll.between(0.45, 0.95) * edge

            guard let blob = CGGradient(colorsSpace: space,
                                        colors: [cg(colour, alpha: 1, in: space),
                                                 cg(colour, alpha: 0, in: space)] as CFArray,
                                        locations: [0, 1])
            else { continue }
            context.drawRadialGradient(blob, startCenter: centre, startRadius: 0,
                                       endCenter: centre, endRadius: radius, options: [])
        }

        // One shaft of light. It makes the figure read as a form rather than a stain.
        let light = lightest(ink)
        let from = CGPoint(x: roll.between(0.1, 0.9) * edge, y: 0)
        let to = CGPoint(x: roll.between(0.1, 0.9) * edge, y: edge)
        let middle = roll.between(0.3, 0.7)
        if let shaft = CGGradient(colorsSpace: space,
                                  colors: [cg(light, alpha: 0, in: space),
                                           cg(light, alpha: shaftAlpha, in: space),
                                           cg(light, alpha: 0, in: space)] as CFArray,
                                  locations: [0, CGFloat(middle), 1]) {
            context.drawLinearGradient(shaft, start: from, end: to,
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }

        guard let drawn = context.makeImage() else { return nil }

        // Then the whole picture is blurred. That turns six circles into one shape with no hard edges.
        let source = CIImage(cgImage: drawn)
        let soft = source.clampedToExtent()
            .applyingGaussianBlur(sigma: edge / blurDivisor)
            .cropped(to: source.extent)
        return blurring.createCGImage(soft, from: source.extent, format: .RGBA8, colorSpace: space)
    }

    /// Whether this ink is light enough that what goes behind it should be dark. This is the desktop's
    /// `CoverColor.PrefersBlackInk`.
    public static func isLight(_ ink: RGB) -> Bool {
        (0.2126 * Double(ink.r) + 0.7152 * Double(ink.g) + 0.0722 * Double(ink.b)) / 255 > 0.5
    }

    // ── the desktop's figures, kept the same ──

    private static let borderSamples = 64
    private static let see: UInt8 = 24
    private static let mostlyEmpty = 0.5
    private static let solid: UInt8 = 250
    private static let enough = 64
    private static let underALightMark = 0.22
    private static let underADarkMark = 0.74
    private static let blobs = 6
    private static let blurDivisor = 7.0
    private static let lit = 0.72
    private static let shaftAlpha = Double(0x5A) / 255
    /// `SoftFigure.Tile`'s variant, which is part of the seed.
    private static let variant: UInt32 = 2

    private static let blurring = CIContext(options: [.cacheIntermediates: false])

    // ── helpers ──

    /// The picture's pixels, premultiplied RGBA, at its own size.
    private static func rgba(_ picture: CGImage) -> [UInt8]? {
        let width = picture.width, height = picture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(picture, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }

    /// The mean of a small square, with the transparent part counted as black. This is the desktop's
    /// `CoverColor.Average`.
    private static func average(_ square: [UInt8]) -> RGB? {
        guard square.count >= 4 else { return nil }
        var red = 0, green = 0, blue = 0, count = 0
        for at in stride(from: 0, to: square.count, by: 4) {
            red += Int(square[at]); green += Int(square[at + 1]); blue += Int(square[at + 2])
            count += 1
        }
        return RGB(UInt8(red / count), UInt8(green / count), UInt8(blue / count))
    }

    /// Each colour snapped to the palette and lit, plus the palette's neighbour of the first colour. This is what the
    /// desktop's `SoftFigure.Palette` does.
    private static func palette(_ colours: [RGB], _ identity: String) -> [RGB] {
        var ink = colours.prefix(3).map { dim(nearest($0), lit) }

        let ring = RPMPalette.accents.map(\.base)
        if !ring.isEmpty, let first = colours.first,
           let at = ring.firstIndex(of: nearest(first)) {
            let step = seed(identity) & 1 == 0 ? 1 : ring.count - 1
            ink.append(dim(ring[(at + step) % ring.count], lit))
        }
        return ink
    }

    /// The nearest palette colour. A colour with no hue to match returns itself. This is the desktop's
    /// `RpmPalette.Nearest`.
    private static func nearest(_ colour: RGB) -> RGB {
        RPMPalette.nearest(to: colour)?.base ?? colour
    }

    /// Three neighbours on the palette's ring, chosen by where the name lands on it. This is the desktop's
    /// `SoftFigure.RingColours`, used for a mark too small to read.
    private static func ringColours(_ identity: String) -> [RGB] {
        let ring = RPMPalette.accents.map(\.base)
        guard !ring.isEmpty else { return [] }
        let at = Int(seed(identity) % UInt32(ring.count))
        return [ring[at], ring[(at + 1) % ring.count], ring[(at + ring.count - 1) % ring.count]]
    }

    private static func dim(_ colour: RGB, _ amount: Double) -> RGB {
        RGB(channel(Double(colour.r) * amount), channel(Double(colour.g) * amount),
            channel(Double(colour.b) * amount))
    }

    private static func lift(_ colour: RGB, _ amount: Double) -> RGB {
        func up(_ c: UInt8) -> UInt8 { channel(Double(c) + (255 - Double(c)) * amount) }
        return RGB(up(colour.r), up(colour.g), up(colour.b))
    }

    private static func channel(_ value: Double) -> UInt8 { UInt8(max(0, min(255, value))) }

    private static func brightness(_ colour: RGB) -> Double {
        0.2126 * Double(colour.r) + 0.7152 * Double(colour.g) + 0.0722 * Double(colour.b)
    }

    private static func darkest(_ ink: [RGB]) -> RGB { ink.min { brightness($0) < brightness($1) }! }
    private static func lightest(_ ink: [RGB]) -> RGB { ink.max { brightness($0) < brightness($1) }! }

    private static func cg(_ colour: RGB, alpha: Double, in space: CGColorSpace) -> CGColor {
        CGColor(colorSpace: space, components: [CGFloat(colour.r) / 255, CGFloat(colour.g) / 255,
                                                CGFloat(colour.b) / 255, CGFloat(alpha)])!
    }

    /// FNV-1a hash over the name's lowercased UTF-16 units. This is the desktop's `SoftFigure.Seed`.
    static func seed(_ name: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for unit in name.lowercased().utf16 {
            hash ^= UInt32(unit)
            hash = hash &* 16_777_619
        }
        return hash
    }

    /// xorshift32 random generator. This is the desktop's `SoftFigure.Roll`. It lays one picture out the same way
    /// every time, from one number.
    struct Roll {
        private var state: UInt32

        init(_ seed: UInt32) { state = seed == 0 ? 0x9E37_79B9 : seed }

        mutating func between(_ low: Double, _ high: Double) -> Double {
            state ^= state << 13
            state ^= state >> 17
            state ^= state << 5
            return low + (high - low) * (Double(state) / Double(UInt32.max))
        }
    }
}
