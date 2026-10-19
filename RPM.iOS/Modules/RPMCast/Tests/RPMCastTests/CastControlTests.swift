import Foundation
import Testing
@testable import RPMCast

/// What the app tells RPM's own receiver about the record.
///
/// The media on the receiver is one endless stream, and the tracks inside it change without the receiver knowing. So a
/// track change has nothing to report on the media namespace. A receiver that only reads the LOAD keeps showing the record
/// that the queue started with, for the whole session. This channel fixes that.
///
/// The key names must match the web receiver in `rpm.Api/wwwroot/cast/receiver.html`. A key that is renamed on one side only
/// still compiles, but its value never arrives.
@Suite("What the room is told is playing")
struct CastControlTests {

    private func fields(_ payload: String) -> [String: Any] {
        let data = payload.data(using: .utf8) ?? Data()
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    @Test func itIsAMetaMessageWithTheWordsOnIt() {
        let said = CastNowPlaying(title: "Teardrop", artist: "Massive Attack",
                                  album: "Mezzanine", seconds: 330)

        let out = fields(said.payload)
        #expect(out["type"] as? String == "meta")
        #expect(out["title"] as? String == "Teardrop")
        #expect(out["artist"] as? String == "Massive Attack")
        #expect(out["album"] as? String == "Mezzanine")
        #expect(out["duration"] as? Double == 330)
    }

    /// The clock anchor: at stream second `streamAt`, the record is `trackAt` seconds in. The receiver counts forward from
    /// its own media clock. So the running time on a television is correct without anything being sent four times a second.
    @Test func theClockAnchorGoesWithIt() {
        let said = CastNowPlaying(title: "A", trackAt: 12, streamAt: 415.5)

        let out = fields(said.payload)
        #expect(out["trackAt"] as? Double == 12)
        #expect(out["streamAt"] as? Double == 415.5)
    }

    /// Zero is a real value, and it must be on the wire. A record that starts at its beginning has a `trackAt` of zero.
    /// That is every record except the first one in a stream that was opened by a seek. Some receivers read a missing
    /// `streamAt` as zero, but that should not be relied on.
    @Test func nothingIsSaidRatherThanLeftOut() {
        let out = fields(CastNowPlaying(title: "A").payload)
        #expect(out["trackAt"] as? Double == 0)
        #expect(out["streamAt"] as? Double == 0)
    }

    /// A field that is not known is left out. It is not sent as empty. The receiver draws a line for each field it gets,
    /// so an empty value would show as a blank line under the title.
    @Test func whatIsNotKnownIsNotSent() {
        let out = fields(CastNowPlaying(title: "Untitled").payload)
        #expect(out["artist"] == nil)
        #expect(out["album"] == nil)
        #expect(out["duration"] == nil)
        #expect(out["art"] == nil)
    }

    /// The cover address is sent under `art`, which is the key that the receiver reads.
    @Test func theCoversAddressIsCalledArt() {
        let said = CastNowPlaying(title: "A", artUrl: "http://10.0.0.2:8080/art/beef.jpg")
        #expect(fields(said.payload)["art"] as? String == "http://10.0.0.2:8080/art/beef.jpg")
    }
}
