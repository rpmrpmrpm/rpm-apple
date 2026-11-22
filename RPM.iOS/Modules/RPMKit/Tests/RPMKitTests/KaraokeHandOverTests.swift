import Foundation
import Testing
@testable import RPMKit

// ── the early hand-over: a line takes over as its measured words start ──

private let sheet = LyricSheet.parse("""
    [00:10.00]first line here
    [00:14.00]second line
    """)

private func index(of text: String, in score: LyricScore) -> Int {
    score.parts.firstIndex { if case .words(let line) = $0.piece { line.text == text } else { false } }!
}

@Test func aLineSungBeforeItsStampIsShownAsTheLightArrives() {
    let measured = [
        MeasuredLine(index: 0, seconds: 10.0, text: "first line here",
                     words: [MeasuredWord(from: 10.0, to: 11.0), MeasuredWord(from: 11.0, to: 12.0),
                             MeasuredWord(from: 12.0, to: 13.0)]),
        MeasuredLine(index: 1, seconds: 14.0, text: "second line",
                     words: [MeasuredWord(from: 13.5, to: 13.8), MeasuredWord(from: 13.8, to: 14.5)]),
    ]
    let score = LyricScore.of(sheet)
    let heard = KaraokeLines.heard(score, measured: measured)
    let second = index(of: "second line", in: score)

    // The voice starts the second line at 13.5, half a second before its stamp.
    #expect(KaraokeLines.held(score, piece: second - 1, seconds: 13.0, heard: heard) == second - 1)
    #expect(KaraokeLines.held(score, piece: second - 1, seconds: 13.2, heard: heard) == second)
    // Once the stamp is reached, it stays.
    #expect(KaraokeLines.held(score, piece: second, seconds: 14.1, heard: heard) == second)
}

@Test func aLineIsNotShownEarlyWhileTheOneBeforeIsStillSung() {
    let measured = [
        MeasuredLine(index: 0, seconds: 10.0, text: "first line here",
                     words: [MeasuredWord(from: 10.0, to: 11.0), MeasuredWord(from: 11.0, to: 12.0),
                             MeasuredWord(from: 12.0, to: 13.7)]),
        MeasuredLine(index: 1, seconds: 14.0, text: "second line",
                     words: [MeasuredWord(from: 13.5, to: 13.8), MeasuredWord(from: 13.8, to: 14.5)]),
    ]
    let score = LyricScore.of(sheet)
    let heard = KaraokeLines.heard(score, measured: measured)
    let second = index(of: "second line", in: score)

    // The first line's last word runs to 13.7; the second line waits for its own first word at 13.5.
    #expect(KaraokeLines.held(score, piece: second - 1, seconds: 13.3, heard: heard) == second - 1)
    #expect(KaraokeLines.held(score, piece: second - 1, seconds: 13.5, heard: heard) == second)
}

@Test func aLineIsNeverShownMoreThanASecondBeforeItsStamp() {
    let measured = [
        MeasuredLine(index: 0, seconds: 10.0, text: "first line here",
                     words: [MeasuredWord(from: 10.0, to: 10.5), MeasuredWord(from: 10.5, to: 11.0),
                             MeasuredWord(from: 11.0, to: 11.5)]),
        MeasuredLine(index: 1, seconds: 14.0, text: "second line",
                     words: [MeasuredWord(from: 12.0, to: 13.8), MeasuredWord(from: 13.8, to: 14.5)]),
    ]
    let score = LyricScore.of(sheet)
    let heard = KaraokeLines.heard(score, measured: measured)
    let second = index(of: "second line", in: score)

    #expect(KaraokeLines.held(score, piece: second - 1, seconds: 12.5, heard: heard) == second - 1)
    #expect(KaraokeLines.held(score, piece: second - 1, seconds: 13.0, heard: heard) == second)
}

@Test func theFirstLineTakesOverFromTheIntroBeforeItsStamp() {
    let measured = [
        MeasuredLine(index: 0, seconds: 10.0, text: "first line here",
                     words: [MeasuredWord(from: 9.6, to: 10.5), MeasuredWord(from: 10.5, to: 11.0),
                             MeasuredWord(from: 11.0, to: 11.5)]),
    ]
    let score = LyricScore.of(sheet)
    let heard = KaraokeLines.heard(score, measured: measured)
    let first = index(of: "first line here", in: score)

    #expect(KaraokeLines.held(score, piece: nil, seconds: 9.0, heard: heard) == nil)
    #expect(KaraokeLines.held(score, piece: nil, seconds: 9.3, heard: heard) == first)
}

// ── every line is sung for a moment ──

private func words(_ pairs: [(Double, Double)]) -> [MeasuredWord] {
    pairs.map { MeasuredWord(from: $0.0, to: $0.1) }
}

/// JT's "Oh", as LRCLIB has it and as the cloud measured it. The sheet stamps "And they used to..."
/// at 17.28 and the next line at 17.52, and the line was not measured; the measured last word of the
/// line before runs to 17.51, and the next line's first word is measured at 17.40. The rules alone go
/// from "You get these..." straight to "If they get out of line" at 17.51.
@Test(arguments: [true, false])
func aLineSqueezedBetweenItsNeighboursIsStillSung(asides: Bool) {
    let oh = LyricSheet.parse("""
        [00:08.55]To crown you the queen of bad bitches worldwide
        [00:11.98](I don't fuck with these niggas, I don't fuck with these hoes)
        [00:12.74]Now with that crown
        [00:14.31]You get these beautiful crystal slippers, baby
        [00:17.28]And they used to, not wear, but to crack a ho in they head
        [00:17.52]If they get out of line
        [00:22.82](I don't fuck with these niggas, I don't fuck with these hoes)
        [00:25.74]Pull up double-R, this that Rih and Rocky
        """)
    let measured = [
        MeasuredLine(index: 2, seconds: 8.55, text: "To crown you the queen of bad bitches worldwide",
                     words: words([(8.07, 8.13), (8.25, 8.51), (8.59, 8.71), (8.79, 8.85), (8.91, 9.45),
                                   (9.61, 9.65), (9.81, 10.07), (10.19, 10.55), (10.61, 11.57)])),
        MeasuredLine(index: 3, seconds: 11.98,
                     text: "(I don't fuck with these niggas, I don't fuck with these hoes)",
                     words: words([(11.42, 11.44), (11.46, 11.56), (11.58, 11.66), (11.68, 11.76),
                                   (11.82, 11.94), (11.96, 12.10), (12.12, 12.14), (12.16, 12.40),
                                   (12.48, 12.59), (12.59, 12.70), (12.70, 12.84), (12.84, 12.98)])),
        MeasuredLine(index: 4, seconds: 12.74, text: "Now with that crown",
                     words: words([(12.52, 12.64), (12.74, 12.90), (13.02, 13.18), (13.40, 13.92)])),
        MeasuredLine(index: 5, seconds: 14.31, text: "You get these beautiful crystal slippers, baby",
                     words: words([(14.01, 14.09), (14.19, 14.31), (14.37, 14.61), (14.81, 15.31),
                                   (15.47, 15.85), (15.99, 16.43), (16.51, 17.51)])),
        MeasuredLine(index: 7, seconds: 17.52, text: "If they get out of line",
                     words: words([(17.40, 17.90), (18.66, 18.90), (19.20, 19.32), (19.42, 19.72),
                                   (20.02, 20.24), (21.10, 21.56)])),
    ]
    let score = LyricScore.of(oh, asides: asides)
    let heard = KaraokeLines.heard(score, measured: measured)
    let slippers = index(of: "You get these beautiful crystal slippers, baby", in: score)
    let squeezed = index(of: "And they used to, not wear, but to crack a ho in they head", in: score)
    let outOfLine = index(of: "If they get out of line", in: score)

    // The rules alone pass over the squeezed line.
    let rule = { (seconds: Double) in
        KaraokeLines.held(score, piece: score.index(at: seconds), seconds: seconds, heard: heard)
    }
    #expect(rule(17.4) == slippers)
    #expect(rule(17.6) == outOfLine)

    // The hand-overs give it a moment of its own, and the next line follows.
    let handovers = KaraokeLines.handovers(score, heard: heard)
    #expect(handovers.piece(at: 17.4) == slippers)
    #expect(handovers.piece(at: 17.6) == squeezed)
    #expect(handovers.piece(at: 17.51 + KaraokeLines.shortest - 0.05) == squeezed)
    #expect(handovers.piece(at: 17.51 + KaraokeLines.shortest + 0.05) == outOfLine)
}

@Test func theHandOversAreTheRulesWhereNoLineIsSqueezed() {
    let handovers = KaraokeLines.handovers(LyricScore.of(sheet), heard: [])
    #expect(handovers.piece(at: 9.9) == nil)
    #expect(handovers.piece(at: 10.0) == 0)
    #expect(handovers.piece(at: 14.0) == 1)
    #expect(abs((handovers.next(after: 10.5) ?? 0) - 14.0) < 1e-9)
}
