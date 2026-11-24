#if os(iOS)
import RPMKit
import StoreKit
import SwiftUI

/// The sheet for becoming a supporter: Apple's subscription view for the group "Supporter (rpm)",
/// with rpm's header above it.
///
/// Apple's view lists the week, month and year subscriptions with the local prices, and shows the
/// renewal terms, Restore, and the links to the terms and the privacy page that App Review checks
/// for. Every purchase carries the account's id (`appAccountToken`), so the accounts service knows
/// whose support it is. The sheet closes when the service has confirmed the purchase.
public struct SupporterSheet: View {
    private let account: UUID
    private let onPurchase: (VerificationResult<StoreKit.Transaction>) async -> SupporterPost?

    /// A line under the header when a purchase did not end in support: pending, another account's
    /// subscription, or not confirmed yet.
    @State private var note: String?
    @Environment(\.dismiss) private var dismiss

    /// - Parameters:
    ///   - account: the signed-in account's id (its Cognito `sub`).
    ///   - onPurchase: sends the purchase to the accounts service and says how it answered.
    public init(account: UUID, onPurchase: @escaping (VerificationResult<StoreKit.Transaction>) async -> SupporterPost?) {
        self.account = account
        self.onPurchase = onPurchase
    }

    public var body: some View {
        SubscriptionStoreView(groupID: SupporterStore.groupID) {
            header
        }
        .storeButton(.visible, for: .restorePurchases)
        .subscriptionStorePolicyDestination(url: RpmSite.terms, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: RpmSite.privacy, for: .privacyPolicy)
        .inAppPurchaseOptions { [account] _ in [.appAccountToken(account)] }
        .onInAppPurchaseCompletion { _, result in
            guard case .success(let purchase) = result else { return }
            switch purchase {
            case .success(let verification):
                switch await onPurchase(verification) {
                case .confirmed?: dismiss()
                case .otherAccount?: note = Loc.get("Supporter_OtherAccount")
                default: note = Loc.get("Supporter_PurchaseFailed")
                }
            case .pending:
                note = Loc.get("Supporter_PurchasePending")
            default:
                // Cancelled by the person. StoreKit shows its own message for a failure.
                break
            }
        }
        .background(RPMInk.ground)
        .preferredColorScheme(.dark)
    }

    /// The same list of what supporters get as the Android TV set-up and the desktop.
    private static let perks = [
        "Supporter_PerkStorage", "Supporter_PerkBitrate", "Supporter_PerkRecognition", "Supporter_PerkDj",
        "Supporter_PerkKaraoke", "Supporter_PerkBackdrop", "Supporter_PerkBadge", "Supporter_PerkCommunity",
    ]

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Loc.get("Cloud_BecomeSupporter"))
                .font(RPMFont.display(26))
                .foregroundStyle(.white)
            Text(Loc.get("Supporter_StoreBody"))
                .font(RPMFont.display(15))
                .foregroundStyle(RPMInk.white(0xCC / 255))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Self.perks, id: \.self) { key in
                    HStack(spacing: 10) {
                        Text(Glyph.check)
                            .font(RPMFont.icon(12))
                            .foregroundStyle(RPMInk.gold)
                            .frame(width: 18)
                        Text(Loc.get(key))
                            .font(RPMFont.display(14))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(.top, 4)

            if let note {
                Text(note)
                    .font(RPMFont.display(14))
                    .foregroundStyle(RPMInk.gold)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 28)
    }
}
#endif
