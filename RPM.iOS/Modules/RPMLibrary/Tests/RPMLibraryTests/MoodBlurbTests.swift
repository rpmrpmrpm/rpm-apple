import Testing
import Foundation
@testable import RPMLibrary

/// Which kinds of music a mood list names, and the sentence built from them. The cases match the
/// desktop's `MoodBlurbTests`, so both apps describe a list the same way.
struct MoodBlurbTests {
    private func tags(_ rows: (String, Int)...) -> [String?] {
        rows.flatMap { tag, count in Array(repeating: Optional(tag), count: count) }
    }

    @Test func theBiggestKindsAreNamedFirst() {
        #expect(MoodBlurb.spoken(tags(("Jazz", 5), ("Rock", 20), ("Pop", 10))) == ["rock", "pop", "jazz"])
    }

    @Test func noMoreThanThreeAreNamed() {
        let spoken = MoodBlurb.spoken(tags(("Rock", 20), ("Pop", 18), ("Jazz", 16), ("Blues", 14),
                                           ("Folk", 12)))

        #expect(spoken == ["rock", "pop", "jazz"])
    }

    /// A kind that is only one song in fifty is left out of the list.
    @Test func aKindBarelyPresentIsNotNamed() {
        #expect(MoodBlurb.spoken(tags(("Rock", 49), ("Reggae", 1))) == ["rock"])
    }

    @Test func theSpellingsOfOneKindAreCountedTogether() {
        #expect(MoodBlurb.spoken(tags(("Deep House", 8), ("Acid House", 7), ("Rock", 5))) == ["house", "rock"])
    }

    @Test func anUntaggedListNamesNothing() {
        #expect(MoodBlurb.spoken([]).isEmpty)
        #expect(MoodBlurb.spoken([nil, nil, nil]).isEmpty)
        #expect(MoodBlurb.spoken(tags(("Norwegian Sea Shanties", 10))).isEmpty)
    }

    @Test func theNamesAreJoinedAsASentenceWouldJoinThem() {
        #expect(MoodBlurb.listed([]) == "")
        #expect(MoodBlurb.listed(["rock"]) == "rock")
        #expect(MoodBlurb.listed(["rock", "pop"]) == "rock and pop")
        #expect(MoodBlurb.listed(["rock", "pop", "jazz"]) == "rock, pop and jazz")
    }

    @Test func aMoodListIsDescribedByWhatIsOnIt() {
        let sentence = MoodBlurb.sentence(kind: "Energetic", genres: tags(("Rock", 10), ("Pop", 5)))

        #expect(sentence == "The rock and pop to get you amped up!")
    }

    /// A sleep list spans every genre, so it names none of them.
    @Test func sleepNamesNoGenres() {
        #expect(MoodBlurb.sentence(kind: "Sleep", genres: []) == "Perfect music for the small hours.")
    }

    /// Only mood lists get a sentence. Other lists say what they are in their title.
    @Test func onlyTheMoodsAreDescribed() {
        #expect(MoodBlurb.sentence(kind: "RightNow", genres: tags(("Rock", 10))) == nil)
        #expect(MoodBlurb.sentence(kind: "Classical", genres: tags(("Classical", 10))) == nil)
    }

    /// A mood list with no tagged tracks gets no sentence, rather than a sentence with a gap in it.
    @Test func aMoodListWithNoTagsHasNoSentence() {
        #expect(MoodBlurb.sentence(kind: "Calm", genres: [nil, nil]) == nil)
    }
}
