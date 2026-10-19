import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

private func T(_ path: String, title: String, artist: String, album: String,
               disc: Int = 0, track: Int = 0, seconds: Double = 100) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.trackNumber = track
    tags.discNumber = disc
    tags.durationSeconds = seconds

    return CloudTrack(rpmId: path, relativePath: path, title: title,
                      artist: artist, album: album, tags: tags)
}

private func wall() -> [CloudTrack] {
    [
        T("Radiohead/Kid A/02 x.flac", title: "The National Anthem",
          artist: "Radiohead", album: "Kid A", track: 2),
        T("Radiohead/Kid A/01 y.flac", title: "Everything In Its Right Place",
          artist: "Radiohead", album: "Kid A", track: 1),
        T("Joni Mitchell/Blue/01 z.flac", title: "All I Want",
          artist: "Joni Mitchell", album: "Blue", track: 1),
    ]
}

@Test func aListingBecomesRecordsInShelfOrder() {
    let albums = AlbumWall.group(wall())
    #expect(albums.map(\.album) == ["Blue", "Kid A"])
    #expect(albums.map(\.artist) == ["Joni Mitchell", "Radiohead"])
}

@Test func aRecordsTracksComeBackInReadingOrder() {
    let kidA = try! #require(AlbumWall.group(wall()).first { $0.album == "Kid A" })
    #expect(kidA.tracks.map(\.title)
        == ["Everything In Its Right Place", "The National Anthem"])
}

/// Tracks without numbers are sorted by title, so a record with no numbers reads alphabetically, not in
/// the order the listing arrived.
@Test func anUnnumberedRecordReadsAlphabetically() {
    let tracks = [
        T("A/B/z.flac", title: "Zebra", artist: "A", album: "B"),
        T("A/B/a.flac", title: "Antelope", artist: "A", album: "B"),
        T("A/B/m.flac", title: "Marmot", artist: "A", album: "B"),
    ]
    let album = try! #require(AlbumWall.group(tracks).first)
    #expect(album.tracks.map(\.title) == ["Antelope", "Marmot", "Zebra"])
    #expect(album.isOrdered == false, "a record with no numbers is not in the record's order")
}

@Test func aNumberedRecordSaysItIsInOrder() {
    // Bound outside the macro: #expect splits the expression into parts, and a key path passed to a
    // rethrows function is then seen as throwing.
    let ordered = AlbumWall.group(wall()).allSatisfy { $0.isOrdered }
    #expect(ordered)
}

@Test func aRecordKnowsHowLongItRuns() {
    let kidA = try! #require(AlbumWall.group(wall()).first { $0.album == "Kid A" })
    #expect(kidA.duration == .seconds(200))
}

// ── whether a redraw is worth it ──

@Test func twoReadingsOfAnUnchangedLibraryAreTheSame() {
    #expect(AlbumWall.same(AlbumWall.group(wall()), AlbumWall.group(wall())))
}

/// Correcting a misspelled artist must redraw the wall. An album key comes from the FOLDER, so the key
/// does not change. A comparison of keys alone would miss the edit, and the phone would keep drawing the
/// old rows until the app was launched twice.
@Test func aCorrectedArtistIsADifferentLibrary() {
    var fixed = wall()
    fixed[2] = T("Joni Mitchell/Blue/01 z.flac", title: "All I Want",
                 artist: "Joni Mitchel", album: "Blue", track: 1)

    #expect(AlbumWall.same(AlbumWall.group(wall()), AlbumWall.group(fixed)) == false)
}

@Test func aRetitledTrackIsADifferentLibrary() {
    var fixed = wall()
    fixed[0] = T("Radiohead/Kid A/02 x.flac", title: "The National Anthem (remaster)",
                 artist: "Radiohead", album: "Kid A", track: 2)

    #expect(AlbumWall.same(AlbumWall.group(wall()), AlbumWall.group(fixed)) == false)
}

@Test func aFixedRunningOrderIsADifferentLibrary() {
    var moved = wall()
    moved[0] = T("Radiohead/Kid A/02 x.flac", title: "The National Anthem",
                 artist: "Radiohead", album: "Kid A", track: 5)

    #expect(AlbumWall.same(AlbumWall.group(wall()), AlbumWall.group(moved)) == false)
}

/// A classical record is drawn from its works, so a catalogue refresh that only fills in the works must
/// still redraw the page.
@Test func aTrackGivenItsWorkIsADifferentLibrary() {
    var named = wall()
    var tags = named[0].tags ?? CloudTrackTags()
    tags.work = "Kid A"
    named[0] = CloudTrack(rpmId: named[0].rpmId, relativePath: named[0].relativePath,
                          title: named[0].title, artist: named[0].artist,
                          album: named[0].album, tags: tags)

    #expect(AlbumWall.same(AlbumWall.group(wall()), AlbumWall.group(named)) == false)
}

/// Only the visible fields are compared, not the whole row. A changed stamp or path with nothing visible
/// changing is not worth a rebuild of a wall with a thousand covers.
@Test func aStampThatMovedWithNothingOnScreenMovingIsTheSameLibrary() {
    let before = AlbumWall.group(wall())

    let after = AlbumWall.group(wall().map {
        CloudTrack(rpmId: $0.rpmId, sha256: "different", relativePath: $0.relativePath,
                   originalSize: 999, title: $0.title, artist: $0.artist, album: $0.album,
                   addedAt: 12345, tags: $0.tags, updatedAt: 999)
    })

    #expect(AlbumWall.same(before, after))
}

/// Durations are compared with a tolerance. A re-analysis that moves a track by a hundredth of a second
/// does not need a redraw.
@Test func aDurationThatMovedByAHundredthIsTheSameTrack() {
    let a = T("A/B/x.flac", title: "x", artist: "A", album: "B", seconds: 100.00)
    let b = T("A/B/x.flac", title: "x", artist: "A", album: "B", seconds: 100.04)
    let c = T("A/B/x.flac", title: "x", artist: "A", album: "B", seconds: 100.60)

    #expect(AlbumWall.same(a, b))
    #expect(AlbumWall.same(a, c) == false)
}

@Test func aLibraryThatGainedARecordIsADifferentLibrary() {
    let more = wall() + [T("Nick Drake/Pink Moon/01 a.flac", title: "Pink Moon",
                           artist: "Nick Drake", album: "Pink Moon", track: 1)]
    #expect(AlbumWall.same(AlbumWall.group(wall()), AlbumWall.group(more)) == false)
}
