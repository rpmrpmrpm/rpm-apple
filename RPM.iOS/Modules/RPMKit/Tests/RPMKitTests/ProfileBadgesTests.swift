import Testing
import Foundation
@testable import RPMKit

// The same cases as the Android app's `ProfileBadgesTest`: the two phones must unlock the same badges.

@Test func anEmptyCollectionUnlocksNothing() {
    #expect(RPMProfileBadges.unlocked(albums: 0, tracks: 0, genreAlbums: [:]).isEmpty)
}

@Test func theSizeBadgesFollowTheAlbumCount() {
    let held = RPMProfileBadges.unlocked(albums: 1_610, tracks: 23_329, genreAlbums: [:])
    #expect(held == ["first-spin", "crate-digger", "record-collector", "music-connoisseur", "ten-thousand"])
}

@Test func aGenreBadgeNeedsAFifthAndTwentyFive() {
    // 30 of 100 is a fifth and 25: unlocked. 30 of 200 is not a fifth.
    #expect(RPMProfileBadges.unlocked(albums: 100, tracks: 1_000, genreAlbums: ["Jazz": 30]).contains("jazz"))
    #expect(!RPMProfileBadges.unlocked(albums: 200, tracks: 2_000, genreAlbums: ["Jazz": 30]).contains("jazz"))
    // 20 of 50 is a fifth but not 25.
    #expect(!RPMProfileBadges.unlocked(albums: 50, tracks: 500, genreAlbums: ["Jazz": 20]).contains("jazz"))
}

@Test func aGenreBadgeCountsItsWholeFamily() {
    let held = RPMProfileBadges.unlocked(albums: 100, tracks: 1_000, genreAlbums: ["Indie": 15, "Punk": 10, "Rock": 5])
    #expect(held.contains("rock"))
}

@Test func theRangeBadgesCountGenresWithFiveAlbums() {
    let ten = Dictionary(uniqueKeysWithValues: (1...10).map { ("Genre \($0)", 5) })
    #expect(RPMProfileBadges.unlocked(albums: 50, tracks: 500, genreAlbums: ten).contains("genre-hopper"))
    #expect(!RPMProfileBadges.unlocked(albums: 50, tracks: 500, genreAlbums: ten).contains("omnivore"))
    // The shelf for music that cannot be filed is not a genre.
    var nine = Dictionary(uniqueKeysWithValues: (1...9).map { ("Genre \($0)", 5) })
    nine["Other / Unknown"] = 50
    #expect(!RPMProfileBadges.unlocked(albums: 95, tracks: 950, genreAlbums: nine).contains("genre-hopper"))
}

@Test func everyBadgeHasAUniqueIdOfTheServersShape() {
    #expect(Set(RPMProfileBadges.all.map(\.id)).count == RPMProfileBadges.all.count)
    #expect(RPMProfileBadges.all.allSatisfy { $0.id.range(of: "^[a-z0-9-]{1,40}$", options: .regularExpression) != nil })
}

@Test func aBadgeColourReadsItsWireAndFallsBackToTheFirst() {
    #expect(RPMProfileBadges.colour("#2563EB") == 0x2563EB)
    #expect(RPMProfileBadges.colour("") == RPMProfileBadges.colours[0])
    #expect(RPMProfileBadges.colour("blue") == RPMProfileBadges.colours[0])
    #expect(RPMProfileBadges.wire(0x2563EB) == "#2563EB")
}
