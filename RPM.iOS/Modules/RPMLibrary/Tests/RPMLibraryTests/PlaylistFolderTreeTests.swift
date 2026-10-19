import Testing
@testable import RPMLibrary

/// Mirrors the desktop's `RPM.Core.Tests/PlaylistFolderTreeTests.cs`, so both apps place folders
/// the same way.

// ── where a playlist sits ──

@Test func aPlaylistNobodyFiledIsAtTheTopOfTheTree() {
    #expect(PlaylistFolderTree.isIn([], []))
}

@Test func aPlaylistInAFolderIsNotAtTheTopOfTheTree() {
    #expect(PlaylistFolderTree.isIn(["Rock"], []) == false)
}

@Test func aPlaylistDeeperDownIsNotInTheFolderItPassesThrough() {
    #expect(PlaylistFolderTree.isIn(["Rock", "90s"], ["Rock"]) == false)
}

@Test func aPlaylistDeeperDownIsUnderTheFolderItPassesThrough() {
    #expect(PlaylistFolderTree.isUnder(["Rock", "90s"], ["Rock"]))
}

/// A folder counts as being under itself. Playlists directly in it are part of what it holds.
@Test func aFolderHoldsWhatIsDirectlyInItAsWell() {
    #expect(PlaylistFolderTree.isUnder(["Rock"], ["Rock"]))
}

@Test func nothingInOneBranchIsUnderAnother() {
    #expect(PlaylistFolderTree.isUnder(["Pop", "90s"], ["Rock"]) == false)
}

@Test func everythingIsUnderTheTopOfTheTree() {
    #expect(PlaylistFolderTree.isUnder(["Rock", "90s"], []))
}

@Test func caseIsNotWhatTellsTwoFoldersApart() {
    #expect(PlaylistFolderTree.isIn(["rock"], ["Rock"]))
}

// ── what one level shows ──

@Test func theTopOfTheTreeShowsTheFoldersAtTheTopOfTheTree() {
    let rows = PlaylistFolderTree.foldersIn([["Rock"], ["Pop"], ["Rock", "90s"]], at: [])
    #expect(rows.map(\.name) == ["Pop", "Rock"])
}

/// Within one folder, the name identifies the folder. The user is in one place at a time, so two folders
/// named "90s" are never on screen together.
@Test func twoFoldersOfOneNameInDifferentBranchesNeverMeet() {
    let chains = [["Rock", "90s"], ["Pop", "90s"]]
    #expect(PlaylistFolderTree.foldersIn(chains, at: ["Rock"]).map(\.name) == ["90s"])
    #expect(PlaylistFolderTree.foldersIn(chains, at: ["Pop"]).map(\.name) == ["90s"])
}

@Test func steppingIntoAFolderCarriesTheWholeWayDownToIt() {
    let rows = PlaylistFolderTree.foldersIn([["Rock", "90s"]], at: ["Rock"])
    let row = try! #require(rows.first)
    #expect(rows.count == 1)
    #expect(row.path == ["Rock", "90s"])
}

@Test func aFolderAppearsOnceHoweverManyPlaylistsAreInIt() {
    let rows = PlaylistFolderTree.foldersIn([["Rock"], ["Rock"], ["Rock"]], at: [])
    #expect(rows.count == 1)
    #expect(rows.first?.name == "Rock")
}

/// The cloud stores no folders of its own. A folder is known only from the playlists in it, so an empty
/// one is not shown.
@Test func aFolderHoldingNothingIsNotAFolderThePhoneKnowsAbout() {
    #expect(PlaylistFolderTree.foldersIn([[], []], at: []).isEmpty)
}

// ── what a folder counts ──

@Test func aFolderCountsWhatIsDirectlyInIt() {
    let rows = PlaylistFolderTree.foldersIn([["Rock"], ["Rock"]], at: [])
    #expect(rows.first?.playlists == 2)
}

/// The count is for the rows the tap opens to, not everything below. Here that is one playlist and one
/// folder, not the two playlists inside the folder.
@Test func aFolderCountsTheRowsOpeningItShows() {
    let rows = PlaylistFolderTree.foldersIn(
        [["Rock"], ["Rock", "90s"], ["Rock", "90s", "Indie"]], at: [])
    #expect(rows.count == 1)
    #expect(rows.first?.playlists == 2)
}

/// A folder that holds only other folders must not show a count of zero. A folder exists because something
/// is filed in it or below it, so the tap always opens something.
@Test func aFolderHoldingOnlyFoldersDoesNotReadAsEmpty() {
    let rows = PlaylistFolderTree.foldersIn([["Rock", "90s"], ["Rock", "80s"]], at: [])
    #expect(rows.first?.playlists == 2)
}

// ── where you end up standing ──

@Test func aFolderThatStillHoldsSomethingIsWhereYouStay() {
    #expect(PlaylistFolderTree.stillOpen(["Rock"], folders: [["Rock", "90s"]]) == ["Rock"])
}

@Test func aFolderWhoseLastPlaylistHasGonePutsYouInTheOneThatHeldIt() {
    #expect(PlaylistFolderTree.stillOpen(["Rock", "90s"], folders: [["Rock"]]) == ["Rock"])
}

@Test func aWholeBranchGoingPutsYouBackAtTheTopOfTheTree() {
    #expect(PlaylistFolderTree.stillOpen(["Rock", "90s"], folders: [["Pop"]]).isEmpty)
}

@Test func anAccountWithNothingLeftInItPutsYouAtTheTopOfTheTree() {
    #expect(PlaylistFolderTree.stillOpen(["Rock"], folders: []).isEmpty)
}

@Test func aFolderHoldingOnlyFoldersIsStillAPlaceYouCanStand() {
    #expect(PlaylistFolderTree.stillOpen(["Rock"], folders: [["Rock", "90s"]]) == ["Rock"])
}

@Test func theTopOfTheTreeIsAlwaysSomewhereYouCanBe() {
    #expect(PlaylistFolderTree.stillOpen([], folders: []).isEmpty)
}
