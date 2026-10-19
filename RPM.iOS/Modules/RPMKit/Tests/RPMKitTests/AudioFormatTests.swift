import Testing
import Foundation
@testable import RPMKit

/// **The one that matters.** `.m4a` carries either AAC or Apple Lossless, and calling
/// a lossless rip "AAC" is exactly the wrong way round. Only what the decoder said
/// can tell them apart.
@Test func anAppleLosslessRipIsNotCalledAac() {
    #expect(AudioFormat.codec(extension: ".m4a", description: "MPEG-4 Audio (alac)") == "ALAC")
    #expect(AudioFormat.codec(extension: ".m4a", description: "Apple Lossless") == "ALAC")
    #expect(AudioFormat.codec(extension: ".m4a") == "AAC")
}

/// "eac3" contains "ac3", so the wider one is asked first.
@Test func dolbyInsideAnM4aIsNotAac() {
    #expect(AudioFormat.codec(extension: ".m4a", description: "MPEG-4 (ec-3)") == "Dolby Digital Plus")
    #expect(AudioFormat.codec(extension: ".m4a", description: "eac3 5.1") == "Dolby Digital Plus")
    #expect(AudioFormat.codec(extension: ".m4a", description: "ac-3 surround") == "Dolby Digital")
}

@Test func theOrdinaryExtensionsAnswerForThemselves() {
    #expect(AudioFormat.codec(extension: ".flac") == "FLAC")
    #expect(AudioFormat.codec(extension: "flac") == "FLAC")
    #expect(AudioFormat.codec(extension: ".FLAC") == "FLAC")
    #expect(AudioFormat.codec(extension: ".mp3") == "MP3")
    #expect(AudioFormat.codec(extension: ".dsf") == "DSD")
}

@Test func somethingThisDoesNotKnowIsNotGuessedAt() {
    #expect(AudioFormat.codec(extension: ".xyz") == nil)
    #expect(AudioFormat.codec(extension: "") == nil)
    #expect(AudioFormat.codec(extension: nil) == nil)
    #expect(AudioFormat.codec(extension: "   ") == nil)
}

// ── the layout ──

/// A badge every record wears is not a badge.
@Test func stereoIsSaidBySayingNothing() {
    #expect(AudioFormat.channels(2) == nil)
    #expect(AudioFormat.channels(0) == nil)
}

@Test func surroundIsSaidTheWayPeopleSayIt() {
    #expect(AudioFormat.channels(6) == "5.1")
    #expect(AudioFormat.channels(8) == "7.1")
    #expect(AudioFormat.channels(1) == "Mono")
    #expect(AudioFormat.channels(12) == "7.1.4")
}

@Test func aCountNobodyHasANameForGetsNoName() {
    #expect(AudioFormat.channels(9) == nil)
    #expect(AudioFormat.channels(64) == nil)
}

// ── how good it is ──

/// Each kind is asked the question it can answer: a lossless file by its resolution,
/// a lossy one by its bitrate.
@Test func aLosslessFileIsJudgedByItsResolution() {
    #expect(AudioFormat.quality(codec: "FLAC", bitsPerSample: 16, sampleRate: 44100,
                                bitrateKbps: 900) == "16/44.1")
    #expect(AudioFormat.quality(codec: "FLAC", bitsPerSample: 24, sampleRate: 96000,
                                bitrateKbps: 0) == "24/96")
}

/// 44.1 keeps its decimal; 48 and 96 do not grow one.
@Test func aRoundSampleRateDoesNotGrowADecimal() {
    #expect(AudioFormat.quality(codec: "ALAC", bitsPerSample: 16, sampleRate: 48000,
                                bitrateKbps: 0) == "16/48")
    #expect(AudioFormat.quality(codec: "ALAC", bitsPerSample: 24, sampleRate: 88200,
                                bitrateKbps: 0) == "24/88.2")
}

@Test func aLossyFileIsJudgedByItsBitrate() {
    #expect(AudioFormat.quality(codec: "MP3", bitsPerSample: 16, sampleRate: 44100,
                                bitrateKbps: 320) == "320 kbps")
}

/// A lossless stream nobody measured says nothing rather than a bitrate nobody chose.
@Test func aLosslessFileWithNoDepthSaysNothing() {
    #expect(AudioFormat.quality(codec: "FLAC", bitsPerSample: 0, sampleRate: 44100,
                                bitrateKbps: 900) == nil)
}

// ── the whole line ──

@Test func aSleeveLineIsCodecThenQualityThenLayout() {
    #expect(AudioFormat.describe(extension: ".flac", channels: 6, bitsPerSample: 24,
                                 sampleRate: 96000) == ["FLAC", "24/96", "5.1"])
}

@Test func whatIsNotKnownIsLeftOut() {
    #expect(AudioFormat.describe(extension: ".flac", channels: 2) == ["FLAC"])
    #expect(AudioFormat.describe(extension: nil, channels: 6) == ["5.1"])
    #expect(AudioFormat.describe(extension: nil, channels: 2).isEmpty)
}

// ── off a catalogue row ──

@Test func aRowWithNoFormatSaysNothingAtAll() {
    var tags = CloudTrackTags()
    #expect(!tags.hasFormat)
    #expect(tags.format.isEmpty)

    tags.bitrateKbps = 320   // Not enough on its own: nothing says what the file is.
    #expect(tags.format.isEmpty)
}

@Test func aBackfilledRowDescribesItself() {
    var tags = CloudTrackTags()
    tags.extension = ".flac"
    tags.channels = 2
    tags.bitsPerSample = 16
    tags.sampleRate = 44100

    #expect(tags.format == ["FLAC", "16/44.1"])
}
