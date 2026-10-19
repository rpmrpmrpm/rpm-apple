import Foundation
import Testing
@testable import RPMAudio

/// Seeking in a record that is still being encoded as it is sent.
///
/// **The two kinds of stream are seeked differently, and a URL does not show which kind it is.**
/// A stored object supports byte ranges. A seek sends a range request, and the byte offset comes
/// from the parser. A live rendition has no stored bytes to request. The encoder is asked for a
/// time in seconds and starts there. That time is exact, because the encoder holds the whole
/// record.
///
/// A wrong choice fails silently in both cases. A range request sent to the encoder returns the
/// start of the track. The needle moves, but the music does not. A `from=` query sent to the
/// store is ignored, so it fails in the same way.
@Suite("A needle in a record that is still being made")
struct LiveSeekTests {

    private let stored = URL(string: "https://store.example/rate/320/abc.m4a?X-Amz-Signature=deadbeef")!
    private let live = URL(string: "https://live.example/live/v1.abc.320.99.sig")!

    // ── which request each kind of resume makes ──

    @Test func theTopOfARecordAsksForNothingInParticular() {
        let resume = TrackFeed.Resume.theTop

        #expect(resume.address(of: live) == live)
        #expect(resume.range == nil)
    }

    @Test func aByteIsARangeRequestAgainstTheSameAddress() {
        let resume = TrackFeed.Resume.theByte(4096, landingAt: 12.5)

        #expect(resume.address(of: stored) == stored)
        #expect(resume.range == "bytes=4096-")
    }

    /// A live seek sends the time in the query and no range. A range header would be answered by
    /// an encoder that has not yet written byte 4096 of the file, so it has no answer for that byte.
    @Test func aSecondIsAQueryAndNeverARange() throws {
        let resume = TrackFeed.Resume.theSecond(94.5)
        let asked = resume.address(of: live)

        #expect(resume.range == nil)

        let query = try #require(URLComponents(url: asked, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains { $0.name == "from" && $0.value == "94.5" })
    }

    /// A signed address already has a query. The query must be kept, because it holds the
    /// signature.
    @Test func aSecondIsAddedToWhateverQueryIsAlreadyThere() throws {
        let asked = TrackFeed.Resume.theSecond(30).address(of: stored)

        let query = try #require(URLComponents(url: asked, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains { $0.name == "X-Amz-Signature" && $0.value == "deadbeef" })
        #expect(query.contains { $0.name == "from" })
    }

    /// The server parses the number using its own culture settings. "94,5" would be read as 945,
    /// which is far past the end of the record. The number must always use a point.
    @Test func aSecondIsWrittenWithAPointWhateverThePhoneCallsADecimal() throws {
        let asked = TrackFeed.Resume.theSecond(94.5).address(of: live)

        #expect(asked.absoluteString.contains("from=94.5"))
        #expect(!asked.absoluteString.contains(","))
    }

    /// A time past the data that has arrived is still a valid time. The encoder holds the whole
    /// record and can start at any second of it. Range-reading a file that is still being written
    /// cannot do this.
    @Test func aSecondPastWhatHasArrivedIsStillASecond() {
        #expect(TrackFeed.Resume.theSecond(600).range == nil)
        #expect(TrackFeed.Resume.theSecond(600).address(of: live).absoluteString.contains("from=600"))
    }

    // ── what the feed does with them ──

    /// A live feed does not ask the parser where a time falls. It answers before any byte of the
    /// record is decoded. This is the case for a seek early in the first play.
    @Test func aLiveFeedMovesToASecondWithoutHavingParsedAnything() {
        let feed = TrackFeed()
        feed.start(live, kind: .live)

        #expect(feed.moveTo(94.5) == 94.5)

        feed.stop()
    }

    /// A stored feed refuses until the parser has read the header. Only then is the byte offset
    /// known.
    @Test func aStoredFeedStillRefusesUntilItCanWorkOutTheByte() {
        let feed = TrackFeed()
        feed.start(stored, kind: .stored)

        #expect(feed.moveTo(94.5) == nil)

        feed.stop()
    }

    @Test func nothingCanBeSeekedBeforeAnythingHasBeenStarted() {
        #expect(TrackFeed().moveTo(1) == nil)
    }
}
