import Foundation
import Testing
@testable import RPMCast

/// The volume conversation with a speaker.
///
/// There are two failure modes, and they are the reason this is not a plain setter. Every change that is sent comes back as a
/// status. If every report is believed, the app follows its own echo. A finger held on a volume key sends changes faster than
/// a speaker can answer them. Two sends in flight can then arrive in either order.
@Suite("The one knob, which belongs to the speaker")
struct CastVolumeTests {

    /// Records what was sent, so that a test can count it.
    final class Sent: @unchecked Sendable {
        private let gate = NSLock()
        private var levels: [Double] = []

        func note(_ level: Double) { gate.withLock { levels.append(level) } }
        var all: [Double] { gate.withLock { levels } }
        var count: Int { gate.withLock { levels.count } }
    }

    func made(quiet: Duration = .seconds(2), every: Duration = .milliseconds(20))
    -> (CastVolume, Sent) {
        let sent = Sent()
        return (CastVolume(every: every, quiet: quiet) { sent.note($0) }, sent)
    }

    // ── the echo ──

    /// Nothing has been requested yet, so whatever the room reports is the truth. This is the start of a cast.
    /// The speaker is already at some level.
    @Test func theRoomsOwnLevelIsAdoptedBeforeAnythingIsSent() {
        let (volume, _) = made()

        #expect(volume.adopt(0.2) == 20)
        #expect(volume.level == 20)
    }

    /// A status that carries the level we just asked for is our own change coming back.
    @Test func ourOwnLevelComingBackIsNotSomebodyTurningIt() {
        let (volume, _) = made()

        volume.set(40, live: true)
        #expect(volume.adopt(0.40) == nil, "it followed its own echo")
        #expect(volume.level == 40)
    }

    /// **This stops the slider jumping back under the finger.** A status that is in flight during a drag carries the level
    /// from before the drag. Adopting it would pull the level backwards.
    @Test func aStaleReportDuringADragIsIgnored() {
        let (volume, _) = made()

        volume.set(40, live: true)
        #expect(volume.adopt(0.55) == nil, "it adopted a level from before the drag")
        #expect(volume.level == 40)
    }

    /// After enough time with nothing sent, a report means that someone in the room changed the level.
    @Test func aReportLongAfterOurOwnChangeIsSomebodyElse() async throws {
        let (volume, _) = made(quiet: .milliseconds(50))

        volume.set(40, live: true)
        try await Task.sleep(for: .milliseconds(120))

        #expect(volume.adopt(0.55) == 55)
        #expect(volume.level == 55)
    }

    /// A difference of one point either way is the speaker's own rounding, not a person turning the knob.
    /// Following it would move the level off the value that was just chosen.
    @Test(arguments: [0.40, 0.41, 0.395])
    func aPointEitherWayIsQuantisationRatherThanAHand(reported: Double) async throws {
        let (volume, _) = made(quiet: .milliseconds(20))

        volume.set(40, live: true)
        try await Task.sleep(for: .milliseconds(60))

        #expect(volume.adopt(reported) == nil, "it followed a rounding error")
    }

    /// **A status that is already on the wire when a cast ends arrives afterwards.** A player that acts on it would set the
    /// volume of something else to a level that was never meant for it.
    @Test func nothingIsAdoptedOnceTheCastIsOver() {
        let (volume, _) = made()

        volume.close()
        #expect(volume.adopt(0.8) == nil)
    }

    @Test func aRoomThatHasSaidNothingChangesNothing() {
        let (volume, _) = made()
        #expect(volume.adopt(nil) == nil)
    }

    // ── what actually goes out ──

    /// **The bug that this file exists to stop.** A level sent to a sink as soon as it is created, before anything is loaded,
    /// sets a room at 20% to whatever level the phone is at.
    @Test func nothingIsSentBeforeThereIsAStreamToTurnUp() async throws {
        let (volume, sent) = made()

        volume.set(75, live: false)
        try await Task.sleep(for: .milliseconds(80))

        #expect(sent.count == 0, "it turned a room nobody was listening to")
        #expect(volume.level == 75, "it forgot the number")
    }

    /// A drag produces a change for each pixel. What goes out is the latest value, at a steady rate. **Only one send is in
    /// flight at a time.** Two sends that overlap can arrive in either order, and the speaker keeps the one that arrives last.
    @Test func adragIsCoalescedRatherThanSentPerPixel() async throws {
        let (volume, sent) = made(every: .milliseconds(30))

        for step in stride(from: 20, through: 60, by: 2) { volume.set(step, live: true) }
        try await Task.sleep(for: .milliseconds(300))

        #expect(sent.count < 21, "it sent \(sent.count) of the 21 steps")
        #expect(sent.count >= 1)

        // Wherever it stopped is where the speaker ends up.
        #expect(sent.all.last == 0.60, "the room did not end on the level asked for")
        #expect(volume.level == 60)
    }

    @Test func aLevelIsHeldInsideTheRange() {
        let (volume, _) = made()

        volume.set(-40, live: false)
        #expect(volume.level == 0)

        volume.set(400, live: false)
        #expect(volume.level == 100)
    }
}
