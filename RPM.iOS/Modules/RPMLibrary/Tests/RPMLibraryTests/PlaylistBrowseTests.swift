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

private func browse(_ at: [String] = [], _ playlists: [PlaylistSet],
                    queue: [CloudTrack] = [], favorites: [CloudTrack]? = []) -> PlaylistBrowse {
    PlaylistBrowse.of(at: at, playlists: playlists, queue: queue, favorites: favorites)
}

// ── the two lists nobody made ──

/// The queue is always a row at the top, even when it is empty. It is where the music is, and a row that
/// appears and disappears is one that the user cannot learn to find.
@Test func theQueueIsARowWhenThereIsNothingInIt() {
    let rows = browse([], []).rows

    #expect(rows.count == 2)
    #expect(rows[0].kind == .queue)
    #expect(rows[1].kind == .favorites)
}

/// These lists are not filed in any folder. Showing them inside a folder would say that they are.
@Test func neitherOfThemIsDrawnInsideAFolder() {
    let rows = browse(["Mixes"], [set("Late", in: ["Mixes"])],
                      queue: [track("q")], favorites: [track("f")]).rows

    #expect(rows.count == 1)
    #expect(rows[0].name == "Late")
}

/// On a borrowed shelf the marked songs are nil, not empty. A borrowed row cannot be marked from a phone, so
/// the list would always be empty. A row that is always empty is worse than no row.
@Test func aBorrowedShelfHasNoMarkedSongsRow() {
    let rows = PlaylistBrowse.of(at: [], playlists: [], queue: [], favorites: nil).rows

    #expect(rows.map(\.kind) == [.queue])
}

@Test func theQueueCarriesWhatIsInIt() {
    let queue = [track("a", seconds: 100), track("b", seconds: 200)]
    let row = browse([], [], queue: queue).rows[0]

    #expect(row.tracks.count == 2)
    #expect(row.duration == .seconds(300))
    #expect(row.artSource?.rpmId == "a")
}

// ── the tree ──

/// Folders above playlists, as the desktop's own grid has them and as every file
/// browser does: the places are the frame and the things are what is in it.
@Test func foldersComeAboveThePlaylistsBesideThem() {
    let rows = browse([], [set("Aardvark"), set("Zebra", in: ["Mixes"])],
                      favorites: nil).rows

    #expect(rows.map(\.name) == ["", "Mixes", "Aardvark"])
    #expect(rows[1].isFolder)
    #expect(!rows[2].isFolder)
}

@Test func bothAreAlphabeticalWhateverOrderTheyArriveIn() {
    let rows = browse([], [set("zoo"), set("Alpha"), set("mid")], favorites: nil).rows

    #expect(rows.dropFirst().map(\.name) == ["Alpha", "mid", "zoo"])
}

/// The count is for the rows behind the tap, not for everything below the folder. A folder that says
/// "45 playlists" but opens on six rows would describe something nobody sees. A folder also never shows zero,
/// because a folder exists only when something is under it.
@Test func aFolderRowCountsTheRowsOpeningItShows() {
    let rows = browse([], [set("a", in: ["Mixes"]),
                           set("b", in: ["Mixes", "Late"]),
                           set("c", in: ["Mixes", "Late", "Deeper"])],
                      favorites: nil).rows

    #expect(rows.dropFirst().map(\.name) == ["Mixes"])
    // "a", and the folder "Late", not the two playlists filed away beneath it.
    #expect(rows[1].playlists == 2)
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
                        favorites: nil).rows[1]

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
    let made = browse(["Mixes", "Late"], [], queue: [track("q")])

    #expect(made.at.isEmpty)
    #expect(made.rows.map(\.kind) == [.queue, .favorites])
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
                     favorites: nil).rows[1]

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

/// A song cannot be added to the queue or to the marked songs. A picker that showed them would
/// offer two places that refuse songs.
@Test func aPickerSeesTheTreeAndNeitherOfTheGeneratedLists() {
    let made = PlaylistBrowse.places(at: [], playlists: [set("a"), set("b", in: ["Mixes"])])

    #expect(made.rows.map(\.name) == ["Mixes", "a"])
    #expect(!made.rows.contains { $0.kind == .queue })
    #expect(!made.rows.contains { $0.kind == .favorites })
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
