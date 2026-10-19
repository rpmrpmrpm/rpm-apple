import Testing
import Foundation
import RPMKit
import RPMLibrary
@testable import RPMAudio

// ── tracks on a computer on the home network ──
//
// The silent store stands in for both: it serves the cloud's address and, under another path,
// the computer's. A computer that does not answer is a port nothing listens on.

private func track(_ id: String) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.durationSeconds = 20
    return CloudTrack(rpmId: id, relativePath: "x/\(id).wav", title: id,
                      artist: "Talk Talk", album: "Laughing Stock", tags: tags)
}

@MainActor
private func until(_ what: String, within: Duration = .seconds(15),
                   _ done: @MainActor () -> Bool) async throws {
    let end = ContinuousClock.now.advanced(by: within)
    while ContinuousClock.now < end {
        if done() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    Issue.record("timed out waiting for \(what)")
}

/// A home network that offers one address for every track until it is told the address failed.
@MainActor
private final class OneComputer: NearbyCopies {
    let base: URL
    private(set) var failed: [URL] = []
    private(set) var asked: [String] = []

    init(base: URL) { self.base = base }

    func address(of track: CloudTrack, on shelf: CloudShelf) async -> URL? {
        asked.append(track.rpmId)
        guard failed.isEmpty else { return nil }
        // The path is unique on the silent store. This tells a read from the computer apart from
        // a read from the cloud.
        return base.appendingPathComponent("near-" + track.rpmId)
    }

    func failed(_ address: URL) { failed.append(address) }
}

@Suite("Records on a computer on the home network", .serialized)
@MainActor
struct NearbyCopiesTests {

    /// A track the computer serves plays from it, and the cloud is never asked to sign it.
    @Test func aTrackOnAComputerPlaysFromItAndIsNeverSigned() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }

        let computer = OneComputer(base: store.address(of: "computer").deletingLastPathComponent())
        let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(),
                         copies: NoCopies(), nearby: computer, reach: NetworkReach(),
                         levelling: .album, levelsClassical: false, classical: { _ in false },
                         cover: { _ in nil })

        await rpm.play([track("t0")], from: 0, because: .somebodyAskedForIt)
        try await until("the record to play") { rpm.isPlaying }

        #expect(computer.asked.contains("t0"))
        #expect(computer.failed.isEmpty)
        #expect(store.asked.contains("near-t0"))
        #expect(!store.asked.contains("t0"), "a track on the computer was signed from the cloud")
        #expect(rpm.trouble == nil)
        rpm.stop()
    }

    /// A computer that does not answer is reported, and the track plays from the cloud.
    @Test func aComputerThatDoesNotAnswerIsReportedAndTheCloudPlays() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }

        let computer = OneComputer(base: URL(string: "http://127.0.0.1:9/rpm/track")!)
        let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(),
                         copies: NoCopies(), nearby: computer, reach: NetworkReach(),
                         levelling: .album, levelsClassical: false, classical: { _ in false },
                         cover: { _ in nil })

        await rpm.play([track("t1")], from: 0, because: .somebodyAskedForIt)
        try await until("the record to play from the cloud") { rpm.isPlaying }

        #expect(computer.failed.count == 1)
        #expect(store.asked.contains("t1"), "the cloud was not asked after the computer failed")
        rpm.stop()
    }
}
