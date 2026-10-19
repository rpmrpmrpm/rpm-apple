import Foundation
import CoreGraphics
import ImageIO

/// An artist's logo, cut to its lettering and reduced to the pixels it is drawn at.
///
/// This is the phone's port of the desktop's `ArtScaler.Trim` and `ArtScaler.FitMark`
/// (`RPM.Desktop/Services/Art/ArtScaler.cs`). It does two jobs:
///
/// - **Trim.** Catalogues publish every logo on one canvas (800 by 310 on fanart.tv), whatever the
///   lettering inside it is. Drawn as published, the lettering sits off centre, and most of the height
///   it is drawn at is transparent margin.
/// - **Fit.** A logo is published several times larger than it is drawn. A renderer that does that
///   reduction itself reads a few source pixels per output pixel and skips the rest. The thin strokes of
///   lettering then break up. Here the picture is halved by averaging 2x2 blocks while more than a factor
///   of two remains. Then it is finished with the B-spline cubic (B=1, C=0). That cubic has no negative
///   lobe, so it adds no light or dark line beside a stroke, unlike the ordinary bicubic. Every step works
///   on premultiplied alpha, so transparent pixels add no colour.
///
/// The caller draws the result at its own pixel size, one image pixel per screen pixel.
public enum Lettering {
    /// Alpha at or below this counts as empty when the margins are cut. It is not zero. A mark with a soft
    /// shadow fades to an alpha of one or two well before it reaches nothing.
    static let trimFloor: UInt8 = 8

    /// The picture at its own size. Nil if the bytes are not a picture.
    public static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(
            data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        return CGImageSourceCreateImageAtIndex(source, 0, [
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }

    /// The smallest part of the picture that holds every pixel with alpha above ``trimFloor``.
    /// The picture is returned as it came where there is nothing to cut, nothing visible, or no alpha to read.
    public static func trimmed(_ image: CGImage) -> CGImage {
        guard let plane = Plane(image) else { return image }

        var left = plane.width, right = -1, top = plane.height, bottom = -1
        plane.bytes.withUnsafeBufferPointer { pixels in
            for y in 0..<plane.height {
                let row = y * plane.width * 4
                for x in 0..<plane.width where pixels[row + x * 4 + 3] > trimFloor {
                    if x < left { left = x }
                    if x > right { right = x }
                    if y < top { top = y }
                    bottom = y
                }
            }
        }

        guard right >= left, bottom >= top else { return image }
        if left == 0, top == 0, right == plane.width - 1, bottom == plane.height - 1 { return image }

        return plane.cut(x: left, y: top, width: right - left + 1, height: bottom - top + 1)
            .image() ?? image
    }

    /// The tallest the picture may be drawn, in pixels: `cap`, or less where a picture that tall would be wider
    /// than `room`. A long name set as one word costs its height several times over in width, so the height
    /// alone cannot set the limit. A `room` of zero means no width is known yet, and then the cap alone applies.
    public static func height(of image: CGImage, cap: Int, room: Int) -> Int {
        guard image.width > 0, image.height > 0, room > 0 else { return cap }

        let fits = Int((Double(room) * Double(image.height) / Double(image.width)).rounded(.down))
        return max(1, min(cap, fits))
    }

    /// The picture reduced to `height` pixels tall, with its width in proportion.
    ///
    /// A picture that is not taller than that is returned as it came. A mark enlarged past its own resolution
    /// is soft, for the opposite reason. So the result can be shorter than requested, and the caller draws it
    /// at the size it is.
    public static func fitted(_ image: CGImage, height: Int) -> CGImage {
        guard height > 0, image.height > height, let plane = Plane(image) else { return image }

        // Halve while more than a factor of two is left. Each halving is the mean of every 2x2 block, which is one
        // mipmap level. The loop stops while the picture is still taller than the target, so the last step is
        // always a reduction of two or less.
        var source = plane
        while source.height > height * 2, source.width > 1 {
            source = source.halved()
        }

        // Both sides come from the original proportions, not from the halved picture. Rounding at each halving then
        // cannot change the mark's shape. The height is exact, so it never misses the cap by a pixel.
        let wide = max(1, Int((Double(plane.width) * Double(height) / Double(plane.height)).rounded()))

        return source.resampled(width: wide, height: height).image() ?? image
    }
}

/// A picture as premultiplied RGBA, eight bits a channel, rows from the top.
struct Plane {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    /// The picture drawn one to one into an sRGB buffer. Nil if it cannot be drawn.
    init?(_ image: CGImage) {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            return nil
        }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }

            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drawn else { return nil }
        self.init(width: width, height: height, bytes: bytes)
    }

    func image() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(bytes) as CFData)
        else { return nil }

        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    func cut(x: Int, y: Int, width: Int, height: Int) -> Plane {
        var out = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let from = ((y + row) * self.width + x) * 4
            out.replaceSubrange(row * width * 4 ..< (row + 1) * width * 4,
                                with: bytes[from ..< from + width * 4])
        }
        return Plane(width: width, height: height, bytes: out)
    }

    /// Half the size each way. Each pixel is the mean of a 2x2 block. An odd last row or column is read twice
    /// rather than dropped.
    func halved() -> Plane {
        let wide = max(1, width / 2), high = max(1, height / 2)
        var out = [UInt8](repeating: 0, count: wide * high * 4)

        bytes.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<high {
                    let y0 = min(y * 2, height - 1), y1 = min(y * 2 + 1, height - 1)
                    for x in 0..<wide {
                        let x0 = min(x * 2, width - 1), x1 = min(x * 2 + 1, width - 1)
                        let a = (y0 * width + x0) * 4, b = (y0 * width + x1) * 4
                        let c = (y1 * width + x0) * 4, d = (y1 * width + x1) * 4
                        let o = (y * wide + x) * 4
                        for channel in 0..<4 {
                            let sum = Int(src[a + channel]) + Int(src[b + channel])
                                + Int(src[c + channel]) + Int(src[d + channel])
                            dst[o + channel] = UInt8((sum + 2) / 4)
                        }
                    }
                }
            }
        }

        return Plane(width: wide, height: high, bytes: out)
    }

    /// Resampled to `width` by `height` with the B-spline cubic, across and then down. Four taps a side, with
    /// edges clamped. This is meant for a reduction of two or less. Past that, four taps skip pixels, which is
    /// why ``halved()`` runs first.
    func resampled(width wide: Int, height high: Int) -> Plane {
        let across = Self.taps(from: width, to: wide)
        let down = Self.taps(from: height, to: high)

        // Across: every source row, at the new width.
        var middle = [Float](repeating: 0, count: height * wide * 4)
        bytes.withUnsafeBufferPointer { src in
            middle.withUnsafeMutableBufferPointer { dst in
                for y in 0..<height {
                    let row = y * width * 4
                    for x in 0..<wide {
                        let tap = across[x]
                        let o = (y * wide + x) * 4
                        for k in 0..<4 {
                            let i = row + tap.index[k] * 4
                            let w = tap.weight[k]
                            dst[o] += w * Float(src[i])
                            dst[o + 1] += w * Float(src[i + 1])
                            dst[o + 2] += w * Float(src[i + 2])
                            dst[o + 3] += w * Float(src[i + 3])
                        }
                    }
                }
            }
        }

        // Down: every new column, at the new height.
        var out = [UInt8](repeating: 0, count: high * wide * 4)
        middle.withUnsafeBufferPointer { src in
            out.withUnsafeMutableBufferPointer { dst in
                for y in 0..<high {
                    let tap = down[y]
                    for x in 0..<wide {
                        var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
                        for k in 0..<4 {
                            let i = (tap.index[k] * wide + x) * 4
                            let w = tap.weight[k]
                            r += w * src[i]
                            g += w * src[i + 1]
                            b += w * src[i + 2]
                            a += w * src[i + 3]
                        }

                        // The weights are never negative and sum to one. So no channel can leave 0...255, or exceed the
                        // alpha, except through float error. The clamp below handles that.
                        let alpha = Self.byte(a)
                        let o = (y * wide + x) * 4
                        dst[o] = min(Self.byte(r), alpha)
                        dst[o + 1] = min(Self.byte(g), alpha)
                        dst[o + 2] = min(Self.byte(b), alpha)
                        dst[o + 3] = alpha
                    }
                }
            }
        }

        return Plane(width: wide, height: high, bytes: out)
    }

    /// For each output pixel: where its centre falls in the source, and the four pixels around it.
    static func taps(from source: Int, to target: Int) -> [FourTaps] {
        let scale = Double(source) / Double(target)

        return (0..<target).map { out in
            let centre = (Double(out) + 0.5) * scale - 0.5
            let base = Int(centre.rounded(.down))
            let t = Float(centre - Double(base))

            func at(_ offset: Int) -> Int { min(max(base + offset, 0), source - 1) }

            return FourTaps(index: [at(-1), at(0), at(1), at(2)],
                            weight: [bSpline(1 + t), bSpline(t), bSpline(1 - t), bSpline(2 - t)])
        }
    }

    /// The four source pixels that one output pixel reads, and their weights.
    struct FourTaps {
        let index: [Int]
        let weight: [Float]
    }

    /// The cubic B-spline (B=1, C=0). It is never negative, and its four weights at any offset sum to one.
    static func bSpline(_ x: Float) -> Float {
        let x = abs(x)
        if x < 1 { return (3 * x * x * x - 6 * x * x + 4) / 6 }
        if x < 2 { let u = 2 - x; return u * u * u / 6 }
        return 0
    }

    static func byte(_ value: Float) -> UInt8 {
        UInt8(min(max(value.rounded(), 0), 255))
    }
}
