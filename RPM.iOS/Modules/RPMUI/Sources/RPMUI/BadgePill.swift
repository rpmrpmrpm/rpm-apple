import SwiftUI
import RPMKit

/// A badge as the page shows it under the name: its name in italics, stamped on a pill the way the supporter's mark
/// is (``SupporterMark``), in the badge's colour and not in gold. The face runs diagonally from a dark corner through
/// a light band; the rim is a step brighter; the lettering is the lightest tint of the colour. It is the Android app's
/// `BadgePill`.
struct BadgePill: View {
    let badge: RPMProfileBadges.Badge

    /// The colour's wire value, `#RRGGBB`; empty for the first badge colour.
    let colour: String
    var size: CGFloat = 14

    var body: some View {
        let rgb = RPMProfileBadges.colour(colour)
        let base = Color(rgb: rgb)
        let dark = Self.blend(rgb, toward: 0, by: 0.35)
        let light = Self.blend(rgb, toward: 1, by: 0.55)
        let pill = Capsule(style: .continuous)

        Text(badge.name)
            .font(RPMFont.display(size))
            .italic()
            .lineLimit(1)
            .foregroundStyle(Self.blend(rgb, toward: 1, by: 0.8))
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background {
                pill.fill(LinearGradient(stops: [.init(color: dark.opacity(0.55), location: 0),
                                                 .init(color: base.opacity(0.60), location: 0.30),
                                                 .init(color: light.opacity(0.70), location: 0.42),
                                                 .init(color: base.opacity(0.60), location: 0.52),
                                                 .init(color: dark.opacity(0.55), location: 1)],
                                         startPoint: .bottomLeading, endPoint: .topTrailing))
            }
            .overlay {
                pill.strokeBorder(LinearGradient(stops: [.init(color: base.opacity(0.70), location: 0),
                                                         .init(color: light, location: 0.45),
                                                         .init(color: base.opacity(0.70), location: 1)],
                                                 startPoint: .bottomLeading, endPoint: .topTrailing),
                                  lineWidth: 1)
            }
    }

    /// The colour `rgb` (0xRRGGBB) moved towards black (0) or white (1) by `share`.
    static func blend(_ rgb: UInt32, toward target: Double, by share: Double) -> Color {
        func channel(_ shift: UInt32) -> Double {
            let value = Double((rgb >> shift) & 0xFF) / 255
            return value + (target - value) * share
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }
}
