import Foundation
import Testing
@testable import RPMKit

/// The generated table, read the way the app reads it.
///
/// **These are about the plumbing, not about the words.** Whether a French sentence is
/// good French is not something a test can ask; whether the French file is in the
/// bundle, whether a key resolves, and whether a missing one is loud rather than quiet
/// are all things it can.
@Suite("The string table")
struct LocTests {

    @Test func aKeyThatIsThereResolves() {
        #expect(Loc.get("AlbumSort_Artist") == "By artist")
    }

    /// **A missing key renders as the key**, which is what the desktop does. English
    /// everywhere would look correct in one locale out of five and wrong in four.
    @Test func aKeyThatIsNotThereIsItsOwnName() {
        #expect(Loc.get("Nothing_Is_Keyed_Like_This") == "Nothing_Is_Keyed_Like_This")
    }

    @Test func placeholdersAreFilledIn() {
        // Not a table key: what is being checked is the formatting, and a real key
        // would tie this test to a sentence somebody is free to rewrite.
        #expect(String(format: "%1$@ of %2$@", "3", "8") == "3 of 8")
    }

    /// All five are in the bundle. A locale that did not make it through SwiftPM's
    /// resource processing is a phone that silently speaks English.
    ///
    /// **Folded when compared**: SwiftPM writes `zh-Hans.lproj` out as `zh-hans.lproj`,
    /// and the system's own matching is case-insensitive about a language tag. What is
    /// being asked here is whether the file is there, not how it is spelled.
    @Test func allFiveLocalesShipped() throws {
        let shipped = Set(Loc.table.localizations.map { $0.lowercased() })

        for locale in ["en", "fr", "es", "de", "zh-Hans"] {
            #expect(shipped.contains(locale.lowercased()), "\(locale) is not in the bundle")
        }
    }

    /// The table is the same one the desktop reads, so a key the desktop has is a key
    /// this head has. One spot check against a long-standing string.
    @Test func itIsTheSameTableTheDesktopReads() throws {
        let french = try #require(Loc.table.path(forResource: "fr", ofType: "lproj"))
        let bundle = try #require(Bundle(path: french))

        #expect(bundle.localizedString(forKey: "AlbumSort_Artist", value: nil, table: nil)
                == "Par artiste")
    }
}
