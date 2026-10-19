import Testing
import Foundation
import RPMKit
import RPMRadio
@testable import RPMAudio

// A station whose stream drops.

@MainActor
private func until(_ what: String, within: Duration = .seconds(10),
                   _ done: @MainActor () -> Bool) async throws {
    let end = ContinuousClock.now.advanced(by: within)
    while ContinuousClock.now < end {
        if done() { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    Issue.record("timed out waiting for \(what)")
}

@Suite("A station that drops", .serialized)
@MainActor
struct StationReconnectTests {
    private func player() -> Player {
        Player(source: NeverSigns(), shelves: AnyShelf(), copies: NoCopies(), nearby: NothingNearby(),
               reach: NetworkReach(), levelling: .album, levelsClassical: false,
               classical: { _ in false }, cover: { _ in nil })
    }

    /// If a stream does not answer, the player tries again instead of giving up at once.
    /// While it waits, it reports that it is reconnecting.
    @Test func aStationThatDropsIsTunedInAgain() async throws {
        let rpm = player()
        rpm.tune(RadioStation(uuid: "s1", name: "Nowhere FM", streamUrl: "http://127.0.0.1:9/live"))

        try await until("the player to start reconnecting") { rpm.reconnecting }
        #expect(rpm.station?.uuid == "s1")
        #expect(rpm.trouble == nil)

        rpm.stop()
        #expect(rpm.reconnecting == false)
    }

    /// Tuning another station starts the count again and ends the reconnecting.
    @Test func tuningAnotherStationEndsTheReconnecting() async throws {
        let rpm = player()
        rpm.tune(RadioStation(uuid: "s1", name: "Nowhere FM", streamUrl: "http://127.0.0.1:9/live"))
        try await until("the player to start reconnecting") { rpm.reconnecting }

        rpm.tune(RadioStation(uuid: "s2", name: "Also Nowhere", streamUrl: "notaurl"))
        #expect(rpm.reconnecting == false)
        #expect(rpm.station == nil || rpm.station?.uuid == "s2")
    }

    @Test func theWaitsDoubleToFifteenSeconds() {
        #expect(Player.reconnectWaits.first == .milliseconds(500))
        #expect(Player.reconnectWaits.last == .seconds(15))
        #expect(Player.mostReconnects == 8)
    }
}

/// A stream source that never signs anything. A radio station needs no signature.
private struct NeverSigns: StreamSource {
    func stream(_ shelf: CloudShelf, rpmId: String, kilobits: Int) async throws -> (url: URL, kilobits: Int, kind: StreamKind) {
        throw URLError(.cannotConnectToHost)
    }
}
