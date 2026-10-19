import Foundation
import CoreGraphics
import ImageIO
import RPMDesign
import RPMKit

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

/// Turns downloaded bytes into something the wall can draw.
///
/// **The whole file exists to avoid one thing: decoding a picture at its own size and then shrinking it.** A scanned
/// sleeve is often three thousand pixels square. That is thirty-six megabytes decoded, for a card about a hundred and
/// seventy points wide. Doing that six hundred times runs the phone out of memory. The system then removes pictures
/// and text from the screen to free space.
///
/// ImageIO has this built in. `CGImageSourceCreateThumbnailAtIndex` reads the file and makes the smaller image
/// directly, so the full-size bitmap never exists. That is why this uses ImageIO and not a draw into a context.
public enum Thumbnail {
    /// The longest edge a cover is kept at, in pixels.
    ///
    /// It is chosen from the largest size a card can ever be. On a wide phone, the wall pinches down to one card
    /// across, which is about 430 points. At three device pixels per point, that is 1300 pixels. The value 1024 is a
    /// little under that. The loss is small, and it is not visible on a sleeve. It also keeps a whole library's
    /// covers inside a few dozen megabytes.
    public static let stored = 1024

    /// Decodes a picture straight to the size it will be drawn at.
    ///
    /// The source is not cached (`shouldCache: false`), because the source is thrown away here. Caching it would
    /// hold the encoded data twice.
    public static func of(_ data: Data, edge: Int) -> CGImage? {
        guard edge > 0,
              let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }

        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            // Always. A JPEG's own embedded thumbnail is only about 160 pixels, and it would be returned in place of
            // the sleeve.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // Rotated as the file says. A cover with an orientation tag is rare, and a sideways cover on the wall is
            // easy to notice.
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: edge,
        ] as CFDictionary)
    }

    /// The 48 pixel square that `CoverColor` reads a sleeve's colour from.
    ///
    /// It is drawn from the picture that is already scaled down, not from the bytes. So a cover is decoded once and
    /// answers both questions.
    ///
    /// It is drawn onto black, and that matters. A cover with transparency is composited against what the wall is
    /// really made of. `CoverColor` skips near-black pixels, so the transparent part adds nothing rather than grey.
    public static func square(_ image: CGImage, edge: Int = 48) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: edge * edge * 4)
        let space = CGColorSpaceCreateDeviceRGB()

        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: edge, height: edge,
                bitsPerComponent: 8, bytesPerRow: edge * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }

            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: edge, height: edge))
            return true
        }

        return drawn ? bytes : nil
    }

    /// What colour this sleeve is, as an accent.
    public static func accent(of image: CGImage) -> Accent? { colours(of: image).accent }

    /// Every colour one sleeve has to give, read from a single 48 pixel square.
    ///
    /// One square is used, not three. The downscale is the expensive part. Three readings would be three passes over
    /// the same two thousand pixels.
    public static func colours(of image: CGImage) -> SleeveColours {
        guard let square = square(image) else { return .none }

        // **Two of the sleeve's own colours, not one and a guess.** This is the bargain the desktop made in
        // `VinylPressing.PaletteFromArt`. The first colour is scored exactly as `CoverColor.highlight` scores it, so it
        // is the highlight. The second is the next colour that differs from the first. So the room does not
        // have to make one up. See ``SleeveColours/shade``.
        let vivid = CoverColor.palette(rgba: square, count: 2)

        return SleeveColours(
            accent: CoverColor.tint(rgba: square).flatMap { RPMPalette.nearest(to: $0) },
            dominant: CoverColor.dominant(rgba: square),
            highlight: vivid.first ?? CoverColor.highlight(rgba: square),
            shade: vivid.count > 1 ? vivid[1] : nil)
    }

    /// Re-encodes a picture for the disk cache.
    ///
    /// **The picture is kept as a JPEG at a known size, not as whatever arrived.** This is the one place where this
    /// differs from the desktop's cache, and the difference is worth stating. If the original were stored, a library
    /// of six hundred records would take a gigabyte of the phone's space. Every later launch would also decode those
    /// same three thousand pixels again, to draw a card a fifth of that size. Storing the downscaled picture takes a
    /// few dozen megabytes, and the decode is already the right size. The picture is only ever shown. It is never
    /// edited and never sent back, so nothing needs the full resolution.
    ///
    /// **The picture decides the format, and the format is not a preference.** A sleeve is a photograph of a square,
    /// and a JPEG is the right format for it. A disc label is a picture with a hole cut in it. The corners of the
    /// photograph are transparent, and that transparency is what makes it a record rather than a rectangle. A JPEG
    /// cannot store an alpha channel at all. Saving a label as a JPEG would not lose a little quality. It would lose
    /// the shape.
    public static func encoded(_ image: CGImage, _ picture: RecordPicture,
                               quality: Double = 0.82) -> Data? {
        let out = NSMutableData()

        guard let destination = CGImageDestinationCreateWithData(
            out as CFMutableData, picture.keepsAlpha ? png : jpeg, 1, nil) else { return nil }

        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: quality,
        ] as CFDictionary)

        guard CGImageDestinationFinalize(destination) else { return nil }
        return out as Data
    }

    /// What goes to the disk for a picture that arrived as `data` and decoded to `big`.
    ///
    /// The bytes as they arrived where they are a sleeve already in the disk's format and no
    /// larger than ``stored``: the API's cut copy is a JPEG at that edge, and encoding it again
    /// would lose detail a second time for nothing. Anything else is ``encoded(_:_:quality:)``.
    public static func kept(_ data: Data, decoded big: CGImage, _ picture: RecordPicture) -> Data? {
        if !picture.keepsAlpha, isJPEG(data, noLargerThan: stored) { return data }
        return encoded(big, picture)
    }

    /// Whether `data` is a JPEG whose longer side is at most `edge`, read from its header
    /// without decoding it.
    private static func isJPEG(_ data: Data, noLargerThan edge: Int) -> Bool {
        guard let source = CGImageSourceCreateWithData(
                  data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source), (type as String) == (jpeg as String),
              let facts = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = facts[kCGImagePropertyPixelWidth] as? Int,
              let height = facts[kCGImagePropertyPixelHeight] as? Int
        else { return false }

        return max(width, height) <= edge
    }

    private static var jpeg: CFString {
        #if canImport(UniformTypeIdentifiers)
        return UTType.jpeg.identifier as CFString
        #else
        return "public.jpeg" as CFString
        #endif
    }

    private static var png: CFString {
        #if canImport(UniformTypeIdentifiers)
        return UTType.png.identifier as CFString
        #else
        return "public.png" as CFString
        #endif
    }
}

/// Every colour one sleeve gives: the accent that walls and drawers are painted from, and the raw colours that the
/// room behind the player is lit by.
///
/// **The room takes the raw colours. That is why both are kept.** The accent is one of the app's ten accents. That is
/// what makes a wall of six hundred records read as one thing and not as noise. A room built from only those ten
/// would be ten rooms. The room wants this record's own colour. `RoomPalette` does its own lifting and separating,
/// with the same arithmetic the desktop's room uses.
///
/// Each colour may be missing, and a missing one is its own answer, not a failure. A black-and-white press photo has a
/// dominant colour and no highlight. A sleeve that is entirely black or entirely white has neither.
public struct SleeveColours: Hashable, Sendable {
    /// The app's own accent nearest this sleeve.
    public let accent: Accent?

    /// The colour most of the sleeve is.
    public let dominant: RGB?

    /// The most vivid colour in it, which is very often a small part of it.
    public let highlight: RGB?

    /// The next colour on the sleeve that differs from ``highlight``. It is nil where the sleeve has only one colour.
    ///
    /// **Many covers give the same hue for their dominant colour and their highlight.** A gold sleeve with red
    /// lettering is gold twice over. The gold is both the field and the most vivid thing measured on it. Without a
    /// third colour, `RoomPalette` has to turn the hue to find one. Forty-two degrees away from gold is green. So the
    /// room would be green, for a record with no green anywhere on it, while the red sat on the sleeve the whole time.
    /// This is that red.
    ///
    /// The desktop reads its room colours the same way (`VinylPressing.PaletteFromArt`, from `CoverColor.Palette`).
    /// Without this colour, the phone would let the rotation invent the third.
    public let shade: RGB?

    /// A sleeve with nothing to give, or no sleeve at all.
    public static let none = SleeveColours(accent: nil, dominant: nil, highlight: nil,
                                           shade: nil)

    public init(accent: Accent?, dominant: RGB?, highlight: RGB?, shade: RGB? = nil) {
        self.accent = accent
        self.dominant = dominant
        self.highlight = highlight
        self.shade = shade
    }
}
