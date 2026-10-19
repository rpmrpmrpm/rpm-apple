import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// What the downloader does when the store answers a sign request with a live encode. It does not
/// download the file. It asks the store to make the rendition and shows the album as preparing. The
/// store in these tests always answers live, so no transfer starts.
@MainActor
@Suite("Downloading a rate the store has not made", .serialized)
struct AlbumDownloadsTests {
    /// A store that has made nothing at any rate.
    actor NothingMade {
        private(set) var signed: [(rpmId: String, kilobits: Int)] = []
        private(set) var asked: [(rpmIds: [String], kilobits: Int)] = []
        private var failing = 0

        func failNextAsk() { failing += 1 }

        func sign(_ rpmId: String, _ kilobits: Int) -> (url: URL, kilobits: Int, kind: StreamKind) {
            signed.append((rpmId, kilobits))
            return (URL(string: "https://transcoder.invalid/live")!, kilobits, .live)
        }

        func make(_ rpmIds: [String], _ kilobits: Int) throws {
            if failing > 0 {
                failing -= 1
                throw RPMError.refused(status: 400, reason: nil)
            }
            asked.append((rpmIds, kilobits))
        }
    }

    /// The rate the downloader reads, changeable by a test.
    @MainActor final class Setting { var kilobits = 320 }

    private let store = NothingMade()
    private let setting = Setting()
    private let book = DownloadBook(root: FileManager.default.temporaryDirectory
        .appendingPathComponent("rpm-downloads-\(UUID().uuidString)", isDirectory: true))

    private func downloads() -> AlbumDownloads {
        let store = self.store
        let setting = self.setting
        return AlbumDownloads(
            book: book, reach: NetworkReach(),
            sign: { try await store.sign($0, $1) },
            make: { try await store.make($0, $1) },
            rate: { setting.kilobits })
    }

    private func album(_ key: String, _ ids: [String]) -> CloudAlbum {
        CloudAlbum(key: key, album: key, artist: "Talk Talk",
                   tracks: ids.map { CloudTrack(rpmId: $0, title: $0, album: key) })
    }

    /// Waits for the pump that `download` starts by itself. A second pump would only join that one.
    private func until(_ done: @escaping () async -> Bool) async {
        for _ in 0..<200 {
            if await done() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aLiveAnswerIsNotDownloadedAndTheStoreIsAskedToMakeIt() async {
        let downloads = downloads()
        downloads.download(album("a", ["t1", "t2", "t3"]))
        await until { await !self.store.asked.isEmpty }

        let asked = await store.asked
        #expect(asked.count == 1)
        #expect(asked.first?.rpmIds == ["t1", "t2", "t3"])
        #expect(asked.first?.kilobits == 320)

        #expect(downloads.standing(of: "a")
            == .downloading(have: 0, of: 3, fraction: 0, preparing: true))

        // Every track signed once, and none again before its wait is up.
        await downloads.pump()
        #expect(await store.signed.count == 3)
        #expect(await store.asked.count == 1)
        #expect(book.held("t1") == nil)
    }

    /// The store starts the transcoder at most once every thirty seconds, and each run reads the want list
    /// once. Tracks that are added later wait for the five-minute schedule. So the whole album goes in the
    /// first ask, before the tracks are signed one at a time.
    @Test func theFirstLiveAnswerAsksForEveryTrackStillToCome() async {
        let downloads = downloads()
        downloads.download(album("a", ["t1", "t2", "t3", "t4", "t5", "t6"]))
        await until { await self.store.signed.count == 6 }
        await downloads.pump()

        let asked = await store.asked
        #expect(asked.first?.rpmIds == ["t1", "t2", "t3", "t4", "t5", "t6"])
        #expect(asked.count == 1, "the tracks signed after the first ask were asked for again")
    }

    @Test func anAskThatFailedIsSentAgainOnTheNextPass() async {
        await store.failNextAsk()
        let downloads = downloads()
        downloads.download(album("a", ["t1", "t2"]))
        await until { await self.store.signed.count == 2 }
        await downloads.pump()

        let asked = await store.asked
        #expect(asked.count == 1)
        #expect(asked.first?.rpmIds == ["t1", "t2"])

        // Not signed again: the ask is what was lost, not the answer.
        #expect(await store.signed.count == 2)
    }

    @Test func removingAnAlbumThatIsPreparingEndsItsWait() async {
        let downloads = downloads()
        downloads.download(album("a", ["t1", "t2"]))
        await until { await !self.store.asked.isEmpty }

        downloads.remove(["a"])
        #expect(downloads.standing(of: "a") == nil)

        await downloads.pump()
        #expect(await store.signed.count == 2)
        #expect(await store.asked.count == 1)
    }

    @Test func aChangeOfRateSignsAgainAtOnceAndAsksAtTheNewRate() async {
        let downloads = downloads()
        downloads.download(album("a", ["t1", "t2"]))
        await until { await !self.store.asked.isEmpty }

        setting.kilobits = 256
        await downloads.pump()

        let signed = await store.signed
        #expect(signed.map(\.kilobits) == [320, 320, 256, 256])

        let asked = await store.asked
        #expect(asked.map(\.kilobits) == [320, 256])
        #expect(asked.last?.rpmIds == ["t1", "t2"])
    }

    @Test func tryingAgainStartsTheWaitOver() async {
        let downloads = downloads()
        let record = album("a", ["t1"])
        downloads.download(record)
        await until { await !self.store.asked.isEmpty }

        downloads.download(record)
        await until { await self.store.asked.count == 2 }

        #expect(await store.signed.count == 2)
        #expect(await store.asked.count == 2)
    }
}
