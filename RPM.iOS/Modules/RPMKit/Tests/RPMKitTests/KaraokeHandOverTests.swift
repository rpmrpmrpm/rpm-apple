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
