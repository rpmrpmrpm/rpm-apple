import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// The generated lists that the computer sends, shown on the playlists tab.
///
/// These tests check that a cut is rendered and never cut again, that the folder tree matches the
/// desktop's, and that nothing here can be written to.
struct GeneratedListsTests {
    private func track(_ id: String) -> CloudTrack {
        CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: id,
                   artist: "Talk Talk", album: "Spirit of Eden", tags: CloudTrackTags())
    }

    private func cut(_ lists: [CloudMoodList], computedAt: Int64 = 1) -> CloudMoodLists {
        CloudMoodLists(recipe: 1, computedAt: computedAt, lists: lists)
    }

    private var moods: String { "Moods" }
    private var decades: String { "Decades" }
    private var chill: String { Loc.get("Playlists_Calm") }

    // ── the slice of a run that is one list ──

    private func ids(_ count: Int) -> [String] { (0..<count).map { "t\($0)" } }

    @Test func aRunNoDeeperThanTheListIsTheList() {
        // A cut from an older computer build has no run length (`shows` is 0), and a shallow pool
        // gives the same. Both give the whole list.
        #expect(GeneratedLists.window(ids(30), shows: 0, reading: 3) == ids(30))
        #expect(GeneratedLists.window(ids(30), shows: 50, reading: 3) == ids(30))
        #expect(GeneratedLists.window(ids(50), shows: 50, reading: 1) == ids(50))
    }

    @Test func eachReadingIsTheNextStretchOfTheRun() {
        let run = ids(200)

        #expect(GeneratedLists.window(run, shows: 50, reading: 0) == Array(run[0..<50]))
        #expect(GeneratedLists.window(run, shows: 50, reading: 1) == Array(run[50..<100]))
        #expect(GeneratedLists.window(run, shows: 50, reading: 3) == Array(run[150..<200]))

        // The reading wraps round, so refreshing many times always gives a list.
        #expect(GeneratedLists.window(run, shows: 50, reading: 4) == Array(run[0..<50]))
    }

    @Test func theLastSliceOfAnUnevenRunIsStillAFullList() {
        // 130 songs in lists of 50: the third slice would have only thirty songs, which looks like
        // a failed list. So it starts earlier and takes the last 50 songs instead.
        let run = ids(130)

        #expect(GeneratedLists.window(run, shows: 50, reading: 2) == Array(run[80..<130]))
        #expect(GeneratedLists.window(run, shows: 50, reading: 3) == Array(run[0..<50]))
    }

    @Test func aReadingFromALongerRunStillLandsInThisOne() {
        // The computer replaces the whole cut, so a reading kept for a run of four lists can meet a
        // run of two. It must still land inside the run, not past its end.
        let run = ids(100)

        #expect(GeneratedLists.window(run, shows: 50, reading: 7).count == 50)
        #expect(GeneratedLists.window(run, shows: 50, reading: -1).count == 50)
    }

    @Test func theRowsAreTheSliceAndNotTheWholeRun() {
        let run = ids(100)
        let tracks = run.map(track)
        let list = CloudMoodList(kind: "Calm", title: "Chill", folder: ["Moods"],
                                 listId: "chill", trackIds: run, shows: 50)

        let first = GeneratedLists.sets(cut([list]), against: tracks, shelf: .own)
        #expect(first.first?.tracks.count == 50)
        #expect(first.first?.tracks.first?.rpmId == "t0")

        let next = GeneratedLists.sets(cut([list]), against: tracks, shelf: .own,
                                       readings: ["chill": 1])
        #expect(next.first?.tracks.first?.rpmId == "t50")

        // Only the songs in this slice that cannot be resolved count as missing, not the rest of
        // the run. A row that said "50 songs, 50 missing" would be wrong for a list that is all
        // here.
        #expect(next.first?.missing == 0)
    }

    // ── what a list is called ──

    /// The name on a cut comes from the computer, which owns the titles. Copying its title table here would
    /// let the two drift apart.
    @Test func theComputersNameIsTheNameOnACut() {
        let list = CloudMoodList(kind: "Calm", genre: "Rock", title: "Slow Burn",
                                 trackIds: ["a"])
        #expect(GeneratedLists.name(list) == "Slow Burn")
    }

    /// A mood name is the exception. The app translates it into five languages, but the name sent by the
    /// computer is in whatever language the computer used.
    // ── Your mix ──

    @Test func yourMixReadsInThePhonesLanguage() {
        let list = CloudMoodList(kind: "RightNow", title: "Ton mix", trackIds: ["a"])
        #expect(GeneratedLists.name(list) == Loc.get("Playlists_RightNow"))
    }

    /// Your mix is cut from the owner's listening. The owner's own shelf shows it. A borrowed shelf does not.
    @Test func yourMixIsShownOnTheOwnShelfAndNotOnABorrowedOne() {
        let sent = cut([CloudMoodList(kind: "RightNow", title: "Your mix",
                                      folder: ["Generated"], trackIds: ["a"]),
                        CloudMoodList(kind: "Calm", title: "Chill", folder: [moods], trackIds: ["a"])])

        let own = GeneratedLists.sets(sent, against: [track("a")], shelf: .own)
        let lent = GeneratedLists.sets(sent, against: [track("a")], shelf: .of("lender"))

        #expect(own.map(\.name).contains(Loc.get("Playlists_RightNow")))
        #expect(!lent.map(\.name).contains(Loc.get("Playlists_RightNow")))
        #expect(lent.map(\.name).contains(chill))
    }

    /// The listening lists are the owner's too, and a borrowed shelf leaves them out.
    @Test func theListeningListsAreShownOnTheOwnShelfAndNotOnABorrowedOne() {
        let sent = cut([CloudMoodList(kind: "OnRepeat", title: "On repeat",
                                      folder: ["Generated"], trackIds: ["a"]),
                        CloudMoodList(kind: "LateNight", title: "Late night",
                                      folder: ["Generated"], trackIds: ["a"]),
                        CloudMoodList(kind: "Calm", title: "Chill", folder: [moods], trackIds: ["a"])])

        let own = GeneratedLists.sets(sent, against: [track("a")], shelf: .own)
        let lent = GeneratedLists.sets(sent, against: [track("a")], shelf: .of("lender"))

        #expect(own.map(\.name).contains("On repeat"))
        #expect(own.map(\.name).contains("Late night"))
        #expect(lent.map(\.name) == [chill])
    }

    @Test func aWholeMoodReadsInThePhonesLanguageAndNotTheComputers() {
        let list = CloudMoodList(kind: "Calm", title: "Détente", trackIds: ["a"])
        #expect(GeneratedLists.name(list) == chill)
    }

    /// The folder a mood opens is named the same as that mood's row. The name is taken from the row, not
    /// worked out again.
    @Test func aMoodsPlaceIsCalledWhatItsOwnRowIsCalled() {
        let moodsFolder = Loc.get("Playlists_MoodsFolder")
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Windswept", title: "Windswept Nights", trackIds: ["a"]),
                 CloudMoodList(kind: "Windswept", genre: "Rock", title: "Gale", trackIds: ["a"])]),
            against: [track("a")], shelf: .own)

        #expect(sets[0].name == "Windswept Nights")
        #expect(sets[0].folder == [moodsFolder, "Windswept Nights"])
        #expect(sets[1].folder == [moodsFolder, "Windswept Nights"])
        #expect(GeneratedLists.isPooled(sets[0]))
    }

    /// A cut sent without names has none. Every fallback name here is the desktop's own name, not
    /// an invention.
    @Test func anUnnamedListFallsBackTheWayTheDesktopDoes() {
        #expect(GeneratedLists.name(CloudMoodList(kind: "Calm", trackIds: ["a"])) == chill)
        #expect(GeneratedLists.name(
            CloudMoodList(kind: "Calm", genre: "Rock", trackIds: ["a"])) == "Rock")
        #expect(GeneratedLists.name(
            CloudMoodList(kind: "Decade", decade: 1970, trackIds: ["a"])) == "1970s")
    }

    /// A mood this build has no name for is shown under the name the computer sent. The list still plays.
    @Test func aMoodThisBuildDoesNotKnowReadsAsWhatItCalledItself() {
        #expect(GeneratedLists.name(CloudMoodList(kind: "Windswept", trackIds: ["a"])) == "Windswept")
        #expect(GeneratedLists.moodName("Windswept") == nil)
    }

    /// A title of nothing but spaces is not a name. It falls through as if none came.
    @Test func aBlankTitleIsNotAName() {
        let list = CloudMoodList(kind: "Calm", title: "   ", trackIds: ["a"])
        #expect(GeneratedLists.name(list) == chill)
    }

    // ── where one sits ──

    /// The arrangement the computer sent, used as sent.
    @Test func aListSitsWhereTheComputerSaidItSits() {
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Calm", folder: ["Moods"], trackIds: ["a"]),
                 CloudMoodList(kind: "Decade", decade: 1970,
                               folder: ["Decades"], trackIds: ["a"])]),
            against: [track("a")], shelf: .own)

        #expect(sets.count == 2)
        #expect(sets[0].folder == ["Moods"])
        #expect(sets[1].folder == ["Decades"])
    }

    /// A step with no name is not a place. A step of only spaces would become a folder with no name.
    @Test func aBlankStepInTheChainIsNotAPlace() {
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Calm", folder: ["  "], trackIds: ["a"])]),
            against: [track("a")], shelf: .own)

        #expect(sets[0].folder == [Loc.get("Playlists_MoodsFolder")])
    }

    /// A cut from a computer that sends no folder layout is placed the way this app files its own lists.
    @Test func aCutWithNoArrangementIsPlacedTheWayThisAppFilesItsOwn() {
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Calm", trackIds: ["a"]),
                 CloudMoodList(kind: "Calm", genre: "Rock", title: "Slow Burn", trackIds: ["a"]),
                 CloudMoodList(kind: "Decade", decade: 1970, trackIds: ["a"])]),
            against: [track("a")], shelf: .own)

        #expect(sets[0].folder == [Loc.get("Playlists_MoodsFolder"), chill])
        #expect(sets[1].folder == [Loc.get("Playlists_MoodsFolder"), chill])
        #expect(sets[2].folder == [Loc.get("Playlists_DecadesFolder")])
    }

    /// A mood that has cuts under it is a place. Its own list is one of the items inside that place, not a
    /// separate row that opens a folder. Each row must lead to exactly one thing.
    @Test func aMoodWithCutsIsAPlaceAndItsOwnListIsInThere() {
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Calm", folder: ["Moods"], trackIds: ["a"]),
                 CloudMoodList(kind: "Calm", genre: "Rock", title: "Slow Burn",
                               folder: ["Moods", chill], trackIds: ["a"])]),
            against: [track("a")], shelf: .own)

        // The computer put the mood in Moods and its cut under the mood's own row. The row that
        // cannot be in both places moves down into the place with the same name.
        #expect(sets[0].folder == ["Moods", chill])
        #expect(sets[0].name == chill)
        #expect(sets[1].folder == ["Moods", chill])
        #expect(sets[1].name == "Slow Burn")

        // And it is the row that opens that place, so it is drawn first inside it.
        #expect(GeneratedLists.isPooled(sets[0]))
        #expect(!GeneratedLists.isPooled(sets[1]))
    }

    /// A mood with no place of the same name stays where it was put. A mood with no cuts is a plain
    /// row, and it must not become a folder with one item in it.
    @Test func aMoodWithNoPlaceNamedAfterItStaysWhereItWasPut() {
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Sleep", folder: ["Moods"], trackIds: ["a"])]),
            against: [track("a")], shelf: .own)

        #expect(sets[0].folder == ["Moods"])
    }

    /// A mood with no cuts below it is a plain row. Its name must not become a folder with nothing in it.
    @Test func aMoodWithNoGenresBelowItIsNotAFolder() {
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Sleep", trackIds: ["a"])]),
            against: [track("a")], shelf: .own)

        #expect(sets.count == 1)
        #expect(sets[0].folder == [Loc.get("Playlists_MoodsFolder")])
    }

    // ── what one holds ──

    /// The whole list is kept, and the missing count is based on what this phone can see, the same way as a
    /// stored playlist. On a borrowed shelf only the songs the owner put in the cloud can be resolved. A list
    /// trimmed to those songs would depend on one account's view of the library.
    @Test func recordsThisPhoneCannotSeeAreCountedAndNotDropped() {
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Calm", trackIds: ["a", "gone", "b"])]),
            against: [track("a"), track("b")], shelf: .own)

        #expect(sets[0].tracks.map(\.rpmId) == ["a", "b"])
        #expect(sets[0].missing == 1)
    }

    /// In the cut's order, not alphabetical order. The computer sorts the songs best first, and that order is
    /// part of the list.
    @Test func theRecordsKeepTheOrderTheyWereCutIn() {
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Calm", trackIds: ["c", "a", "b"])]),
            against: [track("a"), track("b"), track("c")], shelf: .own)

        #expect(sets[0].tracks.map(\.rpmId) == ["c", "a", "b"])
    }

    /// A list with no songs is not shown. The computer does not send one, and one that arrives is not drawn.
    @Test func anEmptyListIsNotARow() {
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Calm", trackIds: [])]),
            against: [track("a")], shelf: .own)

        #expect(sets.isEmpty)
    }

    /// A computer that has not made any cuts yet sends an empty cut. That is a normal answer, not a failure.
    @Test func anEmptyCutIsNoRowsAtAll() {
        #expect(GeneratedLists.sets(cut([]), against: [track("a")], shelf: .own).isEmpty)
    }

    // ── read only ──

    /// The id does not refer to anything in the store. A write would not change a list. It would create a
    /// playlist from a cut that the computer replaces on its next run.
    @Test func everyGeneratedListIsMarkedAsOneAndIsNotWritable() {
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Calm", trackIds: ["a"])]),
            against: [track("a")], shelf: .own)

        #expect(sets[0].origin == .generated)
        #expect(sets[0].isWritable == false)
    }

    /// A borrowed shelf carries the lists its owner cut, and they are read the same way. The store checks the
    /// access grant, not this app.
    @Test func aBorrowedShelfGetsTheOwnersLists() {
        let shelf = CloudShelf.of("someone-else")
        let sets = GeneratedLists.sets(
            cut([CloudMoodList(kind: "Calm", trackIds: ["a"])]),
            against: [track("a")], shelf: shelf)

        #expect(sets[0].shelf == shelf)
        #expect(sets[0].isWritable == false)
    }

    /// Two cuts of the same shelf give the same ids, so a row keeps its identity between launches. No cloud
    /// playlist id can match one of these ids.
    @Test func theIdsAreStableAndCannotCollideWithAStoredPlaylist() {
        let made = { GeneratedLists.sets(
            self.cut([CloudMoodList(kind: "Calm", genre: "Rock",
                                    listId: "0f5c2b1e-4a3d-4c5b-9e7a-1d2c3b4a5f60",
                                    trackIds: ["a"])]),
            against: [self.track("a")], shelf: .own)[0].id }

        #expect(made() == made())

        // The prefix is a character that no cloud id contains. This makes the two sets of ids
        // disjoint, not just unlikely to meet.
        #expect(made().hasPrefix("\u{1}"))
        #expect(!UUID().uuidString.lowercased().hasPrefix("\u{1}"))
    }

    // ── the whole shelf, shaped as the computer offers it ──

    /// A cut shaped like the real one.
    ///
    /// `LibraryDatabase.OfferedGeneratedLists` offers, for each mood, the whole-shelf list and then
    /// one list per genre worth listing. Only the four moods in `SmartPlaylists.BrokenOutByGenre`
    /// are split by genre. The six decades come after them. Sleep and Classical are never split by
    /// genre. The titles are the desktop's own, from `SmartPlaylistFace.Titles`.
    private func wholeCut() -> CloudMoodLists {
        var lists: [CloudMoodList] = []

        // The folders match what `SmartPlaylistFace.FolderChain` sends: a mood sits in Moods, its
        // cuts sit under the mood's own row, and the decades sit in Decades.
        func mood(_ kind: String, _ name: String, _ cuts: [(String, String)]) {
            lists.append(CloudMoodList(kind: kind, folder: ["Moods"], trackIds: ["a"]))
            for (genre, title) in cuts {
                lists.append(CloudMoodList(kind: kind, genre: genre, title: title,
                                           folder: ["Moods", name], trackIds: ["a"]))
            }
        }

        mood("Energetic", Loc.get("Playlists_Energetic"),
             [("Rock", "Amplified"), ("Metal", "Wall of Sound"),
              ("Punk", "Fast and Loud"), ("Rap", "Rap Core")])
        mood("Calm", chill, [("Rock", "Slow Burn"), ("Jazz", "Jazz Club")])
        mood("Danceable", Loc.get("Playlists_Danceable"),
             [("Disco", "Disco Fever"), ("House", "Warehouse")])
        mood("Focus", Loc.get("Playlists_Focus"),
             [("Jazz", "The Lounge"), ("Classical", "Andante")])
        mood("Sleep", Loc.get("Playlists_Sleep"), [])
        mood("Classical", Loc.get("Playlists_Classical"), [])

        for decade in [1960, 1970, 1980, 1990, 2000, 2010] {
            lists.append(CloudMoodList(kind: "Decade", decade: decade,
                                       folder: ["Decades"], trackIds: ["a"]))
        }

        return cut(lists)
    }

    private func rows(_ at: [String]) -> [PlaylistRow] {
        PlaylistBrowse.of(
            at: at,
            playlists: GeneratedLists.sets(wholeCut(), against: [track("a")], shelf: .own),
            queue: [], favorites: nil).rows
    }

    /// Two folders at the top. Each shows how many rows are inside it.
    @Test func theShelfPutsTwoFoldersAtTheTop() {
        // The queue is always the first row at the top of the tree.
        let top = Array(rows([]).dropFirst())

        #expect(top.map(\.name) == [decades, moods])
        #expect(top.allSatisfy { $0.isFolder })
        #expect(top[0].playlists == 6)

        // Six rows: four moods that are places, and two that are plain lists. The count is not the
        // twenty lists under them, which the user does not see at this level.
        #expect(top[1].playlists == 6)
    }

    /// A mood with cuts under it is a place. A mood without cuts is a list. Places are listed above lists, as
    /// this tab shows at every level.
    @Test func theMoodsFolderHoldsThePlacesAndThePlainMoods() {
        let inside = rows([moods])

        #expect(inside.map(\.name) == [
            Loc.get("Playlists_Energetic"), chill,
            Loc.get("Playlists_Danceable"), Loc.get("Playlists_Focus"),
            Loc.get("Playlists_Classical"), Loc.get("Playlists_Sleep"),
        ])
        #expect(inside.prefix(4).allSatisfy { $0.isFolder })
        #expect(inside.suffix(2).allSatisfy { !$0.isFolder })

        // Its own list, and the four cuts of it.
        #expect(inside[0].playlists == 5)
    }

    /// **The Adrenaline place holds playlists.** Its own list comes first, as the whole list is what someone
    /// opening the place wants. The cuts follow.
    @Test func adrenalineIsAPlaceHoldingItsOwnListAndTheCutsOfIt() {
        let inside = rows([moods, Loc.get("Playlists_Energetic")])

        #expect(inside.map(\.name) == [
            Loc.get("Playlists_Energetic"),
            "Amplified", "Fast and Loud", "Rap Core", "Wall of Sound",
        ])
        #expect(inside.allSatisfy { !$0.isFolder })
        #expect(inside.allSatisfy { $0.tracks.count == 1 })
    }

    /// A mood that is never split by genre is a plain list, not a place holding one item.
    @Test func aMoodWithNoCutsIsNotAPlace() {
        let inside = rows([moods])
        let classical = try! #require(inside.first { $0.name == Loc.get("Playlists_Classical") })

        #expect(!classical.isFolder)
        #expect(classical.tracks.count == 1)
    }

    @Test func theDecadesStandBesideTheMoodsAndNotUnderThem() {
        let inside = rows([decades])

        #expect(inside.map(\.name) == ["1960s", "1970s", "1980s", "1990s", "2000s", "2010s"])
        #expect(inside.allSatisfy { !$0.isFolder })
    }
}
