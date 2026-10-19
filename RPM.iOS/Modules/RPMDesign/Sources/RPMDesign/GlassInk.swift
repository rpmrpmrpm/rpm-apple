import Foundation

/// A colour lifted to the lightness a thin line needs on the app's dark glass.
///
/// The colour is read from a record, not chosen. A sleeve can give a near-black, and a line
/// two points wide in that colour cannot be seen. The check is a type, not a function call,
/// so it cannot be skipped. A view that paints with a cover's colour takes a `GlassInk`, and
/// the only way to make one is through the lift.
///
/// Lightness is Oklab's L. It is the same measure that ``RPMPalette`` uses to snap accents.
/// The ten accents range from 0.370 (Forest) to 0.805 (Lime).
public struct GlassInk: Hashable, Sendable {
    /// The colour as it is drawn: the colour asked for, or that colour with enough white mixed
    /// in to reach ``floor``.
    public let rgb: RGB

    /// The lightness a line has to reach. It is set just under Azure, which measures 0.549 and
    /// reads well on the glass. Eight of the ten accents are drawn exactly as they are. Only
    /// Forest (0.370) and Indigo (0.476) are lifted.
    public static let floor = 0.54

    public init(_ colour: RGB) {
        rgb = Self.lifted(colour)
    }

    /// What a record with no colour to give is drawn in.
    public static let white = GlassInk(RGB(255, 255, 255))

    /// `colour` with as much white mixed in as the floor needs. Returns `colour` itself where
    /// it is already light enough.
    ///
    /// White is mixed in, rather than moving along Oklab's L. A move along L would need the
    /// inverse transform, and it could leave the colour gamut. Mixing with white always stays
    /// in gamut, and it keeps the hue of the sleeve. The cost is some chroma, which is the right
    /// trade here. A line is read as light first and as a colour second.
    private static func lifted(_ colour: RGB) -> RGB {
        guard RPMPalette.oklab(colour).l < floor else { return colour }

        // Mixed in linear light and found by bisection. Lightness rises as the mix rises, and
        // full white is the top end, so the floor always lies between the two ends. Sixteen
        // steps are enough to land inside one byte.
        var below = 0.0, above = 1.0
        for _ in 0 ..< 16 {
            let middle = (below + above) / 2
            if RPMPalette.oklab(mixed(colour, white: middle)).l < floor {
                below = middle
            } else {
                above = middle
            }
        }

        return mixed(colour, white: above)
    }

    /// `colour` with `white` parts of white light in it, from 0 to 1.
    private static func mixed(_ colour: RGB, white part: Double) -> RGB {
        func channel(_ stored: UInt8) -> UInt8 {
            let light = linear(stored)
            return encoded(light + (1 - light) * part)
        }

        return RGB(channel(colour.r), channel(colour.g), channel(colour.b))
    }

    /// One channel with the sRGB transfer curve removed, and then put back. Mixing must happen
    /// in light, not in the stored encoding. Mixing the encoded values gives a result that is
    /// darker than the arithmetic says.
    private static func linear(_ stored: UInt8) -> Double {
        let v = Double(stored) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func encoded(_ light: Double) -> UInt8 {
        let held = min(max(light, 0), 1)
        let v = held <= 0.0031308 ? held * 12.92 : 1.055 * pow(held, 1 / 2.4) - 0.055
        return UInt8(clamping: Int((v * 255).rounded()))
    }
}
