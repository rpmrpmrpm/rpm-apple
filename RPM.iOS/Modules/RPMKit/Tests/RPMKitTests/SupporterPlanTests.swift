import Testing
@testable import RPMKit

/// The plan that the glass colour follows while the app is open. Each test makes its own plan,
/// because `SupporterPlan.shared` is the app's.
@MainActor
struct SupporterPlanTests {
    @Test func itStartsFromWhatItIsGiven() {
        #expect(SupporterPlan(isSupporter: true).isSupporter)
        #expect(!SupporterPlan(isSupporter: false).isSupporter)
    }

    /// A new supporter gets the colour at once, unlike the gold ground, which waits for the next
    /// launch.
    @Test func everyAnswerChangesItAtOnce() {
        let plan = SupporterPlan(isSupporter: false)

        plan.heard(true)
        #expect(plan.isSupporter)

        plan.heard(false)
        #expect(!plan.isSupporter)
    }
}
