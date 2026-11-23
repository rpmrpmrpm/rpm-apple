import Testing
import Foundation
import AudioToolbox
import RPMKit
import RPMLibrary
@testable import RPMAudio

// ── an original this device cannot decode, which the catalogue did not name ──
//
// iOS and tvOS do not decode AC-3 or E-AC-3. The catalogue's codec text normally keeps such an
// original from being asked for (``PlaysHere``), but a track can have no codec text. Then the
// original arrives, the decoder refuses it from its header, and the player asks for the AAC copy.
//
// The fixture is two seconds of a 440 Hz tone, E-AC-3 in an MPEG-4 file, as the desktop uploads
// it. The store in these tests serves it as the original, and silence as the copy.

private func track(_ id: String) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.durationSeconds = 20
    // A file type that decodes here and no codec text: the catalogue says nothing about Dolby.
    return CloudTrack(rpmId: id, relativePath: "x/\(id).wav", title: id,
                      artist: "Talk Talk", album: "Laughing Stock", tags: tags)
}

private func dolby() throws -> URL {
    try #require(Bundle.module.url(forResource: "Fixtures/tone-eac3", withExtension: "m4a"))
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

/// Signs the original of a track at one path of the silent store and the copy at another, so a
/// test can see which of the two was read.
private struct OriginalOrCopy: StreamSource {
    let store: SilentStore

    func stream(_ shelf: CloudShelf, rpmId: String,
                rate: AudioLadder.AskedRate) async throws -> (url: URL, kilobits: Int, kind: StreamKind) {
        let name = rate.isTheOriginal ? "\(rpmId)-original" : rpmId
        return (store.address(of: name), rate.kilobits, .stored)
    }
}

/// One track downloaded as its original, in a file this device does not decode.
private struct HeldDolby: PhoneCopies {
    let rpmId: String
    let file: URL

    func copy(of id: String) -> PhoneCopy? {
        id == rpmId ? PhoneCopy(file: file, kilobits: AudioLadder.original) : nil
    }
}

/// A home network whose computer serves every track's original from the silent store.
@MainActor
private final class DolbyComputer: NearbyCopies {
    let store: SilentStore
    private(set) var asked: [String] = []
    private(set) var failed: [URL] = []

    init(store: SilentStore) { self.store = store }

    func address(of track: CloudTrack, on shelf: CloudShelf) async -> URL? {
        asked.append(track.rpmId)
        return store.address(of: "near-" + track.rpmId)
    }

    func failed(_ address: URL) { failed.append(address) }
}

@Test func theDecoderRefusesDolbyFromItsHeader() throws {
    let bytes = try Data(contentsOf: try dolby())
    let source = StreamedPcm()

    #expect(throws: StreamedPcm.Trouble.notDecodedHere) { try source.take(bytes) }
    #expect(source.notDecodedHere)
    #expect(!source.ready, "a decoder was made for a format this device does not decode")

    // Nothing more is parsed once it is refused.
    #expect(throws: StreamedPcm.Trouble.notDecodedHere) { try source.take(Data([0, 1, 2, 3])) }
}

@Test func aFormatThatDecodesIsNotRefused() throws {
    let source = try SilentRecord.source(seconds: 1)
    #expect(!source.notDecodedHere)
    #expect(source.ready)
}

@Test func onlyAc3AndEnhancedAc3AreDolby() {
    #expect(StreamedPcm.isDolby(kAudioFormatAC3))
    #expect(StreamedPcm.isDolby(kAudioFormatEnhancedAC3))
    #expect(!StreamedPcm.isDolby(kAudioFormatMPEG4AAC))
    #expect(!StreamedPcm.isDolby(kAudioFormatAppleLossless))
    #expect(!StreamedPcm.isDolby(kAudioFormatFLAC))
}

@Suite("An original this device cannot decode", .serialized)
@MainActor
struct DolbyOriginalTests {

    private func player(_ store: SilentStore, copies: any PhoneCopies = NoCopies(),
                        nearby: any NearbyCopies = NothingNearby(),
                        found: FoundUndecodable) -> Player {
        let rpm = Player(source: OriginalOrCopy(store: store), shelves: AnyShelf(),
                         copies: copies, nearby: nearby, reach: NetworkReach(),
                         levelling: .album, levelsClassical: false,
                         classical: { _ in false }, cover: { _ in nil }, found: found)
        rpm.kilobits = AudioLadder.original
        return rpm
    }

    /// **The safety net.** The original is refused from its header, and the copy plays in the same
    /// start: no message, and the track is remembered. The next play asks for the copy at once.
    @Test func aDolbyOriginalPlaysFromItsCopyWithNoMessage() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }
        store.serves(try Data(contentsOf: try dolby()), for: "d1-original", headers: [:])

        let found = FoundUndecodable()
        let rpm = player(store, found: found)

        await rpm.play([track("d1")], from: 0, because: .somebodyAskedForIt)
        try await until("the copy to play") { rpm.isPlaying }

        #expect(rpm.trouble == nil, "a message was shown: \(rpm.trouble ?? "")")
        #expect(rpm.failure == .none)
        #expect(found.contains("d1"))
        #expect(store.asked.filter { $0 == "d1-original" }.count == 1)
        #expect(store.asked.contains("d1"), "the copy was not asked for")
        rpm.stop()

        await rpm.play([track("d1")], from: 0, because: .somebodyAskedForIt)
        try await until("the copy to play again") { rpm.isPlaying }

        #expect(store.asked.filter { $0 == "d1-original" }.count == 1,
                "the original was asked for again")
        rpm.stop()
    }

    /// The look-ahead does the same for the next record, so the queue moves on to its copy.
    @Test func theLookAheadAsksForTheCopyOfTheNextRecord() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }
        store.serves(try Data(contentsOf: try dolby()), for: "d2-original", headers: [:])

        let found = FoundUndecodable()
        let rpm = player(store, found: found)

        await rpm.play([track("plain"), track("d2")], from: 0, because: .somebodyAskedForIt)
        try await until("the look-ahead to fetch the copy") { store.asked.contains("d2") }

        #expect(found.contains("d2"))
        #expect(rpm.trouble == nil)
        rpm.stop()
    }

    /// A copy that is refused as well is a real failure. It is reported, and nothing is asked for
    /// a third time.
    @Test func aCopyThatIsRefusedTooIsReported() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }
        let bytes = try Data(contentsOf: try dolby())
        store.serves(bytes, for: "d3-original", headers: [:])
        store.serves(bytes, for: "d3", headers: [:])

        let rpm = player(store, found: FoundUndecodable())

        await rpm.play([track("d3")], from: 0, because: .somebodyAskedForIt)

        #expect(rpm.failure == .notPlayable)
        #expect(rpm.trouble != nil)
        #expect(store.asked.filter { $0 == "d3-original" }.count == 1)
        #expect(store.asked.filter { $0 == "d3" }.count == 1)
    }

    /// A downloaded original that does not decode here is streamed from the copy.
    @Test func aDownloadedDolbyOriginalIsStreamedFromTheCopy() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }

        let found = FoundUndecodable()
        let rpm = player(store, copies: HeldDolby(rpmId: "d4", file: try dolby()), found: found)

        await rpm.play([track("d4")], from: 0, because: .somebodyAskedForIt)
        try await until("the copy to play") { rpm.isPlaying }

        #expect(rpm.trouble == nil)
        #expect(found.contains("d4"))
        #expect(store.asked.contains("d4"))
        #expect(!store.asked.contains("d4-original"), "the original was signed as well")
        rpm.stop()
    }

    /// A computer on the home network that serves a Dolby original is not reported as failed: it
    /// answered. The copy comes from the cloud, and the computer is not asked for the track again.
    @Test func aComputerWithADolbyOriginalIsNotMarkedAway() async throws {
        let store = SilentStore()
        try await store.start()
        defer { store.stop() }
        store.serves(try Data(contentsOf: try dolby()), for: "near-d5", headers: [:])

        let found = FoundUndecodable()
        let computer = DolbyComputer(store: store)
        let rpm = player(store, nearby: computer, found: found)

        await rpm.play([track("d5")], from: 0, because: .somebodyAskedForIt)
        try await until("the copy to play") { rpm.isPlaying }

        #expect(rpm.trouble == nil)
        #expect(computer.failed.isEmpty, "the computer was marked away")
        #expect(found.contains("d5"))
        #expect(store.asked.contains("d5"))
        rpm.stop()

        await rpm.play([track("d5")], from: 0, because: .somebodyAskedForIt)
        try await until("the copy to play again") { rpm.isPlaying }

        #expect(computer.asked.filter { $0 == "d5" }.count == 1, "the computer was asked again")
        rpm.stop()
    }
}
