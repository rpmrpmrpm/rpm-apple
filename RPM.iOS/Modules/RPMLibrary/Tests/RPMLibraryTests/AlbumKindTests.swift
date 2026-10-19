import Testing
@testable import RPMLibrary

/// Mirrors the desktop's `RPM.Core.Tests/AlbumKindTests.cs`, so both apps classify records the same way.
///
/// What a record's name says about it. Each reading moves records to a different shelf on an artist's
/// page. The tests mostly check records that must stay where they are, because a wrong move is worse
/// than a missed one.
@Suite struct AlbumKindTests {
    @Test(arguments: ["Live at the Apollo", "Live At Wembley Stadium", "Unplugged (Live)",
                      "MTV Unplugged [Live]", "Rattle and Hum - Live", "Live 1975",
                      "LIVE!", "Live"])
    func aNightInFrontOfAnAudience(title: String) {
        #expect(AlbumKind.isLive(title))
    }

    /// The show's name is the whole tag, and a show is a set played in front of an audience. A studio
    /// box set with a similar name ("Storyteller") is not live.
    @Test(arguments: [("VH1 Storytellers", true), ("Storytellers", true),
                      ("Storyteller", false), ("Storyteller: The Complete Anthology", false)])
    func aSetWithTheTalkingLeftIn(pair: (title: String, live: Bool)) {
        #expect(AlbumKind.isLive(pair.title) == pair.live)
    }

    /// "Unplugged" alone names the live format, with or without "Live" in the title.
    @Test(arguments: ["MTV Unplugged", "Unplugged in New York", "Unplugged"])
    func aNightThatOnlySaysUnplugged(title: String) {
        #expect(AlbumKind.isLive(title))
    }

    /// A record sold as sessions was recorded live in a room, so it is shelved with the concerts, not with
    /// the studio albums.
    @Test(arguments: ["The Abbey Road Sessions", "The Complete Peel Sessions",
                      "Daytrotter Sessions", "Sessions@AOL"])
    func aRecordPlayedThroughInARoom(title: String) {
        #expect(AlbumKind.isLive(title))
    }

    /// Only the plural "Sessions" counts. The singular is not matched, and neither is a longer word that
    /// contains it.
    @Test(arguments: ["Session", "Jam Session", "Obsessions", "Possessions"])
    func theSingularAndTheWordsThatHoldItAreNotRead(title: String) {
        #expect(!AlbumKind.isLive(title))
    }

    /// The word appears inside many other words. Each of these is an ordinary record.
    @Test(arguments: ["Alive", "Stayin' Alive", "Olive", "Living Things", "Delivered",
                      "Livery Stable Blues", ""])
    func aWordThatMerelyHoldsTheLettersIsNotOne(title: String) {
        #expect(!AlbumKind.isLive(title))
    }

    @Test func nothingAtAllIsNotALiveRecord() {
        #expect(!AlbumKind.isLive(nil))
    }

    /// A known cost of the rule: a studio record whose name starts with "Live" is filed as live. This is
    /// accepted on purpose.
    @Test(arguments: ["Live Through This", "Live Forever"])
    func aStudioRecordNamedForTheWordIsCaughtToo(title: String) {
        #expect(AlbumKind.isLive(title))
    }

    @Test(arguments: ["Runaway - Single", "Runaway - single", "Flashing Lights – Single",
                      "Flashing Lights — Single", "Stronger -Single", "Best Of - Singles"])
    func oneSongReleasedOnItsOwn(title: String) {
        #expect(AlbumKind.isSingle(title))
    }

    /// The dash is half of the rule. Without it, "Single" is an ordinary word, as in "Single Ladies".
    @Test(arguments: ["Single Ladies", "Singles", "Singles Soundtrack", "Single File", ""])
    func theWordWithoutTheDashIsAnOrdinaryTitle(title: String) {
        #expect(!AlbumKind.isSingle(title))
    }

    @Test func nothingAtAllIsNotASingle() {
        #expect(!AlbumKind.isSingle(nil))
    }

    @Test(arguments: ["The Essential Michael Jackson", "Greatest Hits",
                      "The Very Best of Prince", "Best Of Both Worlds", "The Collection",
                      "Singles Collection", "Anthology 1", "The Definitive Rod Stewart",
                      "Hits", "Essentials"])
    func aGatheringUpRatherThanARecord(title: String) {
        #expect(AlbumKind.isCompilation(title))
    }

    /// Each entry must match a whole word or phrase. These titles contain the letters of an entry but are
    /// ordinary records.
    @Test(arguments: ["Recollection", "Collective Soul", "Best Coast", "Graduation",
                      "Hitsville", ""])
    func aTitleThatMerelyHoldsTheLettersIsNotOne(title: String) {
        #expect(!AlbumKind.isCompilation(title))
    }

    @Test func nothingAtAllIsNotACompilation() {
        #expect(!AlbumKind.isCompilation(nil))
    }

    /// A known limit: a compilation whose title looks like an album title is filed with the albums. No list
    /// of phrases can tell them apart.
    @Test(arguments: ["Legend", "Hot Rocks"])
    func aCompilationThatDoesNotSaySoIsMissed(title: String) {
        #expect(!AlbumKind.isCompilation(title))
    }

    /// Music written for a film, show or game, judged by the name it is released under.
    @Test(arguments: ["Purple Rain (Original Soundtrack)",
                      "Guardians of the Galaxy: Awesome Mix Vol. 1 - Soundtrack",
                      "The Dark Knight - Original Score", "Blade Runner (Film Score)",
                      "Music from the Motion Picture Pulp Fiction",
                      "Music from the HBO Original Series Game of Thrones",
                      "Music from Baz Luhrmann's Film The Great Gatsby",
                      "Hamilton (Original Broadway Cast Recording)",
                      "Final Fantasy VII OST"])
    func musicWrittenForSomethingBeingWatched(title: String) {
        #expect(AlbumKind.isSoundtrack(title))
    }

    /// A known cost of the rule: a studio record with "Music from" in its title is filed as a soundtrack.
    /// The phrase is treated as a strong sign, which is the trade-off accepted here.
    @Test func aStudioRecordNamedMusicFromSomewhereIsCaughtToo() {
        #expect(AlbumKind.isSoundtrack("Music from Big Pink"))
    }

    /// "Score" is an ordinary word unless the title says what kind of music it is. A title that names only
    /// the film gives no clue, so these records stay on the album shelf.
    @Test(arguments: ["The Score", "Settle the Score", "Purple Rain",
                      "Saturday Night Fever", "Ghostwriter", "Music for the Masses", ""])
    func aRecordThatDoesNotSayItIsOne(title: String) {
        #expect(!AlbumKind.isSoundtrack(title))
    }

    @Test func nothingAtAllIsNotASoundtrack() {
        #expect(!AlbumKind.isSoundtrack(nil))
    }

    /// Each question is separate. A title is checked for each kind on its own.
    @Test func aRecordCanBeNeitherAndCanBeBoth() {
        #expect(!AlbumKind.isLive("Graduation"))
        #expect(!AlbumKind.isSingle("Graduation"))

        #expect(AlbumKind.isLive("Live at Abbey Road - Single"))
        #expect(AlbumKind.isSingle("Live at Abbey Road - Single"))
    }
}
