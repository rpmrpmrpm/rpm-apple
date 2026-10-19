import Testing
@testable import RPMKit

/// Cutting a sheet into what is sung and what is waited through.
///
/// These guard against a fault: if a break were only a line the writer stamped, an
/// instrumental nobody had marked would leave the screen with the words gone and
/// nothing in their place, and the verse after it would show through the whole break.

private func score(_ lrc: String) -> LyricScore { LyricScore.of(LyricSheet.parse(lrc)) }

private func rests(_ score: LyricScore) -> [(Double, Double)] {
    score.parts.compactMap {
        if case .rest(let from, let until) = $0.piece { return (from, until) }
        return nil
    }
}

@Test func aSheetWithNoBreaksInItIsOneStretch() {
    let sung = score("[00:10.00]a\n[00:20.00]b\n[00:30.00]c")

    #expect(sung.section(at: 10) == 0)
    #expect(sung.section(at: 30) == 0)
    // The outro is the one rest, and it closes that stretch rather than opening a new one.
    #expect(rests(sung).count == 1)
}

/// The line the writer stamped with no words in it: a rest, not a line with nothing on
/// it. Drawing it as a line says the singing stopped to nobody.
@Test func aWordlessLineIsARestRatherThanALine() {
    let sung = score("[00:10.00]a\n[00:30.00]\u{266A}\n[01:30.00]b")

    #expect(rests(sung).first?.0 == 30)
    #expect(rests(sung).first?.1 == 90)
    #expect(sung.section(at: 20) == 0)
    #expect(sung.section(at: 40) == 0)   // inside the rest, which closes the first stretch
    #expect(sung.section(at: 95) == 1)
}

/// Nobody stamped anything: there is simply a minute between two lines, which is a
/// solo. Without this rule the words after it would be on the screen from the moment
/// the ones before it were sung.
@Test func aLongWaitBetweenTwoLinesIsABreakEvenThoughNobodyMarkedIt() {
    let sung = score("[00:10.00]a\n[01:30.00]b")

    // The line is left up for as long as it takes to sing before the rest begins.
    #expect(rests(sung).contains { $0 == (10 + LyricScore.sung, 90) })
    #expect(sung.section(at: 12) == 0)
    #expect(sung.section(at: 60) == 0)
    #expect(sung.section(at: 95) == 1)
}

/// A breath is not a break. Ordinary singing has gaps of a few seconds all through it
/// and cutting the sheet at every one of them would be a screen that never holds still.
@Test func anOrdinaryGapIsNotABreak() {
    let sung = score("[00:10.00]a\n[00:19.00]b\n[00:28.00]c")

    #expect(sung.section(at: 28) == 0)
    #expect(rests(sung).count == 1)   // the outro alone
}

/// A rest never begins on the same second as the line before it: the words would go on
/// the beat the last line of a verse arrived.
@Test func theLineBeforeARestIsLeftUpLongEnoughToSingIt() {
    let sung = score("[00:10.00]a\n[01:30.00]b")

    #expect(sung.index(at: 10).map { sung.parts[$0].piece } == .words(LyricSheet.parse("[00:10.00]a").lines[0]))
    #expect(rests(sung).first?.0 == 18)
}

/// The threshold is the wait the desktop uses, and it is the one the fade
/// obeys: whenever the words go, there are dots.
@Test func theBreakIsTheSameLengthTheDesktopUses() {
    #expect(LyricScore.rest == 20)

    let just = score("[00:10.00]a\n[00:30.00]b")     // exactly the threshold
    #expect(just.section(at: 35) == 1)

    let under = score("[00:10.00]a\n[00:29.00]b")
    #expect(under.section(at: 35) == 0)
}

/// After the last line the wait never ends, and a sheet that simply stops leaves its
/// last line lit for the length of it.
@Test func aSheetEndsInARestThatNeverFinishes() {
    let sung = score("[00:10.00]a")

    #expect(rests(sung).last?.1 == .infinity)
    #expect(sung.section(at: 11) == 0)
}

/// Before the first line there is no piece at all: an intro is a real part of a song and
/// the score does not pretend the first line has started.
@Test func nothingIsBeingSungBeforeTheFirstLine() {
    #expect(score("[00:10.00]a").index(at: 3) == nil)
    #expect(score("[00:10.00]a").section(at: 3) == nil)
}

/// The row identity a list needs, and the order it draws in.
@Test func thePiecesAreNumberedInTheOrderTheyAreSung() {
    let sung = score("[00:10.00]a\n[01:30.00]b")

    #expect(sung.parts.map(\.id) == Array(0..<sung.parts.count))
    #expect(sung.parts.map(\.seconds) == [10, 18, 90, 98])
}
