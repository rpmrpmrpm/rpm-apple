import Testing
@testable import RPMRadio

/// The same rules are tested in `RPM.Core.Tests/RadioNamesTests.cs`. Change both files together.

private func station(_ name: String) -> RadioStation {
    RadioStation(uuid: name, name: name, streamUrl: "http://example.test/" + name)
}

private func shown(_ names: String...) -> [String] {
    RadioNames.distinguish(names.map(station)).map(\.display)
}

/// Station names as the directory stores them, with stream details in the name. The cleaned
/// name keeps only the station name.
@Test(arguments: [
    ("PureClassixx #Flac", "PureClassixx"),
    ("Intense Radio - We love Dance #HQ# FLAC", "Intense Radio"),
    ("Smooth FM 91.5 - Melbourne - 91.5 FM (AAC+ 320k)", "Smooth FM 91.5"),
    ("Heart London 106.2 [MP3]", "Heart London 106.2"),
    ("Radio Paradise (320k FLAC)", "Radio Paradise"),
    ("Some Station - MP3 128k", "Some Station"),
    ("Some Station | 320 kbps", "Some Station"),
    ("Jazz24 #HQ", "Jazz24"),
])
func theStreamsSpecificationComesOutOfTheName(each: (String, String)) {
    #expect(RadioNames.clean(each.0) == each.1)
}

/// **Numbers and punctuation in a station name are usually part of the name.** Removing them
/// would rename a broadcaster, which is worse than an untidy name.
@Test(arguments: [
    "Radio 538", "100% NL", "538 TOP 50", "Studio Brussel", "NPO Radio 1", "Radio 10",
    "Sky Radio 101 FM", "3FM", "Q music Nederland", "Arrow Classic Rock", "Radio Gelderland",
])
func aStationNameIsLeftExactlyAsItWasWritten(name: String) {
    #expect(RadioNames.clean(name) == name)
}

@Test func aNumberIsOnlyABitrateInsideTheBandAStreamUses() {
    #expect(RadioNames.clean("Radio 4") == "Radio 4")
    #expect(RadioNames.clean("Kiss 108") == "Kiss 108")
    #expect(RadioNames.clean("Some Station 128k") == "Some Station")
}

/// An empty name is worse than an untidy one, so a name that is only stream details is kept.
@Test func aNameThatIsNothingButSpecificationKeepsIt() {
    #expect(RadioNames.clean("FLAC") == "FLAC")
    #expect(RadioNames.clean("#HQ#") == "#HQ#")
}

@Test func nothingToCleanComesBackAsItWas() {
    #expect(RadioNames.clean("") == "")
    #expect(RadioNames.clean(nil) == "")
}

// ── and the tag line ──

@Test func theTagLineKeepsOnlyWhatAStationPlays() {
    #expect(RadioNames.genres(["90s", "club", "dance", "flac", "##browserfriendly", "320k"])
            == ["90s", "club", "dance"])
}

@Test func qmusicsTagLineLosesTheDirectorysOwnNote() {
    #expect(RadioNames.genres(["##browserfriendly", "mix", "pop"]) == ["mix", "pop"])
}

@Test func aStationWithNoGenresLeftShowsNone() {
    #expect(RadioNames.genres(["mp3", "128k", "#hq"]).isEmpty)
    #expect(RadioNames.genres([]).isEmpty)
    #expect(RadioNames.genres(nil).isEmpty)
}

// ── the text after a spaced dash ──

@Test(arguments: [
    ("Intense Radio - We love Dance", "Intense Radio"),
    ("Radio 538 - Non-stop", "Radio 538"),
    ("KINK \u{2013} Distortion", "KINK"),
    ("Some Station | The best hits", "Some Station"),
    ("A - B - C", "A"),
])
func everythingAfterASpacedDashIsAStrapline(each: (String, String)) {
    #expect(RadioNames.clean(each.0) == each.1)
}

/// A hyphen inside a word is part of the word. Cutting at every dash would change each of
/// these names.
@Test(arguments: ["Hi-Fi Radio", "K-Rock", "Radio X-tra", "Rock-FM", "Non-Stop Pop", "1-2-3 Radio"])
func aHyphenInsideAWordIsNotAStrapline(name: String) {
    #expect(RadioNames.clean(name) == name)
}

/// If a name starts with a dash, there is no station name before it. The whole name is kept,
/// and the leading dash is removed.
@Test func aNameThatStartsWithADashKeepsItsWords() {
    #expect(RadioNames.clean("- The Station") == "The Station")
    #expect(RadioNames.clean(" - Only This") == "Only This")
}

// ── the text after a dash, kept when it tells two stations apart ──

/// Concertzender runs these as separate stations. Both would be cleaned to "Concertzender",
/// so the list would show the same name twice. The text after the dash is kept instead.
@Test func twoStationsSharingAHeadKeepTheirStraplines() {
    #expect(shown("Concertzender - De Gehoorde Stilte", "Concertzender - Hard Bop")
            == ["Concertzender - De Gehoorde Stilte", "Concertzender - Hard Bop"])
}

/// Only names that would clash keep this text. Otherwise it is extra noise.
@Test func theStationsThatShareNothingStillLoseTheirs() {
    #expect(shown("Concertzender - De Gehoorde Stilte", "Concertzender - Hard Bop",
                  "Intense Radio - We love Dance")
            == ["Concertzender - De Gehoorde Stilte", "Concertzender - Hard Bop", "Intense Radio"])
}

@Test func aBareNameBesideAStraplineIsLeftAlone() {
    #expect(shown("Concertzender", "Concertzender - Hard Bop")
            == ["Concertzender", "Concertzender - Hard Bop"])
}

/// Two entries with the same name have no extra text to tell them apart, so both keep the
/// plain name.
@Test func twoOfTheSameNameStayTheSameName() {
    #expect(shown("Radio 538", "Radio 538") == ["Radio 538", "Radio 538"])
}

/// Stream details, such as the bitrate, are removed even when names clash. They never tell
/// stations apart.
@Test func aKeptStraplineStillLosesTheSpecification() {
    #expect(shown("Jazz FM - Bebop #HQ FLAC", "Jazz FM - Hard Bop (MP3 320k)")
            == ["Jazz FM - Bebop", "Jazz FM - Hard Bop"])
}


// ── the folded name: the key that shows whether two entries are one station ──

/// Words such as "FM" and "UK" are left out of the key. Contributors add them in different
/// combinations for the same station.
@Test(arguments: ["Heart", "Heart FM", "Heart UK", "HEART (UK)"])
func oneStationFoldsToOneKeyHoweverItWasTyped(_ name: String) {
    #expect(RadioNames.fold(name, "GB") == "heart")
}

/// Spellings of the Dutch station Qmusic. All of them must give one key.
@Test(arguments: ["Qmusic", "Q-Music", "Q music Nederland", "QMUSIC NEDERLAND",
                  "QMUSIC NEDERLAND AAC HIGH"])
func theSpellingsOfOneDutchStationFoldTogether(_ name: String) {
    #expect(RadioNames.fold(name, "NL") == "qmusic")
}

/// Another channel of a broadcaster is a different station. It differs from the main channel
/// by one word. Keys must match exactly, not by prefix, so these stay separate.
@Test func aBroadcastersOtherChannelsKeepTheirOwnKeys() {
    let parent = RadioNames.fold("Radio 10", "NL")
    #expect(parent != RadioNames.fold("Radio 10 non-stop", "NL"))
    #expect(parent != RadioNames.fold("Radio 10 60's & 70's Hits", "NL"))
    #expect(RadioNames.fold("Qmusic", "NL") != RadioNames.fold("Qmusic Non-Stop", "NL"))
    #expect(RadioNames.fold("Sky Radio", "NL") != RadioNames.fold("Sky Radio Christmas", "NL"))
}

/// A country word at the start of a name is part of the brand, so it is kept. "GB News" must
/// not match "News Radio UK".
@Test func aCountryWordAtTheHeadIsPartOfTheName() {
    #expect(RadioNames.fold("GB News", "GB") == "gbnews")
    #expect(RadioNames.fold("GB News", "GB") != RadioNames.fold("News Radio UK", "GB"))
    #expect(RadioNames.fold("France Inter", "FR") == "franceinter")
}

/// A country word after the first word is a qualifier, and it is optional. Both forms give
/// the same key.
@Test func aCountryWordAfterTheHeadIsAQualifier() {
    #expect(RadioNames.fold("Classic FM", "GB") == RadioNames.fold("Classic FM UK", "GB"))
    #expect(RadioNames.fold("Virgin Radio Italia", "IT") == RadioNames.fold("Virgin Radio Italy", "IT"))
    #expect(RadioNames.fold("Nostalgie", "FR") == RadioNames.fold("Radio Nostalgie France", "FR"))
}

/// A country word is dropped only in its own country. "Italia" is a qualifier for an Italian
/// station, but part of the name for a station in another country.
@Test func aCountryWordIsOnlyDroppedInItsOwnCountry() {
    #expect(RadioNames.fold("Virgin Radio", "GB") != RadioNames.fold("Virgin Radio Italia", "GB"))
    #expect(RadioNames.fold("Radio Italia", "GB") == "italia")
}

/// Stream details are removed first, using the same rule as the shown name.
@Test func theSpecificationIsNotPartOfTheKey() {
    #expect(RadioNames.fold("BBC Radio 4", "GB") == RadioNames.fold("BBC Radio 4 (128k)", "GB"))
    #expect(RadioNames.fold("KINK", "NL") == RadioNames.fold("Kink 192k mp3", "NL"))
    #expect(RadioNames.fold("Radio Caroline", "GB") == RadioNames.fold("Radio Caroline AAC 96 kbps", "GB"))
}

/// Names are read as Unicode, not only as ASCII letters. With only ASCII letters, "Вести FM"
/// and "Ретро FM" would both become "fm" and merge into one station.
@Test func aNameInAnotherScriptKeepsItsLetters() {
    #expect(RadioNames.fold("Вести FM", "RU") != RadioNames.fold("Ретро FM", "RU"))
    #expect(!RadioNames.fold("美国之音", "CN").isEmpty)
}

/// Accents are ignored in the key, so "Rádio" and "Radio" give the same key.
@Test func accentsFoldAway() {
    #expect(RadioNames.fold("Radio Comercial", "PT") == RadioNames.fold("Rádio Comercial", "PT"))
}

/// A name that is only noise keeps its words, so the key is never empty. Empty keys would
/// merge unrelated stations.
@Test func aNameThatIsAllNoiseStillFilesUnderSomething() {
    #expect(RadioNames.fold("Radio", "NL") == "radio")
    #expect(RadioNames.fold("The Station", "NL") == "thestation")
    #expect(RadioNames.fold("Radio Nederland", "NL") == "nederland")
    #expect(RadioNames.fold("", "NL").isEmpty)
    #expect(RadioNames.fold(nil, nil).isEmpty)
}

/// Without a country code, no word is treated as a country word.
@Test func noCountryMeansNoQualifierIsDropped() {
    #expect(RadioNames.fold("Classic FM UK", nil) == "classicuk")
}
