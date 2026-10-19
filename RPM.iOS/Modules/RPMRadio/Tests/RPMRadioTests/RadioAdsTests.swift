import Testing
@testable import RPMRadio

/// The same rules are tested in `RPM.Core.Tests/RadioAdsTests.cs`. Change both files together.

private func carries(_ tags: [String]) -> Bool {
    RadioAds.carriesAds(tags: tags, name: nil, homepage: nil)
}

@Test(arguments: [
    ["commercial", "hot adult contemporary", "london"],
    ["commercial", "dance", "electronic"],
    ["bloemfontein", "commercial", "local news"],
])
func aStationThatSaysItIsCommercialIsMarked(tags: [String]) {
    #expect(carries(tags))
}

@Test(arguments: ["public radio", "public service", "new york public radio", "Public Radio",
                  "öffentlich-rechtlich", "government"])
func aPublicBroadcasterIsMarked(tag: String) {
    #expect(carries([tag, "news"]))
}

@Test(arguments: ["non-commercial", "noncommercial", "no ads", "ad-free", "werbefrei"])
func aStationThatSaysItCarriesNoneIsNotMarked(tag: String) {
    #expect(!carries([tag, "jazz"]))
}

@Test func sayingBothMeansTheOneThatIsSpecific() {
    #expect(!carries(["public radio", "non-commercial"]))
    #expect(!carries(["non-commercial"]))
}

@Test func aStationThatSaysNothingIsNotMarked() {
    #expect(!carries(["90s", "club", "dance"]))
    #expect(!carries([]))
}

@Test(arguments: ["Advertisement", "advertisements", "ADVERTISING", "Ad Break", "Commercial",
                  "Reclame", "Werbung", "Publicité", "Publicidad", "- Werbung -", "[reclame]",
                  "  Advertisement  "])
func aStationAnnouncingABreakIsInOne(announced: String) {
    #expect(RadioAds.isAdBreak(announced))
}

@Test(arguments: ["The Commercials - Advertisement For Myself", "Werbung für die Liebe",
                  "Adele - Hello", "Adverts of Our Lives - The Band"])
func aRecordThatMerelyMentionsOneIsNotABreak(announced: String) {
    #expect(!RadioAds.isAdBreak(announced))
}

@Test func nothingAnnouncedIsNotABreak() {
    #expect(!RadioAds.isAdBreak(nil))
    #expect(!RadioAds.isAdBreak(""))
    #expect(!RadioAds.isAdBreak("   "))
    #expect(!RadioAds.isAdBreak("- - -"))
}

@Test(arguments: [
    ("NPO Radio 1", "https://www.nporadio1.nl/"),
    ("NPO Radio 2", "http://www.nporadio2.nl/"),
    ("3FM", "https://www.npo3fm.nl/"),
    ("Radio 538", "https://www.538.nl/"),
    ("Sky Radio", "https://www.skyradio.nl/"),
    ("Radio 10", "https://www.radio10.nl/"),
    ("Joe", "https://joe.nl/"),
    ("QMUSIC NEDERLAND", "https://qmusic.nl/"),
    ("100% NL", "https://www.100p.nl/"),
    ("Arrow Classic Rock", "https://www.arrow.nl/"),
    ("Radio Gelderland", "https://www.omroepgelderland.nl/"),
])
func aKnownBroadcasterIsMarked(each: (String, String)) {
    #expect(RadioAds.carriesAds(tags: ["pop"], name: each.0, homepage: each.1))
}

@Test func theSiteAnswersEvenWhereTheNameWouldNot() {
    #expect(RadioAds.carriesAds(tags: [], name: "Some Rebrand", homepage: "https://www.538.nl/some/page"))
    #expect(RadioAds.carriesAds(tags: [], name: "Some Rebrand", homepage: "https://nporadio1.nl/"))
}

@Test(arguments: ["Nippon Radio", "Bbcrooklyn Sound", "Radio NPO Tribute", "Intense Radio"])
func aNameThatMerelyContainsOneIsNotThatBroadcaster(name: String) {
    #expect(!RadioAds.carriesAds(tags: ["dance"], name: name, homepage: "https://example.test/"))
}

@Test func aStationSayingItCarriesNoneIsTakenAtItsWord() {
    #expect(!RadioAds.carriesAds(tags: ["non-commercial"], name: "NPO Radio 1",
                                 homepage: "https://www.nporadio1.nl/"))
}

@Test func anUnknownStationIsStillNotMarked() {
    #expect(!RadioAds.carriesAds(tags: ["dance"], name: "Intense Radio",
                                 homepage: "https://www.intenseradio.com/"))
}

@Test(arguments: ["Spot Block Start", "Spot Block", "spot block start"])
func aSpotBlockStartingIsABreak(announced: String) {
    #expect(RadioAds.isAdBreak(announced))
    #expect(!RadioAds.isBreakOver(announced))
}

@Test(arguments: ["Spot Block End", "spot block end"])
func aSpotBlockEndingIsNeitherABreakNorARecord(announced: String) {
    #expect(RadioAds.isBreakOver(announced))
    #expect(!RadioAds.isAdBreak(announced))
}

@Test(arguments: ["Spot - Wet Leg", "The Blockheads - Spot The Difference", nil, ""] as [String?])
func anythingElseIsNeither(announced: String?) {
    #expect(!RadioAds.isAdBreak(announced))
    #expect(!RadioAds.isBreakOver(announced))
}
