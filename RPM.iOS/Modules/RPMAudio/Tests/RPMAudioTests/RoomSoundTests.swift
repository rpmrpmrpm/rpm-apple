import Foundation
import AVFAudio
import Testing
@testable import RPMAudio

/// The sound kept for the visualiser.
///
/// **The window must follow the playhead.** Without that, the visualiser draws a still picture
/// while a speaker plays. The pump decodes up to eight seconds ahead of a room (`RoomFeed.lead`).
/// Reading the newest samples would draw audio that has not played yet.
@Suite("The sound kept for the picture")
struct RoomSoundTests {

    /// Where the sound has got to, as something a test can move.
    private final class Playhead: @unchecked Sendable {
        var at: AVAudioFramePosition?
        init(_ at: AVAudioFramePosition? = nil) { self.at = at }
    }

    private static let block: AVAudioFrameCount = 8192

    /// A block whose every sample is `value`, so a window can say which block it came
    /// from without any arithmetic.
    private func marked(_ value: Float) -> AVAudioPCMBuffer {
        let format = StreamedPcm.engineFormat
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.block)!
        buffer.frameLength = Self.block

        for channel in 0..<Int(format.channelCount) {
            buffer.floatChannelData![channel].update(repeating: value, count: Int(Self.block))
        }
        return buffer
    }

    /// Writes `count` blocks in order, the nth marked n+1.
    private func fill(_ sound: RoomSound, blocks count: Int) {
        var at: AVAudioFramePosition = 0
        for i in 0..<count {
            sound.write(marked(Float(i + 1)), at: at)
            at += AVAudioFramePosition(Self.block)
        }
    }

    // ── the property that casting depends on ──

    @Test func theWindowIsReadAtThePlayheadAndNotAtTheWriteHead() {
        let sound = RoomSound()
        let head = Playhead()
        sound.reads { [head] in head.at }

        fill(sound, blocks: 10)

        // The room is six blocks behind what has been decoded. What it is playing is the
        // fourth block, and that is what the picture must be drawn from.
        head.at = AVAudioFramePosition(Self.block) * 4

        var window = [Float](repeating: 0, count: Int(Self.block))
        #expect(sound.fill(&window))
        #expect(window.allSatisfy { $0 == 4 })

        // And on the handset, where the playhead is at the end of what was handed over.
        head.at = AVAudioFramePosition(Self.block) * 10
        #expect(sound.fill(&window))
        #expect(window.allSatisfy { $0 == 10 })
    }

    @Test func thereIsNothingToDrawUntilThereIsAWindowOfIt() {
        let sound = RoomSound()
        let head = Playhead()
        sound.reads { [head] in head.at }

        fill(sound, blocks: 4)
        var window = [Float](repeating: 0, count: Int(Self.block))

        // Half a window is available. `fill` returns false, not half a window of silence.
        head.at = AVAudioFramePosition(Self.block) / 2
        #expect(sound.fill(&window) == false)

        // And before the speaker has said anything at all.
        head.at = nil
        #expect(sound.fill(&window) == false)
    }

    /// A start and a seek both set the engine's count back to zero, and nothing else signals this.
    /// The rewind is read from the frame that is passed in. This works whenever the window is
    /// asked for, so no caller has to remember to reset it.
    @Test func aNewTimelineTakesTheOldOneWithIt() {
        let sound = RoomSound()
        let head = Playhead()
        sound.reads { [head] in head.at }

        fill(sound, blocks: 10)

        // `begin` is called for another record, or for the same record from another second.
        sound.write(marked(99), at: 0)

        var window = [Float](repeating: 0, count: Int(Self.block))

        // The old record's position is no longer valid.
        head.at = AVAudioFramePosition(Self.block) * 4
        #expect(sound.fill(&window) == false)

        head.at = AVAudioFramePosition(Self.block)
        #expect(sound.fill(&window))
        #expect(window.allSatisfy { $0 == 99 })
    }

    /// A room that is further behind than the ring is too far back. The window cannot be drawn
    /// there, and it must not be guessed. Those seconds have been overwritten by later audio.
    @Test func aRoomThatFallsFurtherBehindThanTheRingIsRefused() {
        let sound = RoomSound()
        let head = Playhead()
        sound.reads { [head] in head.at }

        let blocks = RoomSound.size / Int(Self.block) + 4
        fill(sound, blocks: blocks)

        var window = [Float](repeating: 0, count: Int(Self.block))

        head.at = AVAudioFramePosition(Self.block) * 2
        #expect(sound.fill(&window) == false)

        // The newest end of the ring can still be read.
        head.at = AVAudioFramePosition(Self.block) * AVAudioFramePosition(blocks)
        #expect(sound.fill(&window))
        #expect(window.allSatisfy { $0 == Float(blocks) })
    }

    @Test func theRateIsTheEnginesToSayAndIsNotKnownUntilSomethingIsWritten() {
        let sound = RoomSound()
        #expect(sound.rate == 0)
        #expect(sound.ready == false)

        fill(sound, blocks: 1)
        #expect(sound.rate == StreamedPcm.engineFormat.sampleRate)
        #expect(sound.ready)
    }
}
