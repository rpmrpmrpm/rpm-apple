import SwiftUI
import RPMKit

/// The two sliders that dim and blur the app's background (``BackdropVeil``), under the backdrop
/// tiles on the Appearance settings and in the welcome's look step. The background behind them
/// changes as they move.
struct BackdropVeilSliders: View {
    @AppStorage(BackdropVeil.dimKey) private var dim = 0.0
    @AppStorage(BackdropVeil.blurKey) private var blur = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            slider(Loc.get("Settings_BackgroundDim"), value: $dim)
            slider(Loc.get("Settings_BackgroundBlur"), value: $blur)
        }
    }

    private func slider(_ said: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(said)
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0xB3 / 255))

            Slider(value: value, in: 0...1)
                .rpmControlTint()
                .accessibilityLabel(said)
        }
    }
}
