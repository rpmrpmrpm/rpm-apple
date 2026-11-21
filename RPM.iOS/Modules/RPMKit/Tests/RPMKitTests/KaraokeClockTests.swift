import Foundation
import Testing
@testable import RPMKit

private func near(_ a: Double, _ b: Double, _ within: Double = 1e-9) -> Bool { abs(a - b) <= within }

@Test func theClockFollowsAnEvenPosition() {
    let clock = KaraokeClock()
    #expect(near(clock.seconds(reported: 10.0, advancing: true, at: 1.0), 10.0))
    #expect(near(clock.seconds(reported: 10.5, advancing: true, at: 1.5), 10.5))
    #expect(near(clock.seconds(reported: 12.0, advancing: true, at: 3.0), 12.0))
}

@Test func aStepBackIsTakenUpSlowlyAndTheClockNeverGoesBack() {
    let clock = KaraokeClock()
    _ = clock.seconds(reported: 10.0, advancing: true, at: 0)
    var last = 10.0
    // From here the player reports 0.2 s less than the clock carries it to.
    for frame in 1...300 {
        let now = Double(frame) * 0.016
        let shown = clock.seconds(reported: 10.0 + now - 0.2, advancing: true, at: now)
        #expect(shown >= last)
        last = shown
    }
    // After almost five seconds the step is taken up.
    #expect(near(last, 10.0 + 300 * 0.016 - 0.2, 0.005))
}

@Test func aStepForwardIsTakenUpSlowly() {
    let clock = KaraokeClock()
    _ = clock.seconds(reported: 10.0, advancing: true, at: 0)
    // 0.2 s ahead after 0.1 s: the clock moves at most a twentieth faster.
    #expect(near(clock.seconds(reported: 10.3, advancing: true, at: 0.1), 10.105))
}

@Test func aSeekAndAPauseGoStraightThere() {
    let clock = KaraokeClock()
    _ = clock.seconds(reported: 10.0, advancing: true, at: 0)
    #expect(near(clock.seconds(reported: 60.0, advancing: true, at: 0.1), 60.0))
    #expect(near(clock.seconds(reported: 30.0, advancing: false, at: 0.2), 30.0))
}
