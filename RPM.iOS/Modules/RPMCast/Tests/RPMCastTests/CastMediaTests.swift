import Foundation
import Testing
@testable import RPMCast

/// What goes on the wire for a LOAD, and what comes back.
@Suite("Handing a track to a speaker")
struct CastMediaTests {

    private func fields(of media: CastMedia) throws -> [String: Any] {
        let data = try #require(media.payload.data(using: .utf8))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    /// **Both fields, on purpose.** `contentId` is the field the protocol has always used, and `contentUrl` is the newer name.
    /// Receivers in use read one or the other. Sending only one makes the load work on some speakers and fail on others.
    @Test func theAddressIsSentUnderBothNames() throws {
        let media = CastMedia(url: "http://192.168.1.9:8787/a.wav", contentType: "audio/wav")
        let inner = try #require(try fields(of: media)["media"] as? [String: Any])

        #expect(inner["contentId"] as? String == media.url)
        #expect(inner["contentUrl"] as? String == media.url)
        #expect(inner["contentType"] as? String == "audio/wav")
    }

    /// A receiver needs a duration before it shows a running time. So a known length is declared, and an unknown one is sent as live.
    @Test func aLengthThatIsKnownIsDeclared() throws {
        let known = try fields(of: CastMedia(url: "u", contentType: "audio/wav", seconds: 212))
        let live = try fields(of: CastMedia(url: "u", contentType: "audio/mpeg"))

        let first = try #require(known["media"] as? [String: Any])
        let second = try #require(live["media"] as? [String: Any])

        #expect(first["streamType"] as? String == "BUFFERED")
        #expect(first["duration"] as? Double == 212)
        #expect(second["streamType"] as? String == "LIVE")
        #expect(second["duration"] == nil)
    }

    @Test func theWordsGoOnTheTelevision() throws {
        let media = CastMedia(url: "u", contentType: "audio/mpeg", title: "Orinoco Flow",
                              artist: "Enya", album: "Watermark",
                              artworkUrl: "http://host/art.jpg", seconds: 269)

        let inner = try #require(try fields(of: media)["media"] as? [String: Any])
        let words = try #require(inner["metadata"] as? [String: Any])

        #expect(words["metadataType"] as? Int == 3)
        #expect(words["title"] as? String == "Orinoco Flow")
        #expect(words["artist"] as? String == "Enya")
        #expect(words["albumName"] as? String == "Watermark")

        let images = try #require(words["images"] as? [[String: String]])
        #expect(images.first?["url"] == "http://host/art.jpg")
    }

    @Test func aTrackWithNoCoverSendsNoImages() throws {
        let inner = try #require(
            try fields(of: CastMedia(url: "u", contentType: "audio/wav"))["media"] as? [String: Any])
        let words = try #require(inner["metadata"] as? [String: Any])

        #expect(words["images"] == nil)
        #expect(words["artist"] == nil)
    }

    @Test func aLoadStartsPlayingByItself() throws {
        #expect(try fields(of: CastMedia(url: "u", contentType: "audio/wav"))["autoplay"] as? Bool == true)
    }

    // ── what comes back ──

    /// The reply to a LOAD, from a real Nest Audio. **`IDLE` with no reason means the receiver has taken the track
    /// and has not started it.** Treating that state as a failure would reject every load.
    @Test func theAnswerToALoadIsIdleAndThatIsFine() throws {
        let taken = try #require(MediaStatus.of(
            #"{"requestId":3,"type":"MEDIA_STATUS","status":[{"mediaSessionId":1,"playerState":"IDLE"}]}"#))

        #expect(taken.accepted)
        #expect(!taken.failed)
        #expect(taken.mediaSessionId == 1)
    }

    /// The same state with the opposite meaning. A URL that the receiver could not fetch and a track that simply ended
    /// both show `IDLE`. Only the reason tells them apart.
    @Test func aLoadItCouldNotFetchSaysWhy() throws {
        let broken = try #require(MediaStatus.of(
            #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":1,"playerState":"IDLE","idleReason":"ERROR"}]}"#))
        let done = try #require(MediaStatus.of(
            #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":1,"playerState":"IDLE","idleReason":"FINISHED"}]}"#))

        #expect(broken.failed)
        #expect(!done.failed)
        #expect(!done.accepted)
    }

    @Test func aPlayingStatusCarriesWhereItHasGotTo() throws {
        let playing = try #require(MediaStatus.of(
            #"{"type":"MEDIA_STATUS","status":[{"mediaSessionId":1,"playerState":"PLAYING","currentTime":1.679}]}"#))

        #expect(playing.isPlaying)
        #expect(playing.currentTime == 1.679)
    }

    @Test func anEmptyStatusIsNotOne() {
        #expect(MediaStatus.of(#"{"type":"MEDIA_STATUS","status":[]}"#) == nil)
        #expect(MediaStatus.of("nonsense") == nil)
    }

    // ── how a LOAD reply is read ──

    /// **A cancelled LOAD is not a refused one.** Reading them as the same thing would stop the music on every second
    /// press of next. Two skips within a second send two LOADs. The receiver drops the first one for the second, and it says
    /// so. A sender that read that answer as a failure would treat a working speaker as broken.
    @Test func aCancelledLoadIsBeingOvertakenRatherThanRefused() {
        let cancelled = #"{"type":"LOAD_CANCELLED","requestId":4}"#

        #expect(CastLink.reading(cancelled) == .superseded)
    }

    /// A receiver that will not play the track says so. This is a real refusal, and it must end the cast.
    @Test func aFailedLoadIsARefusal() {
        let failed = #"{"type":"LOAD_FAILED","requestId":4,"reason":"LOAD_FAILED"}"#

        #expect(CastLink.reading(failed) == .refused("LOAD_FAILED"))
    }

    /// The usual answer is a media status. That means the receiver holds the track. Whether it is playing is a later question.
    /// See `CastLink.load`.
    @Test func aMediaStatusIsTheReceiverHoldingIt() {
        let taken = """
            {"type":"MEDIA_STATUS","status":[{"mediaSessionId":3,"playerState":"IDLE"}]}
            """

        #expect(CastLink.reading(taken) == .taken)
    }
}
