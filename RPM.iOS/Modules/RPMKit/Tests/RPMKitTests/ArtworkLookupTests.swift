import Testing
import Foundation
@testable import RPMKit

/// What `/artwork` answers with, as the phone reads it.
///
/// The square thumbs are fanart.tv's. An older server sends no `thumbs` at all, and that
/// must read as "no squares" rather than as a failed lookup: a failed lookup is retried
/// and never remembered, so an artist would be asked about on every screen.
struct ArtworkLookupTests {
    private func decode(_ json: String) throws -> ArtworkLookup {
        try JSONDecoder().decode(ArtworkLookup.self, from: Data(json.utf8))
    }

    @Test func theSquaresAreReadApartFromTheBackdrops() throws {
        let said = try decode("""
            {"cover":null,"backgrounds":["https://a/bg.jpg"],"thumbs":["https://a/sq.jpg"],"logo":null}
            """)

        #expect(said.backgrounds == ["https://a/bg.jpg"])
        #expect(said.thumbs == ["https://a/sq.jpg"])
    }

    @Test func aServerThatSendsNoThumbsIsNoSquares() throws {
        let said = try decode("""
            {"cover":null,"backgrounds":["https://a/bg.jpg"],"logo":null}
            """)

        #expect(said.thumbs.isEmpty)
        #expect(said.backgrounds.count == 1)
    }

    @Test func theLogoIsRead() throws {
        let said = try decode("""
            {"cover":null,"backgrounds":[],"thumbs":[],"logo":"https://a/logo.png"}
            """)

        #expect(said.logo == "https://a/logo.png")
    }

    @Test func noLogoIsNil() throws {
        let said = try decode("""
            {"cover":null,"backgrounds":[],"thumbs":[]}
            """)

        #expect(said.logo == nil)
    }
}
