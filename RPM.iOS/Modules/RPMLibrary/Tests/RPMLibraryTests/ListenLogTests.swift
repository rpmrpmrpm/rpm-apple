import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// The listens this phone has not sent yet. Every listen worth writing down goes to the store, which cuts
/// the lists that read the log. They are kept here until the store has taken them, across launches and
/// without a signal.
struct ListenLogTests {
    private func note(_ log: ListenLog, _ rpmId: String, at: Int64 = 1_790_000_000, counted: Bool = true) async {
        await log.note(rpmId: rpmId, at: at, heardSeconds: counted ? 200 : 20, lengthSeconds: 240,
                       counted: counted, localHour: 22, localDayOfWeek: 3)
    }

    @Test func aListenIsKeptWithAnIdOfItsOwnUntilItIsSent() async {
        let log = ListenLog(inMemory: true)
        await note(log, "t1")
        await note(log, "t1", counted: false)

        let unsent = await log.unsent(limit: 50, in: log.pass())
        #expect(unsent.count == 2)
        #expect(Set(unsent.map(\.listenId)).count == 2)
        #expect(unsent[0].rpmId == "t1")
        #expect(unsent[0].counted)
        #expect(!unsent[1].counted)
        #expect(unsent[0].localHour == 22)
        #expect(unsent[0].localDayOfWeek == 3)

        await log.noteSent(unsent, in: log.pass())
        #expect(await log.unsent(limit: 50, in: log.pass()).isEmpty)
    }

    @Test func aListenOfATrackWithNoCloudIdIsNotKept() async {
        let log = ListenLog(inMemory: true)
        await note(log, "")
        #expect(await log.unsent(limit: 50, in: log.pass()).isEmpty)
    }

    /// The store does not hold a starter track, so a listen of one is not kept for it.
    @Test func aListenOfAStarterTrackIsNotKept() async throws {
        let log = ListenLog(inMemory: true)
        let starter = try #require(StarterTracks.tracks.first).rpmId
        await note(log, starter)
        await note(log, "t1")
        #expect(await log.unsent(limit: 50, in: log.pass()).map(\.rpmId) == ["t1"])
    }

    @Test func oldestGoFirstAndTheRestWait() async {
        let log = ListenLog(inMemory: true)
        for i in 0..<5 { await note(log, "t\(i)", at: 1_790_000_000 + Int64(i)) }

        let first = await log.unsent(limit: 3, in: log.pass())
        #expect(first.map(\.rpmId) == ["t0", "t1", "t2"])
        await log.noteSent(first, in: log.pass())

        #expect(await log.unsent(limit: 3, in: log.pass()).map(\.rpmId) == ["t3", "t4"])
    }

    /// A listen noted while a send was on its way is not marked sent by that send's answer.
    @Test func aListenNotedDuringASendStaysUnsent() async {
        let log = ListenLog(inMemory: true)
        await note(log, "t1")
        let sending = await log.unsent(limit: 50, in: log.pass())
        await note(log, "t2")

        await log.noteSent(sending, in: log.pass())

        #expect(await log.unsent(limit: 50, in: log.pass()).map(\.rpmId) == ["t2"])
    }

    @Test func listensSurviveARelaunch() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let path = folder.appendingPathComponent("listens.json.z")

        let first = ListenLog(at: path)
        await note(first, "t1")

        let again = ListenLog(at: path)
        await again.load()
        #expect(await again.unsent(limit: 50, in: again.pass()).map(\.rpmId) == ["t1"])
    }

    /// Signing out clears the log, and a pass that began before it changes nothing after it: the next
    /// account must not send the last one's listens.
    @Test func signingOutForgetsAndAnOlderPassDoesNothing() async {
        let log = ListenLog(inMemory: true)
        await note(log, "t1")
        let old = await log.pass()

        await log.forget()
        await note(log, "t2")

        #expect(await log.unsent(limit: 50, in: old).isEmpty)
        await log.noteSent([CloudListen(listenId: "x", rpmId: "t2", at: 1, heardSeconds: 1, lengthSeconds: 1,
                                        counted: true, localHour: 0, localDayOfWeek: 0)], in: old)
        #expect(await log.unsent(limit: 50, in: log.pass()).map(\.rpmId) == ["t2"])
    }

    /// A phone that never reaches the store does not grow the file without end. The oldest go first.
    @Test func theLogKeepsAtMostItsCeiling() async {
        let log = ListenLog(inMemory: true, keepAtMost: 3)
        for i in 0..<5 { await note(log, "t\(i)", at: Int64(i)) }

        #expect(await log.unsent(limit: 50, in: log.pass()).map(\.rpmId) == ["t2", "t3", "t4"])
    }
}
