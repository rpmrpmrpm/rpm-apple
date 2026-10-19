import Testing
import Foundation
import RPMKit
@testable import RPMAudio

/// The queue as the list shows it: which rows are shown, the identity each row keeps while it is
/// dragged, and where a drag lands.
///
/// Both faults these tests guard against look reasonable in the code. A row identified by its
/// position works until something is dragged. A list of the whole queue works until a record
/// starts at track ten.

private func track(_ id: String) -> CloudTrack {
    CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: id,
               artist: "Dire Straits", album: "Making Movies", tags: CloudTrackTags())
}

private func queue(_ ids: String...) -> [CloudTrack] { ids.map(track) }

// ── what is shown ──

/// Tracks above the one that started the sitting were never played, so they are not shown.
/// Showing them would say that they were played and skipped.
@Test func theRowsBeginWhereTheSittingDid() {
    let rows = QueueRows.of(queue("a", "b", "c", "d"), .sitting(from: 2, playing: 2))

    #expect(rows.map(\.track.rpmId) == ["c", "d"])
    #expect(rows.map(\.at) == [2, 3])
}

/// A stored playlist is not a sitting: all of it is shown and none of it is behind
/// a needle.
@Test func awholeListShowsEverythingAndNothingIsPlayed() {
    let rows = QueueRows.of(queue("a", "b", "c"), .whole)

    #expect(rows.count == 3)
    #expect(rows.allSatisfy { $0.state == .coming })
}

@Test func aRowKnowsWhetherItIsBehindTheNeedleUnderItOrAheadOfIt() {
    let rows = QueueRows.of(queue("a", "b", "c", "d"), .sitting(from: 0, playing: 2))

    #expect(rows.map(\.state) == [.played, .played, .playing, .coming])
}

/// The top is read from the player, and a queue edit can move it between one frame and the next.
@Test func aTopPastTheEndOfTheQueueIsAnEmptyListRatherThanACrash() {
    #expect(QueueRows.of(queue("a", "b"), .sitting(from: 9, playing: nil)).isEmpty)
    #expect(QueueRows.of(queue("a", "b"), .sitting(from: -3, playing: nil)).count == 2)
}

// ── identity ──

/// If the position were the identity, a reorder would move no row. Each row would keep its id
/// and get different contents. The list would then draw two rows in one place, with a gap where
/// the third one should be.
@Test func aRowCarriesItsIdentityWithItWhenTheQueueIsReordered() {
    let before = QueueRows.of(queue("a", "b", "c"), .whole)
    let after = QueueRows.of(queue("c", "a", "b"), .whole)

    #expect(before.map(\.id) == ["a#0", "b#0", "c#0"])
    #expect(after.map(\.id) == ["c#0", "a#0", "b#0"])
}

/// A queue can hold the same song twice. A playlist can name it twice, and "play next" can move
/// one copy past another. Two rows with the same id would make the list draw one of them and lose
/// the other.
@Test func twoCopiesOfTheSameSongAreTwoDifferentRows() {
    let rows = QueueRows.of(queue("a", "b", "a"), .whole)

    #expect(rows.map(\.id) == ["a#0", "b#0", "a#1"])
    #expect(Set(rows.map(\.id)).count == 3)
}

/// The count runs over the whole queue, not over the rows shown. Pressing back shows more rows.
/// If a row's id changed because of that, the list would treat it as a different song.
@Test func anIdentityDoesNotChangeWhenTheSittingReachesFurtherBack() {
    let deep = QueueRows.of(queue("a", "b", "a", "c"), .sitting(from: 2, playing: 2))
    let back = QueueRows.of(queue("a", "b", "a", "c"), .sitting(from: 1, playing: 1))

    #expect(deep.map(\.id) == ["a#1", "c#0"])
    #expect(back.map(\.id) == ["b#0", "a#1", "c#0"])
}

// ── where a drag lands ──

private func drop(_ look: QueueLook, count: Int, from: Int, to: Int) -> (from: Int, to: Int)? {
    let rows = QueueRows.of((0..<count).map { track("t\($0)") }, look)
    return QueueRows.drop(rows, look, from: IndexSet(integer: from), to: to, count: count)
}

/// `SwiftUI` reports the row that the drop is placed before. The player is told the landing spot
/// after the dragged row has been removed. So dragging the first row to the end is a drop at
/// index 5 and a landing at index 4.
@Test func aRowDraggedDownLandsOnePlaceBeforeTheRowItWasDroppedAt() {
    #expect(drop(.whole, count: 5, from: 0, to: 5).map { $0.to } == 4)
    #expect(drop(.whole, count: 5, from: 0, to: 3).map { $0.to } == 2)
}

/// Dragging up needs no such correction: nothing above the landing spot has moved.
@Test func aRowDraggedUpLandsWhereItWasDropped() {
    #expect(drop(.whole, count: 5, from: 4, to: 1).map { $0.to } == 1)
}

/// The rows on the screen are not queue positions when the list starts part way in. The third row
/// of a list that starts at t2 is t4, not t2.
@Test func aDragIsTranslatedOutOfTheScreenAndIntoTheQueue() {
    // Shown: t2 playing, then t3, t4, t5. The last of them dragged up one.
    let moved = drop(.sitting(from: 2, playing: 2), count: 6, from: 3, to: 2)

    #expect(moved?.from == 5)
    #expect(moved?.to == 4)
}

/// A row with nowhere to go. The only place above it is the playing record, so the drag is
/// refused. It does not land back where it started.
@Test func theOneRowAfterTheNeedleCannotBeDraggedOverIt() {
    #expect(drop(.sitting(from: 3, playing: 3), count: 5, from: 1, to: 0) == nil)
}

/// **A drag never lands in the past.** The rows above the needle have already been played.
/// Dropping a song there would ask for it to play before now, so the row is placed just after the
/// playing record instead.
@Test func aRowDroppedAboveTheNeedleLandsJustAfterItInstead() {
    let moved = drop(.sitting(from: 0, playing: 2), count: 5, from: 4, to: 0)

    #expect(moved?.to == 3)
}

/// Nothing is playing. The top of the list is the lowest place a row can land.
@Test func withNothingPlayingTheFloorIsTheTopOfTheList() {
    #expect(drop(.sitting(from: 2, playing: nil), count: 5, from: 1, to: 0).map { $0.to } == 2)
}

@Test func adragThatEndsWhereItBeganIsNothingToDo() {
    #expect(drop(.whole, count: 5, from: 2, to: 2) == nil)
    #expect(drop(.whole, count: 5, from: 2, to: 3) == nil)
}
