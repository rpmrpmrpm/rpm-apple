import Testing
@testable import RPMLibrary

/// Mirrors `RPM.Core.Tests/PlaylistMergeTests.cs`, case for case and name for name. The test cases
/// are kept unchanged on purpose. This merge has the highest impact of any arithmetic in the app,
/// and its failure mode is a playlist that empties itself. A Swift version that passed only
/// Swift-shaped tests would prove only that it agreed with itself.
private func merge(_ published: [String], _ mine: [String], _ theirs: [String]) -> [String] {
    PlaylistMerge.songs(ancestor: .published(published), mine: mine, theirs: theirs)
}

// ── one side moved ──

@Test func nothingChangedAnywhereIsTheSameList() {
    #expect(merge(["a", "b"], ["a", "b"], ["a", "b"]) == ["a", "b"])
}

@Test func onlyTheOtherHeadMovedSoItsListIsTakenWhole() {
    #expect(merge(["a", "b"], ["a", "b"], ["a", "b", "c"]) == ["a", "b", "c"])
}

@Test func onlyThisHeadMovedSoItsListStands() {
    #expect(merge(["a", "b"], ["a", "b", "c"], ["a", "b"]) == ["a", "b", "c"])
}

/// This is the case the whole-list shortcut is for. If a reorder went through the counting
/// arithmetic, it would return the published order and silently undo the reorder.
@Test func aReorderMadeHereSurvivesAnUnchangedCloud() {
    #expect(merge(["a", "b", "c"], ["c", "a", "b"], ["a", "b", "c"]) == ["c", "a", "b"])
}

// ── both sides moved ──

@Test func twoHeadsAddingDifferentSongsKeepBoth() {
    #expect(merge(["a"], ["a", "x"], ["a", "y"]) == ["a", "y", "x"])
}

@Test func aRemovalHereStandsAgainstAnAdditionThere() {
    #expect(merge(["a", "b"], ["a"], ["a", "b", "y"]) == ["a", "y"])
}

@Test func aRemovalThereStandsAgainstAnAdditionHere() {
    #expect(merge(["a", "b"], ["a", "b", "x"], ["a"]) == ["a", "x"])
}

@Test func bothRemovingTheSameSongRemovesItOnce() {
    #expect(merge(["a", "b"], ["a"], ["a"]) == ["a"])
}

/// If both heads add the same song, that is one change made twice, not two changes. Adding the two counts
/// together would turn a list of songs into a list of pairs of songs.
@Test func bothAddingTheSameSongDoesNotAddItTwice() {
    #expect(merge(["a"], ["a", "x"], ["a", "x"]) == ["a", "x"])
}

// ── order ──

/// When both sides reorder, there is no single right answer. One side must lose, and the published
/// order wins, because every other head already uses it.
@Test func whenBothReorderedThePublishedOrderWins() {
    #expect(merge(["a", "b", "c"], ["c", "b", "a"], ["b", "c", "a"]) == ["b", "c", "a"])
}

/// An added song has no place in an order that has never seen it, so it goes at the end.
@Test func anAdditionHereIsAppendedAfterThePublishedOrder() {
    #expect(merge(["a", "b"], ["a", "b", "x"], ["b", "a"]) == ["b", "a", "x"])
}

// ── the same song twice, on purpose ──

@Test func aSecondCopyAddedThereIsKept() {
    #expect(merge(["a", "b"], ["a", "b"], ["a", "a", "b"]) == ["a", "a", "b"])
}

@Test func aSecondCopyRemovedHereGoes() {
    #expect(merge(["a", "a"], ["a"], ["a", "a", "y"]) == ["a", "y"])
}

@Test func eachHeadAddingTheSameCopyIsOneChange() {
    #expect(merge(["a"], ["a", "a"], ["a", "a"]) == ["a", "a"])
}

// ── emptying ──

@Test func aPlaylistEmptiedHereEmpties() {
    #expect(merge(["a", "b"], [], ["a", "b"]).isEmpty)
}

@Test func aPlaylistEmptiedThereEmpties() {
    #expect(merge(["a", "b"], ["a", "b"], []).isEmpty)
}

@Test func emptiedHereKeepsWhatTheOtherHeadAdded() {
    #expect(merge(["a", "b"], [], ["a", "b", "y"]) == ["y"])
}

// ── no ancestor ──

/// This is the failure the type exists to prevent. Without an ancestor, nothing can be shown to have been
/// removed, so nothing is removed. If "unknown" were read as a known empty list, every song would count as a
/// removal, and the playlist would empty itself on its first sync.
@Test func withNoAncestorNothingIsRemoved() {
    let merged = PlaylistMerge.songs(ancestor: .unknown, mine: ["a", "x"], theirs: ["a", "y"])
    #expect(merged == ["a", "y", "x"])
}

@Test func withNoAncestorASongHeldTwiceOnOneSideIsKeptTwice() {
    let merged = PlaylistMerge.songs(ancestor: .unknown, mine: ["a", "a"], theirs: ["a"])
    #expect(merged == ["a", "a"])
}

@Test func anUnknownAncestorSaysSo() {
    #expect(PlaylistBase.unknown.isKnown == false)
    #expect(PlaylistBase.published([]).isKnown)
}

/// A known empty ancestor is a real answer, and it is different from an unknown one. Both sides' songs are
/// additions to a list that really was empty.
@Test func aKnownEmptyAncestorAddsBothSides() {
    #expect(merge([], ["x"], ["y"]) == ["y", "x"])
}

// ── what a pusher asks ──

/// An unknown base never matches. This makes a playlist with no record of a published state upload,
/// instead of sitting silently.
@Test func anUnknownBaseMatchesNothing() {
    #expect(PlaylistBase.unknown.matches([]) == false)
    #expect(PlaylistBase.unknown.matches(["a"]) == false)
}

@Test func aPublishedBaseMatchesOnlyTheSameSongsInTheSameOrder() {
    let base = PlaylistBase.published(["a", "b"])
    #expect(base.matches(["a", "b"]))
    #expect(base.matches(["b", "a"]) == false)
    #expect(base.matches(["a"]) == false)
    #expect(base.matches(["a", "b", "c"]) == false)
}
