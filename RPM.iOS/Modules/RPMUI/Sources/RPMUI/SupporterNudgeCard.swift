import SwiftUI
import RPMKit

/// The supporter pop-up: a small glass card in the middle of the dimmed screen that asks a listener who does not pay to
/// consider becoming a supporter. When it shows is decided by `SupporterNudge` (RPMDesign).
///
/// It is drawn over the app like ``ReportSheet``, and not as a system alert, so it has the app's own look. A tap on the
/// dim around the card, or Not now, closes it.
public struct SupporterNudgeCard: View {
    private let onSupport: () -> Void
    private let onClose: () -> Void

    /// - Parameters:
    ///   - onSupport: the key Become a supporter. The caller closes the card and opens the subscription sheet
    ///     (``SupporterSheet``).
    ///   - onClose: Not now, or a tap outside the card.
    public init(onSupport: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onSupport = onSupport
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0xB3 / 255)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(spacing: 14) {
                Text(Loc.get("Supporter_NudgeTitle"))
                    .font(RPMFont.displayBold(19))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(Loc.get("Supporter_NudgeBody"))
                    .font(RPMFont.display(14))
                    .foregroundStyle(RPMInk.white(0xCC / 255))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                // One key under the other: in some languages Become a supporter is too long to share a row.
                Button(Loc.get("Cloud_BecomeSupporter"), action: onSupport)
                    .buttonStyle(RPMGlassButton(.primary))

                Button(Loc.get("Supporter_Later"), action: onClose)
                    .buttonStyle(RPMGlassButton(.ghost))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(width: 330)
            .rpmGlassCard(radius: 18)
        }
    }
}
