import Testing
import Foundation
@testable import RPMKit

/// The choice of sheet for an explicit record. LRCLIB often holds a clean sheet and an explicit
/// sheet for one song, and the record marked explicit must get the explicit one. The same cases are
/// tested on the desktop (`RPM.Core.Tests/ExplicitLyricsTests.cs`) and in the Android apps (core
/// `ExplicitLyricsTest.kt`).
@Suite("The uncensored sheet, picked")
struct ExplicitLyricsTests {

    let masked = LyricSheet.parse("[00:01.00]You think you can f*** with me\n[00:04.00]Get the **** out of my way")
    let full = LyricSheet.parse("[00:01.00]You think you can fuck with me\n[00:04.00]Get the fuck out of my way")
    let dropped = LyricSheet.parse("[00:01.00]You think you can mess with me\n[00:04.00]Get out of my way")
    let plainA = LyricSheet.parse("[00:01.00]Hello there\n[00:04.00]Nice to meet you")
    let plainB = LyricSheet.parse("[00:01.10]Hello there\n[00:04.10]Nice to meet you")

    private func score(_ lrc: String) -> Int {
        ExplicitLyrics.score(LyricSheet.parse(lrc))
    }

    @Test func aMaskedWordCostsMoreThanAnExplicitWordEarns() {
        #expect(ExplicitLyrics.score(masked) == -2 * ExplicitLyrics.maskPenalty)
        #expect(ExplicitLyrics.score(full) == 2)
        #expect(ExplicitLyrics.score(dropped) == 0)
    }

    @Test func everyCommonMaskIsSeen() {
        #expect(score("[00:01.00]What the sh*t") == -ExplicitLyrics.maskPenalty)
        #expect(score("[00:01.00]What the f#ck") == -ExplicitLyrics.maskPenalty)
        #expect(score("[00:01.00]What the ###") == -ExplicitLyrics.maskPenalty)
        #expect(score("[00:01.00]What the [Censored]") == -ExplicitLyrics.maskPenalty)
    }

    @Test func aNumberSignBeforeADigitIsNotAMask() {
        #expect(score("[00:01.00]Straight in at #1") == 0)
    }

    @Test func punctuationAndCapitalsDoNotHideAnExplicitWord() {
        #expect(score("[00:01.00]\"Fuckin',\" she said. SHIT!") == 2)
    }

    @Test func theFullExplicitSheetBeatsTheMaskedCleanSheet() {
        // The exact lookup returned the clean sheet. The search has both.
        #expect(ExplicitLyrics.pick(exact: masked, found: [masked, full]) == full)
    }

    @Test func theFullExplicitSheetBeatsACleanSheetThatDropsTheWords() {
        #expect(ExplicitLyrics.pick(exact: dropped, found: [full]) == full)
    }

    @Test func aTieKeepsTheExactAnswer() {
        #expect(ExplicitLyrics.pick(exact: plainB, found: [plainA, plainB]) == plainB)
    }

    @Test func aTieWithoutAnExactAnswerKeepsLrclibsOrder() {
        #expect(ExplicitLyrics.pick(exact: .empty, found: [plainA, plainB]) == plainA)
    }

    @Test func noCandidatesIsNoSheet() {
        #expect(!ExplicitLyrics.pick(exact: .empty, found: []).isSynced)
        #expect(!ExplicitLyrics.pick(exact: .empty, found: [LyricSheet.parse("words without times")]).isSynced)
    }
}
