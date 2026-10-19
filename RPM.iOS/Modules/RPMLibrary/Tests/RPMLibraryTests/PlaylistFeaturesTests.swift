import Testing
import Foundation
@testable import RPMLibrary

/// Which artists a playlist features, and the "Featuring" line built from them. The cases match the
/// desktop's `PlaylistFeaturesTests`.
struct PlaylistFeaturesTests {
    @Test func theArtistTheListIsBuiltAroundWinsHoweverTheyWereTyped() {
        let featured = PlaylistFeatures.of(
            ["Kanye West", "Kanye West & Ty Dolla $ign", "Jay-Z & Kanye West", "Rihanna"], most: 3)

        #expect(featured.named.first == "Kanye West")
    }

    @Test func everyoneNamedLeavesNobodyOver() {
        let featured = PlaylistFeatures.of(["Blur", "Pulp"], most: 3)

        #expect(featured.named == ["Blur", "Pulp"])
        #expect(featured.more == 0)
    }

    @Test func theRestAreCountedRatherThanNamed() {
        let featured = PlaylistFeatures.of(["A Band", "B Band", "C Band", "D Band", "E Band"], most: 2)

        #expect(featured.named.count == 2)
        #expect(featured.more == 3)
    }

    @Test func oneArtistTypedTwoWaysIsOneArtist() {
        let featured = PlaylistFeatures.of(["Blur", "BLUR", "blur"], most: 3)

        #expect(featured.named == ["Blur"])
        #expect(featured.more == 0)
    }

    @Test func aSongThatNamesNobodyIsNotAnAct() {
        let featured = PlaylistFeatures.of(["Blur", nil, "", "   "], most: 3)

        #expect(featured.named == ["Blur"])
        #expect(featured.more == 0)
    }

    @Test func tiesFallBackToTheNameSoTheLineIsTheSameLineEveryTime() {
        #expect(PlaylistFeatures.of(["Zebra", "Aardvark", "Mongoose"], most: 3).named
                == ["Aardvark", "Mongoose", "Zebra"])
    }

    @Test func aListThatNamesNobodyFeaturesNobody() {
        let featured = PlaylistFeatures.of([nil, ""], most: 3)

        #expect(featured.named.isEmpty)
        #expect(featured.more == 0)
    }

    @Test func namingNoneOfThemStillCountsThemAll() {
        let featured = PlaylistFeatures.of(["Blur", "Pulp"], most: 0)

        #expect(featured.named.isEmpty)
        #expect(featured.more == 2)
    }

    // ── the line ──

    @Test func theLineNamesThreeAndCountsTheRest() {
        let line = PlaylistFeatures.line(blurb: nil,
                                         credits: ["Blur", "Blur", "Pulp", "Suede", "Oasis", "Elastica"])

        #expect(line == "Featuring Blur, Elastica, Oasis and 2 more")
    }

    @Test func aShortListIsNamedWhole() {
        #expect(PlaylistFeatures.line(blurb: nil, credits: ["Blur", "Pulp"]) == "Featuring Blur, Pulp")
    }

    @Test func theSentenceComesFirstAndTheNamesAfterIt() {
        let line = PlaylistFeatures.line(blurb: "Perfect music for the small hours.",
                                         credits: ["Blur"])

        #expect(line == "Perfect music for the small hours. Featuring Blur")
    }

    @Test func aMoodListWhoseSongsCreditNobodyKeepsItsSentence() {
        #expect(PlaylistFeatures.line(blurb: "Perfect music for the small hours.", credits: [nil])
                == "Perfect music for the small hours.")
    }

    @Test func nothingToSayIsNoLine() {
        #expect(PlaylistFeatures.line(blurb: nil, credits: [nil, ""]) == nil)
    }
}
