import Foundation
import Testing
@testable import RPMCast

/// What the room said, and the difference between two kinds of nothing.
///
/// **The case that mattered most.** A receiver whose media session has ended still answers `GET_STATUS`, with an empty list,
/// because it has no media to describe. Read as a `MediaStatus?`, that is nil. That is the same as a speaker that did not answer.
/// So a stop pressed at the speaker would look like silence.
@Suite("What the room said")
struct RoomReportTests {

    private let playing = """
        {"type":"MEDIA_STATUS","status":[{"mediaSessionId":7,"playerState":"PLAYING","currentTime":12.5}]}
        """

    private let stopped = #"{"type":"MEDIA_STATUS","status":[]}"#

    @Test func aRoomWithMediaIsReadAsHoldingIt() {
        let status = MediaStatus.of(playing)
        #expect(status?.playerState == "PLAYING")
        #expect(status?.mediaSessionId == 7)
    }

    /// This is the shape that a stopped receiver answers with. It is **not** nothing. It is an answer, and the answer is
    /// that there is no media.
    @Test func aStoppedRoomAnswersWithAnEmptyList() {
        #expect(MediaStatus.of(stopped) == nil)
        #expect(stopped.contains(#""MEDIA_STATUS""#))
    }

    @Test func theThreeAnswersAreDistinct() {
        #expect(RoomReport.nothingLoaded.isEmptyHanded)
        #expect(RoomReport.noAnswer.isEmptyHanded == false)

        let status = MediaStatus.of(playing)!
        #expect(RoomReport.holding(status).isEmptyHanded == false)
        #expect(RoomReport.holding(status) != .nothingLoaded)
        #expect(RoomReport.nothingLoaded != .noAnswer)
    }

    /// An `IDLE` with a reason is still a room that holds media, so it takes the usual path.
    @Test func idleWithAReasonIsStillHeld() {
        let idle = """
            {"type":"MEDIA_STATUS","status":[{"mediaSessionId":9,"playerState":"IDLE","idleReason":"CANCELLED"}]}
            """
        #expect(MediaStatus.of(idle)?.idleReason == "CANCELLED")
    }

    /// Any other message on the media namespace is not an answer to the question that was asked. It must not be read as a stop.
    @Test func anotherKindOfMessageIsNoAnswer() {
        let other = #"{"type":"INVALID_REQUEST","reason":"INVALID_MEDIA_SESSION_ID"}"#
        #expect(MediaStatus.of(other) == nil)
        #expect(other.contains(#""MEDIA_STATUS""#) == false)
    }
}
