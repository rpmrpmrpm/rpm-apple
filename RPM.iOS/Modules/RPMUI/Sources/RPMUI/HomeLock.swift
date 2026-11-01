import SwiftUI
import RPMKit
import RPMLibrary

/// Replaces the home screen until there is enough music for it to be useful.
///
/// With fewer than 20 albums, the Recently added row is the whole collection in a different
/// order, and the suggestions can only offer records that are already on the screen above them.
/// So the screen shows what it is waiting for and how much is still needed, and does not draw
/// four rows of the same fifteen records. There is no button: music is added in rpm on the
/// computer, not on the phone, so the text says where to add it.
struct HomeLock: View {
    let gate: FeatureGate

    /// The owner of the collection on screen, or nil for the person's own. Only the owner can
    /// add music, so a shared collection does not say how.
    let lender: String?

    var body: some View {
        VStack(spacing: 14) {
            Text(Loc.get("Home_Heading"))
                .font(RPMFont.displayBold(26))

            Text(line)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            // An empty collection has nothing to measure. Its line says how to fill it.
            if gate.have > 0 {
                progress
            }
        }
        .padding(.horizontal, RPMLayout.margin)
    }

    private var line: String {
        switch (gate.have > 0, lender == nil) {
        case (false, true): Loc.get("Rpm_Library_Empty")
        case (false, false): Loc.get("Rpm_Share_EmptyShelf")
        case (true, true): Loc.get("Rpm_HomeLock_Body")
        case (true, false): Loc.get("HomeLock_Body")
        }
    }

    private var progress: some View {
        VStack(spacing: 12) {
            // The bar shows the amount at a glance. The line below gives the exact numbers.
            GeometryReader { box in
                ZStack(alignment: .leading) {
                    Capsule().fill(RPMInk.glassWash)
                    Capsule()
                        .fill(RPMInk.white(0xB8 / 255))
                        .frame(width: max(2, box.size.width * gate.fraction))
                }
            }
            .frame(width: 220, height: 4)

            Text(Loc.get("HomeLock_Progress", gate.have, gate.want))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }
}
