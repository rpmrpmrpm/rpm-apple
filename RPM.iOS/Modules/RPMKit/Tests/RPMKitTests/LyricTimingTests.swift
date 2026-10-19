import Testing
import Foundation
@testable import RPMKit

/// Karaoke's timing: the desktop's sweep, and the word timing a desktop or the transcoder measured
/// off the record. The Android `LyricScoreTest` and `MeasuredLyricsTest`, case for case.
struct LyricTimingTests {
    @Test func theSweepSharesALineByLengthAndEndsOnTheNextLine() {
        let spans = LyricTiming.sweep("aa bbbb", from: 10, until: 10.6)
        #expect(spans.count == 2)
        #expect(abs(spans[0].from - 10.0) < 1e-9)
        #expect(abs(spans[0].to - 10.2) < 1e-9)
        #expect(abs(spans[1].to - 10.6) < 1e-9)
        #expect(spans.map(\.start) == [0, 3])
        #expect(spans.map(\.length) == [2, 4])
    }

    @Test func theSweepIsNeverSlowerThanItsCap() {
        let spans = LyricTiming.sweep("seven!!", from: 0, until: 60)
        #expect(abs((spans.last?.to ?? 0) - 7 / LyricTiming.slowestChars) < 1e-9)
    }

    private let measured = [MeasuredLine(index: 3, seconds: 12.5, text: "hello there you",
                                         words: [MeasuredWord(from: 12.6, to: 12.9), MeasuredWord(from: 13.4, to: 13.8),
                                                 MeasuredWord(from: 14.0, to: 14.2)])]

    @Test func theSameLineTakesTheMeasuredMoments() throws {
        let spans = try #require(MeasuredLyrics.forLine(measured, text: "hello there you", seconds: 12.5))
        #expect(spans.map(\.from) == [12.6, 13.4, 14.0])
        #expect(spans.map(\.start) == [0, 6, 12])
    }

    @Test func anotherSheetsLineIsNotUsed() {
        #expect(MeasuredLyrics.forLine(measured, text: "hello there", seconds: 12.5) == nil)
        #expect(MeasuredLyrics.forLine(measured, text: "hello there you", seconds: 14.0) == nil)
    }

    /// A measurement covers a sheet when three in four of its sung lines are placed.
    @Test func aMeasurementCoversASheetWhenMostOfItsLinesArePlaced() {
        let sheet = LyricSheet.parse("[00:12.50]hello there you\n[00:20.00]and another")
        #expect(!MeasuredLyrics.covers(measured, sheet: sheet))
        let both = measured + [MeasuredLine(index: 4, seconds: 20, text: "and another",
                                            words: [MeasuredWord(from: 20, to: 20.5), MeasuredWord(from: 20.6, to: 21)])]
        #expect(MeasuredLyrics.covers(both, sheet: sheet))
    }
}
