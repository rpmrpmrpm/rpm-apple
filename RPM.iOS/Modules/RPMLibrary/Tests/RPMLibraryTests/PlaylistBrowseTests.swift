import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// What the playlists tab shows at one place in the tree.
///
/// The desktop (C#) works this out inside `PlaylistsPage.Rebuild`, which cannot be called in a test
/// without a page. These tests follow what its code comments say, because that is the only
/// specification there is.

private func track(_ id: String, seconds: Double = 200) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.durationSeconds = seconds
    return CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: id,
                      artist: "Talk Talk", album: "Spirit of Eden", tags: tags)
}

private func set(_ name: String, in folder: [String] = [], tracks: [CloudTrack] = [],
                 missing: Int = 0, origin: PlaylistOrigin = .stored) -> PlaylistSet {
    PlaylistSet(id: "p-\(name)", name: name, tracks: tracks, missing: missing,
                folder: folder, stamp: 0, shelf: .own, origin: origin)
}

/// A list the computer generated, keyed as `GeneratedLists.sets` keys it.
private func cut(_ name: String, kind: String, genre: String? = nil, decade: Int = 0,
                 in folder: [String], tracks: [CloudTrack] = [track("c")]) -> PlaylistSet {
    PlaylistSet(id: "\u{1}mood/\(name)", name: name, tracks: tracks, missing: 0,
                folder: folder, stamp: 0, shelf: .own, origin: .generated,
                cut: GeneratedCut(kind: kind, genre: genre, decade: decade))
}

private func browse(_ at: [String] = [], _ playlists: [PlaylistSet],
                    favorites: [CloudTrack]? = []) -> PlaylistBrowse {
    PlaylistBrowse.of(at: at, playlists: playlists, favorites: favorites)
}

private var favourites: String { Loc.get("Playlists_FavoriteTracks") }

// ── no queue, and the listening lists at the top ──

/// The queue has no row. The queue key on the player shows it, and the desktop leaves it out of its tree.
/// Nothing marked and nothing stored is an empty tab.
@Test func anEmptyShelfHasNoRows() {
    #expect(browse([], []).rows.isEmpty)
}

/// The listening lists stand at the top of the tree, as lists of their own. The computer files them in its
/// Smart playlists folder, and the phone apps have no such folder.
@Test func theListeningListsStandAtTheTop() {
    let lists = [
        cut("On repeat", kind: "OnRepeat", in: ["Smart playlists"]),
        cut("Your mix", kind: "RightNow", in: ["Smart playlists"]),
    ]

    let top = browse([], lists, favorites: nil).rows

    #expect(top.map(\.name) == ["On repeat", "Your mix"])
    #expect(top.allSatisfy { !$0.isFolder })
}

/// The app's lists come above the person's own, as on Android. Each group is by name.
@Test func theAppsListsComeAboveThePersonsOwn() {
    let lists = [set("Aardvark"), cut("Your mix", kind: "RightNow", in: ["Smart playlists"]), set("Zebra")]

    let top = browse([], lists, favorites: [track("f")]).rows

    #expect(top.map(\.name) == [favourites, "Your mix", "Aardvark", "Zebra"])
    #expect(top[0].kind == .favorites(GeneratedLists.marked([track("f")], among: [])!))
}

/// **The computer's copy and the phone's list are one row.** The phone's marks are newer, so its songs win.
/// The copy gives only its id, for its picture.
@Test func theMarkedSongsTakeThePlaceOfTheComputersCopy() {
    let lists = [
        cut("Favourite tracks", kind: "FavoriteTracks", in: ["Listes intelligentes"],
            tracks: [track("old")]),
        cut("On repeat", kind: "OnRepeat", in: ["Listes intelligentes"]),
    ]

    let top = browse([], lists, favorites: [track("new1"), track("new2")]).rows

    #expect(top.map(\.name) == [favourites, "On repeat"])
    #expect(top[0].tracks.map(\.rpmId) == ["new1", "new2"])
    #expect(top[0].set?.id == "\u{1}mood/Favourite tracks", "the computer's id, for its picture")
    #expect(top[0].id == "\u{1}favorites", "the row is the marked songs, whatever the copy is called")
}

/// Nothing marked on this phone is the newer answer, so the computer's older copy is not shown either.
@Test func nothingMarkedHidesTheComputersCopyToo() {
    let lists = [cut("Favourite tracks", kind: "FavoriteTracks", in: ["Smart playlists"])]

    #expect(browse([], lists, favorites: []).rows.isEmpty)
}

/// On a borrowed shelf the marked songs are nil, not empty. The cut is shown as the computer sent it.
@Test func aBorrowedShelfKeepsTheCutAsItWasSent() {
    let lists = [cut("Chill", kind: "Calm", in: ["Moods"])]
    let rows = PlaylistBrowse.of(at: [], playlists: lists, favorites: nil).rows

    #expect(rows.map(\.name) == ["Moods"])
    #expect(!rows.contains { if case .favorites = $0.kind { return true } else { return false } })
}

@Test func theMarkedSongsCarryWhatIsInThem() {
    let marked = [track("a", seconds: 100), track("b", seconds: 200)]
    let row = browse([], [], favorites: marked).rows[0]

    #expect(row.tracks.count == 2)
    #expect(row.duration == .seconds(300))
    #expect(row.artSource?.rpmId == "a")
}

// ── what a folder shows ──

/// The desktop's marks: the moods picture on Moods, a clock on Decades (inside Moods, as on Android), and the
/// mood's own mark on each mood that has cuts under it. A person's folder is plain.
@Test func eachOfTheAppsFoldersHasItsOwnFace() {
    let lists = [
        cut("Chill", kind: "Calm", in: ["Moods", "Chill"]),
        cut("Slow Burn", kind: "Calm", genre: "Rock", in: ["Moods", "Chill"]),
        cut("Sleep", kind: "Sleep", in: ["Moods"]),
        cut("1980s", kind: "Decade", decade: 1980, in: ["Decades"]),
        set("Mine", in: ["Road trips"]),
    ]

    let top = browse([], lists, favorites: nil).rows
    #expect(top.map(\.face) == [.moods, .plain])

    let moods = browse(["Moods"], lists, favorites: nil).rows
    #expect(moods.map(\.name) == ["Decades", "Chill", "Sleep"])
    #expect(moods.map(\.face) == [.decades, .mood("Calm"), nil], "a mood with no cuts is a list, not a folder")
}

/// A person's folder never shows the app's marks, even when it holds a generated list beside their own.
@Test func aFolderHoldingAListSomebodyMadeIsPlain() {
    let lists = [cut("Chill", kind: "Calm", in: ["Moods"]), set("Mine", in: ["Moods"])]

    #expect(browse([], lists, favorites: nil).rows[0].face == .plain)
}

/// The app's folders come first. A person's own folders follow by name, even one whose name sorts before
/// them. The lists come after every folder.
@Test func theAppsFoldersComeFirst() {
    let lists = [
        cut("1980s", kind: "Decade", decade: 1980, in: ["Decades"]),
        cut("Chill", kind: "Calm", in: ["Moods"]),
        set("Mine", in: ["Aardvark"]),
        set("Other", in: ["Zebra"]),
    ]

    let top = browse([], lists, favorites: [track("f")]).rows

    #expect(top.map(\.name) == ["Moods", "Aardvark", "Zebra", favourites])
}

/// A shelf with no moods has nowhere to put the decades, so they stay where the computer filed them.
@Test func withNoMoodsTheDecadesStayWhereTheyWereFiled() {
    let lists = [cut("1980s", kind: "Decade", decade: 1980, in: ["Decades"])]

    let top = browse([], lists, favorites: nil).rows

    #expect(top.map(\.name) == ["Decades"])
    #expect(top[0].face == .decades)
}

// ── the tree ──

/// Folders above playlists, as the desktop's own grid has them and as every file
/// browser does: the places are the frame and the things are what is in it.
@Test func foldersComeAboveThePlaylistsBesideThem() {
    let rows = browse([], [set("Aardvark"), set("Zebra", in: ["Mixes"])],
                      favorites: nil).rows

    #expect(rows.map(\.name) == ["Mixes", "Aardvark"])
    #expect(rows[0].isFolder)
    #expect(!rows[1].isFolder)
}

@Test func bothAreAlphabeticalWhateverOrderTheyArriveIn() {
    let rows = browse([], [set("zoo"), set("Alpha"), set("mid")], favorites: nil).rows

    #expect(rows.map(\.name) == ["Alpha", "mid", "zoo"])
}

/// The count is for the rows behind the tap, not for everything below the folder. A folder that says
/// "45 playlists" but opens on six rows would describe something nobody sees. A folder also never shows zero,
/// because a folder exists only when something is under it.
@Test func aFolderRowCountsTheRowsOpeningItShows() {
    let rows = browse([], [set("a", in: ["Mixes"]),
                           set("b", in: ["Mixes", "Late"]),
                           set("c", in: ["Mixes", "Late", "Deeper"])],
                      favorites: nil).rows

    #expect(rows.map(\.name) == ["Mixes"])
    // "a", and the folder "Late", not the two playlists filed away beneath it.
    #expect(rows[0].playlists == 2)
}

@Test func steppingIntoAFolderShowsWhatIsDirectlyInIt() {
    let made = browse(["Mixes"], [set("a", in: ["Mixes"]),
                                  set("b", in: ["Mixes", "Late"]),
                                  set("c", in: [])])

    #expect(made.at == ["Mixes"])
    #expect(made.rows.map(\.name) == ["Late", "a"])
}

/// A folder has no track order of its own and no cover image.
@Test func aFolderCarriesNoTracks() {
    let folder = browse([], [set("a", in: ["Mixes"], tracks: [track("t")])],
                        favorites: nil).rows[0]

    #expect(folder.isFolder)
    #expect(folder.tracks.isEmpty)
    #expect(folder.artSource == nil)
}

// ── standing somewhere that has gone ──

/// **The most important case.** A folder becomes empty when its last playlist is deleted on a
/// computer. If the path were kept as it was, the user would stay in a folder that no longer
/// exists, looking at a list that will never fill.
@Test func aFolderThatHasEmptiedPutsTheReaderBackWhereItWas() {
    let made = browse(["Mixes", "Late"], [set("a", in: ["Mixes"])])

    #expect(made.at == ["Mixes"])
    #expect(made.rows.map(\.name) == ["a"])
}

@Test func aTreeThatHasGoneEntirelyPutsTheReaderAtTheTop() {
    let made = browse(["Mixes", "Late"], [set("a")])

    #expect(made.at.isEmpty)
    #expect(made.rows.map(\.name) == ["a"])
}

/// The correction is always applied. The caller passes in where it was standing and gets back where
/// it is now.
@Test func whereYouAreComesBackWithWhatIsOnScreen() {
    let made = browse(["MIXES"], [set("a", in: ["Mixes"])])

    #expect(made.at == ["MIXES"], "the reader's own spelling is not overwritten")
    #expect(made.rows.map(\.name) == ["a"])
}

// ── the header reads off the same answer ──

@Test func thereIsNowhereToGoBackToAtTheTopOfTheTree() {
    #expect(browse([], []).back == nil)
    #expect(browse([], []).path.isEmpty)
}

@Test func oneStepInGoesBackToTheTopAndSaysNoPath() {
    let made = browse(["Mixes"], [set("a", in: ["Mixes"])])

    #expect(made.back == [])
    #expect(made.path.isEmpty, "the name alone is the whole answer one step in")
}

/// The path shows where the folder sits. Without it, a folder two levels deep would look like one of several
/// folders with the same name, and the user could not tell which one is open.
@Test func twoStepsInSaysWhereTheFolderSits() {
    let made = browse(["Mixes", "Late"], [set("a", in: ["Mixes", "Late"])])

    #expect(made.path == ["Mixes"])
    #expect(made.back == ["Mixes"])
}

// ── what a stored playlist carries ──

@Test func aPlaylistCarriesItsTracksAndWhatIsMissingFromThem() {
    let row = browse([], [set("Mine", tracks: [track("a"), track("b")], missing: 3)],
                     favorites: nil).rows[0]

    #expect(row.tracks.count == 2)
    #expect(row.missing == 3)
    #expect(row.artSource?.rpmId == "a")
    #expect(row.id == "p-Mine")
}

/// Rows must be told apart by a stable id, because the list is rebuilt at every step into and out
/// of a folder.
@Test func everyRowIsTellableFromEveryOther() {
    let rows = browse([], [set("a"), set("b"), set("c", in: ["Mixes"])]).rows

    #expect(Set(rows.map(\.id)).count == rows.count)
}

// ── the tree a picker walks ──

/// A song cannot be added to the marked songs. A picker that showed them would offer a place that
/// refuses songs.
@Test func aPickerSeesTheTreeAndNotTheMarkedSongs() {
    let made = PlaylistBrowse.places(at: [], playlists: [set("a"), set("b", in: ["Mixes"])])

    #expect(made.rows.map(\.name) == ["Mixes", "a"])
    #expect(!made.rows.contains { if case .favorites = $0.kind { return true } else { return false } })
}

/// Otherwise it is the same walk, so the correction to the current folder still applies.
@Test func aPickerStandingInAFolderThatHasGoneComesBack() {
    let made = PlaylistBrowse.places(at: ["Mixes", "Late"], playlists: [set("a", in: ["Mixes"])])

    #expect(made.at == ["Mixes"])
    #expect(made.rows.map(\.name) == ["a"])
}

// ── a mood is a place, and its own list is the first thing in it ──

/// The row for the whole Chill list must come first. Alphabetical order would put it among its own cuts, just
/// because of its letters.
@Test func aMoodsOwnListIsTheFirstRowInIt() {
    let made = browse(["Moods", "Chill"], [
        set("Chill", in: ["Moods", "Chill"], tracks: [track("a")], origin: .generated),
        set("Adagio", in: ["Moods", "Chill"], tracks: [track("b")], origin: .generated),
        set("Slow Burn", in: ["Moods", "Chill"], tracks: [track("c")], origin: .generated),
    ])

    #expect(made.rows.map(\.name) == ["Chill", "Adagio", "Slow Burn"])
}

/// Only the list whose name matches the name of its place is moved to the top. A playlist that the user named
/// after its folder is not moved.
@Test func aStoredPlaylistNamedAfterItsFolderIsNotMovedToTheTop() {
    let made = browse(["Mixes"], [set("Mixes", in: ["Mixes"]), set("Ambient", in: ["Mixes"])])

    #expect(made.rows.map(\.name) == ["Ambient", "Mixes"])
}

/// The computer makes these lists from the collection and replaces them whole on its next run, so a
/// song added to one would be lost. The folders that hold only these lists are hidden too, because
/// a place with nothing to open would refuse songs.
@Test func aPickerIsNotOfferedAGeneratedListNorTheFolderItSatIn() {
    let made = PlaylistBrowse.places(at: [], playlists: [
        set("a"),
        set("Chill", in: ["Moods"], origin: .generated),
        set("Slow Burn", in: ["Moods", "Chill"], origin: .generated),
    ])

    #expect(made.rows.map(\.name) == ["a"])
}
