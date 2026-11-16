import SwiftUI
import RPMKit

/// What a profile page is drawn on (``RPMProfile/pageGround``): a solid colour, or one of the
/// app's backgrounds. An empty or unknown value is the app's standard background, not the reader's
/// own choice: a person's page looks the same to everyone.
struct PageGroundView: View {
    let wire: String

    var body: some View {
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
