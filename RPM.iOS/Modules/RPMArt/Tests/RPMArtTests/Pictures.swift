import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import RPMDesign

/// A cover, as an image file: a field of one colour with a patch of another colour over part of
/// it. Most covers look like this.
enum Pictures {
    static func drawn(field: RGB, splash: RGB? = nil, share: Double = 0,
                      edge: Int = 300) -> CGImage {
        let context = CGContext(
            data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

        context.setFillColor(colour(field))
        context.fill(CGRect(x: 0, y: 0, width: edge, height: edge))

        if let splash, share > 0 {
            let height = Double(edge) * share
            context.setFillColor(colour(splash))
            context.fill(CGRect(x: 0, y: 0, width: Double(edge), height: height))
        }

        return context.makeImage()!
    }

    static func png(field: RGB, splash: RGB? = nil, share: Double = 0, edge: Int = 300) -> Data {
        encoded(drawn(field: field, splash: splash, share: share, edge: edge), as: UTType.png)
    }

    static func jpeg(field: RGB, splash: RGB? = nil, share: Double = 0, edge: Int = 300) -> Data {
        encoded(drawn(field: field, splash: splash, share: share, edge: edge), as: UTType.jpeg)
    }

    /// A disc image, as the desktop cuts a record: a filled circle on a transparent ground. The
    /// transparent corners matter, because they make it a disc and not a square with a picture of a
    /// disc on it.
    static func disc(_ colour: RGB, edge: Int = 300) -> Data {
        let context = CGContext(
            data: nil, width: edge, height: edge, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

        context.clear(CGRect(x: 0, y: 0, width: edge, height: edge))
        context.setFillColor(Pictures.colour(colour))
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: edge, height: edge))

        return encoded(context.makeImage()!, as: UTType.png)
    }

    /// How opaque one pixel is, from 0 to 255. Used by tests that check whether the transparency was
    /// kept.
    static func opacity(of image: CGImage, atX x: Int, y: Int) -> UInt8 {
        var pixel: [UInt8] = [0, 0, 0, 0]

        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

            // Move the wanted pixel under the one-pixel context.
            context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
        }

        return pixel[3]
    }

    /// One pixel's colour, counted from the top left. Used by tests that check which part of a
    /// picture was kept.
    static func rgb(of image: CGImage, atX x: Int, fromTop y: Int) -> RGB {
        var pixel: [UInt8] = [0, 0, 0, 0]

        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(
                data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

            // A context counts up from the bottom, so row `y` from the top is this far up.
            context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y),
                                           width: image.width, height: image.height))
        }

        return RGB(pixel[0], pixel[1], pixel[2])
    }

    private static func encoded(_ image: CGImage, as type: UTType) -> Data {
        let out = NSMutableData()
        let destination = CGImageDestinationCreateWithData(
            out as CFMutableData, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        _ = CGImageDestinationFinalize(destination)
        return out as Data
    }

    static func colour(_ rgb: RGB) -> CGColor {
        CGColor(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255,
                blue: Double(rgb.b) / 255, alpha: 1)
    }
}
