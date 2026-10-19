import SwiftUI
import RPMKit
import RPMLibrary

/// Replaces the home screen until there is enough music for it to be useful.
///
/// With fewer than 20 albums, the Recently added row is the whole collection in a different
/// order, and the suggestions can only offer records that are already on the screen above them.
/// So the screen shows what it is waiting for and how much is still needed, and does not draw
/// four rows of the same fifteen records.
struct HomeLock: View {
    let gate: FeatureGate
    let onAddMusic: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text(Loc.get("HomeLock_Kicker"))
                .font(RPMFont.display(12))
                .tracking(2)
                .foregroundStyle(RPMInk.white(0x99 / 255))

            Text(Loc.get("Home_Heading"))
                .font(RPMFont.displayBold(26))

            Text(Loc.get("HomeLock_Body"))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            progress

            Button(action: onAddMusic) {
                Text(Loc.get("HomeLock_AddMusic"))
                    .font(.system(size: 15, weight: .medium))
                    .padding(.horizontal, RPMLayout.margin)
                    .frame(height: 44)
                    .contentShape(Capsule())
                    .rpmGlass(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, RPMLayout.margin)
    }

    private var progress: some View {
        VStack(spacing: 6) {
            // The bar shows the amount at a glance. The sentences below give the exact numbers.
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

            Text(gate.toGo == 1
                 ? Loc.get("HomeLock_ToGoOne")
                 : Loc.get("HomeLock_ToGo", gate.toGo))
                .font(.system(size: 12))
                .foregroundStyle(RPMInk.white(0x99 / 255))
        }
        .padding(.top, 6)
    }
}
