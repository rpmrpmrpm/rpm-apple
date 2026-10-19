import Foundation
import Testing
import RPMKit
import RPMRadio
@testable import RPMSession

/// The last queue, kept between runs.
@Suite struct KeptQueueTests {
    private func folder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("rpm.tests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func tracks(_ count: Int) -> [CloudTrack] {
        (0..<count).map { CloudTrack(rpmId: "t\($0)", relativePath: "x/t\($0).flac", title: "t\($0)",
                                     artist: "Talk Talk", album: "Spirit of Eden", tags: nil) }
    }

    @Test func aQueueIsReadBackAsItWasKept() async throws {
        let file = KeptQueueFile(folder: try folder())
        let what = KeptQueue.What.tracks(tracks(4), at: 2, seconds: 31.5)

        await file.write(KeptQueue(account: "a", what: what))

        #expect(await file.read(for: "a") == what)
    }

    @Test func aStationIsReadBackAsItWasKept() async throws {
        let file = KeptQueueFile(folder: try folder())
        let what = KeptQueue.What.station(RadioStation(uuid: "s1", name: "Radio 538",
                                                       streamUrl: "http://example.invalid/538"))

        await file.write(KeptQueue(account: "a", what: what))

        #expect(await file.read(for: "a") == what)
    }

    /// A different account on the same TV does not see the previous account's queue.
    @Test func anotherAccountFindsNothing() async throws {
        let file = KeptQueueFile(folder: try folder())
        await file.write(KeptQueue(account: "a", what: .tracks(tracks(2), at: 0, seconds: 0)))

        #expect(await file.read(for: "b") == nil)
    }

    @Test func forgettingLeavesNothing() async throws {
        let file = KeptQueueFile(folder: try folder())
        await file.write(KeptQueue(account: "a", what: .tracks(tracks(2), at: 1, seconds: 5)))

        await file.write(nil)

        #expect(await file.read(for: "a") == nil)
    }

    /// The newest write is the one kept.
    @Test func aLaterQueueReplacesTheEarlier() async throws {
        let file = KeptQueueFile(folder: try folder())
        await file.write(KeptQueue(account: "a", what: .tracks(tracks(2), at: 0, seconds: 0)))
        let later = KeptQueue.What.tracks(tracks(5), at: 4, seconds: 12)

        await file.write(KeptQueue(account: "a", what: later))

        #expect(await file.read(for: "a") == later)
    }

    /// A track position past the end of the list is not a queue that can be restored.
    @Test func aPlaceOutsideTheListFindsNothing() async throws {
        let file = KeptQueueFile(folder: try folder())
        await file.write(KeptQueue(account: "a", what: .tracks(tracks(2), at: 5, seconds: 0)))

        #expect(await file.read(for: "a") == nil)
    }

    @Test func nothingKeptFindsNothing() async throws {
        #expect(await KeptQueueFile(folder: try folder()).read(for: "a") == nil)
    }
}
