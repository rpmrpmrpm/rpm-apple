import Testing
@testable import RPMDesign

/// When the supporter pop-up shows: every 50th launch, never for a supporter, never while the plan is not known.
/// The Android app's `SupporterNudgeTest` asks the same.
@Suite("The supporter pop-up")
struct SupporterNudgeTests {
    @Test("every 50th launch of an account that does not pay")
    func fiftieth() {
        #expect(!SupporterNudge.due(launch: 49, supporter: false))
        #expect(SupporterNudge.due(launch: 50, supporter: false))
        #expect(!SupporterNudge.due(launch: 51, supporter: false))
        #expect(SupporterNudge.due(launch: 100, supporter: false))
        #expect(SupporterNudge.due(launch: 150, supporter: false))
    }

    @Test("never for a supporter", arguments: [49, 50, 51, 100])
    func supporter(launch: Int) {
        #expect(!SupporterNudge.due(launch: launch, supporter: true))
    }

    @Test("never while the plan is not known", arguments: [49, 50, 51, 100])
    func unknown(launch: Int) {
        #expect(!SupporterNudge.due(launch: launch, supporter: nil))
    }

    @Test("no launch counted is not a launch that shows")
    func none() {
        #expect(!SupporterNudge.onLaunch(0))
        #expect(!SupporterNudge.due(launch: 0, supporter: false))
    }
}
