import Foundation
import Testing
@testable import RPMKit

private func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-6 }

@Test func aLetterIsFullyLitOnItsMomentAndUnlitASoftnessBefore() {
    // Not the last word, so not a held note. Four letters over 0.4 s is 0.1 s a letter.
    let word = WordSpan(start: 0, length: 4, from: 10.0, to: 10.4)
    func at(_ letter: Int, _ now: Double) -> Double {
        KaraokeLight.through(word, letter: letter, last: false, now: now, earliest: word.from)
    }
    #expect(near(at(0, 10.0), 1))
    #expect(near(at(0, 10.0 - KaraokeLight.glyphSoftness), 0))
    #expect(near(at(0, 10.0 - KaraokeLight.glyphSoftness / 2), 0.5))
    // The third letter opens two shares in, and arrives over the softness, which is wider than its
    // share.
    #expect(near(at(2, 10.2), 1))
    #expect(near(at(2, 10.1), 0.5))
}

@Test func theLightMovesThroughAWordSoSeveralLettersArePartLit() {
    let word = WordSpan(start: 0, length: 6, from: 5.0, to: 5.3)
    let lit = (0..<6).map {
        KaraokeLight.through(word, letter: $0, last: false, now: 5.1, earliest: word.from)
    }
    #expect(zip(lit, lit.dropFirst()).allSatisfy { $0 >= $1 })
    #expect(lit.filter { $0 > 0 && $0 < 1 }.count >= 3)
}

@Test func aHeldLastWordCaughtOnlyAtItsEndIsSweptThroughTheHold() {
    // "it" ends at 85.5, then "on" is measured as 89.28 to 89.32. The light goes through "on" over
    // the hold, not in 40 ms.
    let spans = [WordSpan(start: 0, length: 2, from: 85.0, to: 85.5),
                 WordSpan(start: 3, length: 2, from: 89.28, to: 89.32)]
    var lit = KaraokeLight.light(spans, now: 86.3, fades: true)
    #expect(lit[2] > KaraokeLight.rest && lit[2] < 1)
    lit = KaraokeLight.light(spans, now: 87.0, fades: true)
    #expect(lit[3] > KaraokeLight.rest && lit[3] < 1)
    lit = KaraokeLight.light(spans, now: 89.32, fades: true)
    #expect(near(lit[3], 1))
}

@Test func aSliverOfAWordAfterAPauseEasesInInsteadOfSnapping() {
    // In the middle of a line: "up" measured as 10.96 to 11.0 after a pause is swept over half a
    // second before its end, not 40 ms.
    let spans = [WordSpan(start: 0, length: 2, from: 9.0, to: 9.5),
                 WordSpan(start: 3, length: 2, from: 10.96, to: 11.0),
                 WordSpan(start: 6, length: 3, from: 11.2, to: 11.6)]
    var lit = KaraokeLight.light(spans, now: 10.2, fades: true)
    #expect(near(lit[2], KaraokeLight.rest))
    lit = KaraokeLight.light(spans, now: 10.6, fades: true)
    #expect(lit[2] > KaraokeLight.rest && lit[3] < 1)
    lit = KaraokeLight.light(spans, now: 11.0, fades: true)
    #expect(near(lit[3], 1))
}

@Test func theLineFadesBackToRestSlowlyAfterItsLastWord() {
    let spans = [WordSpan(start: 0, length: 2, from: 0.0, to: 0.5)]
    #expect(near(KaraokeLight.light(spans, now: 0.5, fades: true)[1], 1))
    #expect(near(KaraokeLight.light(spans, now: 0.5 + KaraokeLight.lineFade / 2, fades: true)[1],
                 KaraokeLight.rest + (1 - KaraokeLight.rest) * 0.5))
    #expect(near(KaraokeLight.light(spans, now: 0.5 + KaraokeLight.lineFade, fades: true)[1],
                 KaraokeLight.rest))
    // A line that is still being sung stays lit after its last word.
    #expect(KaraokeLight.light(spans, now: 0.5 + KaraokeLight.lineFade * 3, fades: false)
        .allSatisfy { near($0, 1) })
}

@Test func aHeldWordIsSweptSlowlyOverItsHold() {
    // Two letters held for a second: half a second a letter, so the second letter is lit at 20.5 s.
    let word = WordSpan(start: 0, length: 2, from: 20.0, to: 21.0)
    func at(_ letter: Int, _ now: Double) -> Double {
        KaraokeLight.through(word, letter: letter, last: true, now: now, earliest: word.from)
    }
    #expect(near(at(0, 20.0), 1))
    #expect(near(at(1, 20.0), 0))
    #expect(near(at(1, 20.25), 0.5))
    #expect(near(at(1, 20.5), 1))
}

@Test func aStretchedWordIsCrossedNoSlowerThanTheHeldRate() {
    // Three letters measured over ten seconds: the aligner lost the thread. The last letter is lit
    // by two held steps.
    let word = WordSpan(start: 0, length: 3, from: 0.0, to: 10.0)
    #expect(near(KaraokeLight.through(word, letter: 2, last: false, now: 2 * KaraokeLight.heldGlyph,
                                      earliest: word.from), 1))
}

@Test func lightFillsEveryLetterFromRestToOne() {
    let spans = LyricTiming.sweep("so far away", from: 0.0, until: 2.0)
    #expect(KaraokeLight.letters(spans) == 9)
    #expect(KaraokeLight.light(spans, now: -1.0, fades: true).allSatisfy { near($0, KaraokeLight.rest) })
    // Every letter is lit as the last word ends, and back at rest once the line has faded after it.
    #expect(KaraokeLight.light(spans, now: spans[spans.count - 1].to, fades: true).allSatisfy { near($0, 1) })
    #expect(KaraokeLight.light(spans, now: 10.0, fades: true).allSatisfy { near($0, KaraokeLight.rest) })
}

// ── which line is shown ──

private let sheet = LyricSheet.parse("""
    [00:10.00]first line here
    [00:14.00]second line
    """)

@Test func measuredWordsOutsideTheLinesOwnTimeAreNotTaken() {
    let measured = [MeasuredLine(index: 0, seconds: 10.0, text: "first line here",
                                 words: [MeasuredWord(from: 3.0, to: 3.5),
                                         MeasuredWord(from: 3.5, to: 4.0),
                                         MeasuredWord(from: 4.0, to: 4.5)])]
    // All three words end more than a second before the line starts.
    #expect(KaraokeLines.heard(measured, text: "first line here", seconds: 10.0, next: 14.0) == nil)
}

@Test func theLineBeforeStaysUpWhileItsLastMeasuredWordIsSung() {
    let measured = [
        MeasuredLine(index: 0, seconds: 10.0, text: "first line here",
                     words: [MeasuredWord(from: 10.0, to: 11.0), MeasuredWord(from: 11.0, to: 12.0),
                             MeasuredWord(from: 12.0, to: 14.5)]),
        MeasuredLine(index: 1, seconds: 14.0, text: "second line",
                     words: [MeasuredWord(from: 14.8, to: 15.2), MeasuredWord(from: 15.2, to: 16.0)]),
    ]
    let score = LyricScore.of(sheet)
    let heard = KaraokeLines.heard(score, measured: measured)
    let second = score.parts.firstIndex { if case .words(let line) = $0.piece { line.text == "second line" } else { false } }!

    // At 14.2 the stamp says the second line, but the first is still on its last word.
    #expect(KaraokeLines.held(score, piece: second, seconds: 14.2, heard: heard) == second - 1)
    // Once the second line's first word starts, it is shown.
    #expect(KaraokeLines.held(score, piece: second, seconds: 14.9, heard: heard) == second)
}

@Test func withNothingMeasuredTheStampsDecide() {
    let score = LyricScore.of(sheet)
    let heard = KaraokeLines.heard(score, measured: [])
    #expect(KaraokeLines.held(score, piece: 1, seconds: 14.2, heard: heard) == 1)
    #expect(KaraokeLines.held(score, piece: nil, seconds: 1, heard: heard) == nil)
}

@Test func anUnmeasuredLineIsSweptByLength() {
    let score = LyricScore.of(sheet)
    let heard = KaraokeLines.heard(score, measured: [])
    let first = score.parts.first { if case .words = $0.piece { true } else { false } }!
    let spans = KaraokeLines.spans(of: first, in: score, heard: heard)
    #expect(spans.count == 3)
    #expect(spans.first?.from == 10.0)
}
