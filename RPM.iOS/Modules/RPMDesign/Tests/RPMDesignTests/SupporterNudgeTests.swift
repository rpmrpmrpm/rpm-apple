import Testing
@testable import RPMDesign

/// When the supporter pop-up shows: every 50th launch for an account that does not pay, every 100th for a closed
/// beta tester, never for a paying supporter, never while the plan is not known. The Android app's
/// `SupporterNudgeTest` asks the same.
@Suite("The supporter pop-up")
struct SupporterNudgeTests {
    @Test("every 50th launch of an account that does not pay")
    func fiftieth() {
        #expect(!SupporterNudge.due(launch: 49, plan: .free))
        #expect(SupporterNudge.due(launch: 50, plan: .free))
        #expect(!SupporterNudge.due(launch: 51, plan: .free))
        #expect(SupporterNudge.due(launch: 100, plan: .free))
        #expect(SupporterNudge.due(launch: 150, plan: .free))
    }

    @Test("every 100th launch of a closed beta tester")
    func hundredth() {
        #expect(!SupporterNudge.due(launch: 50, plan: .tester))
        #expect(!SupporterNudge.due(launch: 99, plan: .tester))
        #expect(SupporterNudge.due(launch: 100, plan: .tester))
        #expect(!SupporterNudge.due(launch: 150, plan: .tester))
        #expect(SupporterNudge.due(launch: 200, plan: .tester))
    }

    @Test("never for a paying supporter", arguments: [49, 50, 51, 100])
    func supporter(launch: Int) {
        #expect(!SupporterNudge.due(launch: launch, plan: .pays))
    }

    @Test("never while the plan is not known", arguments: [49, 50, 51, 100])
    func unknown(launch: Int) {
        #expect(!SupporterNudge.due(launch: launch, plan: nil))
    }

    @Test("a tester is a tester whatever the supporter flag says")
    func plans() {
        #expect(SupporterNudge.Plan.of(supporter: true, tester: true) == .tester)
        #expect(SupporterNudge.Plan.of(supporter: false, tester: true) == .tester)
        #expect(SupporterNudge.Plan.of(supporter: true, tester: false) == .pays)
        #expect(SupporterNudge.Plan.of(supporter: false, tester: false) == .free)
    }

    @Test("no launch counted is not a launch that shows")
    func none() {
        #expect(!SupporterNudge.onLaunch(0))
        #expect(!SupporterNudge.due(launch: 0, plan: .free))
        #expect(!SupporterNudge.due(launch: 0, plan: .tester))
    }
}
