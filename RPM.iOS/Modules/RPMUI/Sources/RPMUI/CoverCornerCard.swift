import SwiftUI
import RPMKit

/// The settings card that chooses how round the covers are (``CoverCorner``), from square corners
/// to round ones. See ``CoverCornerSlider``.
struct CoverCornerCard: View {
    var body: some View {
        SettingsCardFrame(Glyph.corners, Loc.get("Settings_CoverCorners")) {
            CoverCornerSlider()
        }
    }
}

/// The slider that chooses how round the covers are, with a cover beside it that shows the
/// rounding as it moves. It is on the Appearance settings and in the welcome's look step.
///
/// **The covers of the app change when the finger lifts**, not on every step of the slider. Every
/// cover on every page that is built reads the setting, and drawing them all again on each step
/// would make the slider stutter. The cover on the card follows the finger.
struct CoverCornerSlider: View {
    /// The share while the finger is on the slider. Nil when it is not.
    @State private var moving: CGFloat?

    /// Whether a finger is on the slider. A change made without one, such as VoiceOver's, is
    /// kept at once.
    @State private var dragging = false

    /// The size of the cover beside the slider.
    private static let edge: CGFloat = 56

    var body: some View {
        let shown = moving ?? CoverCorner.share

        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: Self.edge * shown, style: .continuous)
                .fill(LinearGradient(colors: [RPMInk.cyan, RPMInk.selectedWash],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    RoundedRectangle(cornerRadius: Self.edge * shown, style: .continuous)
                        .strokeBorder(RPMInk.cardBorder, lineWidth: 1)
                }
                .frame(width: Self.edge, height: Self.edge)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Slider(value: Binding(get: { moving ?? CoverCorner.share },
                                      set: { now in
                                          if dragging { moving = now }
                                          else { CoverRounding.shared.share = now }
                                      }),
                       in: 0...CoverCorner.roundest,
                       onEditingChanged: { held in
                           dragging = held
                           if !held, let moving {
                               CoverRounding.shared.share = moving
                               self.moving = nil
                           }
                       })
                    .rpmControlTint()
                    .accessibilityLabel(Loc.get("Settings_CoverCorners"))

                HStack {
                    Text(Loc.get("Settings_CoverCornersSharp"))
                    Spacer()
                    Text(Loc.get("Settings_CoverCornersRound"))
                }
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .accessibilityHidden(true)
            }
        }
    }
}
