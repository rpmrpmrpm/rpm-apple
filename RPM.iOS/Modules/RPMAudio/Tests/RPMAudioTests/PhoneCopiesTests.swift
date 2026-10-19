import Testing
import Foundation
import RPMKit
import RPMLibrary
@testable import RPMAudio

// ── downloaded records, and what the player does without a network ──
//
// These tests run the whole path against the silent store. Each test asks what reaches the
// network and what reaches the speaker. Neither part shows the answer alone.

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

@Suite("Records on the phone", .serialized)
@MainActor
struct PhoneCopiesTests {

    /// **The purpose of a download.** A track with a copy on the phone is read from the copy.
    /// The store is never asked to sign it.
    @Test func aTrackOnThePhoneIsReadFromItAndNeverSigned() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }

        let copies = Copies()
        try copies.hold("t0")

        let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(),
                         copies: copies, nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })

        await rpm.play([track("t0")], from: 0, because: .somebodyAskedForIt)
        try await until("the record to play") { rpm.isPlaying }

        #expect(!store.asked.contains("t0"), "a downloaded track was fetched from the store")
        #expect(rpm.trouble == nil)
        rpm.stop()
    }

    /// Offline, a queue that mixes downloaded and streamed records starts on the first one
    /// that is on the phone, and nothing is asked of the network.
    @Test func offlineAStartStepsOverWhatIsNotOnThePhone() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }

        let copies = Copies()
        try copies.hold("t2")

        let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(),
                         copies: copies, nearby: NothingNearby(), reach: await FixedLine.offline(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })

        await rpm.play((0..<4).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)

        #expect(rpm.index == 2)
        try await until("the record on the phone to play") { rpm.isPlaying }
        #expect(store.asked.isEmpty, "the store was asked for something while offline")
        rpm.stop()
    }

    /// Offline with nothing on the phone: the error is reported and nothing starts.
    @Test func offlineWithNothingOnThePhoneSaysSo() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }

        let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(),
                         copies: NoCopies(), nearby: NothingNearby(), reach: await FixedLine.offline(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })

        await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)

        #expect(rpm.failure == .offline)
        #expect(rpm.trouble == PlaybackFailure.offline.said)
        #expect(!rpm.isPlaying)
        #expect(store.asked.isEmpty)
    }

    /// **A lost network connection stops a streamed record.** The queue and the position are kept,
    /// so playback can continue from the same place when the connection returns.
    @Test func losingTheLineStopsAStreamedRecordAndKeepsItsPlace() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }

        let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(),
                         copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })

        await rpm.play((0..<3).map { track("t\($0)") }, from: 1, because: .somebodyAskedForIt)
        try await until("the record to play") { rpm.isPlaying }

        rpm.theLineWentAway()

        #expect(!rpm.isPlaying)
        #expect(rpm.failure == .offline)
        #expect(rpm.index == 1)
        #expect(rpm.queue.count == 3)

        // The playback timer must not restart it. Nothing is left in the engine to play.
        try await Task.sleep(for: .milliseconds(400))
        #expect(!rpm.isPlaying)
        rpm.stop()
    }

    /// A record read from the phone does not need the network, and plays on.
    @Test func losingTheLineLeavesARecordOnThePhonePlaying() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }

        let copies = Copies()
        try copies.hold("t0")

        let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(),
                         copies: copies, nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })

        await rpm.play([track("t0")], from: 0, because: .somebodyAskedForIt)
        try await until("the record to play") { rpm.isPlaying }

        rpm.theLineWentAway()
        try await Task.sleep(for: .milliseconds(400))

        #expect(rpm.isPlaying)
        #expect(rpm.failure == .none)
        rpm.stop()
    }
}
