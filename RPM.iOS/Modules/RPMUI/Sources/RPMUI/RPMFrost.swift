import SwiftUI
import UIKit

/// The app's frosted glass: the live scene behind it, blurred, with its own colour kept.
///
/// **Fitted to the Uno app's bar, not chosen freely.** Over a ground of (21, 50, 76) the Uno
/// app's bar reads **(31, 55, 77)**: only slightly lighter, and the blue of the record is still
/// in it. This is the colour to match.
///
/// No stock UIKit or SwiftUI treatment matches it. Every stock material is a blur PLUS a tint
/// towards grey, but the Skia glass in the Uno app only blurs and then lays a `#22000000` veil
/// over the result. So the closest material is corrected. These are the results under the app's
/// veil, over the same ground:
///
/// | material                       | reads            | difference        |
/// | ------------------------------ | ---------------- | ----------------- |
/// | `.dark`                        | (26, 38, 49)     | the blue is gone  |
/// | `.systemMaterialDark`          | (43, 52, 60)     | grey, and light   |
/// | `.systemThinMaterialDark`      | (40, 53, 64)     | still grey        |
/// | `.systemUltraThinMaterialDark` | (45, 58, 70)     | too much red      |
/// | **the same, corrected**        | **(33, 56, 78)** | **2 levels**      |
///
/// `.dark` is not used because it looks like a solid slab: it takes 27 levels of blue out of the
/// ground below it, and every card in the app would show the same loss, because they all sit on
/// this view.
///
/// The correction is one saturation and one veil. Both values are solved, not tuned. A material's
/// tint is a move towards grey, so undoing it is a move away from grey (`saturation`). What that
/// overshoots in brightness is taken off with black. That gives two equations with two unknowns,
/// from the green and blue values that the bar has to reach.
struct RPMFrost: View {
    /// How far the material's grey is pulled back out. Solved, not tuned.
    private static let saturation: Double = 1.93

    /// What the saturation overshoots in brightness, taken back off. On top of the
    /// `#22000000` the chrome and the cards already wear.
    private static let veil: Double = 0.08

    var body: some View {
        Effect()
            .saturation(Self.saturation)
            .overlay { Color.black.opacity(Self.veil) }
    }
}

/// The blur itself. It is a `UIVisualEffectView` and not SwiftUI's `Material`, because the filters
/// above need a view to be applied to, and the material is not one.
private struct Effect: UIViewRepresentable {
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {}
}
