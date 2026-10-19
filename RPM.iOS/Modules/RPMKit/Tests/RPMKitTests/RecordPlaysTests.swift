import Testing
import Foundation
@testable import RPMKit

/// What `metadata/plays` answers with, and the listens matched to where each track sits.
struct RecordPlaysTests {
    private func decode(_ json: String) throws -> RecordPlays {
        try RPMJSON.decoder.decode(RecordPlays.self, from: Data(json.utf8))
    }

    /// The API's own spelling: camel case, as ASP.NET writes `CatalogPlays`.
    @Test func theAnswerIsRead() throws {
        let said = try decode("""
            {"tracks":[{"position":1,"title":"Hello","recordingMbid":"A"}],
             "plays":[{"recordingMbid":"A","listens":1200,"listeners":300}]}
            """)

        #expect(said.tracks == [RecordPlays.Track(position: 1, title: "Hello", recordingMbid: "A")])
        #expect(said.plays == [RecordPlays.Plays(recordingMbid: "A", listens: 1200, listeners: 300)])
    }

    @Test func anEmptyAnswerIsEmpty() throws {
        let said = try decode(#"{"tracks":[],"plays":[]}"#)

        #expect(said.listensByPlace.isEmpty)
    }

    @Test func listensAreMatchedByPositionNotByTitle() {
        let said = RecordPlays(
            tracks: [.init(position: 1, title: "Intro", recordingMbid: "a"),
                     .init(position: 2, title: "The Hit (2011 Remaster)", recordingMbid: "b")],
            plays: [.init(recordingMbid: "B", listens: 9000, listeners: 10),
                    .init(recordingMbid: "a", listens: 40, listeners: 2)])

        #expect(said.listensByPlace == [TrackPlace(disc: 1, position: 1): 40,
                                        TrackPlace(disc: 1, position: 2): 9000])
    }

    /// The second disc starts again at one. Matched on position alone, its track 2 would take the
    /// first disc's place.
    @Test func aSecondDiscIsCountedFromTheListing() {
        let said = RecordPlays(
            tracks: [.init(position: 1, title: "One", recordingMbid: "a"),
                     .init(position: 2, title: "Two", recordingMbid: "b"),
                     .init(position: 1, title: "Demo One", recordingMbid: "c"),
                     .init(position: 2, title: "Demo Two", recordingMbid: "d")],
            plays: [.init(recordingMbid: "b", listens: 5000, listeners: 1),
                    .init(recordingMbid: "d", listens: 3, listeners: 1)])

        #expect(said.listensByPlace == [TrackPlace(disc: 1, position: 2): 5000,
                                        TrackPlace(disc: 2, position: 2): 3])
    }

    /// A track the counts do not mention is absent, not zero: nobody answered for it.
    @Test func aTrackWithNoCountIsAbsent() {
        let said = RecordPlays(
            tracks: [.init(position: 1, title: "One", recordingMbid: "a"),
                     .init(position: 2, title: "Two", recordingMbid: "b")],
            plays: [.init(recordingMbid: "a", listens: 10, listeners: 1)])

        #expect(said.listensByPlace[TrackPlace(disc: 1, position: 2)] == nil)
    }
}
