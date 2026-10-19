import Testing
import Foundation
import RPMKit
import RPMLibrary
@testable import RPMAudio

// Sleep timer rules, without a player.

@Suite("Sleep timer rules")
struct SleepTimerRules {
    private let now = ContinuousClock.now

    @Test func aTimedSettingPausesThatFarAhead() {
        var timer = SleepTimer()
        timer.set(.after(.seconds(900)), now: now)

        #expect(timer.left(now: now, trackLeft: nil) == .seconds(900))
        #expect(timer.left(now: now + .seconds(60), trackLeft: nil) == .seconds(840))
        #expect(!timer.endsWithTheTrack)
    }

    @Test func timeLeftIsNeverNegative() {
        var timer = SleepTimer()
        timer.set(.after(.seconds(60)), now: now)

        #expect(timer.left(now: now + .seconds(90), trackLeft: nil) == .zero)
    }

    @Test func addingTimeMovesTheDeadline() {
        var timer = SleepTimer()
        timer.set(.after(.seconds(300)), now: now)
        timer.add(.seconds(900), now: now + .seconds(100), trackLeft: nil)

        #expect(timer.left(now: now + .seconds(100), trackLeft: nil) == .seconds(1100))
    }

    /// Adding five minutes during the last minute of a track gives six minutes from now. The
    /// timer counts from the end of the track.
    @Test func addingToAnEndOfTrackTimerCountsFromTheEndOfTheTrack() {
        var timer = SleepTimer()
        timer.set(.endOfTrack, now: now)
        timer.add(.seconds(300), now: now, trackLeft: .seconds(60))

        #expect(!timer.endsWithTheTrack)
        #expect(timer.left(now: now, trackLeft: .seconds(60)) == .seconds(360))
    }

    @Test func anEndOfTrackTimerReportsTheTracksOwnTimeLeft() {
        var timer = SleepTimer()
        timer.set(.endOfTrack, now: now)

        #expect(timer.left(now: now, trackLeft: .seconds(75)) == .seconds(75))
        #expect(timer.left(now: now, trackLeft: nil) == nil)
    }

    /// A wake-up that was scheduled before time was added belongs to an old deadline. It does
    /// nothing.
    @Test func aWakeForAnOldDeadlineDoesNothing() {
        var timer = SleepTimer()
        timer.set(.after(.seconds(60)), now: now)
        timer.add(.seconds(300), now: now, trackLeft: nil)

        let fired1 = timer.deadlineArrived(now: now + .seconds(60))
        #expect(!fired1)
        #expect(timer.isOn)

        let fired2 = timer.deadlineArrived(now: now + .seconds(360))
        #expect(fired2)
        #expect(!timer.isOn, "a timer that fired is still on")
    }

    @Test func anEndOfTrackTimerIsNotADeadline() {
        var timer = SleepTimer()
        timer.set(.endOfTrack, now: now)

        let fired3 = timer.deadlineArrived(now: now + .seconds(100_000))
        #expect(!fired3)
        let fired4 = timer.trackEnded()
        #expect(fired4)
        #expect(!timer.isOn)
        let fired5 = timer.trackEnded()
        #expect(!fired5, "the same ending paused twice")
    }

    @Test func aTimedTimerIgnoresTheTrackEnding() {
        var timer = SleepTimer()
        timer.set(.after(.seconds(60)), now: now)

        let fired6 = timer.trackEnded()
        #expect(!fired6)
        #expect(timer.isOn)
    }

    /// The timer's deadline passed while the music was paused and the app was suspended. The
    /// first thing that happens after is a play command from the lock screen. The play is
    /// newer than the deadline, so the play wins, whichever event the app receives first.
    @Test func playAfterTheDeadlineTurnsTheTimerOffInsteadOfBeingPaused() {
        var timer = SleepTimer()
        timer.set(.after(.seconds(60)), now: now)

        timer.somebodyAskedForSound(now: now + .seconds(90))

        #expect(!timer.isOn)
        let fired7 = timer.deadlineArrived(now: now + .seconds(90))
        #expect(!fired7)
    }

    @Test func playBeforeTheDeadlineLeavesTheTimerRunning() {
        var timer = SleepTimer()
        timer.set(.after(.seconds(60)), now: now)

        timer.somebodyAskedForSound(now: now + .seconds(30))

        #expect(timer.isOn)
    }

    @Test func aStationEndsAnEndOfTrackTimerButNotATimedOne() {
        var waiting = SleepTimer()
        waiting.set(.endOfTrack, now: now)
        waiting.stationTuned()
        #expect(!waiting.isOn)

        var timed = SleepTimer()
        timed.set(.after(.seconds(60)), now: now)
        timed.stationTuned()
        #expect(timed.isOn)
    }

    @Test func addingTimeToATimerThatIsOffDoesNothing() {
        var timer = SleepTimer()
        timer.add(.seconds(300), now: now, trackLeft: .seconds(60))

        #expect(!timer.isOn)
    }
}

// The player.

private func track(_ id: String) -> CloudTrack {
    CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: id,
               artist: "Talk Talk", album: "Spirit of Eden", tags: CloudTrackTags())
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

@MainActor
private func player(_ store: SilentStore) -> Player {
    Player(source: SilenceSigned(store: store), shelves: AnyShelf(), copies: NoCopies(), nearby: NothingNearby(),
           reach: NetworkReach(), levelling: .album, levelsClassical: false, classical: { _ in false }, cover: { _ in nil })
}

@MainActor
@Test func aTimedSleepTimerPausesThePlayer() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = player(store)
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)
    #expect(rpm.wantsToPlay)

    rpm.setSleepTimer(.after(.milliseconds(300)))

    try await until("the timer to pause the player") { !rpm.wantsToPlay }
    #expect(!rpm.sleepTimer.isOn)
    #expect(rpm.current?.rpmId == "t0", "the timer did more than pause")

    rpm.stop()
}

@MainActor
@Test func turningTheTimerOffStopsItPausing() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = player(store)
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)

    rpm.setSleepTimer(.after(.milliseconds(300)))
    rpm.turnOffSleepTimer()
    try await Task.sleep(for: .milliseconds(700))

    #expect(rpm.wantsToPlay)

    rpm.stop()
}

/// **With an end-of-track timer, the next record is not handed to the engine.** The track
/// plays to its end and the engine runs out there. If the next record were already loaded, the
/// engine would play into it and be stopped a moment later.
@MainActor
@Test func anEndOfTrackTimerTakesBackTheNextRecordAndGivesItBackWhenTurnedOff() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = player(store)
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)
    try await until("the next record to be handed over") { rpm.loadedBehindTheNeedle }

    rpm.setSleepTimer(.endOfTrack)
    #expect(!rpm.loadedBehindTheNeedle, "the next record would play into the timer")

    rpm.turnOffSleepTimer()
    try await until("the next record to be handed over again") { rpm.loadedBehindTheNeedle }

    rpm.stop()
}

/// The full run on the engine. The track plays out, and the player stops on the next track,
/// paused, with the timer off. Pressing play then plays that next track.
@MainActor
@Test func anEndOfTrackTimerPausesOnTheNextRecordWhenTheTrackEnds() async throws {
    let store = SilentStore()
    store.lasts(2, for: "t0")
    try await store.start()
    defer { store.stop() }

    let rpm = player(store)
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)
    rpm.setSleepTimer(.endOfTrack)

    try await until("the queue to move on", within: .seconds(20)) {
        rpm.index == 1 && !rpm.isBusy
    }

    #expect(!rpm.wantsToPlay, "the next record started playing")
    #expect(!rpm.sleepTimer.isOn)

    rpm.resume()
    #expect(rpm.wantsToPlay)

    rpm.stop()
}

/// A skip is a choice of the next track, not the end of the track. The timer moves to the
/// track that was chosen.
@MainActor
@Test func skippingMovesAnEndOfTrackTimerToTheNextTrack() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = player(store)
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)
    rpm.setSleepTimer(.endOfTrack)

    await rpm.next()

    #expect(rpm.index == 1)
    #expect(rpm.wantsToPlay)
    #expect(rpm.sleepTimer.endsWithTheTrack)
    #expect(!rpm.loadedBehindTheNeedle)

    rpm.stop()
}

@MainActor
@Test func stoppingEndsTheTimer() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = player(store)
    await rpm.play((0..<3).map { track("t\($0)") }, from: 0, because: .somebodyAskedForIt)
    rpm.setSleepTimer(.after(.seconds(900)))

    rpm.stop()

    #expect(!rpm.sleepTimer.isOn)
}

/// When the last track ends with an end-of-track timer, the queue has run out and the session
/// is over.
@MainActor
@Test func anEndOfTrackTimerOnTheLastTrackEndsTheSitting() async throws {
    let store = SilentStore()
    try await store.start()
    defer { store.stop() }

    let rpm = player(store)
    await rpm.play([track("t0")], from: 0, because: .somebodyAskedForIt)
    rpm.setSleepTimer(.endOfTrack)

    rpm.queueRanOut(.theRecordFinished)

    #expect(rpm.isOver)
    #expect(!rpm.sleepTimer.isOn)
}
