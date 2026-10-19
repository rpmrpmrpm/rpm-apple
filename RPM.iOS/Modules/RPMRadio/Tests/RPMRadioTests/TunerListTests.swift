import Testing
@testable import RPMRadio

@Suite struct TunerListTests {
    private func station(_ uuid: String, _ name: String, codec: String = "MP3", votes: Int = 0) -> RadioStation {
        var made = RadioStation(uuid: uuid, name: name, streamUrl: "http://x/\(uuid)")
        made.codec = codec
        made.votes = votes
        return made
    }

    private let plain = TunerSettings(text: "", country: nil, sieve: .off, order: .listed, savedOnly: false)

    @Test func theDirectoryListIsFilteredSortedAndHiddenOnesLeaveIt() {
        let found = [station("a", "Beta", votes: 1), station("b", "Alpha", codec: "AAC", votes: 9),
                     station("c", "Gamma", votes: 5)]
        var settings = plain
        settings.order = .votes
        let list = TunerList.of(settings, .listed(found), saved: [], rules: StationRules(hidden: ["c"], edits: [:]))
        #expect(list.stations.map(\.uuid) == ["b", "a"])
        #expect(list.empty == nil)

        settings.sieve = StationSieve(format: "AAC")
        #expect(TunerList.of(settings, .listed(found), saved: [], rules: .none).stations.map(\.uuid) == ["b"])
    }

    @Test func anEmptyListSaysWhy() {
        var settings = plain
        #expect(TunerList.of(settings, .listed([]), saved: [], rules: .none).empty == .noResults)
        #expect(TunerList.of(settings, .asking, saved: [], rules: .none).empty == nil)
        #expect(TunerList.of(settings, .asking, saved: [], rules: .none).asking)

        settings.sieve = StationSieve(format: "OGG")
        #expect(TunerList.of(settings, .listed([station("a", "A")]), saved: [], rules: .none).empty == .noFilterMatch)

        settings = plain
        settings.savedOnly = true
        #expect(TunerList.of(settings, .directoryDown, saved: [], rules: .none).empty == .noFavorites)
        let saved = TunerList.of(settings, .directoryDown, saved: [station("s", "Saved")], rules: .none)
        #expect(saved.stations.map(\.uuid) == ["s"])
        #expect(!saved.asking)
    }

    @Test func theQuestionTrimsTheTextAndAsksTheGenresTerm() {
        var settings = plain
        settings.text = "  jazz fm "
        settings.sieve = StationSieve(genre: "News")
        #expect(settings.question.text == "jazz fm")
        #expect(settings.question.tag == RadioGenres.term("News"))
    }
}
