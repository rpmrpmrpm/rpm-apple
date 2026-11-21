import SwiftUI
import RPMKit

/// The Hints card on the General part of Settings: one key that shows the welcome and every
/// first-run hint again (``FirstRun/replay()``). Once pressed, the key says the hints are back and
/// cannot be pressed again until the page is opened anew.
///
/// It has the same shape as the page's other cards (`SettingsPage.card`) and the same small key.
struct HintsCard: View {
    /// Whether the key was pressed while this card is shown.
    @State private var back = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(Self.bulb)
                    .font(RPMFont.icon(12))
                    .foregroundStyle(RPMInk.white(0x66 / 255))

                Text(Loc.get("Settings_Hints")).rpmKicker()
            }

            Button(Loc.get(back ? "Settings_HintsBack" : "Settings_ShowHintsAgain")) {
                Haptics.pick()
                back = true
                FirstRun.shared.replay()
            }
            .buttonStyle(RPMGlassButton(.ghost, radius: 9, height: 34, stretches: true, inset: 16, size: 13))
            .disabled(back)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .rpmSection()
    }

    /// A light bulb: the desktop's mark for the hints.
    private static let bulb = "\u{f0eb}"
}
