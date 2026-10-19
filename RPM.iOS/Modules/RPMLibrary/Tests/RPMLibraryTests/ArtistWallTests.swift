import Testing
import Foundation
@testable import RPMLibrary

/// Mirrors the desktop's `RPM.Core.Tests/ArtistWallTests.cs`, case for case. The desktop and the phone build
/// the artist wall from one rule, so both are tested against the same answers.

private func Row(_ album: String, _ albumArtist: String?, _ artist: String?,
                 _ tracks: Int = 1) -> ArtistCreditRow {
    ArtistCreditRow(album: album, albumArtist: albumArtist, artist: artist, tracks: tracks)
}

private func find(_ wall: [ArtistWallItem], _ name: String) throws -> ArtistWallItem {
    let hits = wall.filter { $0.name.compare(name, options: .caseInsensitive) == .orderedSame }
    try #require(hits.count == 1, "expected one box for \(name), got \(hits.count)")
    return hits[0]
}

@Suite struct ArtistWallTests {
    @Test func anOrdinaryAlbumIsOneArtistWithOneRecord() throws {
        let wall = ArtistWall.build([Row("ABBA/Arrival", "ABBA", "ABBA", 10)])

        try #require(wall.count == 1)
        #expect(wall[0].name == "ABBA")
        #expect(wall[0].albums == ["ABBA/Arrival"])
        // One act made it, so it is not a collaboration.
        #expect(wall[0].together.isEmpty)
        #expect(wall[0].appearances.isEmpty)
        #expect(wall[0].own == ["ABBA/Arrival"])
        // Ten tracks, not twenty. The row matches them both as the record's artist and as the tracks' artist,
        // but it is the same ten songs.
        #expect(wall[0].tracks == 10)
    }

    /// A guest gets a box only once they have a record of their own. The guest here is on one track of
    /// another artist's album and has no records, so a box would be a page about someone else's record.
    @Test func aGuestWithNoRecordsOfTheirOwnGetsNoBox() throws {
        let wall = ArtistWall.build([
            Row("Calvin Harris/18 Months", "Calvin Harris", "Calvin Harris", 12),
            Row("Calvin Harris/18 Months", "Calvin Harris", "Calvin Harris feat. Ellie Goulding", 1),
        ])

        try #require(wall.count == 1)
        #expect(wall[0].name == "Calvin Harris")
        #expect(wall[0].albums == ["Calvin Harris/18 Months"])
    }

    /// Once the guest has a record of their own, both artists are on the wall. The guest appearance is shown
    /// separately on the page.
    @Test func aGuestWhoAlsoHasARecordOfTheirOwnGetsBoth() throws {
        let wall = ArtistWall.build([
            Row("Calvin Harris/18 Months", "Calvin Harris", "Calvin Harris", 12),
            Row("Calvin Harris/18 Months", "Calvin Harris", "Calvin Harris feat. Ellie Goulding", 1),
            Row("Ellie Goulding/Halcyon", "Ellie Goulding", "Ellie Goulding", 13),
        ])

        let goulding = try find(wall, "Ellie Goulding")
        #expect(goulding.albums == ["Ellie Goulding/Halcyon"])
        #expect(goulding.appearances == ["Calvin Harris/18 Months"])
        #expect(goulding.tracks == 14)
    }

    /// One artist credited in two spellings is one box.
    @Test func theSameArtistCreditedTwoWaysIsOneBox() throws {
        let wall = ArtistWall.build([
            Row("Ellie Goulding/Halcyon", "Ellie Goulding", "Ellie Goulding", 13),
            Row("Various/Party", "Various Artists", "Ellie Goulding", 1),
            Row("Various/Party", "Various Artists", "Calvin Harris ft. Ellie Goulding", 1),
        ])

        #expect(try find(wall, "Ellie Goulding").tracks == 15)
        #expect(try find(wall, "Ellie Goulding").appearances == ["Various/Party"])
    }

    /// A band whose name contains a separator is not two people. The collection files its record under the
    /// full name, which shows that.
    @Test(arguments: ["Earth, Wind & Fire", "AC/DC", "Simon & Garfunkel"])
    func aBandTheCollectionFilesARecordUnderIsNeverSplit(band: String) throws {
        let wall = ArtistWall.build([Row("Band/Record", band, band, 9)])

        try #require(wall.count == 1)
        #expect(wall[0].name == band)
    }

    /// A separator between two acts that the collection knows separately still splits the credit.
    @Test func anAmpersandBetweenTwoActsStillSplits() throws {
        let wall = ArtistWall.build([
            Row("Queen/Hot Space", "Queen", "Queen", 11),
            Row("Queen/Hot Space", "Queen", "Queen & David Bowie", 1),
            // This artist has a record of their own, so the split has a page to appear on.
            Row("David Bowie/Low", "David Bowie", "David Bowie", 11),
        ])

        #expect(try find(wall, "David Bowie").appearances == ["Queen/Hot Space"])
        #expect(try find(wall, "David Bowie").albums == ["David Bowie/Low"])
    }

    // ── a record two acts made together ──

    /// The case the collaboration rule is for. Both halves are acts the collection already knows,
    /// so the credit names two people, and the record belongs to both.
    @Test func aRecordTwoKnownActsMadeTogetherBelongsToBothOfThem() throws {
        let wall = ArtistWall.build([
            Row("Kanye West/Graduation", "Kanye West", "Kanye West", 13),
            Row("Various/Party", "Various Artists", "Ty Dolla $ign", 1),
            Row("Kanye West & Ty Dolla $ign/Vultures 1", "Kanye West & Ty Dolla $ign",
                "Kanye West & Ty Dolla $ign", 16),
        ])

        #expect(try find(wall, "Kanye West").albums == ["Kanye West/Graduation"])
        #expect(try find(wall, "Kanye West").together == ["Kanye West & Ty Dolla $ign/Vultures 1"])
        #expect(try find(wall, "Ty Dolla $ign").albums.isEmpty)
        #expect(try find(wall, "Ty Dolla $ign").together == ["Kanye West & Ty Dolla $ign/Vultures 1"])

        // There is no box for the pairing itself. The compilation that the second row is on has its own box,
        // because a record filed under the marker belongs to the compilations shelf.
        #expect(wall.map(\.name) == ["Kanye West", "Ty Dolla $ign", ArtistWall.compilations])
    }

    /// The joining words count too. An ordinary split does not cut on these.
    @Test(arguments: ["Kanye West with Common", "Kanye West and Common", "Kanye West x Common",
                      "Kanye West & Common", "Kanye West, Common"])
    func aCollaborationJoinedByAWordIsStillTwoActs(credit: String) throws {
        let wall = ArtistWall.build([
            Row("Kanye West/Graduation", "Kanye West", "Kanye West", 13),
            Row("Common/Be", "Common", "Common", 11),
            Row("Both/Record", credit, credit, 9),
        ])

        #expect(wall.map(\.name) == ["Common", "Kanye West"])
        #expect(try find(wall, "Kanye West").together.contains("Both/Record"))
        #expect(try find(wall, "Common").together.contains("Both/Record"))
    }

    /// The other half of the rule. The collection knows "Nick Cave" as a solo act, so a rule that split a
    /// credit whenever one part was a known act would break up the band.
    @Test func aBandIsNotSplitBecauseOneHalfOfItIsAlsoASoloAct() {
        let wall = ArtistWall.build([
            Row("Nick Cave/Solo", "Nick Cave", "Nick Cave", 10),
            Row("Nick Cave & The Bad Seeds/Let Love In", "Nick Cave & The Bad Seeds",
                "Nick Cave & The Bad Seeds", 10),
        ])

        #expect(wall.map(\.name) == ["Nick Cave", "Nick Cave & The Bad Seeds"])
    }

    /// A band whose name reads like a sentence is not split either. Neither part of the name is an act the
    /// collection knows.
    @Test func aBandWhoseNameHoldsAJoiningWordIsLeftAlone() throws {
        let wall = ArtistWall.build([
            Row("Sleeping With Sirens/Feel", "Sleeping With Sirens", "Sleeping With Sirens", 12),
        ])

        try #require(wall.count == 1)
        #expect(wall[0].name == "Sleeping With Sirens")
    }

    /// A collaborator with no other records in the collection keeps the joint box.
    @Test func aCreditWhoseOtherHalfIsAStrangerStandsWhole() {
        let wall = ArtistWall.build([
            Row("Kanye West/Graduation", "Kanye West", "Kanye West", 13),
            Row("Kanye West & Nobody Else/Record", "Kanye West & Nobody Else",
                "Kanye West & Nobody Else", 9),
        ])

        #expect(wall.map(\.name) == ["Kanye West", "Kanye West & Nobody Else"])
    }

    /// A guest credit is often how the collection learns about a collaborator, so it counts as a known act.
    @Test func aFeaturedCreditIsEnoughToKnowSomebodyBy() throws {
        let wall = ArtistWall.build([
            Row("Kanye West/Graduation", "Kanye West", "Kanye West", 12),
            Row("Kanye West/Graduation", "Kanye West", "Kanye West feat. Kid Cudi", 1),
            Row("Kanye West & Kid Cudi/Kids See Ghosts", "Kanye West & Kid Cudi",
                "Kanye West & Kid Cudi", 7),
        ])

        #expect(try find(wall, "Kid Cudi").together == ["Kanye West & Kid Cudi/Kids See Ghosts"])
        #expect(try find(wall, "Kid Cudi").appearances == ["Kanye West/Graduation"])
    }

    /// Each act's page picks its own songs from a joint record.
    @Test(arguments: [("Kanye West & Ty Dolla $ign", "Ty Dolla $ign"),
                      ("Kanye West with Common", "Common"),
                      ("Kanye West with Common", "Kanye West")])
    func aJointCreditNamesEachOfItsActs(pair: (credit: String, artist: String)) {
        #expect(ArtistWall.names(pair.credit, artist: pair.artist))
    }

    /// A record filed under an artist belongs to that artist, even when its tracks credit only the guests and
    /// never the artist's name.
    @Test func theRecordIsFiledUnderItsAlbumArtistWhateverItsTracksSay() throws {
        let wall = ArtistWall.build([
            Row("Santana/Supernatural", "Santana", "Santana feat. Rob Thomas", 1),
            Row("Santana/Supernatural", "Santana", "Santana feat. Everlast", 1),
        ])

        try #require(wall.count == 1)
        #expect(wall[0].name == "Santana")
        #expect(wall[0].albums == ["Santana/Supernatural"])
        #expect(wall[0].tracks == 2)
    }

    /// An appearance that is also the artist's own record is promoted to a record, whatever the row order.
    @Test func aGuestCreditReadBeforeTheAlbumArtistStillLeavesOneRecord() throws {
        let wall = ArtistWall.build([
            Row("Eminem/The Eminem Show", "Various Artists", "Eminem feat. Dr. Dre", 1),
            Row("Eminem/The Eminem Show", "Eminem", "Eminem", 19),
        ])

        let eminem = try find(wall, "Eminem")
        #expect(eminem.albums == ["Eminem/The Eminem Show"])
        #expect(eminem.appearances.isEmpty)
        #expect(eminem.tracks == 20)
    }

    /// The compilations are a box of their own. The marker is not an artist, so without this box the records
    /// filed under it would not appear on any page.
    @Test func theCompilationMarkerIsTheCompilationsShelf() throws {
        let wall = ArtistWall.build([
            Row("Various/Now 40", "Various Artists", "Various", 1),
            Row("Various/Now 40", "Various Artists", "Blur", 1),
        ])

        try #require(wall.count == 1)
        #expect(wall[0].name == ArtistWall.compilations)
        #expect(wall[0].albums == ["Various/Now 40"])
    }

    /// However the marker is spelt, it is one shelf. It is never split or taken for a band.
    @Test(arguments: ["Various", "Various Artists", "various artist"])
    func everySpellingOfTheMarkerIsTheOneShelf(spelling: String) throws {
        let wall = ArtistWall.build([
            Row("Various/Now 40", "Various Artists", "Blur", 1),
            Row("Various/Now 41", spelling, "Pulp", 1),
        ])

        try #require(wall.count == 1)
        #expect(wall[0].name == ArtistWall.compilations)
        #expect(wall[0].albums == ["Various/Now 40", "Various/Now 41"])
    }

    /// An artist on a compilation who has records of their own keeps them separate from it. The
    /// compilation is an appearance for them.
    @Test func aCompilationIsAnAppearanceForTheArtistsOnIt() throws {
        let wall = ArtistWall.build([
            Row("Blur/Parklife", "Blur", "Blur", 16),
            Row("Various/Now 40", "Various Artists", "Blur", 1),
        ])

        let blur = try find(wall, "Blur")
        #expect(blur.albums == ["Blur/Parklife"])
        #expect(blur.appearances == ["Various/Now 40"])
        #expect(try find(wall, ArtistWall.compilations).albums == ["Various/Now 40"])
    }

    @Test func anUntaggedFolderNamesNobody() {
        #expect(ArtistWall.build([Row("Unsorted", nil, nil, 4)]).isEmpty)
    }

    @Test func theWallReadsInNameOrder() {
        let wall = ArtistWall.build([
            Row("c/x", "Zappa", "Zappa"),
            Row("a/x", "Abba", "Abba"),
            Row("b/x", "middle", "middle"),
        ])

        #expect(wall.map(\.name) == ["Abba", "middle", "Zappa"])
    }

    @Test(arguments: [("ABBA", Character("A")), ("the Beatles", Character("T")),
                      ("Sigur Rós", Character("S")), ("Ólafur Arnalds", Character("O")),
                      ("!!!", Character("#")), ("2Pac", Character("#")),
                      ("", Character("#"))])
    func namesFileUnderTheRailsLetters(pair: (name: String, expected: Character)) {
        #expect(ArtistWall.initial(pair.name) == pair.expected)
    }

    @Test func aNameThatIsNotThereFilesUnderTheBucket() {
        #expect(ArtistWall.initial(nil) == "#")
    }

    /// The wall is read in the rail's order, and the rail puts its bucket last. A plain sort would put names
    /// starting with numbers at the top, and the rail would then point to items above it.
    @Test func namesStartingWithNeitherALetterReadLast() {
        let wall = ArtistWall.build([
            Row("num/x", "2Pac", "2Pac"),
            Row("m/x", "Madonna", "Madonna"),
            Row("sym/x", "!!!", "!!!"),
            Row("a/x", "ABBA", "ABBA"),
        ])

        #expect(wall.map(\.name) == ["ABBA", "Madonna", "!!!", "2Pac"])
    }

    /// Searches that ignore case, accents and punctuation, for when the user is unsure how a band
    /// spells its name.
    @Test(arguments: [("Sigur Rós", "sigur ros"), ("AC/DC", "acdc"),
                      ("Guns N' Roses", "guns n roses"), ("The Beatles", "beatles"),
                      ("Beyoncé", "BEYONCE"), ("Stevie Wonder", "wonder")])
    func theSearchLooksPastCaseAccentsAndPunctuation(pair: (name: String, typed: String)) {
        #expect(ArtistWall.matches(pair.name, pair.typed))
    }

    @Test(arguments: [("Stevie Wonder", "stevie nicks"), ("ABBA", "zappa")])
    func andStillSaysNoToSomebodyElse(pair: (name: String, typed: String)) {
        #expect(!ArtistWall.matches(pair.name, pair.typed))
    }

    /// A query with only a bracket in it must not hide the whole wall while the user is still typing.
    @Test(arguments: ["", "   ", "("])
    func aQueryThatSaysNothingMatchesEverybody(typed: String) {
        #expect(ArtistWall.matches("ABBA", typed))
    }

    @Test func noQueryAtAllMatchesEverybody() {
        #expect(ArtistWall.matches("ABBA", nil))
    }

    @Test func theRailIsTwentySixLettersAndABucket() {
        #expect(ArtistWall.alphabet.count == 27)
        #expect(ArtistWall.alphabet[0] == "A")
        #expect(ArtistWall.alphabet[25] == "Z")
        #expect(ArtistWall.alphabet[26] == "#")
    }

    /// A name with a comma in it stays whole when the artist is also a guest on someone else's record (the
    /// desktop has the same case). Guest credits cut the name in half, and then the artist's own credit would
    /// look like two people.
    @Test func aNameWithACommaInItSurvivesBeingAGuestOnSomebodyElsesRecord() throws {
        let wall = ArtistWall.build([
            Row("Tyler, The Creator/IGOR", "Tyler, The Creator", "Tyler, The Creator", 12),
            Row("A$AP Rocky/Testing", "A$AP Rocky", "A$AP Rocky", 15),
            Row("A$AP Rocky/Testing", "A$AP Rocky", "A$AP Rocky; Tyler, The Creator; Jozzy", 1),
            Row("The Weeknd/Hurry Up Tomorrow", "The Weeknd", "The Weeknd", 22),
            Row("The Weeknd/Hurry Up Tomorrow", "The Weeknd", "The Weeknd, Tyler, The Creator", 1),
        ])

        #expect(wall.map(\.name).sorted() == ["A$AP Rocky", "The Weeknd", "Tyler, The Creator"])
        let tyler = try find(wall, "Tyler, The Creator")
        #expect(tyler.albums == ["Tyler, The Creator/IGOR"])
        #expect(tyler.together.isEmpty)   // a guest verse is not a record the two of them made
        #expect(tyler.appearances == ["A$AP Rocky/Testing", "The Weeknd/Hurry Up Tomorrow"])
    }

    /// The same rejoin for a band. The guest credit is split into parts and then joined back, because the
    /// collection files a record under exactly that name.
    @Test func aBandNamedWithSeparatorsIsRejoinedInsideALongerCredit() throws {
        let wall = ArtistWall.build([
            Row("Earth, Wind & Fire/I Am", "Earth, Wind & Fire", "Earth, Wind & Fire", 9),
            Row("Diana Ross/Diana", "Diana Ross", "Diana Ross", 10),
            Row("Diana Ross/Diana", "Diana Ross", "Diana Ross, Earth, Wind & Fire", 1),
        ])

        #expect(wall.map(\.name).sorted() == ["Diana Ross", "Earth, Wind & Fire"])
        #expect(try find(wall, "Earth, Wind & Fire").appearances == ["Diana Ross/Diana"])
    }

    /// A name is only rejoined when the collection has a record under it. Without such a record,
    /// the credit is still cut at the separators.
    @Test func aCreditTheCollectionFilesNothingUnderIsStillSplit() {
        let wall = ArtistWall.build([
            Row("A$AP Rocky/Testing", "A$AP Rocky", "A$AP Rocky", 15),
            Row("A$AP Rocky/Testing", "A$AP Rocky", "A$AP Rocky; Tyler, The Creator", 1),
        ])

        #expect(wall.map(\.name) == ["A$AP Rocky"])
    }

    /// The grouped split is the flat split cut at "feat".
    @Test func theGroupedSplitIsTheFlatSplitCutAtTheGuestMarker() {
        #expect(ArtistCredit.splitGuests("Tyler, The Creator feat. Frank Ocean") == [["Tyler", "The Creator"], ["Frank Ocean"]])
        #expect(ArtistCredit.splitGuests("Ann & Bob feat. Cal, Dee").flatMap { $0 } == ArtistCredit.split("Ann & Bob feat. Cal, Dee"))
    }
}
