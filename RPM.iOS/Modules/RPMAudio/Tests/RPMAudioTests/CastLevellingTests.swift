import Foundation
import Testing
import RPMCast
@testable import RPMAudio

/// **A record on a speaker is levelled the same way as on the phone.**
///
/// Casting does not use the handset's audio graph. The samples go to the speaker straight from
/// the decoder. So the pump applies the gain before the audio is split between the handset and
/// the room, and the room receives levelled audio.
@Suite("Levelling on a speaker")
struct CastLevellingTests {
    /// A track measured at −12 LUFS plays at −6 dB against the −18 reference. Its peak
    /// is well under the ceiling, so nothing limits the gain.
    private let loud = SourceLoudness(track: Level(lufs: -12, truePeak: 0.25),
                                      album: .unknown, inAlbumOrder: false, albumIsClassical: false)

    /// The loudest sample of the first second the room was handed, as a fraction of full
    /// scale.
    private func peakHandedToTheRoom(_ setting: NormalizeContext,
                                     _ loudness: SourceLoudness) async throws -> Double {
        let engine = PcmEngine(normalize: setting)

        // Enough space that the room never makes the pump wait.
        let ring = PcmRing(seconds: 30)
        let room = RoomFeed(ring: ring, named: "a speaker")
        defer { room.release(); engine.stop() }

        let url = try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
        let feed = StreamedPcm()
        try feed.take(try Data(contentsOf: url))
        feed.finish(.theFileRanOut)

        // The room first, so the handset's own device is never started.
        engine.send(to: room, from: 0)
        try engine.play(feed, loudness: loudness, because: .somebodyAskedForIt)

        let second = 44100 * 4
        let end = ContinuousClock.now.advanced(by: .seconds(10))
        while ring.held < second, ContinuousClock.now < end {
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(ring.held >= second, "the room was handed \(ring.held) bytes")

        let bytes = ring.read(upTo: second)
        var peak: Int16 = 0
        for at in stride(from: 0, to: bytes.count - 1, by: 2) {
            let value = Int16(bitPattern: UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8)
            peak = max(peak, value == .min ? .max : abs(value))
        }
        return Double(peak) / 32767
    }

    @Test func aMeasuredRecordReachesTheRoomLevelled() async throws {
        let asMastered = try await peakHandedToTheRoom(NormalizeContext(mode: .track), .unmeasured)
        let levelled = try await peakHandedToTheRoom(NormalizeContext(mode: .track), loud)

        #expect(asMastered > 0.05, "the fixture is a tone, and read \(asMastered)")

        let ratio = levelled / asMastered
        #expect(abs(ratio - 0.501) < 0.01, "−6 dB is ×0.501, and the room got ×\(ratio)")
    }

    /// With levelling off, the room gets the mastered level, whatever the record measured.
    @Test func levellingOffLeavesTheRoomAtTheMasteredLevel() async throws {
        let asMastered = try await peakHandedToTheRoom(NormalizeContext(mode: .off), .unmeasured)
        let off = try await peakHandedToTheRoom(NormalizeContext(mode: .off), loud)

        #expect(abs(off / asMastered - 1) < 0.001)
    }
}
