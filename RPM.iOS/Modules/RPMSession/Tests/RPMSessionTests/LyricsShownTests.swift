import Testing
import RPMKit
@testable import RPMSession

/// When the player shows the lyrics in place of the cover.
@Suite("The lyrics are shown only while there are lyrics")
struct LyricsShownTests {

    private let sung = LyricSheet.parse("[00:12.00]First line\n[00:15.50]Second line")

    @Test func aRecordWithLyricsShowsThemWhenAskedFor() {
        #expect(sung.isSynced)
        #expect(LyricsLookup.shows(asked: true, sheet: sung, looking: false))
        #expect(!LyricsLookup.shows(asked: false, sheet: sung, looking: false))
    }

    /// The lookup for a new record is still running. The lyrics stay up, so a record that has
    /// lyrics does not show the cover for a moment first.
    @Test func theLyricsStayUpWhileTheNextRecordIsLookedUp() {
        #expect(LyricsLookup.shows(asked: true, sheet: .empty, looking: true))
    }

    /// The next record has no lyrics. The lookup ends with the same empty sheet it started
    /// with, so nothing changes but `looking`. The cover must come back all the same, because
    /// the lyrics key is greyed out and the user cannot close the lyrics themselves.
    @Test func aRecordWithNoLyricsShowsTheCoverEvenThoughTheSheetDidNotChange() {
        #expect(!LyricsLookup.shows(asked: true, sheet: .empty, looking: false))
    }

    /// The user's choice is kept: the record after one with no lyrics shows its lyrics again.
    @Test func theChoiceIsKeptForTheNextRecordWithLyrics() {
        let asked = true
        #expect(!LyricsLookup.shows(asked: asked, sheet: .empty, looking: false))
        #expect(LyricsLookup.shows(asked: asked, sheet: sung, looking: false))
    }
}
