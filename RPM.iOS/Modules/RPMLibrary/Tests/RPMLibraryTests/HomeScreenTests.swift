import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// The home screen as a whole: which rows it has, what is in them, and what the banner shows.
///
/// The rows are read from top to bottom on one screen. So the tests check what the rows do not
/// repeat, as well as what they hold.
struct HomeScreenTests {
    private func album(_ key: String, artist: String = "Somebody", genre: String = "Rock",
                       added: Int64 = 0, plays: Int = 0, lastPlayed: Int64 = 0) -> HomeAlbum {
        HomeAlbum(key: key, album: key, artist: artist, genres: [genre], year: 1980,
                  addedAt: added, plays: plays, lastPlayedAt: lastPlayed)
    }

    private func shelf(_ count: Int, played: Int = 0) -> [HomeAlbum] {
        (0..<count).map {
            album("a\($0)", artist: "Act \($0 % 9)", genre: ["Rock", "Jazz", "Folk"][$0 % 3],
                  added: Int64($0),
                  plays: $0 < played ? played - $0 : 0,
                  lastPlayed: $0 < played ? Int64(played - $0) : 0)
        }
    }

    @Test func aCollectionTooSmallKeepsTheScreenShut() {
        let screen = HomeScreen.build(shelf: shelf(19), songs: [], lists: [], stations: [], draw: 1)

        #expect(screen.gate.open == false)
        #expect(screen.gate.toGo == 1)
    }

    @Test func aCollectionBigEnoughOpensIt() {
        #expect(HomeScreen.build(shelf: shelf(20), songs: [], lists: [], stations: [], draw: 1).gate.open)
    }

    /// A listener who has played nothing gets no row that needs a play history. Empty rows would
    /// only tell the user what they would see after using the app.
    @Test func aCollectionNobodyHasPlayedHasNoListeningRows() {
        let screen = HomeScreen.build(shelf: shelf(30), songs: [], lists: [], stations: [], draw: 1)

        #expect(screen.rows.map(\.kind).contains(.listened) == false)
        #expect(screen.rows.map(\.kind).contains(.played) == false)
        #expect(screen.rows.map(\.kind).contains(.taste) == false)
    }

    /// Suggestions still appear, based on the records that arrived last. A collection lent from
    /// another computer has records but no listening, and so does a new library on its first
    /// evening. The newest records are a weaker answer than a week of listening, but a much better
    /// one than a screen with a single row on a shelf of thousands.
    @Test func aShelfWithNoListeningIsSuggestedFromWhatArrivedLast() {
        let screen = HomeScreen.build(shelf: shelf(30), songs: [], lists: [], stations: [], draw: 1)

        #expect(screen.rows.map(\.kind) == [.suggested, .added])
        #expect(screen.row(.suggested).isEmpty == false)
    }

    @Test func aCollectionThatHasBeenPlayedHasTheListeningRows() {
        let screen = HomeScreen.build(shelf: shelf(30, played: 10), songs: [], lists: [], stations: [], draw: 1)

        #expect(screen.rows.map(\.kind).contains(.listened))
        #expect(screen.rows.map(\.kind).contains(.played))
        #expect(screen.rows.map(\.kind).contains(.added))
    }

    /// The suggestions row sits directly under the recently listened row. A card repeated in both
    /// would make the screen answer its own question.
    @Test func theSuggestionsRepeatNothingFromTheRowAboveThem() {
        let screen = HomeScreen.build(shelf: shelf(40, played: 10), songs: [], lists: [], stations: [], draw: 1)

        let listened = Set(screen.row(.listened))
        let suggested = Set(screen.row(.suggested))

        #expect(suggested.isEmpty == false)
        #expect(suggested.isDisjoint(with: listened))
    }

    /// The banner is built from the rows, so its first card is the record that was on last.
    @Test func theBannerHoldsUpTheRecordThatWasOnLast() {
        let screen = HomeScreen.build(shelf: shelf(40, played: 10), songs: [], lists: [], stations: [], draw: 1)

        #expect(screen.strip.first?.kind == .continue)
        #expect(screen.strip.first?.key == screen.row(.listened).first)
    }

    /// A compilation is filed under Various Artists and has no act to photograph, so the banner
    /// never features it. The rows below still show it, using its cover, not a photo.
    @Test func theBannerLeavesOutVariousArtistsRecords() {
        let various = shelf(40, played: 10).map {
            album($0.key, artist: "Various Artists", added: $0.addedAt, plays: $0.plays,
                  lastPlayed: $0.lastPlayedAt)
        }
        let screen = HomeScreen.build(shelf: various, songs: [], lists: [], stations: [], draw: 1)

        #expect(screen.strip.isEmpty)
        #expect(screen.row(.listened).isEmpty == false)
    }

    /// The same draw gives the same screen. The draw is fixed once per launch. A banner that
    /// rearranged itself while the user was looking at it would be worse than one that never moves.
    @Test func theSameDrawGivesTheSameScreen() {
        let shelf = shelf(40, played: 10)

        let once = HomeScreen.build(shelf: shelf, songs: [], lists: [], stations: [], draw: 7)
        let again = HomeScreen.build(shelf: shelf, songs: [], lists: [], stations: [], draw: 7)

        #expect(once.strip == again.strip)
        #expect(once.rows.map(\.keys) == again.rows.map(\.keys))
    }

    /// Most played is a ranking and keeps its own order, whatever the draw does to the banner.
    @Test func aRankedRowKeepsItsOwnOrder() {
        let shelf = shelf(40, played: 10)

        let row = HomeScreen.build(shelf: shelf, songs: [], lists: [], stations: [], draw: 3).row(.played)

        #expect(row == HomeShelf.played(shelf, count: HomeShelf.rowLength))
    }

    /// The generated lists come from the computer and are shown in the order received. The phone
    /// cannot re-cut them, so their order is the order it was sent.
    @Test func theListsAreOfferedInTheOrderTheyArrived() {
        let screen = HomeScreen.build(shelf: shelf(30, played: 5), songs: [],
                                      lists: ["Chill", "Adrenaline"], stations: [], draw: 1)

        #expect(screen.lists == ["Chill", "Adrenaline"])
        #expect(screen.strip.contains { $0.kind == .madeForYou && $0.key == "Chill" })
    }

    /// The quick selection takes one item of each kind in turn. It does not rank the kinds against
    /// each other, because a record's play count and a list's start count are different measures.
    @Test func theQuickSelectionMixesItsKinds() {
        let screen = HomeScreen.build(shelf: shelf(30, played: 10), songs: [],
                                      lists: ["Chill"], stations: [], draw: 1)

        #expect(screen.quickPicks.isEmpty == false)
        #expect(screen.quickPicks.first?.kind == .album)
        #expect(screen.quickPicks.contains { $0.kind == .playlist })
    }

    /// A station heard on any of the listener's devices is added to the quick selection after a
    /// song, a record and a list. The banner can show it too. Stations reach the phone's home
    /// screen through the synced play log.
    @Test func aStationHeardIsInTheQuickSelectionAndOnTheBanner() {
        let screen = HomeScreen.build(shelf: shelf(30, played: 10), songs: ["t1"],
                                      lists: ["Chill"], stations: ["radio-1"], draw: 1)

        #expect(screen.quickPicks.prefix(4).map(\.kind) == [.song, .album, .playlist, .station])
        #expect(screen.quickPicks.contains(QuickPick(kind: .station, key: "radio-1")))
        #expect(screen.strip.contains { $0.kind == .radio && $0.key == "radio-1" })
    }

    @Test func theQuickSelectionIsNoLongerThanTheScreenShows() {
        let screen = HomeScreen.build(shelf: shelf(60, played: 40), songs: [],
                                      lists: ["Chill", "Adrenaline"], stations: [], draw: 1)

        #expect(screen.quickPicks.count <= QuickPicks.count)
    }
}

extension HomeScreenTests {
    /// The quick selection starts with a song, as the desktop's does. It takes the four kinds in
    /// turn, one from each. A song's play count and a record's play count are different measures.
    @Test func theQuickSelectionDealsASongBeforeARecord() {
        let screen = HomeScreen.build(shelf: shelf(30, played: 10), songs: ["t1", "t2"],
                                      lists: ["Chill"], stations: [], draw: 1)

        #expect(screen.quickPicks.first == QuickPick(kind: .song, key: "t1"))
        #expect(screen.quickPicks.prefix(3).map(\.kind) == [.song, .album, .playlist])
    }

    /// A kind with nothing to offer is skipped, so there is no gap. This is most kinds on a
    /// collection that nobody has played yet.
    @Test func aCollectionThatCanOnlyAnswerWithSongsGetsSongs() {
        let screen = HomeScreen.build(shelf: shelf(30), songs: ["t1", "t2", "t3"],
                                      lists: [], stations: [], draw: 1)

        #expect(screen.quickPicks.map(\.key) == ["t1", "t2", "t3"])
    }
}

/// The quick selection split into panels, as the desktop's `QuickPicksTests` checks it.
struct QuickPicksPanelsTests {
    private func songs(_ count: Int) -> [QuickPick] {
        (1...count).map { QuickPick(kind: .song, key: "s\($0)") }
    }

    /// Items fill each panel from top to bottom, then move to the next panel. The first four go
    /// down the first panel.
    @Test func thePanelsAreFilledDownBeforeAcross() {
        let panels = QuickPicks.inPanels(songs(16), tall: QuickPicks.tall)

        #expect(panels.count == QuickPicks.count / QuickPicks.tall)
        #expect(panels[0].map(\.key) == ["s1", "s2", "s3", "s4"])
        #expect(panels[1].map(\.key) == ["s5", "s6", "s7", "s8"])
        #expect(panels[3].map(\.key) == ["s13", "s14", "s15", "s16"])
    }

    /// A short selection gives fewer panels, not padded ones.
    @Test func aShortSelectionGivesFewerPanels() {
        let panels = QuickPicks.inPanels(songs(6), tall: QuickPicks.tall)

        #expect(panels.map(\.count) == [4, 2])
    }

    @Test func nothingMakesNoPanels() {
        #expect(QuickPicks.inPanels([], tall: QuickPicks.tall).isEmpty)
        #expect(QuickPicks.inPanels(songs(1), tall: 0).isEmpty)
    }
}
