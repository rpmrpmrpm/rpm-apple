import Testing
@testable import RPMRadio

/// Tests for splitting a station's announcement into an artist and a title.

@Test func theOrdinaryAnnouncementIsAnArtistAndATitle() {
    let said = IcyTitle.split("Talk Talk - Desire")
    #expect(said.artist == "Talk Talk")
    #expect(said.title == "Desire")
}

/// **The key rule.** A hyphen inside a name is part of the name, not a separator.
@Test(arguments: ["Jay-Z", "Hi-Fi Sean", "Jean-Michel Jarre"])
func aHyphenInsideANameIsNotASeparator(artist: String) {
    let said = IcyTitle.split("\(artist) - Something")
    #expect(said.artist == artist)
    #expect(said.title == "Something")
}

/// The first separator wins. Text after it, such as a remix or a live tag, stays in the title.
@Test func theFirstSeparatorSplitsAndTheRestStayInTheTitle() {
    let said = IcyTitle.split("Blue Oyster Cult - (Don't Fear) The Reaper - Live")
    #expect(said.artist == "Blue Oyster Cult")
    #expect(said.title == "(Don't Fear) The Reaper - Live")
}

@Test(arguments: [" \u{2013} ", " \u{2014} ", " -- "])
func theOtherDashesStationsUseSplitTheSameWay(dash: String) {
    let said = IcyTitle.split("Enya\(dash)Orinoco Flow")
    #expect(said.artist == "Enya")
    #expect(said.title == "Orinoco Flow")
}

/// A station that announces only its own name gives a title and no artist. An artist is not
/// guessed from half a string.
@Test func somethingThatIsNotAPairIsATitle() {
    let said = IcyTitle.split("NPO Radio 2")
    #expect(said.artist == nil)
    #expect(said.title == "NPO Radio 2")
}

@Test func oneEmptyHalfIsNotAPair() {
    let said = IcyTitle.split("- Live from Paris")
    #expect(said.artist == nil)
    #expect(said.title == "- Live from Paris")
}

@Test func announcingNothingSaysNothing() {
    #expect(IcyTitle.split(nil).title == nil)
    #expect(IcyTitle.split("   ").title == nil)
    #expect(IcyTitle.line(nil) == "")
}

@Test func theOneLineFormJoinsThePairAndLeavesASingleAlone() {
    #expect(IcyTitle.line("Talk Talk - Desire") == "Talk Talk \u{b7} Desire")
    #expect(IcyTitle.line("NPO Radio 2") == "NPO Radio 2")
}

// ── stations that send automation data in the title ──

/// **Automation data.** Many US stations send a list of `key="value"` pairs where the title
/// goes. For example, `Zara Larsson - text="Lush Life" song_spot="M"...` gives the artist
/// "Zara Larsson" and the title "Lush Life", taken from the `text` pair.
@Test func aTitleMadeOfKeysAndValuesIsReadRatherThanPrinted() {
    let said = IcyTitle.split(
        "Zara Larsson - text=\"Lush Life\" song_spot=\"M\" MediaBaseId=\"0\" "
        + "itunesTrackId=\"0\" amgTrackId=\"0\" TAID=\"0\" TPID=\"0\" cartcutId=\"0\" "
        + "amgArtworkURL=\"null\" length=\"00:03:32\" unsID=\"0\" spotInstanceId=\"-1\"")

    #expect(said.artist == "Zara Larsson")
    #expect(said.title == "Lush Life")
}

/// Some stations put the artist in key-value pairs too. Then nothing comes before the pairs.
@Test func thePairsCanCarryTheArtistAsWell() {
    let said = IcyTitle.split("artist=\"Talk Talk\" title=\"Desire\" song_spot=\"M\"")

    #expect(said.artist == "Talk Talk")
    #expect(said.title == "Desire")
}

/// If the text holds only pairs and no readable title, the station's own name is shown. The
/// pair names, such as `MediaBaseId`, are never shown.
@Test func bookkeepingWithNothingReadableInItIsNotPrinted() {
    let said = IcyTitle.split("NPO Radio 2 - MediaBaseId=\"0\" TAID=\"0\"")

    #expect(said.artist == nil)
    #expect(said.title == "NPO Radio 2")
}

/// **A quotation mark in a title is not a key-value pair.** A key is a bare word directly
/// before `="`, which a song title does not contain.
@Test func aTitleWithAQuotationMarkInItIsLeftAlone() {
    let said = IcyTitle.split("The Smiths - Shoplifters Of The World Unite")
    #expect(said.title == "Shoplifters Of The World Unite")

    let quoted = IcyTitle.split("Chic - Le Freak (\"Freak Out\")")
    #expect(quoted.artist == "Chic")
    #expect(quoted.title == "Le Freak (\"Freak Out\")")
}
