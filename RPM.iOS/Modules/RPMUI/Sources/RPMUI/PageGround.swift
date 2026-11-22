import SwiftUI
import RPMKit

/// What a profile page is drawn on (``RPMProfile/pageGround``): a solid colour, or one of the
/// app's backgrounds. An empty or unknown value is the app's standard background, not the reader's
/// own choice: a person's page looks the same to everyone.
///
/// **A change dissolves.** The page opens on the standard background and gets the owner's when the
/// profile has been read, after the page has risen. Nothing else moves at that moment, so the new
/// background fades in over the old one (``dissolve``), as ``ArtGround`` does, and does not replace
/// it in one frame. The same happens when the owner picks another one in the editor.
struct PageGroundView: View {
    let wire: String

    /// The background being replaced, kept at full strength under the new one until the new one
    /// covers it. Fading the old one out at the same time would let whatever is behind the page show
    /// through in the middle, which reads as a flash.
    @State private var under: String?

    /// How far the new background has come in over ``under``.
    @State private var covered: Double = 1

    /// How long the change takes. The same as ``ArtGround``'s default.
    private static let dissolve = 0.25

    var body: some View {
        ZStack {
            if let under { Self.ground(under) }
            Self.ground(wire).opacity(covered)
        }
        .onChange(of: wire) { old, _ in
            under = old
            covered = 0

            withAnimation(.easeInOut(duration: Self.dissolve)) {
                covered = 1
            } completion: {
                // Only once it is covered; see ``under``.
                under = nil
            }
        }
    }

    @ViewBuilder
    private static func ground(_ wire: String) -> some View {
        switch RPMPageGround(wire: wire) {
        case .colour(let value):
            Color(rgb: value).ignoresSafeArea()
        case .backdrop(let id):
            VinylGround(showing: Backdrop.Choice(rawValue: id) ?? .standard)
        case .standard:
            VinylGround(showing: .standard)
        }
    }
}

extension Color {
    /// A colour from 0xRRGGBB.
    init(rgb: UInt32) {
        self.init(red: Double((rgb >> 16) & 0xFF) / 255,
                  green: Double((rgb >> 8) & 0xFF) / 255,
                  blue: Double(rgb & 0xFF) / 255)
    }
}
