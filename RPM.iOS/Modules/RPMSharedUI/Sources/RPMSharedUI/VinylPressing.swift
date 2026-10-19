import SwiftUI
import UIKit
import CoreImage
import RPMDesign

/// The record on the turntable, pressed in a colour.
///
/// Ported from `RPM.Desktop/Presentation/NowPlaying/VinylPressing.cs`. It is one render, tinted:
/// `vinyl-record.png` is the same pressing that the desktop background is made of, rendered from
/// above in plain vinyl with its own lead-in, run-out and rim. Every colour is that one image
/// multiplied by a hue. Separate pre-coloured PNGs could drift apart from each other. This way
/// there is one asset for every colour.
///
/// **The tint is normalised to unit luminance.** This is why the result looks like a pressing and
/// not like a photograph with a filter: multiplying by the tint changes the colour of a pixel but
/// not its brightness. The sweep of light across the disc, the grain of the grooves and the curve
/// of the rim are all brightness, and nothing here changes brightness.
///
/// The colour comes from the sleeve. A sleeve with no colour gives a black record.
public enum VinylPressing {
    /// How far the hue is applied, compared with leaving the vinyl black. It is not applied fully: a
    /// record lit by the artwork is also lit by the room it is in, and a pressing that ignored
    /// that would look like a sticker and not like an object in the room.
    private static let saturation = 0.88

    /// The highest value any one channel may reach. A saturated hue at unit luminance has a channel
    /// several times brighter than the luminance. When the render's own light sweep multiplies it
    /// again, it clips, which flattens the highlight into a patch of colour where the grooves
    /// should still be visible.
    private static let ceiling = 3.2

    /// Rec. 709 luma weights, the same as the desktop app uses.
    private static let luma = (r: 0.2126, g: 0.7152, b: 0.0722)

    /// The colour the deck shows when nothing else is set: the app's azure over black, which is the
    /// source of the app's other dark blues.
    public static let houseHue = RGB(0x01, 0x1C, 0x34)

    /// One pressing per colour, cached. A record's colour is requested more than once during a
    /// track change, and each request needs an image decode and a filter pass.
    private nonisolated(unsafe) static let held = NSCache<NSString, UIImage>()

    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// The record in this colour, or black if the hue is nil.
    ///
    /// This runs off the main thread, because a 1,000 x 1,000 pixel image through a colour matrix
    /// takes noticeable time and the disc is on screen while it runs. The old pressing stays
    /// visible until the new one is ready, as on the desktop.
    public static func press(_ hue: RGB?) async -> Image? {
        let key = (hue.map { "\($0.r),\($0.g),\($0.b)" } ?? "black") as NSString
        if let known = held.object(forKey: key) { return Image(uiImage: known) }

        let pressed = await Task.detached(priority: .userInitiated) { () -> UIImage? in
            guard let url = Bundle.module.url(forResource: "vinyl-record", withExtension: "png"),
                  let neutral = CIImage(contentsOf: url)
            else { return nil }

            let matrix = CIFilter(name: "CIColorMatrix")!
            matrix.setValue(neutral, forKey: kCIInputImageKey)

            let press = rows(for: hue)
            matrix.setValue(press.r, forKey: "inputRVector")
            matrix.setValue(press.g, forKey: "inputGVector")
            matrix.setValue(press.b, forKey: "inputBVector")
            // Alpha is not changed, so the disc stays a disc and does not become a square.
            matrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 1), forKey: "inputAVector")

            guard let out = matrix.outputImage,
                  let cg = context.createCGImage(out, from: neutral.extent)
            else { return nil }

            return UIImage(cgImage: cg)
        }.value

        guard let pressed else { return nil }

        held.setObject(pressed, forKey: key)
        return Image(uiImage: pressed)
    }

    /// The matrix for one hue: three rows, one for each output channel.
    ///
    /// A colour is the render multiplied by the tint: unit luminance, reduced to stay under the
    /// ceiling, then applied only `saturation` of the way. Each row therefore changes its own
    /// channel and nothing else.
    ///
    /// **Black uses a different matrix, not a hue of 0.** The render is not neutral: its body is
    /// blue-black, which is a good base for a coloured record but not black. For black, every row
    /// is the luma weights, which removes the colour. The light sweep, the grain and the rim are
    /// brightness, so they survive unchanged. Only the blue is removed.
    private static func rows(for hue: RGB?) -> (r: CIVector, g: CIVector, b: CIVector) {
        guard let hue else {
            let grey = CIVector(x: luma.r, y: luma.g, z: luma.b, w: 0)
            return (grey, grey, grey)
        }

        let r = Double(hue.r) / 255, g = Double(hue.g) / 255, b = Double(hue.b) / 255
        let brightness = r * luma.r + g * luma.g + b * luma.b
        guard brightness > 1e-6 else { return rows(for: nil) }

        var press = [r / brightness, g / brightness, b / brightness]

        // Pull the values toward neutral until nothing is over the ceiling. Move toward neutral
        // and do not scale down, because scaling down would remove the brightness that unit
        // luminance has just set.
        let peak = press.max() ?? 1
        if peak > ceiling {
            for i in 0..<3 { press[i] = 1 + (press[i] - 1) * ((ceiling - 1) / (peak - 1)) }
        }

        for i in 0..<3 { press[i] = 1 + (press[i] - 1) * saturation }

        return (CIVector(x: press[0], y: 0, z: 0, w: 0),
                CIVector(x: 0, y: press[1], z: 0, w: 0),
                CIVector(x: 0, y: 0, z: press[2], w: 0))
    }
}
