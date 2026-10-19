import Foundation

/// A colour as the palette holds it: three channels, no alpha.
///
/// It is a separate type, not SwiftUI's `Color`. That keeps the matching below testable. `Color`
/// does not expose its components, and the snap is arithmetic on them. The SwiftUI bridge is one
/// line, in `Palette+SwiftUI.swift`.
public struct RGB: Hashable, Sendable {
    public let r: UInt8, g: UInt8, b: UInt8
    public init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
}

/// One of the app's accents: the undimmed tint, and the three-stop ramp that a drawer is painted
/// with.
public struct Accent: Hashable, Sendable {
    public let name: String
    public let base: RGB

    /// Top, middle, foot. The dim ramp that the album drawers produce.
    public let gradient: [RGB]

    public init(name: String, base: RGB, gradient: [RGB]) {
        self.name = name; self.base = base; self.gradient = gradient
    }
}

/// The app's ten accents, and the rule for snapping any colour to the nearest one.
///
/// The colours come from `RPM.Desktop/Assets/RPMPalette.xaml`, through `scripts/gen_palette_swift.py`.
/// They are not typed out again here. Each of the ten is a real drawer tint, produced by the album
/// wall's own calculation over a real cover. A second copy in Swift would become a second set of
/// colours as soon as the first set was changed.
///
/// **Why snap at all.** A photograph's dominant tone is whatever the largest object in the frame
/// happened to be lit by. That is a different accident for every artist. Thousands of those laid out
/// as a wall give thousands of colours and no palette. The wall reads as noise, even when each box is
/// attractive. Snapped to the ten accents, the wall uses the app's own colours in many arrangements,
/// and it reads as one thing.
public enum RPMPalette {
    /// The palette colour nearest to this one, or nil when there is nothing to snap to.
    ///
    /// Nil is a real answer, not a failure. A colour can have no hue in it. A black and white press
    /// photo gives a grey. A grey is not nearer one hue than another. Snapping it anyway would pick
    /// whichever accent is least saturated. A monochrome portrait would then come back washed in dark
    /// green for no reason. The caller keeps the tone the picture actually gave. For a grey photograph
    /// that is a grey box.
    public static func nearest(to colour: RGB) -> Accent? {
        let (l, chroma, hue) = oklch(colour)
        guard chroma >= neutralChroma else { return nil }

        return accents.min { distance(l, chroma, hue, $0) < distance(l, chroma, hue, $1) }
    }

    /// How much colour a tone needs before it counts as having a colour at all.
    ///
    /// Measured as Oklab chroma. The palette's own entries run from about 0.09 to 0.17. A warm or cool
    /// grey measures about 0.015. A photograph with any visible colour cast, such as a pale beige or a
    /// muted navy, is above 0.023. The threshold sits between the two.
    static let neutralChroma = 0.018

    /// How far apart two colours are, for the purpose of choosing which of the ten a colour is
    /// closest to.
    ///
    /// The distance is worked out in Oklch, as three questions: which HUE, how strong, and how bright.
    /// It is not a straight distance in Oklab. A straight distance is dominated by whichever axis is
    /// longest. For a muted colour that is always lightness. A dark navy photo would then match Forest
    /// rather than Azure. A weak blue and a dark green have only darkness in common, and darkness
    /// dominates the sum. Asked for hue first, a blue photograph stays blue however it was lit.
    ///
    /// Hue is circular, so the difference is the short way round. Hue has the most weight. Chroma
    /// decides which of two entries with the same hue a washed-out colour is closer to. Lightness counts
    /// for half, so that Lime and Forest, which share a hue at very different lightness values, do not
    /// merge into one.
    static func distance(_ l: Double, _ chroma: Double, _ hue: Double, _ accent: Accent) -> Double {
        let (al, ac, ah) = oklch(accent.base)

        var dh = abs(hue - ah)
        if dh > .pi { dh = (2 * .pi) - dh }

        let dc = (chroma - ac) * chromaWeight
        let dl = (l - al) * lightnessWeight

        return (dh * dh) + (dc * dc) + (dl * dl)
    }

    private static let chromaWeight = 1.0
    private static let lightnessWeight = 0.5

    /// A colour as the match reads it: Oklab turned to polar form. That gives the same three numbers
    /// a person uses. How bright it is, how much colour it has, and which colour that is.
    public static func oklch(_ colour: RGB) -> (l: Double, chroma: Double, hue: Double) {
        let (l, a, b) = oklab(colour)
        return (l, (a * a + b * b).squareRoot(), atan2(b, a))
    }

    public static func oklab(_ colour: RGB) -> (l: Double, a: Double, b: Double) {
        let r = linear(colour.r), g = linear(colour.g), b = linear(colour.b)

        let cl = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let cm = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let cs = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

        return (
            0.2104542553 * cl + 0.7936177850 * cm - 0.0040720468 * cs,
            1.9779984951 * cl - 2.4285922050 * cm + 0.4505937099 * cs,
            0.0259040371 * cl + 0.7827717662 * cm - 0.8086757660 * cs
        )
    }

    /// One channel with the sRGB transfer curve removed. The stored byte is a display encoding.
    /// Comparing colours in that encoding compares the encoding, not the light.
    private static func linear(_ channel: UInt8) -> Double {
        let v = Double(channel) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}
