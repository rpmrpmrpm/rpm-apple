import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// The banner at the top of the home screen: a few cards, one shown at a time.
///
/// Mirrors `RPM.Core.Tests/HomeFeaturesTests.cs`. These rules must hold: each question gives one
/// card before any question gives a second. A record is featured only once. The strip fills from
/// whatever the collection can answer.
struct HomeFeaturesTests {
    private let continued = ["was-on"]
    private let added = ["new1", "new2", "new3"]
    private let lists = ["Chill", "Adrenaline"]
    private let suggested = ["like1", "like2"]
    private let played = ["most1", "most2"]
    private let listened = ["heard1", "heard2"]
    private let stations = ["station-uuid"]
    private let noneVarious: (String) -> Bool = { _ in false }

    @Test func everyQuestionGetsACardBeforeAnyGetsASecond() {
        let strip = HomeFeatures.strip(
            continued: continued, added: added, lists: lists, suggested: suggested,
            played: played, listened: listened, stations: stations, isVariousArtists: noneVarious, count: HomeFeatures.count)

        #expect(Set(strip.map(\.kind)).count == HomeFeatures.count)
    }

    /// The record that was on last is dealt first, so the Continue card gets it, not whichever
    /// question is asked first.
    @Test func theRecordThatWasOnLastIsDealtFirst() {
        let strip = HomeFeatures.strip(
            continued: ["was-on"], added: ["was-on"], lists: [], suggested: [],
            played: ["was-on"], listened: ["was-on"], stations: [], isVariousArtists: noneVarious, count: 4)

        #expect(strip.first?.kind == .continue)
        #expect(strip.first?.key == "was-on")
        #expect(strip.filter { $0.key == "was-on" }.count == 1)
    }

    /// The most played record is often also a recent listen. The same cover twice in one strip looks like a
    /// stuck banner.
    @Test func aRecordIsFeaturedOnce() {
        let strip = HomeFeatures.strip(
            continued: [], added: [], lists: [], suggested: ["shared"],
            played: ["shared", "other"], listened: ["shared"], stations: [], isVariousArtists: noneVarious,
            count: HomeFeatures.count)

        #expect(strip.filter { $0.key == "shared" }.count == 1)
        #expect(strip.contains { $0.key == "other" })
    }

    /// A list and a record can have the same name without removing each other. They are in separate
    /// namespaces.
    @Test func aListAndARecordWithOneNameAreTwoCards() {
        let strip = HomeFeatures.strip(
            continued: [], added: ["Chill"], lists: ["Chill"], suggested: [],
            played: [], listened: [], stations: [], isVariousArtists: noneVarious, count: 4)

        #expect(strip.count == 2)
        #expect(Set(strip.map(\.kind)) == [.added, .madeForYou])
    }

    /// A new collection has played nothing, so most questions have no answer. The strip is then
    /// filled with the newest records, with no gaps.
    @Test func aCollectionThatHasPlayedNothingFillsFromWhatArrivedLast() {
        let strip = HomeFeatures.strip(
            continued: [], added: added, lists: [], suggested: [],
            played: [], listened: [], stations: [], isVariousArtists: noneVarious, count: HomeFeatures.count)

        #expect(strip.count == added.count)
        #expect(strip.allSatisfy { $0.kind == .added })
    }

    /// A card shows the act's photo, and a Various Artists record has no single act. So each
    /// question skips it and gives its next answer.
    @Test func aVariousArtistsRecordIsNeverFeatured() {
        let strip = HomeFeatures.strip(
            continued: [], added: ["va1", "new1"], lists: [], suggested: ["va2", "like1"],
            played: ["va1"], listened: ["va2", "heard1"], stations: [],
            isVariousArtists: { $0.hasPrefix("va") }, count: HomeFeatures.count)

        #expect(strip == [
            HomeFeature(kind: .added, key: "new1"),
            HomeFeature(kind: .suggested, key: "like1"),
            HomeFeature(kind: .listened, key: "heard1"),
        ])
    }

    /// The Continue card names the record that was on last. If that record is a compilation, there
    /// is no Continue card, and the next recent listen does not move up to take its place.
    @Test func aVariousArtistsRecordThatWasOnLastHasNoContinueCard() {
        let strip = HomeFeatures.strip(
            continued: ["va1"], added: [], lists: [], suggested: [], played: [],
            listened: ["va1", "heard1"], stations: [],
            isVariousArtists: { $0.hasPrefix("va") }, count: HomeFeatures.count)

        #expect(strip == [HomeFeature(kind: .listened, key: "heard1")])
    }

    /// An empty shelf gives an empty strip.
    @Test func anEmptyShelfIsAnEmptyStrip() {
        let strip = HomeFeatures.strip(
            continued: [], added: [], lists: [], suggested: [],
            played: [], listened: [], stations: [], isVariousArtists: noneVarious, count: HomeFeatures.count)

        #expect(strip.isEmpty)
    }

    @Test func theStripIsNoLongerThanItIsAskedFor() {
        let strip = HomeFeatures.strip(
            continued: continued, added: added, lists: lists, suggested: suggested,
            played: played, listened: listened, stations: stations, isVariousArtists: noneVarious, count: 3)

        #expect(strip.count == 3)
        #expect(HomeFeatures.strip(continued: continued, added: added, lists: lists,
                                   suggested: suggested, played: played, listened: listened,
                                   stations: stations, isVariousArtists: noneVarious, count: 0).isEmpty)
    }

    /// The station is dealt last. A collection that can answer every other question keeps its
    /// records and gains a seventh card, without losing one.
    @Test func theStationTakesNothingFromACollectionThatCanAnswerEverything() {
        let withStation = HomeFeatures.strip(
            continued: continued, added: added, lists: lists, suggested: suggested,
            played: played, listened: listened, stations: stations, isVariousArtists: noneVarious, count: HomeFeatures.count)
        let without = HomeFeatures.strip(
            continued: continued, added: added, lists: lists, suggested: suggested,
            played: played, listened: listened, stations: [], isVariousArtists: noneVarious, count: HomeFeatures.count)

        #expect(withStation.filter { $0.kind != .radio }.map(\.key) ==
                without.prefix(HomeFeatures.count - 1).map(\.key))
    }
}

/// The gate that the home screen checks before it shows its features.
struct FeatureGateTests {
    @Test func aGateOpensOnceThereIsEnough() {
        #expect(FeatureGate(have: 20, want: 20).open)
        #expect(FeatureGate(have: 19, want: 20).open == false)
    }

    /// The message reads "12 albums to go". A gate that is already open has nothing left to go, so
    /// the count is never negative.
    @Test func thereIsNeverANegativeAmountToGo() {
        #expect(FeatureGate(have: 30, want: 20).toGo == 0)
        #expect(FeatureGate(have: 8, want: 20).toGo == 12)
    }

    /// The value is limited to 0 to 1 at both ends. A gate that wants nothing counts as finished,
    /// which avoids dividing by zero. A value past the threshold does not make the bar overflow.
    @Test func theBarNeitherDividesByNoughtNorOverflows() {
        #expect(FeatureGate(have: 5, want: 0).fraction == 1)
        #expect(FeatureGate(have: 30, want: 20).fraction == 1)
        #expect(FeatureGate(have: 10, want: 20).fraction == 0.5)
    }
}
