import Testing
@testable import RPMRadio

/// Tests for reading a station's announcement as a song, and for the cover ask made from it. The
/// Android app's `Icy.said` gives the same answers.

@Test func aSongWithAnArtistIsReadAsBoth() {
    let said = StationSaid.of("Govinda - Myself", station: "SomaFM Lush")
    #expect(said == .song(artist: "Govinda", title: "Myself"))
    #expect(said?.coverAsk == SongAsk(artist: "Govinda", title: "Myself"))
}

@Test func aTitleWithoutAnArtistIsASongWithNoCoverAsk() {
    let said = StationSaid.of("Live from the studio", station: "Radio X")
    #expect(said == .song(artist: nil, title: "Live from the studio"))
    #expect(said?.coverAsk == nil)
}

@Test(arguments: ["", "   ", "SomaFM Lush", "somafm lush"])
func nothingOrTheStationsOwnNameSaysNothing(announced: String) {
    #expect(StationSaid.of(announced, station: "SomaFM Lush") == nil)
}

@Test func aLeadingStationNameIsTakenOff() {
    let said = StationSaid.of("Radio 1 - Massive Attack - Teardrop", station: "Radio 1")
    #expect(said == .song(artist: "Massive Attack", title: "Teardrop"))
}

@Test func aStationNameWithNothingAfterItIsKeptWhole() {
    #expect(StationSaid.withoutStation("Radio 1 - ", station: "Radio 1") == "Radio 1 - ")
}

@Test func anAdBreakIsAnAdBreakWithNoSong() {
    let said = StationSaid.of("Advertisement", station: "Radio X")
    #expect(said == .adBreak)
    #expect(said?.title == nil)
    #expect(said?.coverAsk == nil)
}

@Test func theEndOfABreakSaysNothing() {
    #expect(StationSaid.of("Spot Block End", station: "Radio X") == nil)
}

/// "-" or "X" on either side is not a song worth asking about.
@Test(arguments: ["X - Song", "Artist - Y"])
func aOneLetterSideAsksForNoCover(announced: String) {
    #expect(StationSaid.of(announced, station: "Radio X")?.coverAsk == nil)
}

/// Two spellings of one announcement ask once.
@Test func theCoverKeyFoldsCaseAccentsAndSpacing() {
    let one = SongAsk(artist: "Beyoncé", title: "Halo")
    let two = SongAsk(artist: "BEYONCE", title: "  Halo ")
    #expect(one.key == two.key)
    #expect(SongAsk(artist: "Daft  Punk", title: "One More Time").key
        == SongAsk(artist: "daft punk", title: "one more time").key)
}
