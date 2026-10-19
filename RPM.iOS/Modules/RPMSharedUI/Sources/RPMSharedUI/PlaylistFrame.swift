import UIKit
import CoreText
import CoreGraphics
import RPMDesign

/// The frame on the cover of every generated list, lettered with the list's name.
///
/// Ported from `CoverOverlay` in the desktop app, using the same drawing file: a square that is
/// black everywhere except a window cut out of the middle, with the app name in the corner and an
/// empty band down the right-hand side. The drawing is inked in the list's two palette colours and
/// lettered here. Every list uses the same drawing. Lists differ only by the name in the band, the
/// two inks and what shows through the window.
///
/// **The window stays transparent.** The caller decides what goes behind it: a picture for most
/// lists, and the room for the five lists that have no picture of their own. This type returns an
/// image with a transparent window, not a finished cover, and the screens stack it over whatever
/// they already draw. The desktop app differs: it composes a JPEG because it has to store one.
/// Here two layers are drawn, so the room stays live.
///
/// **The name is drawn in code, not stored in the file.** The file would otherwise hold one
/// English name, but the lists have several names, and each name needs translating.
public enum PlaylistFrame {
    /// The lettered frame at this size, or nil if the drawing did not load.
    ///
    /// - Parameters:
    ///   - name: the list's name, in the current locale.
    ///   - look: the list's two inks. See ``RPMDesign/GeneratedListLook``.
    ///   - edge: the side of the square to compose, in points. The screen scale is applied here.
    @MainActor
    public static func image(name: String, look: GeneratedListLook.Look, edge: CGFloat) -> UIImage? {
        guard edge > 0, let drawing = Self.drawing else { return nil }

        let scale = UIScreen.main.scale
        let key = Key(name: name, border: look.border, text: look.text,
                      pixels: Int((edge * scale).rounded()))

        if let already = held.object(forKey: key) { return already }

        guard let made = compose(drawing, name: name, look: look, edge: edge, scale: scale)
        else { return nil }

        held.setObject(made, forKey: key)
        return made
    }

    /// The cache key for one composed frame: a name, two inks and a size. The name is part of it
    /// because the name is drawn into the picture. The inks are part of it because two lists with
    /// the same colours share the same tint.
    private final class Key: NSObject {
        let name: String, border: RGB, text: RGB, pixels: Int

        init(name: String, border: RGB, text: RGB, pixels: Int) {
            self.name = name; self.border = border; self.text = text; self.pixels = pixels
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(name); hasher.combine(border); hasher.combine(text); hasher.combine(pixels)
            return hasher.finalize()
        }

        override func isEqual(_ other: Any?) -> Bool {
            guard let other = other as? Key else { return false }
            return name == other.name && border == other.border
                && text == other.text && pixels == other.pixels
        }
    }

    /// A cache that the system empties under memory pressure, like every picture cache in this
    /// app. A shelf of generated lists holds a few dozen of these frames at two or three sizes.
    ///
    /// On the main actor because the drawing is: a frame is composed while a row is laid out, and
    /// only the main thread does that.
    @MainActor private static let held = NSCache<Key, UIImage>()

    /// The single frame drawing, loaded once and cached, including a failed load. Without caching
    /// the failure, every cover would try to open the missing file again.
    private static let drawing: CGImage? = {
        guard let url = Bundle.module.url(forResource: "PlaylistFrame", withExtension: "png"),
              let data = try? Data(contentsOf: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }

        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    /// Whether the drawing loaded.
    ///
    /// Callers check this first. If a square removed its own mark to make room for a frame that
    /// never loaded, the square would be empty.
    public static var has: Bool { drawing != nil }

    // ── composition ──

    @MainActor
    private static func compose(_ drawing: CGImage, name: String,
                                look: GeneratedListLook.Look,
                                edge: CGFloat, scale: CGFloat) -> UIImage? {
        guard let inked = ramped(drawing, from: look.border, to: look.text) else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: CGSize(width: edge, height: edge), format: format)
            .image { context in
                let canvas = context.cgContext

                // UIKit coordinates have y pointing down, and every number in `ListFrameMetrics`
                // uses them. `draw(in:)` on a `UIImage` flips for us; a `CGImage` would not.
                UIImage(cgImage: inked).draw(in: CGRect(x: 0, y: 0, width: edge, height: edge))

                letter(name, on: canvas, edge: edge, colour: look.text)
            }
    }

    /// Maps the drawing's black and white to a ramp between the two inks.
    ///
    /// The file is greyscale: a black field, white lettering, and antialiased greys where they
    /// meet. A single lookup table is therefore a two-colour ramp: 0 maps to the border colour, 255
    /// maps to the lettering colour, and soft edges land in between. **Alpha is not changed**, so
    /// the window stays transparent and its edge stays as soft as drawn.
    ///
    /// The bytes are premultiplied, so each channel is divided by alpha before it is read as a grey
    /// and multiplied again afterwards. Without this, every antialiased edge reads darker than it
    /// is and a dark fringe appears round the window.
    static func ramped(_ drawing: CGImage, from border: RGB, to text: RGB) -> CGImage? {
        let width = drawing.width, height = drawing.height
        guard width > 0, height > 0 else { return nil }

        var bytes = [UInt8](repeating: 0, count: width * height * 4)

        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }

            context.draw(drawing, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        guard drawn else { return nil }

        // One table per channel, so mixing a pixel is a lookup and not three multiplications.
        // The frame has about 600,000 pixels at the sizes it is composed at.
        var red = [UInt8](repeating: 0, count: 256)
        var green = red, blue = red

        for k in 0..<256 {
            let along = Double(k) / 255
            red[k] = mix(border.r, text.r, along)
            green[k] = mix(border.g, text.g, along)
            blue[k] = mix(border.b, text.b, along)
        }

        for at in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = bytes[at + 3]
            guard alpha > 0 else { continue }

            // Divide out alpha, so a half-covered pixel is read by its own colour and not by how
            // much of it is covered.
            let grey = alpha == 255 ? Int(bytes[at])
                                    : min(255, Int(bytes[at]) * 255 / Int(alpha))

            bytes[at] = premultiplied(red[grey], alpha)
            bytes[at + 1] = premultiplied(green[grey], alpha)
            bytes[at + 2] = premultiplied(blue[grey], alpha)
        }

        return bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }

            return context.makeImage()
        }
    }

    private static func mix(_ from: UInt8, _ to: UInt8, _ along: Double) -> UInt8 {
        UInt8(clamping: Int((Double(from) + (Double(to) - Double(from)) * along).rounded()))
    }

    private static func premultiplied(_ value: UInt8, _ alpha: UInt8) -> UInt8 {
        UInt8(clamping: Int(value) * Int(alpha) / 255)
    }

    // ── the name, rotated ──

    /// Draws the list's name in the band down the right-hand edge.
    ///
    /// **Rotated clockwise, so the tops of the capital letters point to the outer edge.** Y counts
    /// down here, so a +90 degree rotation sends local +x down the picture and local -y out to the
    /// right. This is the reading direction of the original lettering.
    ///
    /// The font is the app's Cabin Bold where it has the letters, and a system font where it does
    /// not. That fallback keeps names such as 你的专属歌单 readable instead of showing empty boxes.
    @MainActor
    private static func letter(_ name: String, on canvas: CGContext,
                               edge: CGFloat, colour: RGB) {
        guard !name.isEmpty else { return }

        let face = SharedFaces.cabinBold
        let measure: (String, CGFloat) -> ListFrameMetrics.Ink = { said, size in
            ink(of: said, face: face, size: size)
        }

        guard let set = ListFrameMetrics.lettering(name, edge: edge, measuring: measure)
        else { return }

        let anchor = ListFrameMetrics.anchor(edge: edge)

        canvas.saveGState()
        canvas.translateBy(x: anchor.x, y: anchor.y)
        canvas.rotate(by: .pi / 2)

        let font = font(face, set.size)

        // UIKit draws from the top of the line box, but the layout maths gives a baseline. The
        // font's ascent converts between them. It is the font's ascent, not the ink's.
        (name as NSString).draw(
            at: CGPoint(x: set.alongBand, y: set.acrossBand - CTFontGetAscent(font)),
            withAttributes: [.font: UIFont(descriptor: CTFontCopyFontDescriptor(font), size: set.size),
                             .foregroundColor: UIColor(red: CGFloat(colour.r) / 255,
                                                       green: CGFloat(colour.g) / 255,
                                                       blue: CGFloat(colour.b) / 255,
                                                       alpha: 1)])

        canvas.restoreGState()
    }

    /// The ink box of one string in this font: the bounds of the glyph outlines, not the line
    /// height the font reserves.
    static func ink(of said: String, face: String?, size: CGFloat) -> ListFrameMetrics.Ink {
        let font = font(face, size)
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: said, attributes: [.font: font]))
        let box = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

        guard box.height > 0 || box.width > 0 else {
            return ListFrameMetrics.Ink(left: 0, width: 0, top: 0, bottom: 0)
        }

        // Core Text measures from a baseline at 0 with y pointing up. The metrics use y pointing
        // down, so the box's top is the negative of its maximum.
        return ListFrameMetrics.Ink(left: box.minX, width: box.width,
                                    top: -box.maxY, bottom: -box.minY)
    }

    private static func font(_ face: String?, _ size: CGFloat) -> CTFont {
        guard let face else { return CTFontCreateUIFontForLanguage(.system, size, nil)! }
        return CTFontCreateWithName(face as CFString, size, nil)
    }
}
