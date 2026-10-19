import Testing
import Foundation
@testable import RPMKit

/// The value a .NET clock reports for the unix epoch. If this is wrong, every
/// favourite this phone writes is nineteen centuries out and the store takes it
/// without a word.
@Test func theUnixEpochIsTheNumberDotNetSaysItIs() {
    #expect(UtcTicks.of(Date(timeIntervalSince1970: 0)) == 621_355_968_000_000_000)
}

@Test func aMomentSurvivesTheRoundTrip() {
    let moment = Date(timeIntervalSince1970: 1_772_000_000)
    #expect(abs(UtcTicks.date(UtcTicks.of(moment)).timeIntervalSince(moment)) < 0.001)
}

@Test func nowIsNow() {
    let ticks = UtcTicks.now
    #expect(abs(UtcTicks.date(ticks).timeIntervalSinceNow) < 2)
}

/// Ticks are hundred-nanosecond intervals, so a second is ten million of them,
/// which is the digit that is easiest to get wrong by a factor of a thousand.
@Test func aSecondIsTenMillionOfThem() {
    let one = Date(timeIntervalSince1970: 1_000_000)
    let two = Date(timeIntervalSince1970: 1_000_001)
    #expect(UtcTicks.of(two) - UtcTicks.of(one) == 10_000_000)
}
