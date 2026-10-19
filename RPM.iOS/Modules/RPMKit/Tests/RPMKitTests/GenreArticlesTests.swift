import Testing
@testable import RPMKit

/// The English Wikipedia article each genre shelf is described by: the desktop's table.
struct GenreArticlesTests {
    @Test func aGenreIsMatchedWithoutRegardToCase() {
        #expect(GenreArticles.title("Rock") == "Rock music")
        #expect(GenreArticles.title(" hip-hop / rap ") == "Hip hop music")
        #expect(GenreArticles.title("R&B") == "Contemporary R&B")
    }

    /// A genre the table does not name has no article: it is never searched for by name.
    @Test func aGenreWithoutAnEntryHasNoArticle() {
        #expect(GenreArticles.title("Other") == nil)
        #expect(GenreArticles.title("") == nil)
    }
}
