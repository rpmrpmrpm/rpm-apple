import SwiftUI
import RPMKit

/// The one line this app shows about the network.
///
/// **It floats over the content and does not push it down.** The wall stays where it is and is
/// drawn from the copy stored on the phone. This bar explains why the covers have stopped
/// loading.
///
/// **It follows the settled reading.** `NetworkReach` waits a short time before it publishes an
/// offline path. A change from Wi-Fi to cellular, or a phone waking up, then does not show this
/// bar for a moment and hide it again.
public struct OfflineBar: View {
    private let showing: Bool

    /// A second line for screens where going offline changes what the user can do. After sign-in,
    /// only downloaded records can be played. Nil over the sign-in form.
    private let detail: String?

    public init(showing: Bool, detail: String?) {
        self.showing = showing
        self.detail = detail
    }

    public var body: some View {
        VStack {
            if showing {
                VStack(spacing: 2) {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.system(size: 12, weight: .semibold))

                        Text(Loc.get("Rpm_Net_Offline"))
                            .font(RPMFont.display(13))
                    }

                    if let detail {
                        Text(detail)
                            .font(RPMFont.display(11))
                            .foregroundStyle(RPMInk.white(0x99 / 255))
                    }
                }
                .foregroundStyle(RPMInk.white(0xCC / 255))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .rpmGlassCard(radius: 12)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: showing)
        // The bar is only a notice. It must never take a tap away from the row below it.
        .allowsHitTesting(false)
    }
}
