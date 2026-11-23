import Foundation
import Testing
@testable import RPMRadio

/// The same rules are tested in the Android app's `RadioHomePicksTest.kt`. Change both files
/// together.

private func station(_ uuid: String, tags: [String] = [], folded: [String] = []) -> RadioStation {
    var made = RadioStation(uuid: uuid, name: uuid.uppercased(),
                            streamUrl: "https://\(uuid).example/stream")
    made.tags = tags
    made.alsoFiledAs = folded
    return made
}

private func uuids(_ picks: [StationPick]) -> [String] { picks.map(\.station.uuid) }

@Test func theBannerTakesHeardAndLocalStationsInTurnHeardFirst() {
    let heard = [station("h1"), station("h2"), station("h3"), station("h4")]
    let local = [station("l1"), station("l2"), station("l3"), station("l4")]
    let banner = RadioHomePicks.banner(heard: heard, local: local)
    #expect(uuids(banner) == ["h1", "l1", "h2", "l2", "h3", "l3"])
    #expect(banner[0].why == .heard)
    #expect(banner[1].why == .local)
}

@Test func theBannerFillsFromOneListWhenTheOtherRunsOutAndListsAStationOnce() {
    let banner = RadioHomePicks.banner(heard: [station("a")],
                                       local: [station("A"), station("b"), station("c")])
    #expect(uuids(banner) == ["a", "b", "c"])
    #expect(banner[0].why == .heard)
}

@Test func aFoldedEntryCountsAsTheStationItIsFoldedInto() {
    let quick = RadioHomePicks.quick(pinned: [station("main", folded: ["other"])],
                                     saved: [station("other"), station("saved")],
                                     suggested: [])
    #expect(uuids(quick) == ["main", "saved"])
}

@Test func theQuickSelectionPutsPinnedThenSavedThenSuggestedAtMostSixteen() {
    let pinned = [station("p1"), station("p2")]
    let saved = [station("s1"), station("p1")]
    let suggested = (1...20).map { station("f\($0)") }
    let quick = RadioHomePicks.quick(pinned: pinned, saved: saved, suggested: suggested)
    #expect(quick.count == 16)
    #expect(uuids(Array(quick.prefix(4))) == ["p1", "p2", "s1", "f1"])
    #expect(quick.prefix(4).map(\.why) == [.pinned, .pinned, .saved, .forYou])
}

@Test func tasteCountsGenresAndTheFirstStationsBreakATie() {
    let stations = [
        station("a", tags: ["jazz"]),
        station("b", tags: ["rock"]),
        station("c", tags: ["rock", "classic rock"]),
        station("d", tags: ["jazz"]),
        station("e", tags: ["pop"]),
    ]
    #expect(RadioHomePicks.taste(stations) == ["Jazz", "Rock"])
}

@Test func suggestionsTakeOneFromEachGenreInTurnAndSkipKnownStations() {
    let jazz = [station("known"), station("j1"), station("j2")]
    let rock = [station("r1"), station("r2"), station("j1")]
    let suggested = RadioHomePicks.suggested([jazz, rock], known: [station("known")], most: 4)
    #expect(suggested.map(\.uuid) == ["r1", "j1", "r2", "j2"])
}

@Test func withoutLeavesOutTheGivenStationsAndTheirFoldedEntries() {
    let left = RadioHomePicks.without([station("a"), station("b"), station("c"), station("b")],
                                      [station("x", folded: ["A"])])
    #expect(left.map(\.uuid) == ["b", "c"])
}

@Test func theQuickSelectionIsCutIntoPanelsOfFourReadDown() {
    let picks = (1...6).map { StationPick(station: station("s\($0)"), why: .saved) }
    let panels = RadioHomePicks.inPanels(picks)
    #expect(panels.map { $0.map(\.station.uuid) } == [["s1", "s2", "s3", "s4"], ["s5", "s6"]])
    #expect(RadioHomePicks.inPanels([]).isEmpty)
}
