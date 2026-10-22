import Testing
import Foundation
import RPMKit
import RPMLibrary
import RPMRadio
@testable import RPMAudio

// ── the two things a player has to be handed ──

private struct Signs: StreamSource {
    func stream(_ shelf: CloudShelf, rpmId: String,
                kilobits: Int) async throws -> (url: URL, kilobits: Int, kind: StreamKind) {
        (URL(string: "https://example.invalid/\(rpmId)")!, kilobits, .stored)
    }

    /// Returns no head clips. These are queue tests. They check which record is next, not how
    /// quickly it starts. A head clip would only make the engine hold audio that no test checks.
    func headClips(_ rpmIds: [String]) async throws -> [String: Data] { [:] }
}

private struct Refuses: StreamSource {
    struct No: Error {}
    func stream(_ shelf: CloudShelf, rpmId: String,
                kilobits: Int) async throws -> (url: URL, kilobits: Int, kind: StreamKind) { throw No() }
    func headClips(_ rpmIds: [String]) async throws -> [String: Data] { throw No() }
}

private struct OwnShelf: ShelfSource {
    func shelf(of rpmId: String?) -> CloudShelf { .own }
}

private func track(_ id: String, album: String = "Spirit of Eden",
                   lufs: Double = 0, peak: Double = 0, seconds: Double = 240) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.durationSeconds = seconds
    tags.loudnessLufs = lufs
    tags.truePeak = peak

    return CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: id,
                      artist: "Talk Talk", album: album, tags: tags)
}

@MainActor
private func player(_ source: any StreamSource = Signs()) -> Player {
    Player(source: source, shelves: OwnShelf(), copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })
}

// ── the classical mark ──

/// The classical flag is read for the track being handed over, and it travels with the audio.
/// The engine holds one setting for all sources, so the flag must come with each track.
@MainActor
@Test func aTrackIsHandedOverWithItsRecordsClassicalMark() {
    let classical = track("t1", album: "Piano Sonatas")
    let ordinary = track("t2", album: "Spirit of Eden")
    let rpm = Player(source: Signs(), shelves: OwnShelf(), copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(),
                     levelling: .album, levelsClassical: false,
                     classical: { $0.album == "Piano Sonatas" }, cover: { _ in nil })

    #expect(rpm.loudness(of: classical).albumIsClassical)
    #expect(!rpm.loudness(of: ordinary).albumIsClassical)
}

@MainActor
@Test func theStoredClassicalSettingReachesTheEngine() {
    let rpm = Player(source: Signs(), shelves: OwnShelf(), copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(),
                     levelling: .album, levelsClassical: true,
                     classical: { _ in true }, cover: { _ in nil })

    #expect(rpm.normalize.includeClassical)
}

// ── the queue ──

@MainActor
@Test func playingARecordStartsWhereItWasAskedTo() async {
    let rpm = player()
    let record = (0..<5).map { track("t\($0)") }

    await rpm.play(record, from: 2, because: .somebodyAskedForIt)

    #expect(rpm.queue.count == 5)
    #expect(rpm.index == 2)
    #expect(rpm.current?.rpmId == "t2")
    #expect(rpm.hasNext)
    #expect(rpm.hasPrevious)
}

@MainActor
@Test func anotherRecordFromTheTopIsStillNews() async {
    let rpm = player()
    var announced: [String?] = []
    rpm.onTrackChanged = { announced.append($0?.rpmId) }

    await rpm.play([track("a0"), track("a1")], from: 0, because: .somebodyAskedForIt)
    await rpm.play([track("b0", album: "Laughing Stock")], from: 0, because: .somebodyAskedForIt)

    // Both are announced. The second one matters most: it has the same index as the first. An
    // announcement made by index would keep the sleeve of the first record on the second.
    #expect(announced == ["a0", "b0"])
}

@MainActor
@Test func theSameTrackIsNotAnnouncedTwice() async {
    let rpm = player()
    var announced = 0
    rpm.onTrackChanged = { _ in announced += 1 }

    // `play` settles twice: once for the tapped track, and again when the address is signed. One
    // tap gives one announcement.
    await rpm.play([track("t0"), track("t1")], from: 1, because: .somebodyAskedForIt)

    #expect(announced == 1)
}

// ── a queue put back ──

/// A saved queue is restored on its track, paused. Nothing plays until play is pressed.
@MainActor
@Test func aQueuePutBackStandsPausedOnItsTrack() async {
    let rpm = player()
    await rpm.cue((0..<4).map { track("t\($0)") }, at: 2, position: .seconds(30))

    #expect(rpm.queue.count == 4)
    #expect(rpm.index == 2)
    #expect(rpm.current?.rpmId == "t2")
    #expect(!rpm.wantsToPlay)
    #expect(!rpm.isPlaying)
}

/// A source that holds every address until `letGo` is called. This lets a test check the player
/// while a track is still opening.
private actor Gate {
    private var asked = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func hold() async {
        asked = true
        await withCheckedContinuation { waiting.append($0) }
    }

    func letGo() {
        waiting.forEach { $0.resume() }
        waiting = []
    }

    var wasAsked: Bool { asked }
}

private struct Held: StreamSource {
    let gate: Gate

    func stream(_ shelf: CloudShelf, rpmId: String,
                kilobits: Int) async throws -> (url: URL, kilobits: Int, kind: StreamKind) {
        await gate.hold()
        return (URL(string: "https://example.invalid/\(rpmId)")!, kilobits, .stored)
    }

    func headClips(_ rpmIds: [String]) async throws -> [String: Data] { [:] }
}

/// Waits for a bounded number of turns until the player asks the gate for an address.
private func untilAsked(_ gate: Gate) async -> Bool {
    for _ in 0..<100_000 where await !gate.wasAsked { await Task.yield() }
    return await gate.wasAsked
}

/// While a restored track is opening, the player already has a pause pending. The play control
/// shows play. The source is paused as soon as it arrives.
@MainActor
@Test func aQueuePutBackOwesItsPauseWhileItOpens() async throws {
    let gate = Gate()
    let rpm = player(Held(gate: gate))
    let start = Task { await rpm.cue((0..<4).map { track("t\($0)") }, at: 2, position: .zero) }

    try #require(await untilAsked(gate))
    #expect(!rpm.wantsToPlay)

    await gate.letGo()
    await start.value
}

/// A queue started in the normal way wants to play while it opens. This is the opposite of the
/// test above, which is about a cued queue.
@MainActor
@Test func anOrdinaryStartWantsToPlayWhileItOpens() async throws {
    let gate = Gate()
    let rpm = player(Held(gate: gate))
    let start = Task { await rpm.play((0..<4).map { track("t\($0)") }, from: 2, because: .somebodyAskedForIt) }

    try #require(await untilAsked(gate))
    #expect(rpm.wantsToPlay)

    await gate.letGo()
    await start.value
}

/// A restored position past the end of the queue loads nothing.
@MainActor
@Test func aQueuePutBackAtNoTrackLoadsNothing() async {
    let rpm = player()
    await rpm.cue([track("t0")], at: 3, position: .zero)

    #expect(rpm.queue.isEmpty)
    #expect(rpm.current == nil)
}

// ── where the sitting began ──

/// The whole record goes into the queue, so that pressing back has somewhere to go. The tracks
/// above the tapped one were never played. A list drawn from position zero would show them as
/// played and skipped.
@MainActor
@Test func aRecordStartedPartWayInHasNothingBehindItYet() async {
    let rpm = player()
    await rpm.play((0..<12).map { track("t\($0)") }, from: 9, because: .somebodyAskedForIt)

    #expect(rpm.queue.count == 12)
    #expect(rpm.earliest == 9)
}

/// Pressing back from the first track of the sitting plays the track above it. That track then
/// belongs to the sitting. It was not skipped.
@MainActor
@Test func pressingBackReachesFurtherIntoTheRecord() async {
    let rpm = player()
    await rpm.play((0..<12).map { track("t\($0)") }, from: 9, because: .somebodyAskedForIt)

    await rpm.previous()

    #expect(rpm.index == 8)
    #expect(rpm.earliest == 8)
}

/// Going forward does not move the top of the list. Only the position changes.
@MainActor
@Test func goingOnDoesNotMoveWhereTheSittingBegan() async {
    let rpm = player()
    await rpm.play((0..<12).map { track("t\($0)") }, from: 9, because: .somebodyAskedForIt)

    await rpm.next()

    #expect(rpm.index == 10)
    #expect(rpm.earliest == 9)
}

/// The same list passed again only moves the needle inside it. A different list starts a new
/// sitting, and the top of the old sitting does not apply to it.
@MainActor
@Test func anotherRecordBeginsItsOwnSitting() async {
    let rpm = player()
    await rpm.play((0..<12).map { track("t\($0)") }, from: 9, because: .somebodyAskedForIt)
    await rpm.play((0..<4).map { track("b\($0)", album: "Laughing Stock") }, from: 1, because: .somebodyAskedForIt)

    #expect(rpm.earliest == 1)
}

/// `earliest` is the number of entries hidden above the list. Removing one of those entries must
/// also reduce this count. Otherwise the list loses a row it should show.
@MainActor
@Test func removingATrackFromAboveTheListKeepsTheCountTrue() async {
    let rpm = player()
    await rpm.play((0..<6).map { track("t\($0)") }, from: 3, because: .somebodyAskedForIt)

    rpm.remove([0])

    #expect(rpm.index == 2)
    #expect(rpm.earliest == 2)
    #expect(rpm.queue.first?.rpmId == "t1")
}

/// Stopping ends the sitting. What comes next starts its own.
@MainActor
@Test func stoppingPutsTheTopOfTheListBack() async {
    let rpm = player()
    await rpm.play((0..<6).map { track("t\($0)") }, from: 3, because: .somebodyAskedForIt)

    rpm.stop()

    #expect(rpm.earliest == 0)
}

@MainActor
@Test func aPositionThatIsNotInTheQueueStartsNothing() async {
    let rpm = player()
    await rpm.play([track("t0")], from: 4, because: .somebodyAskedForIt)

    #expect(rpm.queue.isEmpty)
    #expect(rpm.current == nil)
}

/// A track that cannot be signed shows an error message and does not crash.
@MainActor
@Test func aTrackThatCannotBeSignedSaysSo() async {
    let rpm = player(Refuses())
    await rpm.play([track("t0")], from: 0, because: .somebodyAskedForIt)

    #expect(rpm.trouble != nil)
    #expect(!rpm.isPlaying)
}

/// Signing out, or signing in as another user. A phone that is handed on must not keep the
/// previous user's queue.
@MainActor
@Test func everythingIsGivenBack() async {
    let rpm = player()
    await rpm.play((0..<3).map { track("t\($0)") }, from: 1, because: .somebodyAskedForIt)

    rpm.forget()

    #expect(rpm.queue.isEmpty)
    #expect(rpm.index == nil)
    #expect(rpm.current == nil)
    #expect(!rpm.hasNext && !rpm.hasPrevious)
}

/// Stop is not signing out. The queue and the station are cleared, but the speaker that the sound
/// was going to stays selected. The next thing played goes to the same speaker. The two actions
/// are separate, so Stop does not clear the speaker.
@MainActor
@Test func stopPutsTheMusicDownAndLeavesTheRoomStanding() async {
    let rpm = player()
    await rpm.play((0..<3).map { track("t\($0)") }, from: 1, because: .somebodyAskedForIt)
    rpm.tune(aStation())

    rpm.stop()

    #expect(rpm.queue.isEmpty)
    #expect(rpm.current == nil)
    #expect(rpm.station == nil)
    #expect(!rpm.isPlaying)
    #expect(rpm.position == .zero && rpm.duration == .zero)
}

// ── the end of a sitting ──

/// `isOver` tells the screens that listening has finished. The strip at the foot of the app is
/// hidden, the player is closed, and the listener returns to where the listening started. There
/// are two ways to reach this state, and both give the same answer.
@MainActor
@Test func anAppThatHasPlayedNothingIsAlreadyOver() {
    #expect(player().isOver)
}

@MainActor
@Test func aQueueIsNotOverUntilItIsStopped() async {
    let rpm = player()
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)

    #expect(!rpm.isOver)

    rpm.stop()

    #expect(rpm.isOver)
}

/// **Removing the playing track is not the end of the queue.** The music stops, and the strip
/// hides, but the queue still has tracks to play. So the app must not leave the screen. A screen
/// that treated "nothing under the needle" as the end would close while the user was editing the
/// list.
@MainActor
@Test func takingTheNeedlesTrackOutIsNotTheEndOfTheQueue() async {
    let rpm = player()
    await rpm.play((0..<5).map { track("t\($0)") }, from: 2, because: .somebodyAskedForIt)

    rpm.remove([2])

    #expect(rpm.current == nil)
    #expect(!rpm.isOver, "four tracks are still waiting")
}

@MainActor
@Test func takingTheLastTrackOutIsTheEndOfTheQueue() async {
    let rpm = player()
    await rpm.play([track("t0")], from: 0, because: .somebodyAskedForIt)

    rpm.remove([0])

    #expect(rpm.isOver)
}

/// The record played to its end, and no tracks are left. **This ends the same way as the stop
/// key.** A queue that finishes on its own must not leave a player open. That means no strip at
/// the foot of the screen, and no entry on the lock screen.
@MainActor
@Test func theLastRecordEndingPutsTheQueueDown() async {
    let rpm = player()
    await rpm.play((0..<3).map { track("t\($0)", seconds: 0) }, from: 2, because: .somebodyAskedForIt)

    // The file ran out, and the decoder produced everything the file said it held. **The source
    // reports this reason. The player does not work it out from the needle position.** That is the
    // purpose of `Ending`.
    rpm.queueRanOut(.theRecordFinished)

    #expect(rpm.queue.isEmpty)
    #expect(rpm.current == nil)
    #expect(!rpm.isPlaying)
    #expect(rpm.isOver)
}

/// An ending that is not a normal end. A stream that fails on the last track has a reason to
/// report. Clearing the queue would also remove the message from the screen, because the message
/// is about that record.
@MainActor
@Test func aRecordThatDiedRatherThanEndedKeepsItsPlace() async {
    let rpm = player()
    await rpm.play((0..<2).map { track("t\($0)", seconds: 240) }, from: 1, because: .somebodyAskedForIt)

    rpm.queueRanOut(Ending(why: .theBytesStopped, reachedItsEnd: false))

    #expect(rpm.queue.count == 2)
    #expect(rpm.current?.rpmId == "t1")
    #expect(!rpm.isOver)
    #expect(rpm.trouble != nil, "nothing on the screen says why it went quiet")
}

/// The tab that stopping returns to. This is checked after the station is cleared. A record
/// returns to the library, and a station returns to the radio screen.
@MainActor
@Test func whatWasPlayingOutlivesTheStopThatEndedIt() async {
    let rpm = player()

    await rpm.play([track("t0")], from: 0, because: .somebodyAskedForIt)
    rpm.stop()
    #expect(!rpm.wasTheRadio)

    rpm.tune(aStation())
    rpm.stop()
    #expect(rpm.wasTheRadio, "the station is gone, and where it was heard is not")
}

// ── how loud ──

/// **Album gain in album order, track gain on shuffle.** The queue shows which mode applies, and
/// the player does not store how playback started. So the result is still right after a track is
/// removed.
@MainActor
@Test func aQueueOfOneRecordIsLevelledAsARecord() async {
    let rpm = player()
    await rpm.play((0..<4).map { track("t\($0)", lufs: -14, peak: 0.5) }, from: 0, because: .somebodyAskedForIt)

    #expect(rpm.playingARecord)
    #expect(rpm.levelling.basis == .album)
}

@MainActor
@Test func aQueueOfUnrelatedSongsIsLevelledSongBySong() async {
    let rpm = player()
    await rpm.play([track("a", album: "Hex", lufs: -14, peak: 0.5),
                    track("b", album: "Watermark", lufs: -9, peak: 0.5),
                    track("c", album: "Blue", lufs: -20, peak: 0.5)], from: 0, because: .somebodyAskedForIt)

    #expect(!rpm.playingARecord)
    #expect(rpm.levelling.basis == .track)
}

@MainActor
@Test func aRecordNobodyMeasuredIsPlayedAsItWasMastered() async {
    let rpm = player()
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)

    #expect(rpm.levelling == .none)
    #expect(!rpm.levelling.applies)
}

/// The album level is the weighted mean of the tracks' loudness, not the mean of their decibel
/// values. The peak used for the clamp is the highest peak on the album.
@MainActor
@Test func aRecordsLevelComesFromAllOfIt() async {
    let rpm = player()
    await rpm.play([track("a", lufs: -8, peak: 0.5, seconds: 60),
                    track("b", lufs: -20, peak: 0.99, seconds: 600)], from: 0, because: .somebodyAskedForIt)

    let level = rpm.albumLevel
    #expect(level.known)
    #expect(level.truePeak == 0.99)

    // The ten-minute quiet side weighs far more than the one-minute loud one.
    #expect((level.lufs ?? 0) < -14, "read \(level.lufs ?? 0)")
}

/// **Switching levelling reaches the record already playing.** The setting is held by
/// the engine and read for every block, so there is no track change to wait for.
@MainActor
@Test func switchingLevellingReachesTheRecordAlreadyPlaying() async {
    let rpm = player()
    await rpm.play((0..<3).map { track("t\($0)", lufs: -14, peak: 0.5) }, from: 0, because: .somebodyAskedForIt)
    #expect(rpm.levelling.basis == .album)

    rpm.normalize.mode = .off
    #expect(rpm.levelling == .none)
    #expect(rpm.normalize.mode == .off)

    rpm.normalize.mode = .track
    #expect(rpm.levelling.basis == .track)
}

/// **The gain travels with the audio.** Each record is handed to the engine with the loudness it
/// is levelled from. This applies to the record playing and to the one loaded behind it. So the
/// change to the next record's gain happens on the pump's own clock.
@MainActor
@Test func eachRecordIsHandedToTheEngineWithItsOwnLoudness() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(), copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })
    let record = [track("t0", lufs: -10, peak: 0.5), track("t1", lufs: -20, peak: 0.9)]
    await rpm.play(record, from: 0, because: .somebodyAskedForIt)

    try await until("the next record to be handed over") { rpm.loadedBehindTheNeedle }

    #expect(rpm.loudnessHandedOver.map(\.track) == record.map { Level($0.tags) })
    #expect(rpm.loudnessHandedOver.allSatisfy { $0.inAlbumOrder && $0.album == rpm.albumLevel })

    rpm.stop()
}

/// With levelling off, no gain is applied, whatever the record measured.
@MainActor
@Test func levellingCanBeTurnedOff() async {
    let rpm = player()
    rpm.normalize.mode = .off
    await rpm.play((0..<3).map { track("t\($0)", lufs: -14, peak: 0.5) }, from: 0, because: .somebodyAskedForIt)

    #expect(rpm.levelling == .none)
}

// ── the conversion that the other tests use ──

@Test func durationInSecondsIsTheNumberItSaysItIs() {
    #expect(Duration.seconds(90).seconds == 90)
    #expect(abs(Duration.milliseconds(1500).seconds - 1.5) < 1e-9)
    #expect(Duration.zero.seconds == 0)
}

// ── editing the queue under the needle ──
//
// The arithmetic itself is tested in `QueueEditTests`. These tests check that the player agrees
// with it: what `current` says after the list around it changes.

@MainActor
@Test func takingATrackOutFromAboveTheNeedleKeepsTheSameSongPlaying() async {
    let rpm = player()
    await rpm.play((0..<5).map { track("t\($0)") }, from: 3, because: .somebodyAskedForIt)

    rpm.remove([1])

    #expect(rpm.queue.count == 4)
    #expect(rpm.index == 2)
    #expect(rpm.current?.rpmId == "t3")
}

@MainActor
@Test func takingATrackOutFromBelowTheNeedleDoesNotMoveIt() async {
    let rpm = player()
    await rpm.play((0..<5).map { track("t\($0)") }, from: 1, because: .somebodyAskedForIt)

    rpm.remove([3, 4])

    #expect(rpm.queue.count == 3)
    #expect(rpm.index == 1)
    #expect(rpm.current?.rpmId == "t1")
}

/// This is why `index` is optional. A queue can be on screen with nothing under the needle.
@MainActor
@Test func takingOutTheTrackInTheSpeakerStopsRatherThanPlayingItsNeighbour() async {
    let rpm = player()
    await rpm.play((0..<5).map { track("t\($0)") }, from: 2, because: .somebodyAskedForIt)

    rpm.remove([2])

    #expect(rpm.queue.count == 4)
    #expect(rpm.index == nil)
    #expect(rpm.current == nil)
    #expect(!rpm.hasNext)
    #expect(!rpm.hasPrevious)
}

@MainActor
@Test func aPositionThatIsNotInTheQueueRemovesNothing() async {
    let rpm = player()
    await rpm.play((0..<3).map { track("t\($0)") }, from: 1, because: .somebodyAskedForIt)

    rpm.remove([9])

    #expect(rpm.queue.count == 3)
    #expect(rpm.current?.rpmId == "t1")
}

@MainActor
@Test func draggingTheSongInTheSpeakerTakesTheNeedleWithIt() async {
    let rpm = player()
    await rpm.play((0..<5).map { track("t\($0)") }, from: 4, because: .somebodyAskedForIt)

    rpm.move(from: 4, to: 0)

    #expect(rpm.index == 0)
    #expect(rpm.current?.rpmId == "t4")
    #expect(rpm.queue.map(\.rpmId) == ["t4", "t0", "t1", "t2", "t3"])
}

@MainActor
@Test func draggingAnotherSongPastTheNeedleMovesTheNeedleNotTheSong() async {
    let rpm = player()
    await rpm.play((0..<5).map { track("t\($0)") }, from: 3, because: .somebodyAskedForIt)

    rpm.move(from: 0, to: 4)

    #expect(rpm.current?.rpmId == "t3", "the song in the speaker changed")
    #expect(rpm.index == 2)
    #expect(rpm.queue.map(\.rpmId) == ["t1", "t2", "t3", "t4", "t0"])
}

@MainActor
@Test func droppingASongWhereItWasPickedUpChangesNothing() async {
    let rpm = player()
    await rpm.play((0..<4).map { track("t\($0)") }, from: 2, because: .somebodyAskedForIt)

    rpm.move(from: 1, to: 1)

    #expect(rpm.index == 2)
    #expect(rpm.queue.map(\.rpmId) == ["t0", "t1", "t2", "t3"])
}

/// Removing every track while one is playing: the list empties, the music stops, and nothing is
/// left pointing at a row that no longer exists.
@MainActor
@Test func emptyingTheQueueLeavesNothingPlaying() async {
    let rpm = player()
    await rpm.play((0..<3).map { track("t\($0)") }, from: 1, because: .somebodyAskedForIt)

    rpm.remove([0, 1, 2])

    #expect(rpm.queue.isEmpty)
    #expect(rpm.index == nil)
    #expect(rpm.current == nil)
}

// ── the radio, on the same player ──

private func aStation(_ name: String = "NPO Radio 2") -> RadioStation {
    RadioStation(uuid: "st-\(name)", name: name, streamUrl: "https://example.invalid/\(name).mp3")
}

@MainActor
@Test func tuningAStationLeavesNothingUnderTheNeedle() async {
    let rpm = player()
    rpm.tune(aStation())

    #expect(rpm.station?.name == "NPO Radio 2")
    #expect(rpm.onTheRadio)
    #expect(rpm.queue.isEmpty)
    #expect(rpm.index == nil, "a station is not a position in a queue")
    #expect(rpm.current == nil)
    #expect(!rpm.hasNext && !rpm.hasPrevious)
}

/// Starting a record ends radio listening. The desktop app uses the same rule.
@MainActor
@Test func puttingARecordOnLeavesTheRadio() async {
    let rpm = player()
    rpm.tune(aStation())

    await rpm.play([track("t0"), track("t1")], from: 0, because: .somebodyAskedForIt)

    #expect(rpm.station == nil)
    #expect(!rpm.onTheRadio)
    #expect(rpm.current?.rpmId == "t0")
}

/// **Tuning a station does not end the sitting.** The lock screen reads the end of a sitting
/// from `isOver`. Tuning first clears the track, and then announces the station. The remote sees
/// the first of those changes. If it treated that as the end, the lock screen card would close and
/// the audio session would end, while the station is still starting.
@MainActor
@Test func tuningAStationIsNotTheEndOfTheSitting() async {
    let rpm = player()
    await rpm.play([track("t0")], from: 0, because: .somebodyAskedForIt)

    rpm.tune(aStation())

    #expect(rpm.current == nil, "there is no track under the needle")
    #expect(!rpm.isOver, "and there is still something playing")
}

/// Stopping a station does end the sitting. The stop key clears everything, and that removes the
/// card from the lock screen. An entry that is cleared while the session is still held leaves the
/// card showing with every field empty.
@MainActor
@Test func stoppingAStationIsTheEndOfTheSitting() async {
    let rpm = player()
    rpm.tune(aStation())

    rpm.stop()

    #expect(rpm.station == nil)
    #expect(rpm.isOver)
}

@MainActor
@Test func tuningAnotherStationReplacesTheFirst() async {
    let rpm = player()
    rpm.tune(aStation("First"))
    rpm.tune(aStation("Second"))

    #expect(rpm.station?.name == "Second")
}

/// A station is not levelled. A station has no loudness measurement, and a guessed value could
/// make the station too quiet, so the listener would think the phone is broken.
@MainActor
@Test func aStationIsPlayedAtUnity() async {
    let rpm = player()
    await rpm.play([track("t0", lufs: -6, peak: 1.0)], from: 0, because: .somebodyAskedForIt)

    rpm.tune(aStation())
    #expect(rpm.levelling == .none)
}

@MainActor
@Test func signingOutLeavesTheRadioToo() async {
    let rpm = player()
    rpm.tune(aStation())

    rpm.forget()

    #expect(rpm.station == nil)
    #expect(!rpm.onTheRadio)
}

/// A station with an address that is not valid plays nothing and reports an error. It does not
/// leave the previous track playing under the station's name.
@MainActor
@Test func aStationWithNoUsableAddressSaysSo() async {
    let rpm = player()
    rpm.tune(RadioStation(uuid: "x", name: "Broken", streamUrl: ""))

    #expect(rpm.station == nil)
    #expect(rpm.trouble != nil)
}

// ── which start wins, and what the losing start does ──

/// One track signs to a real file and plays. The other signs to a host name that does not
/// resolve. The test chooses which track is which.
private struct SignsOneRealOneDead: StreamSource {
    let real: String
    let url: URL

    func stream(_ shelf: CloudShelf, rpmId: String,
                kilobits: Int) async throws -> (url: URL, kilobits: Int, kind: StreamKind) {
        (rpmId == real ? url : URL(string: "https://nothing.invalid/\(rpmId)")!, kilobits, .stored)
    }

    func headClips(_ rpmIds: [String]) async throws -> [String: Data] { [:] }
}

/// **A start that loses a race reports nothing.** A record that was passed over keeps failing on
/// its own schedule. A name that does not resolve can take a long time to fail. That failure must
/// not show a message on the screen while another record plays. The test checks the claim while
/// the start is still waiting, not only when it has finished.
@MainActor
@Test func aRecordFlickedPastDoesNotReportItsFailure() async throws {
    let fixture = try #require(Bundle.module.url(forResource: "Fixtures/tone", withExtension: "m4a"))
    let source = SignsOneRealOneDead(real: "b", url: fixture)
    let player = Player(source: source, shelves: OwnShelf(), copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })

    let tracks = [track("a"), track("b")]

    // The start that will lose. It is started and left waiting.
    async let losing: Void = player.play(tracks, from: 0, because: .somebodyAskedForIt)
    try await Task.sleep(for: .milliseconds(20))

    await player.play(tracks, from: 1, because: .somebodyAskedForIt)
    await losing

    #expect(player.index == 1)

    // Paused so the record cannot end during the wait. The fixture is three seconds long, about
    // the same as the wait. A record that ends stops the queue and clears the index.
    player.pause()

    // Long enough for a name that does not resolve to fail. That is when the abandoned start
    // would have reported its error.
    try await Task.sleep(for: .seconds(3))

    #expect(player.index == 1, "the loser took the needle back")
    #expect(player.trouble == nil,
            "the record that was flicked past reported itself: \(player.trouble ?? "")")
}

// ── what the lock screen is told ──

/// **The lock screen must be told about each change.** The lock screen and Control Centre show
/// the state they were last given. The engine does not send them anything. `onPlaybackChanged`
/// is connected to `RemoteControl.showPosition`, which sets the rate and the playback state from
/// `wantsToPlay`. Pause must call `onPlaybackChanged`. Without that call, iOS would show a pause
/// control over silence, with the clock still running.
@MainActor
@Test func pausingSaysSoToWhateverIsDrawingTheKey() async {
    let rpm = player()
    await rpm.play([track("t0")], from: 0, because: .somebodyAskedForIt)

    var told = 0
    rpm.onPlaybackChanged = { told += 1 }

    rpm.pause()
    #expect(told == 1)
    #expect(rpm.wantsToPlay == false)

    // The change is reported again on resume. **The test does not check `wantsToPlay` here.**
    // A test process has no audio device, so the node never reports playing. Checking it would
    // test the harness, not the player.
    rpm.resume()
    #expect(told == 2)
}

/// A key pressed on a player with nothing loaded changes no sound. It still changes the key,
/// because the key shows what was **asked for**. The change must still be reported.
@MainActor
@Test func aKeyThatChangesNoSoundStillSaysSo() async {
    let rpm = player()

    var told = 0
    rpm.onPlaybackChanged = { told += 1 }

    rpm.pause()
    #expect(told == 1)
}

// ── rearranging what is still to come ──

/// **This test runs the whole path, because the fault is not visible in any single part.** The
/// look-ahead hands the next record to the engine a whole track early. So a queue rearranged
/// before the current record ends leaves the old next record loaded behind the needle. The lists
/// redraw, `queue` is correct, and `index` is correct. But the record that plays next is the old
/// one, which the list no longer has in that position. It is announced under the number that the
/// list gave to another track. So the app names one track and plays another.
@MainActor
@Test func rearrangingTakesBackTheRecordAlreadyLoadedBehindTheNeedle() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(), copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })
    await rpm.play((0..<4).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)

    try await until("the next record to be handed over") { rpm.loadedBehindTheNeedle }

    // The listener drags the last record up to play next.
    rpm.move(from: 3, to: 1)

    #expect(rpm.queue.map(\.rpmId) == ["t0", "t3", "t1", "t2"])
    #expect(rpm.loadedBehindTheNeedle == false,
            "t1 is still loaded behind the needle, and it would play under t3's number")

    // And the one the list now says is next takes its place.
    try await until("the new next record to be handed over") { rpm.loadedBehindTheNeedle }
    #expect(store.asked.contains("t3"))

    rpm.stop()
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

// ── a new order for the tracks still to come ──

@MainActor
@Test func shufflingLeavesThePlayedAndThePlayingWhereTheyAre() async {
    let rpm = player()
    await rpm.play((0..<8).map { track("t\($0)") }, from: 3, because: .somebodyAskedForIt)

    rpm.shuffleWhatIsComing()

    #expect(rpm.queue.prefix(4).map(\.rpmId) == ["t0", "t1", "t2", "t3"],
            "the needle's own record, or one behind it, was moved")
    #expect(rpm.index == 3)
    #expect(rpm.current?.rpmId == "t3")
    #expect(Set(rpm.queue.suffix(4).map(\.rpmId)) == ["t4", "t5", "t6", "t7"],
            "the shuffle lost or invented a record")
}

/// The shuffle must change the order. A check on one shuffle could fail by chance, so the test
/// tries up to ten shuffles and expects at least one to change the order.
@MainActor
@Test func shufflingPutsWhatIsComingInAnotherOrder() async {
    let rpm = player()
    let record = (0..<8).map { track("t\($0)") }
    var moved = false

    for _ in 0..<10 {
        await rpm.play(record, from: 0, because: .somebodyAskedForIt)
        rpm.shuffleWhatIsComing()
        if rpm.queue.map(\.rpmId) != record.map(\.rpmId) { moved = true; break }
    }

    #expect(moved, "ten shuffles and the queue never changed")
}

/// The shuffle control is shown only when it does something. The last record of a queue has
/// nothing to reorder, so the control is hidden.
@MainActor
@Test func thereIsNothingToShuffleOnTheLastRecord() async {
    let rpm = player()
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)
    #expect(rpm.canShuffleWhatIsComing)

    await rpm.play((0..<3).map { track("t\($0)") }, from: 2, because: .somebodyAskedForIt)
    #expect(rpm.canShuffleWhatIsComing == false)

    rpm.stop()
    #expect(rpm.canShuffleWhatIsComing == false)
}

// ── hearing a song after this one ──

@MainActor
@Test func aSongSentUpNextLandsAfterTheOnePlaying() async {
    let rpm = player()
    await rpm.play((0..<4).map { track("t\($0)") }, from: 1, because: .somebodyAskedForIt)

    rpm.insertNext([track("x")])

    #expect(rpm.queue.map(\.rpmId) == ["t0", "t1", "x", "t2", "t3"])

    // The record in the speaker keeps its place and its position: nothing about it
    // changed, and nothing started.
    #expect(rpm.index == 1)
    #expect(rpm.current?.rpmId == "t1")
}

/// With nothing playing, "play next" appends the song to the queue. The song is not started.
@MainActor
@Test func aSongSentUpNextWithNothingPlayingIsAnAppend() async {
    let rpm = player()

    rpm.insertNext([track("x")])
    #expect(rpm.queue.map(\.rpmId) == ["x"])
    #expect(rpm.index == nil)
    #expect(rpm.isPlaying == false)

    rpm.insertNext([track("y")])
    #expect(rpm.queue.map(\.rpmId) == ["x", "y"])
}

// ── adding a song to the end ──

@MainActor
@Test func aSongAddedGoesToTheEndAndNothingElseMoves() async {
    let rpm = player()
    await rpm.play((0..<3).map { track("t\($0)") }, from: 1, because: .somebodyAskedForIt)

    rpm.append([track("x")])

    #expect(rpm.queue.map(\.rpmId) == ["t0", "t1", "t2", "x"])
    #expect(rpm.index == 1)
    #expect(rpm.current?.rpmId == "t1")
}

@MainActor
@Test func aSongAddedWithNothingPlayingWaitsInTheQueue() async {
    let rpm = player()

    rpm.append([track("x"), track("y")])
    #expect(rpm.queue.map(\.rpmId) == ["x", "y"])
    #expect(rpm.index == nil)
    #expect(rpm.isPlaying == false)

    rpm.append([])
    #expect(rpm.queue.count == 2)
}

@MainActor
@Test func sendingNothingUpNextChangesNothing() async {
    let rpm = player()
    await rpm.play([track("t0")], from: 0, because: .somebodyAskedForIt)

    rpm.insertNext([])
    #expect(rpm.queue.count == 1)
}

/// **The same fault as the reorder, through a different action.** A song put in front of the
/// record that the look-ahead has already handed over is a queue edit like any other. The engine
/// then holds audio for a slot that now belongs to another track. It plays that audio while the
/// app names the new track.
@MainActor
@Test func aSongSentUpNextTakesBackTheRecordAlreadyLoadedBehindTheNeedle() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(), copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)

    try await until("the next record to be handed over") { rpm.loadedBehindTheNeedle }

    rpm.insertNext([track("x")])

    #expect(rpm.queue.map(\.rpmId) == ["t0", "x", "t1", "t2"])
    #expect(rpm.loadedBehindTheNeedle == false,
            "t1 is still loaded behind the needle, and it would play instead of x")

    try await until("x to be handed over in its place") { rpm.loadedBehindTheNeedle }
    #expect(store.asked.contains("x"))

    rpm.stop()
}

/// **A song added at the end leaves the next record alone.** A mixtape adds a song at every
/// change of track. If each one dropped the record already loaded behind the needle and opened
/// it again, every record would be requested twice, and a record that is encoded while it is
/// sent would be encoded twice.
@MainActor
@Test func aSongAddedAtTheEndDoesNotOpenTheNextRecordAgain() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = Player(source: SilenceSigned(store: store), shelves: AnyShelf(), copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)

    try await until("the next record to be handed over") { rpm.loadedBehindTheNeedle }

    rpm.append([track("x")])

    #expect(rpm.loadedBehindTheNeedle, "the next record was taken back for a song added after it")

    // Long enough for a second request for t1 to reach the store.
    try await Task.sleep(for: .milliseconds(500))
    #expect(store.asked.filter { $0 == "t1" }.count == 1, "asked: \(store.asked)")

    rpm.stop()
}

/// Signs every track to the silent store, except the ones named here, which sign to a host name
/// that does not resolve.
private struct SilenceExcept: StreamSource {
    let store: SilentStore
    let dead: Set<String>

    func stream(_ shelf: CloudShelf, rpmId: String,
                kilobits: Int) async throws -> (url: URL, kilobits: Int, kind: StreamKind) {
        let url = dead.contains(rpmId)
            ? URL(string: "https://nothing.invalid/\(rpmId)")!
            : store.address(of: rpmId)
        return (url, kilobits, .stored)
    }

    func headClips(_ rpmIds: [String]) async throws -> [String: Data] { [:] }
}

/// **The look-ahead does not speak for the record that is playing.** The record after this one
/// failed to open. That is a fact about the next record, and it is reported when the queue
/// reaches it. Shown now, it puts "cannot play" over a record that is playing perfectly well.
@MainActor
@Test func aNextRecordThatWillNotOpenSaysNothingOverThePlayingOne() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = Player(source: SilenceExcept(store: store, dead: ["t1"]), shelves: AnyShelf(), copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })

    // `play` returns when the look-ahead has finished, so t1 has already failed here.
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)

    #expect(rpm.index == 0)
    #expect(rpm.trouble == nil, "the next record's failure was shown: \(rpm.trouble ?? "")")
    #expect(rpm.failure == .none)

    rpm.stop()
}

/// Holds the address of one track until the gate is opened. Every other track signs to the
/// silent store at once.
private struct HoldsOne: StreamSource {
    let store: SilentStore
    let gate: Gate
    let held: String

    func stream(_ shelf: CloudShelf, rpmId: String,
                kilobits: Int) async throws -> (url: URL, kilobits: Int, kind: StreamKind) {
        if rpmId == held { await gate.hold() }
        return (store.address(of: rpmId), kilobits, .stored)
    }

    func headClips(_ rpmIds: [String]) async throws -> [String: Data] { [:] }
}

/// **A look-ahead replaced by a queue edit stops where it is.** Its record is no longer the next
/// one. When its address arrives it must not open it, must not stop the feed of the look-ahead
/// that replaced it, and must not hand anything to the engine. Otherwise the engine holds two
/// records behind the needle, one of them stopped part way.
@MainActor
@Test func aLookAheadReplacedByAQueueEditHandsNothingOver() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let gate = Gate()
    let rpm = Player(source: HoldsOne(store: store, gate: gate, held: "t1"), shelves: AnyShelf(), copies: NoCopies(), nearby: NothingNearby(), reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })

    // The start plays t0 and then waits in its look-ahead for t1's address. t0 is fetched and
    // decoded first, which takes real time, so the wait is measured in time and not in turns.
    let start = Task { await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt) }
    for _ in 0..<300 where await !gate.wasAsked { try await Task.sleep(for: .milliseconds(50)) }
    try #require(await gate.wasAsked)

    // x is now next. Its own look-ahead opens it and hands it over.
    rpm.insertNext([track("x")])
    try await until("x to be handed over") { rpm.loadedBehindTheNeedle }

    // The replaced look-ahead gets its address now.
    await gate.letGo()
    await start.value

    #expect(!store.asked.contains("t1"), "the replaced look-ahead opened its record: \(store.asked)")
    #expect(rpm.loudnessHandedOver.count == 2,
            "the engine holds \(rpm.loudnessHandedOver.count) records, not t0 and x")
    #expect(rpm.trouble == nil)

    rpm.stop()
}

// ── replacing a queue the user changed ──

private let otherAlbum = (0..<4).map { track("b\($0)", album: "Laughing Stock") }

@MainActor
private func playingAnAlbum() async -> Player {
    let rpm = player()
    await rpm.play((0..<6).map { track("t\($0)") }, from: 1, because: .somebodyAskedForIt)
    return rpm
}

@MainActor
@Test func aTapReplacesAQueueNobodyChangedWithoutAsking() async {
    let rpm = await playingAnAlbum()

    guard case .clear(let start) = rpm.replacing(with: otherAlbum, from: 2, tapped: .song) else {
        Issue.record("an unchanged queue asked before it was replaced")
        return
    }
    await rpm.start(start)

    #expect(rpm.queue.map(\.rpmId) == otherAlbum.map(\.rpmId))
    #expect(rpm.current?.rpmId == "b2")
}

@MainActor
@Test func aTapAsksWhenASongWasAddedToTheQueue() async {
    let rpm = await playingAnAlbum()
    rpm.insertNext([track("x")])

    #expect(rpm.hasChangesAhead)
    guard case .asks = rpm.replacing(with: otherAlbum, from: 0, tapped: .song) else {
        Issue.record("a queue with a song added was replaced without asking")
        return
    }
}

@MainActor
@Test func aTapAsksWhenTheQueueWasReordered() async {
    let rpm = await playingAnAlbum()
    rpm.move(from: 5, to: 2)

    guard case .asks = rpm.replacing(with: otherAlbum, from: 0, tapped: .list) else {
        Issue.record("a reordered queue was replaced without asking")
        return
    }
}

/// The same list handed back moves the playing position inside it and loses nothing.
@MainActor
@Test func theQueueItselfHandedBackNeverAsks() async {
    let rpm = await playingAnAlbum()
    rpm.insertNext([track("x")])

    guard case .clear = rpm.replacing(with: rpm.queue, from: 4, tapped: .song) else {
        Issue.record("playing a row of the queue asked to discard the queue")
        return
    }
}

@MainActor
@Test func discardReplacesTheQueueAndForgetsTheChange() async {
    let rpm = await playingAnAlbum()
    rpm.insertNext([track("x")])

    guard case .asks(let question) = rpm.replacing(with: otherAlbum, from: 1, tapped: .song) else {
        Issue.record("expected to be asked")
        return
    }
    await rpm.start(question.discard())

    #expect(rpm.queue.map(\.rpmId) == otherAlbum.map(\.rpmId))
    #expect(rpm.current?.rpmId == "b1")
    #expect(!rpm.hasChangesAhead)
}

/// Play now, keep queue, on a song: that song goes after the playing one and plays, and
/// the rest of the changed queue follows it.
@MainActor
@Test func keepingTheQueuePlaysTheTappedSongBeforeTheRest() async {
    let rpm = await playingAnAlbum()
    rpm.insertNext([track("x")])

    guard case .asks(let question) = rpm.replacing(with: otherAlbum, from: 2, tapped: .song) else {
        Issue.record("expected to be asked")
        return
    }
    await rpm.start(question.keepQueue())

    #expect(rpm.queue.map(\.rpmId) == ["t0", "t1", "b2", "x", "t2", "t3", "t4", "t5"])
    #expect(rpm.current?.rpmId == "b2")
    #expect(rpm.earliest == 1, "keeping the queue started a new one")
    #expect(rpm.hasChangesAhead, "the added song is still to come")
}

/// On a Play or Shuffle button the whole list goes in front of the rest of the queue.
@MainActor
@Test func keepingTheQueueForAListButtonPutsTheWholeListFirst() async {
    let rpm = await playingAnAlbum()
    rpm.insertNext([track("x")])

    guard case .asks(let question) = rpm.replacing(with: otherAlbum, from: 0, tapped: .list) else {
        Issue.record("expected to be asked")
        return
    }
    await rpm.start(question.keepQueue())

    #expect(rpm.queue.map(\.rpmId) == ["t0", "t1", "b0", "b1", "b2", "b3", "x", "t2", "t3", "t4", "t5"])
    #expect(rpm.current?.rpmId == "b0")
}

/// With the playing track removed, nothing is playing and the songs go to the top of
/// what is shown.
@MainActor
@Test func keepingTheQueueWithNothingPlayingPutsTheSongFirst() async {
    let rpm = await playingAnAlbum()
    rpm.remove([1])
    #expect(rpm.index == nil)

    guard case .asks(let question) = rpm.replacing(with: otherAlbum, from: 3, tapped: .song) else {
        Issue.record("expected to be asked")
        return
    }
    await rpm.start(question.keepQueue())

    #expect(rpm.queue.map(\.rpmId) == ["t0", "b3", "t2", "t3", "t4", "t5"])
    #expect(rpm.current?.rpmId == "b3")
}

/// Next, Previous and a tap on a queue row move inside the queue. None of them may
/// take the change away, or the question is never asked again.
@MainActor
@Test func movingInsideTheQueueKeepsTheChange() async {
    let rpm = await playingAnAlbum()
    rpm.move(from: 5, to: 3)
    #expect(rpm.hasChangesAhead)

    await rpm.next()
    #expect(rpm.hasChangesAhead, "Next forgot the change")

    await rpm.previous()
    #expect(rpm.hasChangesAhead, "Previous forgot the change")

    await rpm.jump(to: 0)
    #expect(rpm.hasChangesAhead, "a tap on a queue row forgot the change")
    #expect(rpm.current?.rpmId == "t0")
}

/// Shuffling the whole queue from the Now playing page reorders the queue. It is not a
/// new list, so it counts as a change.
@MainActor
@Test func shufflingTheWholeQueueCountsAsAChange() async {
    let rpm = player()
    let record = (0..<8).map { track("t\($0)") }
    var changed = false

    for _ in 0..<10 {
        await rpm.play(record, from: 0, because: .somebodyAskedForIt)
        await rpm.shuffleTheQueue()
        #expect(rpm.index == 0)
        #expect(rpm.earliest == 0)
        if rpm.queue.map(\.rpmId) != record.map(\.rpmId) { changed = rpm.hasChangesAhead; break }
    }

    #expect(changed, "a shuffled queue did not count as changed")
}

@MainActor
@Test func stoppingLeavesNothingToAskAbout() async {
    let rpm = await playingAnAlbum()
    rpm.insertNext([track("x")])

    rpm.stop()

    #expect(!rpm.hasChangesAhead)
    guard case .clear = rpm.replacing(with: otherAlbum, from: 0, tapped: .song) else {
        Issue.record("a stopped player asked to discard a queue it no longer has")
        return
    }
}
