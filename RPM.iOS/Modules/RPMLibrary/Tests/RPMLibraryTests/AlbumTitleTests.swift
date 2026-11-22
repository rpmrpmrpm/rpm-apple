import Testing
@testable import RPMLibrary

/// Mirrors the Android phone's `AlbumTitleTest`, which follows the desktop's `AlbumTitle`, so all
/// three record pages lift the same editions onto their own line.
@Suite struct AlbumTitleTests {
    @Test func anEditionAtTheEndGoesOnItsOwnLine() {
        let t = AlbumTitle.split("AM I THE DRAMA? (Bonus Edition)")
        #expect(t.name == "AM I THE DRAMA?")
        #expect(t.editions == ["Bonus Edition"])
        #expect(t.full == "AM I THE DRAMA? (Bonus Edition)")
    }

    @Test func twoEditionsComeOffInReadingOrder() {
        let t = AlbumTitle.split("Rumours (Deluxe) [2004 Remaster]")
        #expect(t.name == "Rumours")
        #expect(t.editions == ["Deluxe", "2004 Remaster"])
    }

    @Test func aNestedGroupComesOffWhole() {
        let t = AlbumTitle.split("Album (Deluxe (2019))")
        #expect(t.name == "Album")
        #expect(t.editions == ["Deluxe (2019)"])
    }

    @Test(arguments: ["The Guide (Wommat)", "(What's the Story) Morning Glory?", "( )",
                      "Album (Deluxe", "Short N' Sweet"])
    func bracketsThatAreTheNameStay(title: String) {
        let t = AlbumTitle.split(title)
        #expect(t.name == title)
        #expect(t.editions.isEmpty)
    }

    @Test func aCreditIsNeverAnEdition() {
        #expect(!AlbumTitle.isAside("feat. The Mix Masters"))
        #expect(!AlbumTitle.isAside("with Radio Slave"))
        #expect(!AlbumTitle.isAside("Feathers"))
        #expect(AlbumTitle.isAside("Taylor's Version"))
        #expect(AlbumTitle.isAside("12\" Mix"))
    }
}
