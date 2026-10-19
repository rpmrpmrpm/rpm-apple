import Foundation
import AVFAudio
import AudioToolbox
import Testing
@testable import RPMAudio

/// The reason playback stopped, as reported by the source that stopped.
///
/// **The case this covers:** a stream was cut at a seam, and the clip ran out with nothing
/// after it. The player could only tell a finished record from a short one by comparing the
/// needle position with the length in the tags. So it read the short clip as a finished record
/// and moved on.
///
/// Every source knows why it stopped, and reports the reason.
@Suite("Why the music stopped")
struct EndingTests {

    private func tone() throws -> Data {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
        return try Data(contentsOf: url)
    }

    private func fed(_ bytes: Data, chunk: Int = 4096) throws -> StreamedPcm {
        let source = StreamedPcm()
        for at in stride(from: 0, to: bytes.count, by: chunk) {
            try source.take(bytes[at..<min(at + chunk, bytes.count)])
        }
        return source
    }

    // ── what a source says about itself ──

    /// The ordinary one: everything arrived, everything decoded, the record is over.
    @Test func aWholeRecordReachedItsEnd() throws {
        let source = try fed(try tone())
        while try source.read() != nil {}
        source.finish(.theFileRanOut)

        #expect(source.ending == .theRecordFinished)
        #expect(source.ending.worthAnotherGo == false)
        #expect(source.ending.failure(heard: 3) == PlaybackFailure.none)
    }

    /// **A download that stopped early.** Every byte the store sent arrived and decoded. The
    /// store stopped sending after a third of the file. This is not an error. Only the file header
    /// shows the record is incomplete, when it is compared with the decoded length.
    @Test func aTruncatedDownloadIsNotTheEndOfTheRecord() throws {
        let bytes = try tone()
        let source = try fed(bytes.prefix(bytes.count / 3))
        while try source.read() != nil {}
        source.finish(.theFileRanOut)

        #expect(source.ending.reachedItsEnd == false, "a third of a record read as the whole of it")
        #expect(source.ending.worthAnotherGo, "the rest of it is worth asking for again")
    }

    /// A source with no stated length is trusted. A radio station does not state its length, so
    /// a stop counts as the end.
    @Test func aSourceThatDoesNotSayHowLongItIsIsTakenAtItsWord() throws {
        let source = StreamedPcm()
        source.finish(.theFileRanOut)

        #expect(source.ending.reachedItsEnd)
    }

    /// The start position counts towards the length. A stream that begins half way through a
    /// record is complete when the rest of the record has played.
    @Test func aStreamThatBeganPartWayThroughAddsBackWhatItWasNeverSent() throws {
        let bytes = try tone()
        let source = try fed(bytes)
        let landing = try #require(source.byteToHear(1.5))

        source.expectAJump(landingAt: landing.second)
        try source.take(bytes[Int(landing.byte)...])
        source.finish(.theFileRanOut)
        while try source.read() != nil {}

        #expect(source.begins == landing.second)
        #expect(source.ending.reachedItsEnd,
                "the half it was sent decoded, and the half it was not was counted against it")
    }

    // ── what the reasons mean ──

    /// A refused signature means the session has expired. Retrying the same address does not
    /// help, so no retry is made.
    @Test func aRefusalNamesTheOneFailureSigningInFixes() {
        let refused = Ending(why: .theStoreRefused(403), reachedItsEnd: false)

        #expect(refused.failure(heard: 2) == .signedIn)
        #expect(refused.worthAnotherGo == false)

        let broken = Ending(why: .theStoreRefused(500), reachedItsEnd: false)
        #expect(broken.failure(heard: 2) == .store)
        #expect(broken.worthAnotherGo, "a store that fell over may be back")
    }

    /// **A file that cannot be decoded is not retried.** The same bytes would arrive again, and
    /// the same converter would refuse them. A retry only gives silence.
    @Test func aFileThisPhoneCannotDecodeIsNotTriedAgain() {
        for why in [Ending.Why.theDecoderStopped, .theBytesWouldNotParse] {
            let ending = Ending(why: why, reachedItsEnd: false)

            #expect(ending.worthAnotherGo == false, "\(why) was tried again")
            #expect(ending.failure(heard: 2) == .notPlayable)
        }
    }

    /// The amount heard tells a record that never started apart from one that stopped in the
    /// middle.
    @Test func aDropIsToldApartByHowMuchWasHeard() {
        let dropped = Ending(why: .theBytesStopped, reachedItsEnd: false)

        #expect(dropped.failure(heard: 1) == .unreachable)
        #expect(dropped.failure(heard: 90) == .dropped)
        #expect(dropped.worthAnotherGo)
    }

    /// A track the user stopped on purpose gives no error and is not retried.
    @Test func somethingPutDownSaysNothing() {
        let put = Ending(why: .itWasPutDown, reachedItsEnd: false)

        #expect(put.failure(heard: 30) == PlaybackFailure.none)
        #expect(put.failure(heard: 30).said == nil, "a skipped track put a red line on the screen")
        #expect(put.worthAnotherGo == false)
    }

}

/// Removes the padding that an encoder adds around the audio.
///
/// AAC gives its decoder 2112 frames of priming before the first note, which is about 48 ms at
/// 44.1 kHz. The encoder also pads the last packet after the end. If these frames stay, a three
/// second clip reports a length of about 3.065 seconds, and every calculation built on that
/// length is wrong by the same amount.
///
/// Removing the padding also makes ``StreamedPcm/duration`` the length of the music, not the
/// container. The end of a record is found from that length. The priming is 48 ms of silence at
/// the start of each AAC track, so removing it also shortens the gap between tracks.
@Suite("The encoder's padding")
struct PrimingTests {

    private func opened(_ name: String, _ ext: String) throws -> StreamedPcm {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: ext))
        let source = StreamedPcm()
        try source.take(try Data(contentsOf: url))
        source.finish(.theFileRanOut)
        return source
    }

    private func played(_ source: StreamedPcm) throws -> (frames: AVAudioFramePosition, silence: Int) {
        var frames: AVAudioFramePosition = 0
        var silence = -1

        while let buffer = try source.read(upTo: 4096) {
            if silence < 0, let channel = buffer.floatChannelData?[0] {
                for at in 0..<Int(buffer.frameLength) where abs(channel[at]) > 0.001 {
                    silence = Int(frames) + at
                    break
                }
            }
            frames += AVAudioFramePosition(buffer.frameLength)
        }

        return (frames, silence)
    }

    /// The record starts on the first note, not in the encoder's run-up.
    @Test func theRunUpIsNotHandedOut() throws {
        let source = try opened("tone", "m4a")
        let (frames, silence) = try played(source)

        #expect(silence >= 0, "nothing came out at all")
        #expect(silence < 200, "\(silence) frames of silence in front of a tone that starts at nought")
        #expect(frames > 44_100, "\(frames) frames of a three second record")
    }

    /// The reported length is the length of the music, so the seek offset is measured from where
    /// the clip really ends.
    @Test func theLengthIsTheMusic() throws {
        let clip = try opened("tone", "m4a")
        let said = try #require(clip.duration)

        // The clip is exactly three seconds. The container holds 135168 frames. Subtract 2112
        // frames of priming and 756 frames of padding, and 132300 frames remain, which is 3 s at
        // 44.1 kHz.
        #expect(abs(said - 3) < 0.01, "\(said)s, which is the container rather than the music")
    }

    /// A FLAC file has no padding, so removing it changes nothing.
    @Test func aLosslessRecordHasNoRunUpToTake() throws {
        let source = try opened("tone", "flac")
        let (_, silence) = try played(source)

        #expect(silence >= 0 && silence < 200, "a FLAC lost \(silence) frames it never padded")
    }

    /// The seam is found from the music's own seconds, not the container's. Using container
    /// seconds would land about one priming too far in, and the record would jump.
    @Test func theSeamIsAskedForInTheMusicsOwnSeconds() throws {
        let source = try opened("tone", "m4a")
        let landing = try #require(source.byteToHear(1.5))

        // A packet is 1024 frames. The landing is the last packet boundary at or before 1.5 s of
        // music. 64 packets is 65536 frames of decoder output. Less 2112 frames of priming leaves
        // 63424 frames, which is 1.438 s.
        #expect(landing.second < 1.5)
        #expect(abs(landing.second - 1.438) < 0.03, "landed at \(landing.second)s")
    }
}
