import Foundation
import Testing
@testable import RPMCast

/// Reading what a receiver says. The idle payload below is a real capture from a Nest Audio, with its EQ settings included.
/// What matters about it is what is **missing**. A speaker with nothing running has no `applications` key at all.
@Suite("What the speaker says about itself")
struct ReceiverStatusTests {

    private let idle = """
    {"requestId":1,"status":{"userEq":{"high_shelf":{"frequency":4500,"gain_db":4.0,\
    "quality":0.707},"low_shelf":{"frequency":150,"gain_db":-6.0,"quality":0.707},\
    "max_peaking_eqs":0,"peaking_eqs":[]},"version":2,"volume":{"controlType":"master",\
    "level":0.5,"muted":false,"stepInterval":0.019999999552965164}},"type":"RECEIVER_STATUS"}
    """

    private let running = """
    {"requestId":3,"status":{"applications":[{"appId":"CC1AD845",\
    "displayName":"Default Media Receiver","namespaces":[\
    {"name":"urn:x-cast:com.google.cast.cac"},{"name":"urn:x-cast:com.google.cast.debugoverlay"},\
    {"name":"urn:x-cast:com.google.cast.media"}],"sessionId":"9c2f-41",\
    "statusText":"Default Media Receiver","transportId":"web-5"}],\
    "volume":{"controlType":"master","level":0.5,"muted":false}},"type":"RECEIVER_STATUS"}
    """

    @Test func aSpeakerWithNothingRunningStillReadsAsAStatus() throws {
        let status = try #require(ReceiverStatus.of(idle))

        #expect(status.applications.isEmpty)
        #expect(status.volume?.level == 0.5)
        #expect(status.volume?.muted == false)
    }

    /// Every field that this app does not know about is skipped rather than refused. There are several of them in the payload above.
    @Test func fieldsNobodyHereKnowsAboutDoNotStopIt() throws {
        #expect(ReceiverStatus.of(idle) != nil)
    }

    @Test func aRunningAppSaysWhereToTalkToIt() throws {
        let app = try #require(ReceiverStatus.of(running)?.mediaReceiver)

        #expect(app.sessionId == "9c2f-41")
        #expect(app.transportId == "web-5")
        #expect(app.speaksMedia)
    }

    /// **The transport is not `receiver-0`.** Sending to the wrong one drops the LOAD without an error.
    @Test func theTransportIsNotThePlatform() throws {
        let app = try #require(ReceiverStatus.of(running)?.mediaReceiver)
        #expect(app.transportId != CastMessage.receiver)
    }

    @Test func anAppThatIsNotTheMediaReceiverIsNotOne() throws {
        let other = running.replacingOccurrences(of: "CC1AD845", with: "233637DE")
        let status = try #require(ReceiverStatus.of(other))

        #expect(status.applications.count == 1)
        #expect(status.mediaReceiver == nil)
    }

    // ── the volume ──

    /// A device that is wired into an amplifier controls its own volume. Setting a level on one does **nothing at all**, and it gives
    /// no error. So the volume is checked before it is offered.
    @Test func aFixedVolumeIsNotOursToMove() throws {
        let fixed = idle.replacingOccurrences(of: #""controlType":"master""#,
                                              with: #""controlType":"fixed""#)

        #expect(try #require(ReceiverStatus.of(idle)).volume?.canBeSet == true)
        #expect(try #require(ReceiverStatus.of(fixed)).volume?.canBeSet == false)
    }

    @Test func aSpeakerSaysHowFarOneStepMovesIt() throws {
        let volume = try #require(ReceiverStatus.of(idle)?.volume)
        #expect(volume.stepInterval == 0.019999999552965164)
    }

    @Test func nonsenseIsNotAStatus() {
        #expect(ReceiverStatus.of("not json") == nil)
        #expect(ReceiverStatus.of(#"{"requestId":1,"type":"PONG"}"#) == nil)
    }
}
