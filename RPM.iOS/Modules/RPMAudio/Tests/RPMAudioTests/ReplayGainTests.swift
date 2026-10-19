import Testing
import Foundation
import RPMKit
@testable import RPMAudio

@Test func aQuietRecordIsTurnedUpAndALoudOneDown() {
    #expect(ReplayGain.gainDb(lufs: -24) == 6)
    #expect(ReplayGain.gainDb(lufs: -12) == -6)
    #expect(ReplayGain.gainDb(lufs: -18) == 0)
}

@Test func aTrackNothingMeasuredIsLeftAlone() {
    #expect(ReplayGain.gainDb(lufs: -.infinity) == 0)
    #expect(ReplayGain.gainDb(lufs: .nan) == 0)
}

/// **The ceiling is a limit, not a target.** A quiet recording is not raised up to the ceiling.
/// That would undo the loudness difference that was measured.
@Test func aQuietTrackIsNotPushedUpToTheCeiling() {
    // Peaks at a tenth of full scale, so there is 19 dB of headroom, and the gain
    // asked for is only 6.
    #expect(ReplayGain.clamp(6, truePeak: 0.1) == 6)
}

/// A record mastered at full scale cannot take the boost its loudness asks for. This is the case
/// where the limit matters most.
@Test func aBoostIsHeldBackByWhatItWouldDoToThePeaks() {
    // The peak is at full scale, so there is no headroom. The ceiling is 1 dB below full scale.
    #expect(abs(ReplayGain.clamp(6, truePeak: 1.0) - (-1)) < 1e-9)

    // Already over full scale.
    let over = ReplayGain.clamp(6, truePeak: 1.2)
    #expect(over < -1)
}

@Test func nothingMovesFurtherThanFifteenDecibels() {
    #expect(ReplayGain.clamp(40, truePeak: 0) == 15)
    #expect(ReplayGain.clamp(-40, truePeak: 0) == -15)
}

/// A zero peak means the peak was not measured. It does not mean the track is silent. There is
/// nothing to clamp against, so the gain is kept.
@Test func anUnmeasuredPeakIsNotAClamp() {
    #expect(ReplayGain.clamp(6, truePeak: 0) == 6)
    #expect(ReplayGain.clamp(6, truePeak: -1) == 6)
}

@Test func aGainInDecibelsBecomesAMultiplier() {
    #expect(abs(ReplayGain.linear(0) - 1) < 1e-6)
    #expect(abs(ReplayGain.linear(6) - 1.9953) < 1e-3)
    #expect(abs(ReplayGain.linear(-6) - 0.5012) < 1e-3)
}

// ── a whole record ──

/// **Loudness does not average in decibels.** A record with one loud song and one
/// quiet one is not as loud as the midpoint of the two numbers.
@Test func aRecordIsNotTheMidpointOfItsSongs() {
    let mixed = ReplayGain.albumLufs([(lufs: -10, seconds: 100), (lufs: -30, seconds: 100)])

    #expect(mixed > -20, "the mean of the decibels would have been -20, got \(mixed)")
    #expect(mixed < -10)
}

/// A 40-second interlude counts for less than a 10-minute side.
@Test func aLongSideCountsForMoreThanAnInterlude() {
    let interludeLoud = ReplayGain.albumLufs([(lufs: -6, seconds: 40),
                                              (lufs: -20, seconds: 600)])
    #expect(interludeLoud < -15, "the short loud one dominated: \(interludeLoud)")
}

@Test func aRecordNothingMeasuredHasNoLevel() {
    #expect(ReplayGain.albumLufs([]) == -.infinity)
    #expect(ReplayGain.albumLufs([(lufs: -.infinity, seconds: 100)]) == -.infinity)
}
