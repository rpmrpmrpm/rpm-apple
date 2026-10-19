import SwiftUI

/// The gold of the supporter badge: the gradient stops of the desktop `SupporterBadge`, shared so
/// that the iPhone `SupporterMark` and the Apple TV one look like the same metal at their own
/// sizes.
///
/// **Gold and not the app's cyan**, because cyan means "the one you picked", and a badge in cyan
/// looks like a selection. The sheen is fixed and does not move, as on the desktop: a moving shine
/// costs extra work on every frame it moves.
public enum SupporterMetal {
    /// One of the metal's colours. The helper makes the stops below read as a surface and not as a
    /// list of hex numbers.
    private static func gold(_ alpha: Double, _ r: Double, _ g: Double, _ b: Double) -> Color {
        Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: alpha / 255)
    }

    /// The lettering and the heart: the lightest gold and not white. White on gold looks like a
    /// label stuck to metal, but the mark should look stamped out of the same piece.
    public static let ink = gold(0xFF, 0xF2, 0xDC, 0x9A)

    /// The pill's face, running diagonally across the pill: a stamped surface catches light on a
    /// diagonal. The stops are uneven on purpose: bronze in the corner that faces away from the
    /// light, then gold, then a narrow band of champagne where the light lands, then gold again. An
    /// even ramp looks like a painted gradient. The tight pair of stops at 0.42 and 0.52 makes it
    /// look like a surface.
    public static let face = LinearGradient(
        stops: [.init(color: gold(0x3A, 0x9A, 0x6A, 0x18), location: 0),
                .init(color: gold(0x46, 0xEF, 0xAF, 0x12), location: 0.30),
                .init(color: gold(0x72, 0xEB, 0xD0, 0x7A), location: 0.42),
                .init(color: gold(0x46, 0xEF, 0xAF, 0x12), location: 0.52),
                .init(color: gold(0x38, 0x9A, 0x6A, 0x18), location: 1)],
        startPoint: .bottomLeading, endPoint: .topTrailing)

    /// The rim, one step brighter than the face, so the pill does not look like a flat shape with a
    /// picture painted inside it.
    public static let rim = LinearGradient(
        stops: [.init(color: gold(0x66, 0xB9, 0x8B, 0x1E), location: 0),
                .init(color: gold(0xCC, 0xEB, 0xD0, 0x7A), location: 0.45),
                .init(color: gold(0x66, 0xB9, 0x8B, 0x1E), location: 1)],
        startPoint: .bottomLeading, endPoint: .topTrailing)
}
