import Testing
import Foundation
@testable import RPMKit

/// The LRC reader, against the cases the other head's parser was written for. Every
/// one of these is a real shape a sheet turns up in.
@Suite("An LRC, read")
struct LyricSheetTests {

    @Test func plainLyricsAreNotASheet() {
        // The whole value of a sheet over a wall of text is the timestamps. A caller
        // that asked for something to follow along with is told there is nothing.
        #expect(!LyricSheet.parse("Hello darkness my old friend\nI've come to talk").isSynced)
        #expect(!LyricSheet.parse("").isSynced)
        #expect(!LyricSheet.parse(nil).isSynced)
    }

    @Test func aLineIsTimedAndItsWordsAreItsOwn() throws {
        let sheet = LyricSheet.parse("[00:12.30]Hello darkness\n[00:15.00]My old friend")

        #expect(sheet.lines.count == 2)
        #expect(sheet.lines[0].seconds == 12.3)
        #expect(sheet.lines[0].text == "Hello darkness")
        #expect(sheet.lines[1].seconds == 15)
    }

    /// The digits say the scale, so a two-digit sheet and a three-digit one are both
    /// read correctly. "5" is five tenths, not five hundredths.
    @Test func theFractionsDigitsSayItsScale() {
        #expect(LyricSheet.parse("[00:01.5]a").lines[0].seconds == 1.5)
        #expect(LyricSheet.parse("[00:01.05]a").lines[0].seconds == 1.05)
        #expect(LyricSheet.parse("[00:01.005]a").lines[0].seconds == 1.005)
        // The colon form some writers use for the fraction.
        #expect(LyricSheet.parse("[00:01:50]a").lines[0].seconds == 1.5)
    }

    /// A refrain is written once and stamped four times.
    @Test func aLineWithSeveralStampsLandsOnceForEachOfThem() {
        let sheet = LyricSheet.parse("[00:10.00][01:20.00][02:30.00]The chorus")

        #expect(sheet.lines.map(\.seconds) == [10, 80, 150])
        #expect(sheet.lines.allSatisfy { $0.text == "The chorus" })
    }

    /// **The sign is the LRC convention's, not arithmetic's**: a positive offset means
    /// the words are early and have to be pulled back.
    @Test func theOffsetTagShiftsTheWholeSheet() {
        let early = LyricSheet.parse("[offset:+500]\n[00:10.00]a")
        #expect(early.lines[0].seconds == 9.5)

        let late = LyricSheet.parse("[offset:-500]\n[00:10.00]a")
        #expect(late.lines[0].seconds == 10.5)

        // And never before the top of the record.
        #expect(LyricSheet.parse("[offset:+5000]\n[00:01.00]a").lines[0].seconds == 0)
    }

    /// An LRC that marks an instrumental break with an empty line at 1:12 is saying
    /// something. Dropping it would run the verse into the chorus and leave the
    /// highlight sitting on a line nobody is singing.
    @Test func aBlankLineIsKept() {
        let sheet = LyricSheet.parse("[00:10.00]a\n[00:20.00]\n[00:30.00]b")

        #expect(sheet.lines.count == 3)
        #expect(sheet.lines[1].text.isEmpty)
    }

    @Test func aSheetOutOfOrderIsPutInOrder() {
        let sheet = LyricSheet.parse("[00:30.00]c\n[00:10.00]a\n[00:20.00]b")
        #expect(sheet.lines.map(\.text) == ["a", "b", "c"])
    }

    @Test func metadataTagsAndProseAreSkipped() {
        let sheet = LyricSheet.parse("[ar:Enya]\n[ti:Orinoco Flow]\nsome prose\n[00:10.00]a")

        #expect(sheet.lines.count == 1)
        #expect(sheet.lines[0].text == "a")
    }

    // ── enhanced sheets ──

    @Test func aWordStampedLineCarriesItsWords() throws {
        let sheet = LyricSheet.parse("[00:12.00]<00:12.00>Hello <00:12.90>darkness")
        let words = try #require(sheet.lines[0].words)

        #expect(words.map(\.text) == ["Hello", "darkness"])
        #expect(words[1].seconds == 12.9)

        // And the stamps are gone from the words on the screen.
        #expect(sheet.lines[0].text == "Hello darkness")
    }

    /// A refrain stamped four times has ONE set of word times, which can be true of at
    /// most one of its four performances, and nothing in the file says which. Following
    /// the line alone beats putting the highlight confidently on the wrong word.
    @Test func aRefrainKeepsNoWordTimes() {
        let sheet = LyricSheet.parse("[00:10.00][01:20.00]<00:10.00>La <00:10.50>la")
        #expect(sheet.lines.allSatisfy { $0.words == nil })
    }

    // ── text a screen can show ──

    @Test func aStampLeftInTheWordsIsTakenOut() {
        // The bare form, the round-bracket form, and the word-by-word form.
        #expect(LyricSheet.unstamp("[00:12.30] Hello") == "Hello")
        #expect(LyricSheet.unstamp("(00:12.30) Hello") == "Hello")
        #expect(LyricSheet.unstamp("00:12.300 Hello") == "Hello")
        #expect(LyricSheet.unstamp("<00:12.30>Hello <00:12.90>darkness") == "Hello darkness")
    }

    /// The fraction is required for the bare form, and that is what keeps this a lyric.
    @Test func aTimeInTheWordsIsLeftAlone() {
        #expect(LyricSheet.unstamp("3:15 in the morning") == "3:15 in the morning")
    }

    /// "Only a note" is an empty line made visible, and writers use both, often in one
    /// file. A view that drops one and keeps the other has a gap in half its songs.
    @Test func aLineOfNothingButNotesHasNothingToRead() {
        #expect(LyricSheet.isWordless(""))
        #expect(LyricSheet.isWordless("   "))
        #expect(LyricSheet.isWordless("\u{266A}"))
        #expect(LyricSheet.isWordless("\u{1F3B5} \u{1F3B6}"))
        #expect(!LyricSheet.isWordless("la"))
        // An accidental is something a lyric can be ABOUT.
        #expect(!LyricSheet.isWordless("\u{266F}"))
    }

    // ── finding the singer ──

    @Test func theLineBeingSungIsTheLastOneToHaveStarted() {
        let sheet = LyricSheet.parse("[00:10.00]a\n[00:20.00]b\n[00:30.00]c")

        #expect(sheet.index(at: 9.9) == nil, "an intro is not the first line")
        #expect(sheet.index(at: 10) == 0)
        #expect(sheet.index(at: 19.9) == 0)
        #expect(sheet.index(at: 20) == 1)
        #expect(sheet.index(at: 300) == 2)
    }
}
