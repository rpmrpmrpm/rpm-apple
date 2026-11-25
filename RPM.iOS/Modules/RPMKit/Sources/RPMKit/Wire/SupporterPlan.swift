import Foundation
import Observation

/// Whether the account has the supporter features, as the cloud last said. The colour of the app's
/// glass follows it while the app is open (``GlassColour/value(on:supporter:)``).
///
/// It starts from the note that the last quota read left for the next launch
/// (``SupporterGround/remembered(in:)``), so a supporter's colour is there on the first frame. After
/// that it takes every answer the cloud gives (``heard(_:)``). A quota read that failed is no answer
/// and changes nothing, so a phone without a network does not take a supporter's colour away.
///
/// **It changes while the app is open, and the ground does not.** ``SupporterGround`` waits for the
/// next launch, because a background that changes under a screen looks like a fault. A colour is a
/// light wash over the glass, and a person who has just become a supporter should see the colour
/// they pick at once.
///
/// Observed: the faces read it in their bodies, so a new answer redraws them.
@MainActor
@Observable
public final class SupporterPlan {
    public static let shared = SupporterPlan(isSupporter: SupporterGround.remembered(in: .standard))

    /// Whether the account has the supporter features. False for an account that nobody has
    /// asked about yet, and after a sign-out.
    public private(set) var isSupporter: Bool

    init(isSupporter: Bool) {
        self.isSupporter = isSupporter
    }

    /// The cloud has answered: a quota read, or a sign-out (false). Called next to
    /// ``SupporterGround/adopt(isSupporter:in:)`` and ``SupporterGround/remember(isSupporter:in:)``.
    public func heard(_ isSupporter: Bool) {
        self.isSupporter = isSupporter
    }
}
