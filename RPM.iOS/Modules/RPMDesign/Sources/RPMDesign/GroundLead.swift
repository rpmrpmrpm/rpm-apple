import Foundation

/// The colour an artist's page stands on, read off their photograph. The Android phone app has the
/// same rule with the same numbers (`GroundLead` in `:core`).
///
/// **The photograph's best vivid colour, not its most common one.** The colour most of a photograph
/// is made of is very often the wall or the sky behind the band: grey, beige or white. A page led by
/// that is a grey page. The vivid colour (a jacket, a light, a guitar) is the one a person remembers
/// the photograph by. A photograph with no vivid colour at all (black and white) is led by its most
/// common colour instead.
///
/// **No brighter than ``mostLuminance``.** The page's text is white. A yellow or a pale blue as the
/// ground would leave it hard to read, so a colour brighter than that is darkened, in linear light, to
/// exactly that brightness. Its hue and its saturation stay as they are.
public enum GroundLead {
    /// The brightest the colour may be, as relative luminance (0 is black, 1 is white). White over it
    /// has a contrast of about 4:1, and the page's veil over the colour raises that above 6:1 at the
    /// top of the page.
    public static let mostLuminance: Double = 0.2

    public static func of(glow: RGB?, dominant: RGB?) -> RGB? {
        guard let colour = glow ?? dominant else { return nil }

        let r = linear(colour.r), g = linear(colour.g), b = linear(colour.b)
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        guard luminance > mostLuminance else { return colour }

        let k = mostLuminance / luminance
        return RGB(encoded(r * k), encoded(g * k), encoded(b * k))
    }

    private static func linear(_ value: UInt8) -> Double {
        let c = Double(value) / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ value: Double) -> UInt8 {
        let c = min(max(value, 0), 1)
        let s = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8((s * 255).rounded())
    }
}
