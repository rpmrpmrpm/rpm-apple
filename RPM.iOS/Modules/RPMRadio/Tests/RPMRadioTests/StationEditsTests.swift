import Testing
import RPMKit
@testable import RPMRadio

/// The admin's edits to how a station is shown, as the rpm API's rules carry them. The Android
/// `StationEditsTest` and the desktop's `StationEditsTests`, case for case.
struct StationEditsTests {
    private func station(_ uuid: String, _ name: String, tags: [String] = [], country: String = "NL",
                         clicks: Int = 0) -> RadioStation {
        var made = RadioStation(uuid: uuid, name: name, streamUrl: "https://\(uuid).example/stream")
        made.tags = tags
        made.countryCode = country
        made.clickCount = clicks
        return made
    }

    private func rules(_ edits: [String: StationEdit]) -> StationRules {
        StationRules(hidden: [], edits: edits)
    }

    @Test func aFoldedStationFindsTheEditOfAnyOfItsEntriesItsOwnFirst() {
        var folded = station("a", "NPO Radio 2")
        folded.alsoFiledAs = ["b"]
        let fromB = StationEdit(name: "From b", tags: nil, description: nil)
        let fromA = StationEdit(name: "From a", tags: nil, description: nil)
        #expect(rules(["b": fromB]).edit(of: folded)?.name == "From b")
        #expect(rules(["b": fromB, "a": fromA]).edit(of: folded)?.name == "From a")
    }

    @Test func shownLaysTheEditOnAndKeepsTheDirectorysNameAndTags() {
        let edit = StationEdit(name: "Radio 2", tags: ["news"], description: "A line.")
        let drawn = rules(["a": edit]).shown([station("a", "NPO Radio 2 - Hits", tags: ["pop"])])
        #expect(drawn.count == 1)
        #expect(drawn[0].display == "Radio 2")
        #expect(drawn[0].name == "NPO Radio 2 - Hits")
        #expect(drawn[0].tags == ["pop"])
        #expect(drawn[0].shownTags == ["news"])
    }

    @Test func aStationWithNoEditIsHandedBackAsItWas() {
        let plain = station("a", "X")
        #expect(StationRules.none.edited(plain) == plain)
    }

    @Test func blankValuesAreTheStationsOwnAndAnEmptyEditIsNone() {
        let edit = StationEdit.of(name: " ", tags: [" News", "news", "Talk"], description: "")
        #expect(edit?.name == nil)
        #expect(edit?.tags == ["news", "talk"])
        #expect(edit?.description == nil)
        #expect(StationEdit.of(name: "", tags: [" "], description: nil) == nil)
    }

    @Test func theGenreFilterReadsTheAdminsTags() {
        let drawn = rules(["a": StationEdit(name: nil, tags: ["news"], description: nil)])
            .edited(station("a", "Pop Station", tags: ["pop"]))
        #expect(StationSieve(genre: "News").keeps(drawn))
        #expect(!StationSieve(genre: "Pop").keeps(drawn))
    }

    @Test func aGenreTakesInTheStationsRetaggedIntoIt() {
        let r = rules(["a": StationEdit(name: nil, tags: ["news"], description: nil),
                       "b": StationEdit(name: "Only a title", tags: nil, description: nil)])
        #expect(r.retagged(into: "News") == ["a"])
        #expect(r.retagged(into: "Jazz").isEmpty)
    }

    @Test func anEditedTitleCountsAsThatTitleWhenTwoStationsWouldPrintTheSame() {
        let r = rules(["a": StationEdit(name: "Concertzender", tags: nil, description: nil)])
        let drawn = r.shown([station("a", "Something Else"), station("b", "Concertzender - De Gehoorde Stilte")])
        #expect(drawn.map(\.display) == ["Concertzender", "Concertzender - De Gehoorde Stilte"])
    }

    @Test func theTunersGenreListReadsTheAdminsTags() {
        let settings = TunerSettings(text: "", country: "NL", sieve: StationSieve(genre: "News"), order: .listed,
                                     savedOnly: false)
        let list = TunerList.of(settings,
                                .listed([station("a", "Was Pop", tags: ["pop"]), station("b", "Real News", tags: ["news"])]),
                                saved: [],
                                rules: rules(["a": StationEdit(name: nil, tags: ["news"], description: nil),
                                              "b": StationEdit(name: nil, tags: ["pop"], description: nil)]))
        #expect(list.stations.map(\.uuid) == ["a"])
    }

    @Test func aRetaggedStationJoinsAGenreAnswerInPlayOrderWhereTheQuestionLetsItThrough() {
        let answer = [station("x", "X", clicks: 900), station("y", "Y", clicks: 100)]
        let retagged = [station("k", "Kiss FM", clicks: 500), station("d", "Kiss FM", country: "DE", clicks: 800)]
        let merged = RadioResults.withRetagged(answer, retagged,
                                               RadioQuery(name: "kiss", tag: .holding("news"), countryCode: "nl"))
        #expect(merged.map(\.uuid) == ["x", "k", "y"])
        #expect(RadioResults.withRetagged(answer, [station("x", "X")], RadioQuery()) == answer)
    }

    @Test func theBannerLineIsTheAdminsDescriptionBeforeAnySiteIsRead() async {
        var edited = station("a", "X")
        edited.edit = StationEdit(name: nil, tags: nil, description: "Dutch pop radio")
        let blurbs = StationBlurbs(reach: NetworkReach())
        #expect(await blurbs.of(edited) == "Dutch pop radio")
        #expect(blurbs.answered(edited) == .some("Dutch pop radio"))
    }

    @Test func aHiddenStationLeavesTheShownList() {
        let r = StationRules(hidden: ["a"], edits: [:])
        #expect(r.shown([station("a", "A"), station("b", "B")]).map(\.uuid) == ["b"])
    }
}
