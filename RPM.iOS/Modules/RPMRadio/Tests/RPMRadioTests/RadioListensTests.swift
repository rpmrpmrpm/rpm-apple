import Foundation
import Testing
import RPMKit
@testable import RPMRadio

/// The phone's station log. This phone's rows and the rows from other devices are kept apart.
/// A station's total is the sum of the two. Sent listens are recorded in the amounts sent.
/// The desktop's `RadioListensSyncTests` checks the same rules, so change both together.
///
/// A sync pass can overlap with sign-out. A pass that started before sign-out must not write
/// into the next account's log, so each pass is checked against the current log.
struct RadioListensTests {
    private func station(_ uuid: String, _ name: String = "S") -> RadioStation {
        RadioStation(uuid: uuid, name: name, streamUrl: "https://example.invalid/\(uuid)")
    }

    private func row(_ device: String, _ uuid: String, heard: Double, tunes: Int = 1,
                     at: Int64 = 1_700_000_000, name: String = "S", stamp: Int64 = 1) -> CloudStationListens {
        CloudStationListens(uuid: uuid, deviceId: device, heardSeconds: heard, tunes: tunes,
                            lastHeardAt: at,
                            station: CloudListenedStation(of: station(uuid, name)),
                            updatedAt: stamp)
    }

    private func temporaryFile() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("radio-listens-\(UUID().uuidString).json")
    }

    @Test func aNewLogNamesItselfAndKeepsTheName() async {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let name = await RadioListens(file: file).device
        #expect(name?.isEmpty == false)
        #expect(await RadioListens(file: file).device == name)
    }

    @Test func anotherDevicesListeningAddsToThisPhonesOwn() async {
        let log = RadioListens(file: nil)
        await log.note(station("a"), seconds: 600, newTune: true, at: 10)
        await log.apply([row("desk", "a", heard: 400, tunes: 2)], in: log.pass()!)

        let top = await log.top(5)
        #expect(top.count == 1)
        #expect(top.first?.heardSeconds == 1000)
        #expect(top.first?.tunes == 3)
    }

    /// Each row is a device's running total. Applying the same row again replaces the old value
    /// rather than adding to it.
    @Test func aDevicesRowReplacesItsLastValue() async {
        let log = RadioListens(file: nil)
        await log.apply([row("desk", "a", heard: 400)], in: log.pass()!)
        await log.apply([row("desk", "a", heard: 400)], in: log.pass()!)
        #expect(await log.top(5).first?.heardSeconds == 400)

        await log.apply([row("desk", "a", heard: 900)], in: log.pass()!)
        #expect(await log.top(5).first?.heardSeconds == 900)
    }

    /// The sync listing includes the row at the cursor's timestamp, so the newest row comes back
    /// on each pass. A row that is already held must not count as new, or the log is written again.
    @Test func aRowAlreadyHeldAsItIsIsNotTakenAgain() async {
        let log = RadioListens(file: nil)

        #expect(await log.apply([row("desk", "a", heard: 400)], in: log.pass()!) == 1)
        #expect(await log.apply([row("desk", "a", heard: 400)], in: log.pass()!) == 0)
        #expect(await log.apply([row("desk", "a", heard: 460)], in: log.pass()!) == 1)
    }

    @Test func thisPhonesOwnRowComingBackIsLeftOut() async throws {
        let log = RadioListens(file: nil)
        await log.note(station("a"), seconds: 600, newTune: true, at: 10)
        let mine = try #require(await log.device)

        #expect(await log.apply([row(mine, "a", heard: 600)], in: log.pass()!) == 0)
        #expect(await log.top(5).first?.heardSeconds == 600)
    }

    /// A station heard only on another device still appears in this phone's list, with the
    /// stream details that device sent. The phone can then show and play it.
    @Test func aStationHeardOnlyElsewhereCanBePlayedHere() async {
        let log = RadioListens(file: nil)
        await log.apply([row("desk", "b", heard: 900, name: "Only on the desk")], in: log.pass()!)

        let top = await log.top(5)
        #expect(top.first?.station.name == "Only on the desk")
        #expect(top.first?.station.streamUrl == "https://example.invalid/b")
    }

    /// Parts of one listen are added together. Only the first part counts as a new tuning.
    @Test func thePartsOfOneListenAreOneTuning() async {
        let log = RadioListens(file: nil)
        await log.note(station("a"), seconds: 300, newTune: true, at: 10)
        await log.note(station("a"), seconds: 300, newTune: false, at: 20)

        let top = await log.top(5)
        #expect(top.first?.heardSeconds == 600)
        #expect(top.first?.tunes == 1)
    }

    @Test func onlyThisPhonesOwnListeningIsSent() async {
        let log = RadioListens(file: nil)
        await log.note(station("a"), seconds: 600, newTune: true, at: 10)
        await log.apply([row("desk", "b", heard: 900)], in: log.pass()!)

        let due = await log.unsent(limit: 10, in: log.pass()!)
        #expect(due.map(\.uuid) == ["a"])
        #expect(due.first?.heardSeconds == 600)
        #expect(due.first?.station.name == "S")
    }

    /// Sent listens are recorded from the list read for sending. A listen noted after
    /// that read is still unsent.
    @Test func aListenNotedWhileSendingIsStillDue() async {
        let log = RadioListens(file: nil)
        await log.note(station("a"), seconds: 600, newTune: true, at: 10)

        let due = await log.unsent(limit: 10, in: log.pass()!)
        await log.note(station("a"), seconds: 60, newTune: false, at: 20)
        await log.noteSent(due, in: log.pass()!)

        #expect(await log.unsent(limit: 10, in: log.pass()!).first?.heardSeconds == 660)

        await log.noteSent(await log.unsent(limit: 10, in: log.pass()!), in: log.pass()!)
        #expect(await log.unsent(limit: 10, in: log.pass()!).isEmpty)
    }

    @Test func whatWasSentAndTakenInIsThereOnTheNextLaunch() async {
        let file = temporaryFile()
        defer { try? FileManager.default.removeItem(at: file) }

        let log = RadioListens(file: file)
        await log.note(station("a"), seconds: 600, newTune: true, at: 10)
        await log.noteSent(await log.unsent(limit: 10, in: log.pass()!), in: log.pass()!)
        await log.apply([row("desk", "b", heard: 900)], in: log.pass()!)
        await log.noteCursor(1_700_000_123, in: log.pass()!)

        let again = RadioListens(file: file)
        #expect(await again.unsent(limit: 10, in: again.pass()!).isEmpty)
        #expect(await again.cursor == 1_700_000_123)
        #expect(await again.top(5).map(\.station.uuid) == ["b", "a"])
    }

    /// A log that cannot be parsed is renamed, not overwritten. The phone then starts a new log
    /// with a new device name.
    @Test func aLogThatDoesNotParseIsMovedAside() async throws {
        let file = temporaryFile()
        defer {
            try? FileManager.default.removeItem(at: file)
            try? FileManager.default.removeItem(at: file.appendingPathExtension("unreadable"))
        }
        try Data("{ not json".utf8).write(to: file)

        let log = RadioListens(file: file)

        #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("unreadable").path))
        #expect(await log.device != nil)
    }

    /// A log that exists but cannot be read is not written or synced this session. A new device
    /// name would make this phone's own rows look like another device's rows.
    @Test func aLogThatCouldNotBeReadDoesNotSync() async throws {
        let file = temporaryFile()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try? FileManager.default.removeItem(at: file)
        }

        let first = RadioListens(file: file)
        await first.note(station("a"), seconds: 600, newTune: true, at: 10)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)

        #expect(await RadioListens(file: file).device == nil)
    }

    /// Signing out clears the log and gives the device a new name. The next account neither sees
    /// nor sends the old listening.
    @Test func signingOutKeepsNothingAndTakesANewName() async {
        let log = RadioListens(file: nil)
        await log.note(station("a"), seconds: 600, newTune: true, at: 10)
        let before = await log.device

        await log.forget()

        #expect(await log.top(5).isEmpty)
        #expect(await log.unsent(limit: 10, in: log.pass()!).isEmpty)
        #expect(await log.device != before)
    }

    /// A sync pass still running when the user signs out must not write its results into the new
    /// account's log. The pass also gets none of the new account's unsent listens, because they
    /// would be sent under the old device name.
    @Test func aPassFromBeforeForgettingReadsAndWritesNothing() async throws {
        let log = RadioListens(file: nil)
        let before = try #require(await log.pass())

        await log.forget()
        await log.note(station("next"), seconds: 120, newTune: true, at: 20)

        #expect(await log.apply([row("desk", "b", heard: 900, stamp: 12)], in: before) == 0)
        await log.noteCursor(12, in: before)
        #expect(await log.unsent(limit: 10, in: before).isEmpty)

        #expect(await log.top(10).map(\.station.uuid) == ["next"])
        #expect(await log.cursor == 0)
        // The next account's listening is still to send, by a pass of its own.
        #expect(await log.unsent(limit: 10, in: log.pass()!).count == 1)
    }

    /// The log is replaced on sign-out, even if it could not be read this session. If the old file
    /// stayed, the next launch would read the previous account's listening and send it under the
    /// next account.
    @Test func forgettingReplacesALogThatCouldNotBeRead() async throws {
        let file = temporaryFile()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            try? FileManager.default.removeItem(at: file)
        }

        let first = RadioListens(file: file)
        await first.note(station("a"), seconds: 600, newTune: true, at: 10)
        try FileManager.default.setAttributes([.posixPermissions: 0o200], ofItemAtPath: file.path)

        let second = RadioListens(file: file)
        #expect(await second.device == nil)
        await second.forget()

        // Make the file readable again, as it would be at the next launch. The file must hold the new log.
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let third = RadioListens(file: file)
        #expect(await third.top(10).isEmpty)
        #expect(await third.device != nil)
    }
}

/// Counts the time a station is playing, and hands that time out in parts. Listens shorter
/// than 30 seconds are not handed out, the same minimum as on the desktop.
@MainActor
struct StationCounterTests {
    /// A clock that the test controls.
    final class Clock {
        var now = Date(timeIntervalSince1970: 1_700_000_000)
        func advance(_ seconds: Double) { now += seconds }
    }

    private let one = RadioStation(uuid: "a", name: "A", streamUrl: "https://example.invalid/a")
    private let two = RadioStation(uuid: "b", name: "B", streamUrl: "https://example.invalid/b")

    /// Plays `seconds` of `station` in 0.25-second steps, the same pace as the counter's timer.
    private func play(_ counter: StationCounter, _ clock: Clock, _ station: RadioStation?,
                      seconds: Double, playing: Bool = true) -> [StationCounter.Heard] {
        var out: [StationCounter.Heard] = []
        var left = seconds
        while left > 0 {
            clock.advance(0.25)
            left -= 0.25
            if let heard = counter.read(station: station, playing: playing) { out.append(heard) }
        }
        return out
    }

    @Test func changingStationHandsOutTheListen() {
        let clock = Clock()
        let counter = StationCounter(now: { clock.now })

        _ = counter.read(station: one, playing: true)
        #expect(play(counter, clock, one, seconds: 60).isEmpty)

        let finished = counter.read(station: two, playing: true)
        #expect(finished?.station.uuid == "a")
        #expect(abs((finished?.seconds ?? 0) - 60) < 0.5)
        #expect(finished?.newTune == true)
    }

    /// Changing the dial through six stations is not six listens.
    @Test func aListenUnderTheFloorIsNotHandedOut() {
        let clock = Clock()
        let counter = StationCounter(now: { clock.now })

        _ = counter.read(station: one, playing: true)
        _ = play(counter, clock, one, seconds: 20)

        #expect(counter.read(station: nil, playing: false) == nil)
    }

    /// Only time when the station is playing counts. A stream that is reconnecting delivers no
    /// audio, so it is not counted.
    @Test func timeNotSoundingIsNotCounted() {
        let clock = Clock()
        let counter = StationCounter(now: { clock.now })

        _ = counter.read(station: one, playing: true)
        _ = play(counter, clock, one, seconds: 120, playing: false)
        _ = play(counter, clock, one, seconds: 40)

        let finished = counter.read(station: nil, playing: false)
        #expect(abs((finished?.seconds ?? 0) - 40) < 0.5)
    }

    /// A long listen is handed out in parts, and only the first part counts as a tuning. iOS can
    /// close a backgrounded app without warning. A listen held until the station changed would be lost.
    @Test func aLongListenIsHandedOutInPartsAsOneTuning() {
        let clock = Clock()
        let counter = StationCounter(now: { clock.now })

        _ = counter.read(station: one, playing: true)
        let parts = play(counter, clock, one, seconds: StationCounter.handOutEvery * 2 + 10)

        #expect(parts.count == 2)
        #expect(parts.map(\.newTune) == [true, false])

        let rest = counter.read(station: nil, playing: false)
        #expect(rest?.newTune == false)

        let total = parts.reduce(0) { $0 + $1.seconds } + (rest?.seconds ?? 0)
        #expect(abs(total - (StationCounter.handOutEvery * 2 + 10)) < 0.5)
    }

    /// Moving to the background hands out the time heard so far, and the listen continues. Radio
    /// that keeps playing is not counted as a second tuning.
    @Test func handingOutForTheBackgroundKeepsTheListenGoing() {
        let clock = Clock()
        let counter = StationCounter(now: { clock.now })

        _ = counter.read(station: one, playing: true)
        _ = play(counter, clock, one, seconds: 60)

        let part = counter.handOut()
        #expect(part?.newTune == true)
        #expect(counter.handOut() == nil)

        _ = play(counter, clock, one, seconds: 30)
        let rest = counter.read(station: nil, playing: false)
        #expect(rest?.newTune == false)
        #expect(abs((rest?.seconds ?? 0) - 30) < 0.5)
    }

    /// A gap of several minutes between two readings means the app is suspended. Nothing is
    /// counted for that gap.
    @Test func aSuspendedAppIsNotCountedAsListening() {
        let clock = Clock()
        let counter = StationCounter(now: { clock.now })

        _ = counter.read(station: one, playing: true)
        _ = play(counter, clock, one, seconds: 40)
        clock.advance(600)
        _ = counter.read(station: one, playing: true)

        let finished = counter.read(station: nil, playing: false)
        #expect(abs((finished?.seconds ?? 0) - 40) < 0.5)
    }
}
