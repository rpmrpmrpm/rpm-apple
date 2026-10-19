import Foundation

/// The four colours a room is painted in, worked out from what the sleeve gave up.
///
/// Ported from `RPM.Core/Viz/RoomPalette.cs`, and kept in plain numbers rather than in
/// any app's colour type so that the phone and the desktop paint the same record in the
/// same colour. Both convert on the way in.
///
/// A cover gives a dominant tone, a vivid accent and sometimes a third colour.
/// **None of the three can be used as it is**: covers give muted, uneven tones, and a
/// wash painted in them unchanged is either mud or invisible. What is wanted is the colour
/// that people remember the sleeve as, which is that tone at a higher saturation.
public struct RoomPalette: Equatable, Sendable {
    /// The dark the figures sit on.
    public var ground: SIMD3<Float>

    /// The dominant tone, lit.
    public var tint: SIMD3<Float>

    /// The vivid accent.
    public var glow: SIMD3<Float>

    /// What the second family of figures wears.
    public var shade: SIMD3<Float>

    public init(ground: SIMD3<Float>, tint: SIMD3<Float>,
                glow: SIMD3<Float>, shade: SIMD3<Float>) {
        self.ground = ground
        self.tint = tint
        self.glow = glow
        self.shade = shade
    }

    // The app's own blue, for a sleeve with no colour to give.
    private static let tintFallback = SIMD3<Float>(0.012, 0.443, 0.816)
    private static let glowFallback = SIMD3<Float>(0.02, 0.78, 1.0)
    private static let shadeFallback = SIMD3<Float>(0.62, 0.16, 0.72)
    private static let groundFallback = SIMD3<Float>(0.012, 0.030, 0.070)

    /// The shade for a sleeve with no third colour: a neutral grey, so the second family
    /// stays apart from the first without wearing a colour that is not on the record.
    static let shadeGrey = SIMD3<Float>(repeating: 0.70)

    /// The room with no record in it: the app's own blue, on its own near-black.
    public static let fallback = RoomPalette(ground: groundFallback, tint: tintFallback,
                                             glow: glowFallback, shade: shadeFallback)

    /// The room this cover paints.
    ///
    /// Any of the three may be missing (a black-and-white photograph has no colour to
    /// give). Where the first two are missing, the room keeps the app's own blue.
    public static func from(tint: SIMD3<Float>?, glow: SIMD3<Float>?,
                            shade: SIMD3<Float>?) -> RoomPalette {
        // The accent is the one worth having; the dominant stands in for it, and each
        // stands in for the other when only one of them came back.
        guard let base = tint ?? glow, let accent = glow ?? tint ?? glow else { return fallback }

        // Lifted well clear of black and pushed away from its own grey: a cover's dominant
        // tone is very often a muddy mid-brown, and a room painted in it unchanged is a
        // brown room.
        let litTint = vivid(base, saturate: 1.35, lift: 0.62)
        var litGlow = vivid(accent, saturate: 1.5, lift: 0.90)

        // The sleeve's third colour, where it has one that is genuinely a third and not
        // one of the two already in hand. It is spent below on whichever slot needs it
        // more.
        var spare: SIMD3<Float>? = shade.flatMap {
            same($0, base) || same($0, accent) ? nil : $0
        }

        // Where the dominant tone and the accent are the same hue, the sleeve's third
        // colour becomes the accent, so the big lobes show two colours. With no third
        // colour the accent stays as it is: the tint and the glow then differ only in
        // brightness. A gold cover with red in it is the typical case: the red becomes the
        // glow.
        if same(litTint, litGlow), let instead = spare {
            litGlow = vivid(instead, saturate: 1.5, lift: 0.90)
            spare = nil     // used for the glow, so the shade does not repeat it
        }

        // The second and third families wear the sleeve's third colour, or grey where it
        // has none. **No hue is ever rotated to make one up.** Rotating the dominant hue by
        // 152° and the accent by 42° would put green or teal on a quarter of the rooms, for
        // covers with no green on them, because most covers are red, orange or brown.
        let litShade = spare.map { vivid($0, saturate: 1.35, lift: 0.76) } ?? shadeGrey

        // The dark the figures sit on is the same hue taken almost to black, so the empty
        // parts of the screen still belong to the record without ever competing with it.
        let litGround = vivid(base, saturate: 1.1, lift: 0.16) * 0.55 + groundFallback * 0.45

        return RoomPalette(ground: litGround, tint: litTint, glow: litGlow, shade: litShade)
    }

    /// This palette eased toward another by one frame's worth.
    ///
    /// Frame-rate independent, so a change of record takes the same time on a slow phone
    /// as on a fast one: about a second at the rate the apps use, which makes a track
    /// change a dissolve and not a cut.
    public func eased(to target: RoomPalette, by k: Float) -> RoomPalette {
        RoomPalette(ground: ground + (target.ground - ground) * k,
                    tint: tint + (target.tint - tint) * k,
                    glow: glow + (target.glow - glow) * k,
                    shade: shade + (target.shade - shade) * k)
    }

    // ── the colour arithmetic ──

    /// A colour pushed away from its own grey and set to a working brightness, with the hue
    /// unchanged.
    static func vivid(_ c: SIMD3<Float>, saturate: Float, lift: Float) -> SIMD3<Float> {
        let luma = c.x * 0.2126 + c.y * 0.7152 + c.z * 0.0722
        var v = SIMD3<Float>(repeating: luma) + (c - SIMD3<Float>(repeating: luma)) * saturate
        v = v.clamped(lowerBound: .zero, upperBound: .one)

        let peak = max(v.x, max(v.y, v.z))
        if peak > 1e-4 { v *= lift / peak }

        return v.clamped(lowerBound: .zero, upperBound: .one)
    }

    /// Whether two colours would be called the same colour.
    ///
    /// **Compared as directions**, so a light colour and a dark one of the same hue count
    /// as one colour. That is the question being asked, since two figures painted in those
    /// would look like a single family however far apart their brightness is.
    static func same(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
        let d = normalised(a) - normalised(b)
        return (d * d).sum().squareRoot() < 0.22
    }

    private static func normalised(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let length = (c * c).sum().squareRoot()
        return length > 1e-4 ? c / length : .zero
    }
}

private extension SIMD3 where Scalar == Float {
    static var one: SIMD3<Float> { SIMD3(repeating: 1) }
}
