import Foundation
import Testing
@testable import RPMCast

/// Whether the session that this app launched is still running on the device.
///
/// **This is where a stop pressed at the speaker shows up.** A stop on a Google speaker ends the receiver app, not only its media
/// session. The app quits, and its media transport goes with it. A request to that transport gets no reply, which looks the same
/// as a slow network. The device's own status says so plainly, so the app reads it to check that the launched session is still there.
@Suite("What the device says is running")
struct ReceiverRunningTests {

    private func status(_ payload: String) -> ReceiverStatus? {
        struct Envelope: Decodable { let status: ReceiverStatus }
        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Envelope.self, from: data).status
    }

    private let running = """
        {"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"41BD77B1",
        "sessionId":"s-1","transportId":"t-1","displayName":"rpm",
        "namespaces":[{"name":"urn:x-cast:com.google.cast.media"}]}],
        "volume":{"level":0.4,"muted":false}}}
        """

    /// What a device with nothing running answers: no `applications` key at all.
    private let idle = #"{"type":"RECEIVER_STATUS","status":{"volume":{"level":0.4}}}"#

    @Test func aRunningSessionIsListed() throws {
        let said = try #require(status(running))
        #expect(said.applications.contains { $0.sessionId == "s-1" })
        #expect(said.volume?.level == 0.4)
    }

    /// The stop. Nothing is running, so the session that was launched is not running either.
    @Test func aClosedReceiverListsNothing() throws {
        let said = try #require(status(idle))
        #expect(said.applications.isEmpty)
        #expect(said.applications.contains { $0.sessionId == "s-1" } == false)
    }

    /// **Check the session, not only whether the list is empty.** A device that runs someone else's app is not this cast.
    /// Treating "something is running" as "we are still casting" would leave the phone feeding a stream that nobody fetches.
    @Test func somebodyElsesAppIsNotThisSession() throws {
        let other = """
            {"type":"RECEIVER_STATUS","status":{"applications":[{"appId":"CC1AD845",
            "sessionId":"s-9","transportId":"t-9","displayName":"Default Media Receiver"}]}}
            """
        let said = try #require(status(other))
        #expect(said.applications.isEmpty == false)
        #expect(said.applications.contains { $0.sessionId == "s-1" } == false)
    }

    /// The volume must still be read from the same status, which is requested on the same schedule.
    @Test func theKnobIsStillRead() throws {
        #expect(try #require(status(running)).volume?.level == 0.4)
        #expect(try #require(status(idle)).volume?.level == 0.4)
    }
}
