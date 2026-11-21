import Testing
import Foundation
@testable import RPMKit

/// Which Wikipedias the artist and album pages read, given the reader's choice.
struct ArticleLanguagesTests {
    /// Nothing chosen: the phone's own language, then English.
    @Test func nothingChosenIsThePhonesLanguage() {
        #expect(ArticleLanguages.wikipedias(chosen: "", phone: ["nl-NL", "en"]) == ["nl", "en"])
        #expect(ArticleLanguages.wikipedias(chosen: "", phone: ["en-GB"]) == ["en"])
    }

    /// A chosen language wins over the phone's, and English stays behind it.
    @Test func aChosenLanguageComesFirst() {
        #expect(ArticleLanguages.wikipedias(chosen: "de", phone: ["nl-NL"]) == ["de", "en"])
        #expect(ArticleLanguages.wikipedias(chosen: "en", phone: ["nl-NL"]) == ["en"])
    }

    /// A code from a later build that this one does not offer is the phone's language, so the
    /// pages still read something sensible.
    @Test func aCodeNotOfferedIsThePhonesLanguage() {
        #expect(ArticleLanguages.wikipedias(chosen: "xx", phone: ["fr-FR"]) == ["fr", "en"])
    }

    @Test func thePhonesLanguageIsItsBaseCode() {
        #expect(ArticleLanguages.phoneLanguage(["zh-Hans-CN"]) == "zh")
        #expect(ArticleLanguages.phoneLanguage([]) == "en")
    }

    @Test func elevenLanguagesAreOfferedWithEnglishFirst() {
        #expect(ArticleLanguages.offered.count == 11)
        #expect(ArticleLanguages.offered.first == "en")
        #expect(Set(ArticleLanguages.offered).count == ArticleLanguages.offered.count)
    }

    /// Each language is named in itself, with a capital first letter.
    @Test func aLanguageIsNamedInItself() {
        #expect(ArticleLanguages.name(of: "nl") == "Nederlands")
        #expect(ArticleLanguages.name(of: "en") == "English")
        #expect(ArticleLanguages.name(of: "fr") == "Français")
    }
}
