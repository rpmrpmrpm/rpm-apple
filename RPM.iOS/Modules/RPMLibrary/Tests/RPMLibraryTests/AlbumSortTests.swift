import Testing
import RPMKit
@testable import RPMLibrary

/// Mirrors the desktop's `RPM.Core.Tests/AlbumSortTests.cs`, so both apps sort albums the same way.

private func facts(
    _ album: String, _ artist: String, added: Int64 = 0, year: Int = 0, plays: Int = 0
) -> AlbumFacts {
    AlbumFacts(album: album, artist: artist, addedAt: added, year: year, plays: plays)
}

private func names(_ wall: [AlbumFacts], _ by: AlbumOrdering) -> [String] {
    AlbumSort.by(wall, by) { $0 }.map(\.album)
}

// ── the orders ──

@Test func byArtistPutsAShelfInOrder() {
    let wall = [facts("Kid A", "Radiohead"), facts("Blue", "Joni Mitchell"),
                facts("Amnesiac", "Radiohead")]
    #expect(names(wall, .artist) == ["Blue", "Amnesiac", "Kid A"])
}

@Test func byAlbumIgnoresWhoMadeIt() {
    let wall = [facts("Kid A", "Radiohead"), facts("Blue", "Joni Mitchell"),
                facts("Amnesiac", "Radiohead")]
    #expect(names(wall, .album) == ["Amnesiac", "Blue", "Kid A"])
}

@Test func byAddedPutsTheNewestFirst() {
    let wall = [facts("Old", "A", added: 100), facts("New", "B", added: 300),
                facts("Middling", "C", added: 200)]
    #expect(names(wall, .added) == ["New", "Middling", "Old"])
}

@Test func albumsAddedTogetherFallBackToTheShelfOrder() {
    let wall = [facts("Zoo", "Zebra", added: 5), facts("Aja", "Antelope", added: 5)]
    #expect(names(wall, .added) == ["Aja", "Zoo"])
}

@Test func byYearPutsTheNewestReleaseFirst() {
    let wall = [facts("Older", "A", year: 1971), facts("Newer", "B", year: 1994)]
    #expect(names(wall, .year) == ["Newer", "Older"])
}

/// Albums with no year sort last. Otherwise a library with many untagged albums would always open
/// on those.
@Test func albumsWithNoYearGoLastNotFirst() {
    let wall = [facts("Untagged", "A", year: 0), facts("Tagged", "B", year: 1971)]
    #expect(names(wall, .year) == ["Tagged", "Untagged"])
}

@Test func albumsOfTheSameYearFallBackToTheShelfOrder() {
    let wall = [facts("Zoo", "Zebra", year: 1977), facts("Rumours", "Antelope", year: 1977)]
    #expect(names(wall, .year) == ["Rumours", "Zoo"])
}

@Test func byPlaysPutsTheMostPlayedFirst() {
    let wall = [facts("Never", "A", plays: 0), facts("Often", "B", plays: 50),
                facts("Once", "C", plays: 1)]
    #expect(names(wall, .plays) == ["Often", "Once", "Never"])
}

@Test func albumsNeverPlayedKeepTheShelfOrderBetweenThem() {
    let wall = [facts("Zoo", "Zebra", plays: 0), facts("Played", "Ant", plays: 3),
                facts("Aja", "Antelope", plays: 0)]
    #expect(names(wall, .plays) == ["Played", "Aja", "Zoo"])
}

// ── what a wall knows about an album ──

private func track(added: Int64 = 0, year: Int = 0) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.year = year
    return CloudTrack(rpmId: "x", addedAt: added, tags: tags)
}

@Test func anAlbumWasAddedWhenItsNewestTrackWas() {
    #expect(AlbumSort.addedOf([track(added: 100), track(added: 300), track(added: 200)]) == 300)
}

@Test func anAlbumWithNoTracksWasNeverAdded() {
    #expect(AlbumSort.addedOf([]) == 0)
}

/// A compilation's tracks carry the years of their original recordings. The first track's year and
/// the highest year are both wrong for the compilation, so the most common year is used.
@Test func anAlbumsYearIsTheOneMostOfItsTracksAgreeOn() {
    #expect(AlbumSort.yearOf([track(year: 1971), track(year: 1994), track(year: 1994)]) == 1994)
}

@Test func anUntaggedAlbumHasNoYear() {
    #expect(AlbumSort.yearOf([track(), track()]) == 0)
}

/// On a tie between two years, the earlier one wins. A reissue is the record it was, not the
/// pressing it came on.
@Test func aYearSplitDownTheMiddleTakesTheEarlierOne() {
    #expect(AlbumSort.yearOf([track(year: 1971), track(year: 2011)]) == 1971)
}

@Test func untaggedTracksDoNotDragAnAlbumsYearDown() {
    #expect(AlbumSort.yearOf([track(), track(), track(year: 1971)]) == 1971)
}

@Test func theSameYearRuleAppliesToYearsAlreadyCounted() {
    #expect(AlbumSort.yearFrom([(1971, 1), (1994, 2)]) == 1994)
    #expect(AlbumSort.yearFrom([(1971, 1), (2011, 1)]) == 1971)   // a tie goes to the earlier
    #expect(AlbumSort.yearFrom([]) == 0)
    #expect(AlbumSort.yearFrom([(0, 5), (1971, 1)]) == 1971)      // untagged is not a year
}

// ── edges ──

@Test func anEmptyWallSortsToAnEmptyWall() {
    #expect(AlbumSort.by([AlbumFacts](), .plays) { $0 }.isEmpty)
}

/// A sort that treats two equal albums as less than each other in both directions would drop one.
@Test func twoAlbumsThatAreEqualInEveryWayBothSurviveTheSort() {
    let wall = [facts("Same", "Same"), facts("Same", "Same")]
    #expect(AlbumSort.by(wall, .artist) { $0 }.count == 2)
}
