import Testing
import Foundation
import AVFAudio
@testable import RPMAudio

// The equaliser: the filter pinned to the desktop's own cases (RPM.Core.Tests/EqualizerTests.cs), as
// the Android phone pins its port, then the presets, the stored curve, the speakers a curve belongs
// to, and the stage the pump runs.

private let rate = 44100.0

/// `frames` samples of a sine at `hz`, for one channel.
private func tone(_ hz: Double, frames: Int, amplitude: Double = 0.5, sampleRate: Double = rate) -> [Float] {
    (0..<frames).map { Float(amplitude * sin(2 * Double.pi * hz * Double($0) / sampleRate)) }
}

/// RMS of the back half, so the filter's start does not change the reading.
private func settledRms(_ samples: [Float]) -> Double {
    let from = samples.count / 2
    let sum = samples[from...].reduce(0.0) { $0 + Double($1) * Double($1) }
    return (sum / Double(samples.count - from)).squareRoot()
}

private func rms(_ samples: [Float]) -> Double {
    (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
}

private func gains(_ band: Int, _ db: Double) -> [Double] {
    Equalizer.bands.indices.map { $0 == band ? db : 0 }
}

/// Runs `samples` of channel `channel` through `eq`.
private func run(_ eq: inout Equalizer, _ samples: inout [Float], channel: Int = 0) {
    let frames = samples.count
    samples.withUnsafeMutableBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        eq.process(base, frames: frames, channel: channel)
    }
}

private func level(at hz: Double, band: Int, db: Double, sampleRate: Double = rate) -> Double {
    var eq = Equalizer(sampleRate: sampleRate, channels: 1)!
    eq.setGains(preamp: 0, bands: gains(band, db))
    var samples = tone(hz, frames: Int(sampleRate) / 2, sampleRate: sampleRate)
    let before = settledRms(samples)
    run(&eq, &samples)
    return settledRms(samples) / before
}

// ── bypass ──

@Test func aFlatEqualiserIsBypassedAndLeavesTheSignalUntouched() {
    var eq = Equalizer(sampleRate: rate, channels: 2)!
    #expect(eq.isBypassed)
    var samples = tone(1000, frames: 512)
    let original = samples
    run(&eq, &samples)
    #expect(samples == original)
}

@Test func anyBandOrThePreampAloneLeavesBypass() {
    var eq = Equalizer(sampleRate: rate, channels: 2)!
    eq.setGains(preamp: 0, bands: gains(4, 6))
    #expect(!eq.isBypassed)
    eq.setGains(preamp: 3, bands: gains(-1, 0))
    #expect(!eq.isBypassed)
    eq.setGains(preamp: 0, bands: gains(-1, 0))
    #expect(eq.isBypassed)
}

// ── band gain ──

@Test func boostingABandMakesAToneAtThatFrequencyLouder() {
    #expect(level(at: 1000, band: 4, db: 12) > 1.5)
}

@Test func cuttingABandMakesAToneAtThatFrequencyQuieter() {
    #expect(level(at: 1000, band: 4, db: -12) < 0.7)
}

@Test func boostingOneBandBarelyTouchesADistantFrequency() {
    #expect(abs(level(at: 10000, band: 0, db: 12) - 1) < 0.15)
}

@Test func everyBandRespondsAtItsOwnCentreFrequency() {
    for (band, hz) in Equalizer.bands.enumerated() {
        #expect(level(at: hz, band: band, db: 12) > 1.3, "band \(hz) Hz")
    }
}

@Test func atTheCentreABandGivesItsOwnGain() {
    // +6 dB is twice the amplitude.
    #expect(abs(level(at: 1000, band: 4, db: 6) - 2) < 0.05)
}

// ── pre-amp and clipping ──

@Test func aNegativePreampAttenuatesTheWholeSignal() {
    var eq = Equalizer(sampleRate: rate, channels: 2)!
    eq.setGains(preamp: -6, bands: gains(-1, 0))
    var samples = tone(440, frames: 4096)
    let before = rms(samples)
    run(&eq, &samples)
    #expect(abs(rms(samples) / before - 0.5) < 0.1)
}

@Test func theOutputIsHeldToFullScale() {
    var eq = Equalizer(sampleRate: rate, channels: 2)!
    eq.setGains(preamp: 12, bands: Equalizer.bands.map { _ in 12 })
    var samples = tone(1000, frames: 4096, amplitude: 0.9)
    run(&eq, &samples)
    #expect(samples.allSatisfy { $0 >= -1 && $0 <= 1 })
}

@Test func gainsAreHeldToTwelveDecibels() {
    let sane = level(at: 1000, band: 4, db: 12)
    let wild = level(at: 1000, band: 4, db: 40)
    #expect(abs(sane - wild) < 1e-3)
}

// ── state ──

@Test func resetClearsTheFilterMemorySoTheSameInputGivesTheSameOutput() {
    var eq = Equalizer(sampleRate: rate, channels: 2)!
    eq.setGains(preamp: 0, bands: gains(0, 12))
    var first = tone(60, frames: 2048)
    run(&eq, &first)
    eq.reset()
    var second = tone(60, frames: 2048)
    run(&eq, &second)
    #expect(first == second)
}

@Test func eachChannelHasItsOwnMemoryAndIdenticalChannelsStayIdentical() {
    var eq = Equalizer(sampleRate: rate, channels: 2)!
    eq.setGains(preamp: 2, bands: EqPreset.all[1].gains)
    var left = tone(300, frames: 2048)
    var right = left
    run(&eq, &left, channel: 0)
    run(&eq, &right, channel: 1)
    #expect(left == right)
}

@Test func sixChannelsAreFilteredAsSix() {
    var eq = Equalizer(sampleRate: 48000, channels: 6)!
    eq.setGains(preamp: 0, bands: gains(5, 12))
    var first = tone(3000, frames: 4800, sampleRate: 48000)
    var last = first
    let before = settledRms(first)
    run(&eq, &first, channel: 0)
    run(&eq, &last, channel: 5)
    #expect(settledRms(first) / before > 1.5)
    #expect(first == last)
}

@Test func aSampleRateTooLowOrTooManyChannelsAreRefused() {
    #expect(Equalizer(sampleRate: 4000, channels: 2) == nil)
    #expect(Equalizer(sampleRate: rate, channels: 9) == nil)
    #expect(Equalizer(sampleRate: rate, channels: 0) == nil)
}

// ── streams below 44.1 kHz ──

@Test func bandsPastWhatASlowStreamCanCarryAreLeftFlatAndStayStable() {
    // At 22.05 kHz the 12, 14 and 16 kHz bands lie past the highest frequency (11.025 kHz). Boosted,
    // the cookbook filter would grow without end; left flat, the signal stays as it was.
    var eq = Equalizer(sampleRate: 22050, channels: 1)!
    eq.setGains(preamp: 0, bands: [0, 0, 0, 0, 0, 0, 0, 12, 12, 12])
    #expect(!eq.isBypassed)
    var samples = tone(5000, frames: 22050, sampleRate: 22050)
    let original = samples
    run(&eq, &samples)
    #expect(samples.allSatisfy { $0.isFinite })
    #expect(zip(samples, original).allSatisfy { abs($0 - $1) < 1e-6 })
}

@Test func theBandLabelsAreTheDesktops() {
    #expect(Equalizer.bands.map { Equalizer.label($0) }
            == ["60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K"])
}

// ── presets ──

@Test func thePresetsAreTheDesktopsInItsOrder() {
    #expect(EqPreset.all.count == 8)
    #expect(EqPreset.all.allSatisfy { $0.gains.count == Equalizer.bands.count })
    #expect(EqPreset.all[0].gains == Array(repeating: 0, count: 10))
    #expect(EqPreset.all[5].gains == [7, 6, 5, 3, 1, 0, 0, 0, 0, 0])
    #expect(EqPreset.all.map(\.nameKey) == ["Eq_Flat", "Eq_Rock", "Eq_Pop", "Eq_Jazz", "Eq_Classical",
                                            "Eq_BassBoost", "Eq_Treble", "Eq_Vocal"])
}

@Test func aPresetSetsTheBandsAndLeavesTheSwitchAndThePreamp() {
    let curve = EqCurve.off.withPreamp(-4).withPreset(EqPreset.all[5])
    #expect(!curve.on)
    #expect(curve.preamp == -4)
    #expect(curve.preset == EqPreset.all[5])
    #expect(curve.withBand(0, 3).preset == nil)
}

@Test func flatClearsTheBandsAndThePreampAndKeepsTheSwitch() {
    let curve = EqCurve.off.turned(true).withPreamp(-3).withPreset(EqPreset.all[1]).flattened()
    #expect(curve.on)
    #expect(curve == EqCurve.off.turned(true))
    #expect(curve.preset == EqPreset.all[0])
}

@Test func movesAreHeldToTheRange() {
    let curve = EqCurve.off.withBand(2, 20).withPreamp(-30).withBand(99, 5)
    #expect(curve.gains[2] == 12)
    #expect(curve.preamp == -12)
    #expect(curve.gains.count == 10)
}

// ── stored ──

@Test func aCurveReadsBackAsItWasStored() {
    let curve = EqCurve(on: true, preamp: -3.5, gains: [5, 4, 2, 0, -1, 0, 2, 4, 5, 5])
    #expect(EqCurve.parse(curve.stored) == curve)
    #expect(EqCurve.parse(EqCurve.off.stored) == EqCurve.off)
}

@Test func anythingUnreadableIsOff() {
    #expect(EqCurve.parse(nil) == .off)
    #expect(EqCurve.parse("") == .off)
    #expect(EqCurve.parse("1;x;0,0,0,0,0,0,0,0,0,0") == .off)
    #expect(EqCurve.parse("1;0;0,0,0") == .off)
    #expect(EqCurve.parse("1;NaN;0,0,0,0,0,0,0,0,0,0") == .off)
}

@Test func aStoredValueOutOfRangeIsHeldToIt() {
    let curve = EqCurve.parse("1;40;99,0,0,0,0,0,0,0,0,-99")
    #expect(curve.on)
    #expect(curve.preamp == 12)
    #expect(curve.gains[0] == 12)
    #expect(curve.gains[9] == -12)
}

// ── whose curve ──

@Test func thePhonesSpeakerHasOneCurveWhateverItIsCalled() {
    #expect(EqOutput.pick(kind: .speaker, name: "Speaker", casting: false).key == "speaker")
    #expect(EqOutput.pick(kind: .speaker, name: "Receiver", casting: false).key == "speaker")
    #expect(EqOutput.pick(kind: .speaker, name: "Speaker", casting: false).label == "Speaker")
}

@Test func eachHeadphoneHasItsOwnCurve() {
    let one = EqOutput.pick(kind: .bluetooth, name: "AirPods Pro", casting: false)
    let two = EqOutput.pick(kind: .bluetooth, name: "Sony WH-1000XM5", casting: false)
    #expect(one.key == "bluetooth:AirPods Pro")
    #expect(one.key != two.key)
    #expect(EqOutput.pick(kind: .wired, name: "Headphones", casting: false).key == "wired:Headphones")
}

@Test func castingAndAirPlayShareTheCastCurve() {
    #expect(EqOutput.pick(kind: .bluetooth, name: "AirPods Pro", casting: true) == .cast)
    #expect(EqOutput.pick(kind: .airPlay, name: "Living room", casting: false) == .cast)
    #expect(EqOutput.cast.casting)
    #expect(EqOutput.cast.label == nil)
}

// ── the stage the pump runs ──

private func buffer(_ samples: [Float]) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
    let made = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
    made.frameLength = AVAudioFrameCount(samples.count)
    for channel in 0..<2 {
        for (at, sample) in samples.enumerated() { made.floatChannelData![channel][at] = sample }
    }
    return made
}

private func channel(_ buffer: AVAudioPCMBuffer, _ channel: Int) -> [Float] {
    Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
}

@Test func aCurveThatIsOffLeavesTheSoundAlone() {
    var stage = EqStage()
    let samples = tone(60, frames: 2048)
    let block = buffer(samples)
    stage.apply(EqCurve.off.withPreset(EqPreset.all[5]), to: block, source: 0)
    #expect(channel(block, 0) == samples)
}

@Test func aCurveThatIsOnChangesBothChannelsAlike() {
    var stage = EqStage()
    let samples = tone(60, frames: 4096)
    let block = buffer(samples)
    stage.apply(EqCurve.off.withPreset(EqPreset.all[5]).turned(true), to: block, source: 0)
    #expect(settledRms(channel(block, 0)) > settledRms(samples) * 1.5)
    #expect(channel(block, 0) == channel(block, 1))
}

@Test func aNewSourceStartsFromClearFilterMemory() {
    let curve = EqCurve.off.withPreset(EqPreset.all[5]).turned(true)
    var stage = EqStage()
    let samples = tone(60, frames: 2048)
    let first = buffer(samples)
    stage.apply(curve, to: first, source: 0)
    let second = buffer(samples)
    stage.apply(curve, to: second, source: 1)
    #expect(channel(first, 0) == channel(second, 0))
}
