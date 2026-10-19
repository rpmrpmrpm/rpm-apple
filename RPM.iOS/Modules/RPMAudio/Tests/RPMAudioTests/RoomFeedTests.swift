import Foundation
import AVFAudio
import Testing
import RPMCast
@testable import RPMAudio

/// The room's position between its reports, which arrive four times a second.
///
/// **The estimate between reports is what the picture uses.** A status arrives every 250 ms. A
/// position drawn from the raw reports stays still for five reads and then jumps. That makes the
/// seek bar step, and the level bars flicker. The limits matter most. An estimate that runs past
/// what was handed over, moves backwards, or keeps going after the speaker stops answering is
/// worse than no estimate.
@Suite("Where the room has got to", .serialized)
struct RoomFeedTests {
    private static let block: AVAudioFrameCount = 8192
    private static let rate = StreamedPcm.engineFormat.sampleRate

    private func silence() -> AVAudioPCMBuffer {
        let format = StreamedPcm.engineFormat
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.block)!
        buffer.frameLength = Self.block
        return buffer
    }

    /// A room with `seconds` of audio already handed to it and nothing said yet.
    private func room(holding seconds: Double) async -> RoomFeed {
        let feed = RoomFeed(ring: PcmRing(seconds: 30), named: "a speaker")
        feed.begin(at: 0)

        let blocks = Int((seconds * Self.rate) / Double(Self.block))
        for _ in 0..<blocks { _ = feed.take(silence(), while: { true }) }

        return feed
    }

    private func frames(_ seconds: Double) -> AVAudioFramePosition {
        AVAudioFramePosition(seconds * Self.rate)
    }

    @Test func betweenReportsThePositionFillsInAtOneTimesSpeed() async {
        let feed = await room(holding: 6)
        feed.says(1)

        try? await Task.sleep(for: .milliseconds(200))

        let at = feed.played
        #expect(at != nil)

        // About 0.2 s of music has played. The margin allows for the accuracy of sleep.
        let moved = Double((at ?? 0) - frames(1)) / Self.rate
        #expect(moved > 0.15 && moved < 0.35)
    }

    @Test func theGuessNeverRunsPastWhatWasHandedOver() async {
        // The room holds 1.2 s and the report is at 1 s. Only 0.2 s is left to estimate, so the
        // estimate must not pass what was handed over, whatever the clock says.
        let feed = await room(holding: 1.2)
        feed.says(1)

        try? await Task.sleep(for: .milliseconds(400))

        #expect((feed.played ?? 0) <= frames(1.25))
    }

    @Test func aPausedRoomIsWhereItSaidItWas() async {
        let feed = await room(holding: 6)
        feed.says(1)
        feed.paused = true

        try? await Task.sleep(for: .milliseconds(200))

        #expect(feed.played == frames(1))
    }

    /// The reports jitter. A report that lands behind an estimate already drawn must not move the
    /// needle back. This is the same rule that `says` applies to the report itself.
    @Test func aReportBehindTheGuessDoesNotWalkItBack() async {
        let feed = await room(holding: 6)
        feed.says(1)

        try? await Task.sleep(for: .milliseconds(250))
        let guessed = feed.played ?? 0

        feed.says(1.05)
        #expect((feed.played ?? 0) >= guessed)
    }

    /// A speaker that has stopped answering keeps reporting the same figure. That figure is not
    /// stamped as new, so the estimate stops on its own.
    @Test func itGivesUpFillingInAfterASecond() async {
        let feed = await room(holding: 8)
        feed.says(1)

        try? await Task.sleep(for: .milliseconds(1400))

        // The estimate covers one second and no more, whatever the clock does after that.
        let moved = Double((feed.played ?? 0) - frames(1)) / Self.rate
        #expect(moved > 0.9 && moved < 1.1)
    }

    @Test func aNewStreamForgetsTheGuessWithTheReport() async {
        let feed = await room(holding: 6)
        feed.says(2)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(feed.played != nil)

        feed.begin(at: 0)
        #expect(feed.played == nil)
    }
    // ── the gap between the cut and the next track ──

    /// **The ratchet must be released when the stream is.** A cut leaves `reported` at the
    /// position where the old track had reached. The next stream's first reports are small
    /// numbers. The ratchet would then reject every one of them, and the room's position would
    /// never move again. The pacer would measure a lead that keeps growing, against a figure that
    /// never changes. The stall check would then bring the music home about thirty seconds after
    /// the next track was chosen.
    @Test func aStreamTakenBackLetsGoOfWhereTheLastOneHadReached() async {
        let feed = await room(holding: 6)
        feed.says(4)

        #expect((feed.played ?? 0) >= frames(4))

        feed.takenBack()
        #expect(feed.played == nil)

        // The next stream starts near zero. **This report must be accepted, not ignored**, even
        // though it is below the last one.
        feed.says(0.5)

        let now = try! #require(feed.played)
        #expect(now >= frames(0.5))
        #expect(now < frames(4))
    }

    /// Only the room's reported position is cleared. A cut is not a stall, so the feed must not
    /// look lost. The `lost` flag brings the sound home, so it must stay false.
    @Test func aStreamTakenBackIsNotAStreamThatEnded() async {
        let feed = await room(holding: 6)
        feed.says(3)
        feed.takenBack()

        #expect(feed.lost == false)
        #expect(feed.heard == nil)
    }

    /// The seconds the room reports are seconds into the **stream**. Where that is in the track
    /// depends on where the stream began. A skip and a seek both start a new stream.
    @Test func theNextStreamIsRebasedOnWhereItBegan() async {
        let feed = await room(holding: 6)
        feed.says(4)
        feed.takenBack()

        feed.begin(at: 12)
        for _ in 0..<Int((2 * Self.rate) / Double(Self.block)) {
            _ = feed.take(silence(), while: { true })
        }
        feed.says(1)

        let heard = try! #require(feed.heard)
        #expect(heard >= 13)
        #expect(heard < 14)
    }
}
