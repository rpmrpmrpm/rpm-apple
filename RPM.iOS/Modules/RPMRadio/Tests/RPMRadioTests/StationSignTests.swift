import Testing
@testable import RPMRadio

/// The same rules are tested in `RPM.Core.Tests/StationSignTests.cs`. Change both files together.
/// A call sign is the short mark shown on the dial, at most four letters.

@Test(arguments: [
    // A name that is already a short mark keeps it, even with extra text around it.
    ("KEXP", "KEXP"),
    ("Radio Nova", "NOVA"),
    ("Jazz FM", "JAZZ"),
    ("NPO Radio 2", "NPO2"),
    ("BBC Radio 1", "BBC1"),
    // For many stations the number is the name. Numbers are kept the same way as letters.
    ("Radio 538", "538"),
    ("100% NL", "100"),
    // Three or more meaningful words: use their initials, up to four letters.
    ("Smooth Jazz Lounge Radio", "SJL"),
    ("Kink Distortion Amsterdam Online", "KDA"),
    ("Sky Radio Christmas Hits Nonstop", "SCHN"),
    // Joining words such as "of" and "the" are not used for initials.
    ("Voice of the People Network", "VPN"),
    // One or two meaningful words: use the first four letters.
    ("Classical Music", "CLAS"),
    ("Klassiek", "KLAS"),
    // Accents are removed first, so the same name always gives the same sign.
    ("R\u{e1}dio Comercial", "COME"),
    // Punctuation ends a word, so "Q-Music" is two words. The first four letters are used.
    ("Q-Music", "QMUS"),
])
func signs(each: (String, String)) {
    #expect(StationSign.of(each.0) == each.1)
}

@Test func aNamelessStationGetsNoSign() {
    #expect(StationSign.of(nil) == "")
    #expect(StationSign.of("   ") == "")
    #expect(StationSign.of("!!! ---") == "")
}

/// The word "Radio" is left out, because it does not say which station this is. If "Radio" is
/// the whole name, it is kept, so the station still gets a sign.
@Test func aNameThatIsOnlyNoiseStillSigns() {
    #expect(StationSign.of("Radio") == "RADI")
    #expect(StationSign.of("FM") == "FM")
}

@Test(arguments: [
    "Smooth Jazz Lounge Radio \u{2014} The Netherlands",
    "\u{425}\u{438}\u{442} FM",
    "1.FM - Absolute Top 40 (Hit Radio)",
    "WWWWWWWWWWWWWWWWWWWW",
    "A B C D E F G H",
])
func noSignIsEverWiderThanTheCard(name: String) {
    let sign = StationSign.of(name)
    #expect((1...4).contains(sign.count), "\(name) signed \(sign)")
}

/// The dial card and the station row compute the sign separately. They always agree, because
/// the function has no side effects.
@Test func theSameNameAlwaysSignsTheSame() {
    #expect(StationSign.of("Radio Paradise") == StationSign.of("  radio paradise  "))
}
