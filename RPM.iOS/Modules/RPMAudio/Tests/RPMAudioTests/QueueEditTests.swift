import Testing
@testable import RPMAudio

/// Tests for editing the queue while it plays. The desktop version of these tests is
/// `RPM.Core.Tests/QueueEditTests.cs`.
///
/// The playing track is stored as a position. Every removal above it moves that position. A
/// mistake here does not throw an error. It plays the wrong song next.

private func plan(_ count: Int, _ current: Int?, _ remove: Int...) -> QueueEdit.Removal {
    QueueEdit.planRemoval(count: count, current: current, remove: remove)
}

// ── removing ──

/// Removals are applied from the highest position down. Removing 1 and then 3 from a five-track
/// queue would remove the wrong track, because removing 1 has already moved 3 down to 2.
@Test func removalsComeBackHighestFirst() {
    #expect(plan(5, nil, 1, 3, 0).removals == [3, 1, 0])
}

/// Each track taken from above the playing one pulls it down by exactly one.
@Test(arguments: [(4, [0], 3), (4, [0, 1], 2), (4, [0, 1, 2, 3], 0)])
func thePlayingTrackSlidesDownPastEachRemovalAboveIt(each: (Int, [Int], Int)) {
    let plan = QueueEdit.planRemoval(count: 10, current: each.0, remove: each.1)

    #expect(!plan.removedCurrent)
    #expect(plan.current == each.2)
}

@Test func removalsBelowThePlayingTrackLeaveItWhereItIs() {
    let made = plan(10, 2, 5, 7, 9)

    #expect(!made.removedCurrent)
    #expect(made.current == 2)
}

/// Removing the playing track stops playback. The next track does not slide into its place and
/// start. Nothing is current afterwards.
@Test func removingThePlayingTrackStopsRatherThanSlidingOntoItsNeighbour() {
    let made = plan(5, 2, 2)

    #expect(made.removedCurrent)
    #expect(made.current == nil)
}

/// A selection that includes the playing track stops playback, however many other tracks are
/// selected.
@Test func aSelectionContainingThePlayingTrackStops() {
    let made = plan(6, 3, 0, 1, 3, 5)

    #expect(made.removedCurrent)
    #expect(made.current == nil)
    #expect(made.removals == [5, 3, 1, 0])
}

@Test func withNothingPlayingThereIsNothingToTrack() {
    let made = plan(5, nil, 0, 4)

    #expect(!made.removedCurrent)
    #expect(made.current == nil)
}

/// A stale selection is ignored, without an error. The list may be dragged against a queue that
/// has already changed.
@Test func positionsOffTheEndAreIgnored() {
    let made = plan(3, 1, -1, 3, 99, 2)

    #expect(made.removals == [2])
    #expect(!made.removedCurrent)
    #expect(made.current == 1)
}

/// The same position given twice counts as one removal. Otherwise the second would remove the
/// neighbouring track.
@Test func aRepeatedPositionIsRemovedOnce() {
    let made = plan(4, 3, 1, 1, 1)

    #expect(made.removals == [1])
    #expect(made.current == 2)
}

@Test func removingNothingChangesNothing() {
    let made = plan(4, 2)

    #expect(made.removals.isEmpty)
    #expect(!made.removedCurrent)
    #expect(made.current == 2)
}

/// Removing every track empties the queue. Playback stops, because the playing track was removed.
@Test func removingEveryTrackEmptiesTheQueueAndStops() {
    let made = plan(3, 1, 0, 1, 2)

    #expect(made.removals == [2, 1, 0])
    #expect(made.removedCurrent)
    #expect(made.current == nil)
}

// ── reordering ──

/// Dragging the playing track moves the playing mark with it. Playback does not stop. The song
/// continues, and it has a new position in the queue.
@Test func draggingThePlayingTrackMovesTheMarkWithIt() {
    let made = QueueEdit.planMove(count: 6, current: 4, from: 4, to: 1)

    #expect(made.from == 4)
    #expect(made.to == 1)
    #expect(made.current == 1)
}

/// Moving a track from below the playing one to above it pushes the playing track down by one
/// place. This is easy to get wrong. The insertion must move the playing track as well as the
/// removal. Without the insertion step, the mark ends up one row off.
@Test func aTrackCarriedFromBelowThePlayingOneToAbovePushesItDown() {
    #expect(QueueEdit.planMove(count: 6, current: 3, from: 0, to: 5).current == 2)
}

@Test func aTrackCarriedFromAboveThePlayingOneToBelowPullsItUp() {
    #expect(QueueEdit.planMove(count: 6, current: 3, from: 5, to: 0).current == 4)
}

/// A drag entirely on one side of the playing track cannot move it.
@Test(arguments: [(0, 2), (2, 0), (4, 5), (5, 4)])
func aDragThatStepsOverThePlayingTrackLeavesItAlone(drag: (Int, Int)) {
    #expect(QueueEdit.planMove(count: 6, current: 3, from: drag.0, to: drag.1).current == 3)
}

/// Dropped where it was picked up: there is nothing to apply. The result says so, and the caller
/// does not need to compare positions.
@Test func droppingATrackWhereItStartedIsNothing() {
    let made = QueueEdit.planMove(count: 4, current: 2, from: 1, to: 1)

    #expect(made.isNothing)
    #expect(made.current == 2)
}

/// A drag off either end lands at the end it was dragged towards.
@Test(arguments: [(-3, 0), (99, 3)])
func aDragOffTheEndLandsAtTheEnd(drag: (Int, Int)) {
    #expect(QueueEdit.planMove(count: 4, current: nil, from: 1, to: drag.0).to == drag.1)
}

@Test func aReorderWithNothingPlayingTracksNothing() {
    #expect(QueueEdit.planMove(count: 5, current: nil, from: 0, to: 4).current == nil)
}

/// A queue of one cannot be reordered, and asking is not an error.
@Test func aQueueOfOneHasNothingToReorder() {
    #expect(QueueEdit.planMove(count: 1, current: 0, from: 0, to: 0).isNothing)
}

/// **The plan must match what the list does**: remove at `from`, then insert at `to`. If it
/// differs, the mark follows a different queue from the one on screen.
@Test(arguments: [(0, 3), (3, 0), (1, 4), (4, 2)])
func theMarkFollowsTheTrackARealListWouldEndUpWith(drag: (Int, Int)) throws {
    let queue = ["a", "b", "c", "d", "e"]

    for current in queue.indices {
        let playing = queue[current]
        let made = QueueEdit.planMove(count: queue.count, current: current,
                                      from: drag.0, to: drag.1)

        var after = queue
        let carried = after.remove(at: made.from)
        after.insert(carried, at: made.to)

        #expect(after[try #require(made.current)] == playing)
    }
}

/// The same check for removals: after all the removals are applied, the marked position must hold
/// the playing track.
@Test(arguments: [[0], [1], [4], [0, 1], [1, 3], [0, 2, 4]])
func theMarkFollowsTheTrackARealListWouldEndUpWithAfterRemoving(remove: [Int]) {
    let queue = ["a", "b", "c", "d", "e"]

    for current in queue.indices {
        let playing = queue[current]
        let made = QueueEdit.planRemoval(count: queue.count, current: current, remove: remove)

        var after = queue
        for at in made.removals { after.remove(at: at) }

        if let at = made.current {
            #expect(after[at] == playing)
        } else {
            #expect(!after.contains(playing))
        }
    }
}

// ── which tracks a new order may change ──

/// **Only tracks ahead of the needle can be reordered.** Tracks already played are part of this
/// sitting. The playing track must not be moved out from under the player.
@Test func anotherOrderReachesWhatIsComingAndNothingElse() {
    #expect(QueueEdit.whatIsComing(count: 10, current: 3) == 4..<10)
}

/// With nothing playing, the whole queue is still to come. Starting a shuffled queue is this case.
@Test func nothingPlayingLeavesTheWholeQueueStillToCome() {
    #expect(QueueEdit.whatIsComing(count: 4, current: nil) == 0..<4)
}

/// A stretch of zero or one track cannot be reordered. The caller shows no control for it.
@Test(arguments: [(3, 2), (3, 1), (1, 0), (0, nil), (1, nil)] as [(Int, Int?)])
func aStretchTooShortToReorderIsNothing(queue: (Int, Int?)) {
    #expect(QueueEdit.whatIsComing(count: queue.0, current: queue.1) == nil)
}

/// A position outside the queue is handled without an error. A position past the end has nothing
/// coming. A position before the start counts as nothing played. A queue edit can move the player
/// between one frame and the next, so the position may be out of range.
@Test func aNeedleOffTheEndHasNothingComing() {
    #expect(QueueEdit.whatIsComing(count: 4, current: 99) == nil)
    #expect(QueueEdit.whatIsComing(count: 4, current: -9) == 0..<4)
}

// ── whether the songs still to come were changed ──

private func changed(_ queue: [String], _ current: Int?, _ started: [String]) -> Bool {
    QueueEdit.hasChangesAhead(queue: queue, current: current, started: started)
}

private let album = (0..<10).map { "t\($0)" }

@Test func anAlbumPlayingInOrderHasNoChangesAhead() {
    #expect(!changed(album, 0, album))
    #expect(!changed(album, 3, album))
}

/// Started at track nine, the album is still the whole queue and nothing was changed.
@Test func anAlbumStartedPartWayInHasNoChangesAhead() {
    #expect(!changed(album, 8, album))
}

@Test func nothingLeftToComeIsNeverChanged() {
    #expect(!changed(album, 9, album))
    #expect(!changed(["x", "y"], 1, album))
    #expect(!changed([], nil, album))
}

@Test func aSongAddedAfterThePlayingOneIsAChange() {
    var queue = album
    queue.insert("x", at: 4)

    #expect(changed(queue, 3, album))
}

/// This is an accepted over-report. While the added song plays, the songs after it are the album.
/// But the playing track is not in the album, so the rule cannot tell where it is in the album.
@Test func theAddedSongPlayingStillCountsAsAChange() {
    var queue = album
    queue.insert("x", at: 4)

    #expect(changed(queue, 4, album))
}

/// After the added song has played, the rest of the queue is the album in its original order.
/// Replacing the queue then loses nothing.
@Test func anAddedSongThatHasPlayedIsNoLongerAChange() {
    var queue = album
    queue.insert("x", at: 4)

    #expect(!changed(queue, 5, album))
}

@Test func aSongDraggedIntoTheUpcomingListIsAChange() {
    var queue = album
    let moved = queue.remove(at: 8)
    queue.insert(moved, at: 4)

    #expect(changed(queue, 3, album))
}

/// Removing the next song leaves the end of the queue the same as the album's end. Comparing only
/// the ends would miss the change. The playing track position must be checked too.
@Test func removingTheNextSongIsAChange() {
    var queue = album
    queue.remove(at: 4)

    #expect(changed(queue, 3, album))
}

@Test func removingTheLastSongIsAChange() {
    var queue = album
    queue.remove(at: 9)

    #expect(changed(queue, 3, album))
}

/// Only the songs still to come count. Removing a song that has already played changes nothing
/// that replacing the queue would discard.
@Test func removingAPlayedSongIsNotAChange() {
    var queue = album
    queue.remove(at: 1)

    #expect(!changed(queue, 2, album))
}

/// The playing track was removed, so nothing is playing and the rest of the queue is
/// still there. That is a change.
@Test func removingThePlayingSongIsAChange() {
    var queue = album
    queue.remove(at: 3)

    #expect(changed(queue, nil, album))
}

/// With nothing playing and the queue as it was started, nothing has changed.
@Test func nothingPlayingWithTheQueueAsStartedIsNotAChange() {
    #expect(!changed(album, nil, album))
}

/// A queue with songs added to an empty player was never started from a list.
@Test func songsAddedToAnEmptyPlayerAreAChange() {
    #expect(changed(["x"], nil, []))
}

/// More songs to come than the list ever had means some were added.
@Test func moreToComeThanTheListHadIsAChange() {
    #expect(changed(["x"] + album, 0, album))
}

/// Songs are compared by id. Two copies of one song that swap places count as the same list.
@Test func twoCopiesOfOneSongSwappedAreNotAChange() {
    let started = ["a", "b", "a", "c"]

    #expect(!changed(["a", "b", "a", "c"], 0, started))
}
