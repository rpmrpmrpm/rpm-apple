import Foundation
import Testing
@testable import RPMKit

// The second voice: the desktop's `AsideGroups`, `IsAside`, `AsideText` and `Verse`, with the cases
// the Android phone tests them by.

private func split(_ text: String) -> LyricVoices.Split? {
    LyricVoices.split(text, spans: LyricTiming.sweep(text, from: 0, until: 10))
}

private func texts(_ score: LyricScore) -> [String] {
    score.parts.compactMap { part in
        if case .words(let line) = part.piece { return line.text } else { return nil }
    }
}

@Test func aWholeBracketedLineIsAnAside() {
    #expect(LyricVoices.isAside("(Oh, fuck 'em)"))
    #expect(LyricVoices.isAside("  (Oh)  "))
    #expect(!LyricVoices.isAside("I wish I understood (yeah)"))
    #expect(!LyricVoices.isAside("(Alter ego) dead to me, rah"))
    #expect(!LyricVoices.isAside("(a) and (b)"))
    #expect(!LyricVoices.isAside("()"))
}

@Test func theBracketedWordsGoUnderTheVerse() {
    let parts = split("Milan, darling, Milan (fuck, fuck)")
    #expect(parts?.verse.text == "Milan, darling, Milan")
    #expect(parts?.voice.text == "fuck, fuck")
}

@Test func twoGroupsAreJoinedWithAComma() {
    let parts = split("(Alter ego) dead to me (rah)")
    #expect(parts?.verse.text == "dead to me")
    #expect(parts?.voice.text == "Alter ego, rah")
}

@Test func onlyTheOutermostBracketsCount() {
    let parts = split("I said (go (go) now) okay")
    #expect(parts?.verse.text == "I said okay")
    #expect(parts?.voice.text == "go go now")
}

@Test func aLineWithNoVoiceIsNotSplit() {
    #expect(split("Plain line") == nil)
    #expect(split("(All of it)") == nil)
    #expect(split("Empty ( ) bracket") == nil)
}

@Test func theVerseAfterABracketInAWordGoesOnWithoutASpace() {
    #expect(split("on and on (and on).")?.verse.text == "on and on.")
}

@Test func eachLetterIsLitAsTheSameLetterOfTheWholeLine() {
    let text = "Year of the swamp (ooh)"
    let spans = LyricTiming.sweep(text, from: 0, until: 10)
    let parts = LyricVoices.split(text, spans: spans)
    // "Year" "of" "the" "swamp" are letters 0 to 13; "(ooh)" is 14 to 18, its brackets 14 and 18.
    #expect(parts?.verse.letters.count == 14)
    #expect(parts?.voice.letters == [15, 16, 17])
    #expect(parts?.voice.spans.count == 1)
    #expect(parts?.voice.spans.first?.from == spans.last?.from)
}

@Test func aBackingLineLosesItsBrackets() {
    let text = "(Oh, fuck 'em)"
    let row = LyricVoices.unbracketed(text, spans: LyricTiming.sweep(text, from: 0, until: 10))
    #expect(row.text == "Oh, fuck 'em")
    #expect(row.spans.count == 3)
}

@Test func aBackingLineGoesWithTheLineBeforeIt() {
    let sheet = LyricSheet.parse("""
        [00:10.00]To crown you the queen
        [00:12.00](I don't fuck with these)
        [00:13.00]Now with that crown
        """)
    let score = LyricScore.of(sheet, asides: true)
    #expect(texts(score) == ["To crown you the queen", "Now with that crown"])
    #expect(score.parts[0].asides == [LyricScore.Aside(line: sheet.lines[1], until: 13.0)])
    // The line before it is swept until the backing line starts.
    #expect(KaraokeLines.next(after: score.parts[0], in: score) == 12.0)
    // Without asides, the score is the sheet's.
    #expect(texts(LyricScore.of(sheet)).count == 3)
}

@Test func aBackingLineWithNoLineBeforeItKeepsItsRow() {
    let sheet = LyricSheet.parse("""
        [00:01.00](Ooh)
        [00:03.00]First line
        """)
    #expect(texts(LyricScore.of(sheet, asides: true)).count == 2)
}

@Test func aMeasuredBackingLineShowsAsItsWordsAreSung() {
    let sheet = LyricSheet.parse("""
        [00:10.00]To crown you
        [00:12.00](Oh yeah)
        [00:14.00]Next
        """)
    let aside = LyricScore.of(sheet, asides: true).parts[0].asides[0]
    let measured = [MeasuredLine(index: 1, seconds: 12.0, text: "(Oh yeah)",
                                 words: [MeasuredWord(from: 11.6, to: 12.0),
                                         MeasuredWord(from: 12.0, to: 12.8)])]
    let voice = KaraokeLines.voice(aside, measured: measured)
    #expect(abs(voice.from - (11.6 - KaraokeLines.lead)) < 1e-9)
    #expect(abs(voice.until - 12.8) < 1e-9)

    // Unmeasured, it shows from its stamp, and stays while its last word may still be held.
    let swept = KaraokeLines.voice(aside, measured: [])
    #expect(swept.from == 12.0)
    #expect(abs(swept.until - (14.0 - KaraokeLines.asideGap)) < 1e-9)
}
