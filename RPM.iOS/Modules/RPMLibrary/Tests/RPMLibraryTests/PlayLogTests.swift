import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// What this phone has played, and what the owner's other devices have played.
///
/// The two are kept apart. If they were added together, the store could no longer tell which plays belong to
/// this phone. It could then not send its plays without risking a count that is added twice.
struct PlayLogTests {
    private func row(_ id: String, _ device: String, plays: Int64,
                     at lastPlayed: Int64 = 1, stamp: Int64 = 1) -> CloudTrackPlays {
        CloudTrackPlays(rpmId: id, deviceId: device, plays: plays,
                        lastPlayedAt: lastPlayed, updatedAt: stamp)
    }

    @Test func aPlayIsCountedAndCanBeSent() async {
        let log = PlayLog(inMemory: true)

        await log.note(rpmId: "t1", at: 500)

        #expect(await log.plays(of: "t1") == 1)
        #expect(await log.lastPlayed(of: "t1") == 500)
        let unsent = await log.unsent(limit: 50, in: log.pass())
        #expect(unsent.count == 1)
        #expect(unsent[0].plays == 1)
    }

    @Test func aPlayOfATrackWithNoCloudIdIsNotCounted() async {
        // There is nothing for a row to be keyed on. This is a guard, not a normal case: the phone
        // plays only what the cloud holds. A row keyed on an empty string would be sent to the
        // store and refused.
        let log = PlayLog(inMemory: true)

        await log.note(rpmId: "", at: 500)

        #expect(await log.unsent(limit: 50, in: log.pass()).isEmpty)
    }

    @Test func whatHasBeenSentIsNotOfferedAgain() async {
        let log = PlayLog(inMemory: true)
        await log.note(rpmId: "t1", at: 500)

        await log.noteSent(await log.unsent(limit: 50, in: log.pass()), in: log.pass())

        #expect(await log.unsent(limit: 50, in: log.pass()).isEmpty)
    }

    @Test func aPlayAfterASendIsOfferedAgainAsTheNewTotal() async {
        let log = PlayLog(inMemory: true)
        await log.note(rpmId: "t1", at: 500)
        await log.noteSent(await log.unsent(limit: 50, in: log.pass()), in: log.pass())

        await log.note(rpmId: "t1", at: 600)

        let unsent = await log.unsent(limit: 50, in: log.pass())
        #expect(unsent.count == 1)
        // The total, not the one new play: what travels is this device's own total.
        #expect(unsent[0].plays == 2)
    }

    @Test func aForeignRowAddsToTheTotalAndNotToWhatIsSent() async {
        let log = PlayLog(inMemory: true)
        await log.note(rpmId: "t1", at: 500)

        _ = await log.apply([row("t1", "desk", plays: 4, at: 900)], mine: "phone", in: log.pass())

        #expect(await log.plays(of: "t1") == 5)
        #expect(await log.lastPlayed(of: "t1") == 900)
        let unsent = await log.unsent(limit: 50, in: log.pass())
        #expect(unsent[0].plays == 1)
    }

    @Test func thisPhonesOwnRowComingBackIsIgnored() async {
        // The listing returns every row the listener has, including this phone's own. If it were applied as a
        // foreign row, this phone's count would be doubled on every pull.
        let log = PlayLog(inMemory: true)
        await log.note(rpmId: "t1", at: 500)

        let applied = await log.apply([row("t1", "phone", plays: 1, at: 500)], mine: "phone", in: log.pass())

        #expect(applied == 0)
        #expect(await log.plays(of: "t1") == 1)
    }

    @Test func theSameForeignRowAppliedTwiceMovesNothing() async {
        let log = PlayLog(inMemory: true)
        let arrived = row("t1", "desk", plays: 4, at: 900)

        _ = await log.apply([arrived], mine: "phone", in: log.pass())
        let again = await log.apply([arrived], mine: "phone", in: log.pass())

        #expect(again == 0)
        #expect(await log.plays(of: "t1") == 4)
    }

    @Test func aForeignRowThatGoesBackwardsTakesItsDifferenceBack() async {
        let log = PlayLog(inMemory: true)
        _ = await log.apply([row("t1", "desk", plays: 5, at: 900)], mine: "phone", in: log.pass())

        _ = await log.apply([row("t1", "desk", plays: 1, at: 900, stamp: 2)], mine: "phone", in: log.pass())

        #expect(await log.plays(of: "t1") == 1)
    }

    @Test func everyDeviceCounts() async {
        let log = PlayLog(inMemory: true)
        await log.note(rpmId: "t1", at: 100)

        _ = await log.apply([row("t1", "desk", plays: 4, at: 900),
                             row("t1", "laptop", plays: 2, at: 300)], mine: "phone", in: log.pass())

        #expect(await log.plays(of: "t1") == 7)
        #expect(await log.lastPlayed(of: "t1") == 900)
    }

    @Test func aRowForATrackThisPhoneDoesNotKnowIsKept() async {
        // The row is kept, not dropped. On a cold launch the play rows can arrive before the
        // library listing, and a dropped row would have to be asked for again.
        let log = PlayLog(inMemory: true)

        _ = await log.apply([row("unknown", "desk", plays: 2)], mine: "phone", in: log.pass())

        #expect(await log.plays(of: "unknown") == 2)
    }

    @Test func aTrackNobodyHasPlayedReadsAsNothing() async {
        let log = PlayLog(inMemory: true)

        #expect(await log.plays(of: "t1") == 0)
        #expect(await log.lastPlayed(of: "t1") == 0)
    }

    @Test func theCursorIsTheNewestStampTakenIn() async {
        let log = PlayLog(inMemory: true)

        _ = await log.apply([row("t1", "desk", plays: 1, stamp: 7),
                             row("t2", "desk", plays: 1, stamp: 4)], mine: "phone", in: log.pass())

        #expect(await log.cursor == 7)
    }

    /// A row this phone wrote itself does not move the cursor. The cursor records what has been
    /// taken in from other devices. If the cursor followed this phone's own echo, the next pull
    /// would skip other devices' rows written in between.
    @Test func thisPhonesOwnRowDoesNotMoveTheCursor() async {
        let log = PlayLog(inMemory: true)

        _ = await log.apply([row("t1", "phone", plays: 1, stamp: 9)], mine: "phone", in: log.pass())

        #expect(await log.cursor == 0)
    }

    @Test func itSurvivesBeingWrittenAndReadBack() async {
        let file = URL.temporaryDirectory.appending(path: "plays-\(UUID().uuidString).json.z")
        defer { try? FileManager.default.removeItem(at: file) }

        let log = PlayLog(at: file)
        await log.note(rpmId: "t1", at: 500)
        _ = await log.apply([row("t1", "desk", plays: 4, at: 900, stamp: 10)], mine: "phone", in: log.pass())
        await log.save()

        let again = PlayLog(at: file)
        await again.load()

        #expect(await again.plays(of: "t1") == 5)
        #expect(await again.unsent(limit: 50, in: again.pass())[0].plays == 1)
        #expect(await again.cursor == 10)
    }

    /// A play is written to disk as soon as it is counted.
    ///
    /// The sync pass does not do the only save. Plays counted while the phone is offline would
    /// exist only in memory, and iOS can end a backgrounded app without warning. Writing a few
    /// kilobytes once per track is cheap by comparison.
    @Test func aPlayIsOnTheDiskAsSoonAsItIsCounted() async {
        let file = URL.temporaryDirectory.appending(path: "plays-\(UUID().uuidString).json.z")
        defer { try? FileManager.default.removeItem(at: file) }

        let log = PlayLog(at: file)
        await log.note(rpmId: "t1", at: 500)

        let again = PlayLog(at: file)
        await again.load()
        #expect(await again.plays(of: "t1") == 1)
    }

    /// A row taken in from another device is also written to disk. Then a pull that completed is
    /// not read again from zero after a launch that did not reach its push.
    @Test func rowsTakenInAreOnTheDiskToo() async {
        let file = URL.temporaryDirectory.appending(path: "plays-\(UUID().uuidString).json.z")
        defer { try? FileManager.default.removeItem(at: file) }

        let log = PlayLog(at: file)
        _ = await log.apply([row("t1", "desk", plays: 4, stamp: 12)], mine: "phone", in: log.pass())

        let again = PlayLog(at: file)
        await again.load()
        #expect(await again.plays(of: "t1") == 4)
        #expect(await again.cursor == 12)
    }

    /// A log that cannot be read leaves the phone with no play history, but the app must still
    /// open. A read error must not throw when the user opens their music.
    @Test func aLogThatWillNotReadIsAnEmptyLog() async {
        let file = URL.temporaryDirectory.appending(path: "plays-\(UUID().uuidString).json.z")
        defer { try? FileManager.default.removeItem(at: file) }
        try? Data("not a log".utf8).write(to: file)

        let log = PlayLog(at: file)
        await log.load()

        #expect(await log.plays(of: "t1") == 0)
    }

    /// The file that could not be read is moved aside, and the next play is not written over it.
    @Test func aLogThatDoesNotParseIsMovedAsideNotWrittenOver() async {
        let file = URL.temporaryDirectory.appending(path: "plays-\(UUID().uuidString).json.z")
        let aside = file.appendingPathExtension("unreadable")
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: aside)
        }
        try? Data("not a log".utf8).write(to: file)

        let log = PlayLog(at: file)
        await log.load()
        await log.note(rpmId: "t1", at: 5)

        #expect((try? Data(contentsOf: aside)) == Data("not a log".utf8))
    }

    /// A log that exists but could not be read this session is not written to. Its plays are still
    /// there on the next launch.
    @Test func aLogThatCouldNotBeReadIsNotWrittenOver() async throws {
        let file = URL.temporaryDirectory.appending(path: "plays-\(UUID().uuidString).json.z")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try? FileManager.default.removeItem(at: file)
        }

        let first = PlayLog(at: file)
        await first.note(rpmId: "t1", at: 5)
        let before = try Data(contentsOf: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: file.path)

        let second = PlayLog(at: file)
        await second.load()
        await second.note(rpmId: "t2", at: 6)

        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(try Data(contentsOf: file) == before)
    }

    /// Signing out clears everything. The next account to sign in on this phone must not see the previous
    /// account's plays, or send its unsent plays under its own name.
    @Test func forgettingLeavesNoPlaysNothingToSendAndNoCursor() async {
        let log = PlayLog(inMemory: true)
        await log.note(rpmId: "t1", at: 500)
        _ = await log.apply([row("t2", "desk", plays: 3, stamp: 9)], mine: "phone", in: log.pass())

        await log.forget()

        #expect(await log.unsent(limit: 50, in: log.pass()).isEmpty)
        #expect(await log.everythingPlayed().isEmpty)
        #expect(await log.cursor == 0)
    }

    /// The file is deleted too, so a launch after signing out does not read the previous account's
    /// plays back.
    @Test func forgettingRemovesTheFile() async {
        let file = URL.temporaryDirectory.appending(path: "plays-\(UUID().uuidString).json.z")
        defer { try? FileManager.default.removeItem(at: file) }

        let log = PlayLog(at: file)
        await log.note(rpmId: "t1", at: 5)
        #expect(FileManager.default.fileExists(atPath: file.path))

        await log.forget()

        #expect(!FileManager.default.fileExists(atPath: file.path))
        let again = PlayLog(at: file)
        await again.load()
        #expect(await again.plays(of: "t1") == 0)
    }

    /// This also applies to a file that could not be read this session. Its contents belong to the
    /// account that is signing out. Keeping the file would let the next account send them.
    @Test func forgettingRemovesAFileThatCouldNotBeRead() async throws {
        let file = URL.temporaryDirectory.appending(path: "plays-\(UUID().uuidString).json.z")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try? FileManager.default.removeItem(at: file)
        }

        let first = PlayLog(at: file)
        await first.note(rpmId: "t1", at: 5)
        try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: file.path)

        let second = PlayLog(at: file)
        await second.load()
        await second.forget()

        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    /// A sync pass that is still running when the user signs out. What it brings back belongs to
    /// the account that left, so it is not written into the log that the next account starts with.
    /// It is also given none of the next account's plays to send under the old device id.
    @Test func aPassFromBeforeForgettingReadsAndWritesNothing() async {
        let log = PlayLog(inMemory: true)
        let before = await log.pass()

        await log.forget()
        await log.note(rpmId: "next", at: 7)

        #expect(await log.apply([row("t1", "desk", plays: 4, stamp: 12)], mine: "phone", in: before) == 0)
        await log.noteCursor(12, in: before)
        #expect(await log.unsent(limit: 50, in: before).isEmpty)
        await log.noteSent([TrackPlaysEntry(rpmId: "next", plays: 1, lastPlayedAt: 7)], in: before)

        #expect(await log.plays(of: "t1") == 0)
        #expect(await log.cursor == 0)
        // The next account's play is still to send, by a pass of its own.
        #expect(await log.unsent(limit: 50, in: log.pass()).count == 1)
    }
}
