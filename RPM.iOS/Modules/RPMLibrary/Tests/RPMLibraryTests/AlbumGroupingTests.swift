import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// Mirrors the desktop's `RPM.Core.Tests/CloudAlbumGroupingTests.cs`, so both apps group albums the same way.
///
/// What one album is, using cloud rows. Grouping by track artist plus album name gives one album per guest
/// artist on a compilation, and two records for a two-disc set. These are cases that the desktop's folder
/// rule gets right and a tag pair cannot.

private func T(
    _ path: String, title: String? = nil, artist: String? = nil, album: String? = nil,
    albumArtist: String? = nil, disc: Int = 0, track: Int = 0
) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.trackNumber = track
    tags.discNumber = disc
    tags.albumArtist = albumArtist

    return CloudTrack(
        rpmId: path, sha256: "sha-" + path, relativePath: path, originalSize: 1,
        title: title ?? (path as NSString).lastPathComponent
            .replacingOccurrences(of: ".flac", with: ""),
        artist: artist, album: album, addedAt: 0, tags: tags)
}

private func group(_ tracks: [CloudTrack]) -> [String: [CloudTrack]] {
    Dictionary(grouping: tracks, by: AlbumGrouping.key(for:))
}

private func compilation() -> [CloudTrack] {
    [
        T("Various Artists/Now 22/01 Rhythm Is a Dancer.flac", artist: "Snap!",
          album: "Now 22", albumArtist: "Various Artists", track: 1),
        T("Various Artists/Now 22/02 Ebeneezer Goode.flac", artist: "The Shamen",
          album: "Now 22", albumArtist: "Various Artists", track: 2),
        T("Various Artists/Now 22/03 Sleeping Satellite.flac", artist: "Tasmin Archer",
          album: "Now 22", albumArtist: "Various Artists", track: 3),
    ]
}

@Test func aCompilationIsOneAlbumHoweverManyArtistsPlayOnIt() {
    let albums = group(compilation())
    #expect(albums.count == 1)

    let rows = try! #require(albums.values.first)
    #expect(AlbumGrouping.albumArtist(for: rows, folder: "Various Artists/Now 22") == "Various Artists")
    #expect(AlbumGrouping.albumName(for: rows, folder: "Various Artists/Now 22") == "Now 22")
}

/// The merged mode, which is the default: every disc is in one folder, with track numbers per disc and
/// one album name.
@Test func aMergedMultiDiscSetIsOneAlbum() {
    let tracks = [
        T("The Clash/Sandinista!/01 The Magnificent Seven.flac", artist: "The Clash",
          album: "Sandinista!", albumArtist: "The Clash", disc: 1, track: 1),
        T("The Clash/Sandinista!/02 Hitsville U.K..flac", artist: "The Clash",
          album: "Sandinista!", albumArtist: "The Clash", disc: 1, track: 2),
        T("The Clash/Sandinista!/03 Lose This Skin.flac", artist: "The Clash",
          album: "Sandinista!", albumArtist: "The Clash", disc: 2, track: 1),
    ]
    #expect(group(tracks).count == 1)
}

/// The separate-albums mode adds a disc label to the name and gives each disc its own folder. Those must
/// show as two records, so nothing here may merge them.
@Test func discsFiledAsSeparateAlbumsStaySeparate() {
    let tracks = [
        T("Erasure/Erasure (Disc 1)/01 Intro.flac", artist: "Erasure",
          album: "Erasure (Disc 1)", albumArtist: "Erasure", track: 1),
        T("Erasure/Erasure (Disc 2)/01 Rock Me Gently.flac", artist: "Erasure",
          album: "Erasure (Disc 2)", albumArtist: "Erasure", track: 1),
    ]
    #expect(group(tracks).count == 2)
}

@Test func twoArtistsWithAnIdenticallyNamedAlbumAreTwoAlbums() {
    let tracks = [
        T("Queen/Greatest Hits/01 Bohemian Rhapsody.flac", artist: "Queen",
          album: "Greatest Hits", albumArtist: "Queen", track: 1),
        T("Weezer/Greatest Hits/01 Buddy Holly.flac", artist: "Weezer",
          album: "Greatest Hits", albumArtist: "Weezer", track: 1),
    ]
    #expect(group(tracks).count == 2)
}

/// Same folder, one file with no album tag. The desktop shows one album here because the folder is the
/// album. A tag pair would give two.
@Test func theFolderDecidesWhateverTheTagsDisagreeAbout() {
    let tracks = [
        T("Manu Chao/Clandestino/01 Clandestino.flac", artist: "Manu Chao", album: "Clandestino"),
        T("Manu Chao/Clandestino/02 Desaparecido.flac", artist: "Manu Chao"),
    ]
    #expect(group(tracks).count == 1)
}

@Test func caseAndSeparatorsDoNotSplitAFolder() {
    let tracks = [
        T("Manu Chao/Clandestino/01 Clandestino.flac", artist: "Manu Chao", album: "Clandestino"),
        T(#"manu chao\clandestino\02 Desaparecido.flac"#, artist: "Manu Chao", album: "Clandestino"),
    ]
    #expect(group(tracks).count == 1)
}

@Test func tracksLooseAtTheLibraryRootAreOneAlbum() {
    let tracks = [
        T("stray one.flac", artist: "Somebody"),
        T("stray two.flac", artist: "Somebody Else"),
    ]
    #expect(group(tracks).count == 1)
    #expect(AlbumGrouping.folder(of: "stray one.flac") == "")
}

/// Rows normally have a path, but `relativePath` is optional in the API, so the tags must be enough. In
/// that case the disc labels are removed from the name.
@Test func withoutAPathTheTagsAnswerAndDiscDecorationsComeOff() {
    let discOne = AlbumGrouping.key(
        relativePath: nil, albumArtist: "Erasure", artist: "Erasure", album: "Erasure (Disc 1)")
    let discTwo = AlbumGrouping.key(
        relativePath: nil, albumArtist: "Erasure", artist: "Erasure", album: "Erasure - CD 2")
    #expect(discOne == discTwo)

    // And the album still belongs to its album artist, not to the track's.
    #expect(AlbumGrouping.key(relativePath: nil, albumArtist: "Various Artists",
                              artist: "Snap!", album: "Now 22")
         == AlbumGrouping.key(relativePath: nil, albumArtist: "Various Artists",
                              artist: "The Shamen", album: "Now 22"))
}

/// A blank tag is treated as missing, so this is not a simple nil-coalescing fallback.
@Test func aBlankAlbumArtistFallsBackToTheTrackArtist() {
    #expect(AlbumGrouping.key(relativePath: nil, albumArtist: nil,
                              artist: "Manu Chao", album: "Clandestino")
         == AlbumGrouping.key(relativePath: nil, albumArtist: "   ",
                              artist: "Manu Chao", album: "Clandestino"))
}

/// Artist/Album/track: the last segment is the album and the one above it is the artist. The desktop's
/// card reads the folder this way before any tag has been opened.
@Test func theFolderNamesTheAlbumWhenNoFileCarriesATag() {
    let tracks = [T("Manu Chao/Clandestino/01 untitled.flac")]
    let folder = AlbumGrouping.folder(of: tracks[0].relativePath)

    #expect(AlbumGrouping.albumName(for: tracks, folder: folder) == "Clandestino")
    #expect(AlbumGrouping.albumArtist(for: tracks, folder: folder) == "Manu Chao")
}

@Test func theAlbumArtistOutranksTheTrackArtistAndBothOutrankTheFolder() {
    let tagged = [T("V/Now 22/01 x.flac", artist: "Snap!", albumArtist: "Various Artists")]
    let trackOnly = [T("V/Now 22/01 x.flac", artist: "Snap!")]

    #expect(AlbumGrouping.albumArtist(for: tagged, folder: "V/Now 22") == "Various Artists")
    #expect(AlbumGrouping.albumArtist(for: trackOnly, folder: "V/Now 22") == "Snap!")
}

/// An untagged disc counts as disc 1. An untagged track sorts last within its own disc, not at the end of
/// the record.
@Test func discsComeApartInReadingOrder() {
    let tracks = [
        T("a/b/d2t1.flac", disc: 2, track: 1),
        T("a/b/d1t2.flac", disc: 1, track: 2),
        T("a/b/nothing.flac"),
        T("a/b/d1t1.flac", disc: 1, track: 1),
    ]

    let discs = AlbumTracklist.byDisc(tracks, discOf: AlbumGrouping.disc(of:),
                                      trackOf: AlbumGrouping.track(of:))

    #expect(discs.count == 2)
    #expect(discs[0].discNumber == 1)
    #expect(discs[0].tracks.map(\.title) == ["d1t1", "d1t2", "nothing"])
    #expect(discs[1].tracks.map(\.title) == ["d2t1"])
}

@Test func aSingleDiscAlbumIsOneSectionSoNoDividerIsDrawn() {
    let tracks = [T("a/b/one.flac", track: 1), T("a/b/two.flac", track: 2)]
    #expect(AlbumTracklist.byDisc(tracks, discOf: AlbumGrouping.disc(of:),
                                 trackOf: AlbumGrouping.track(of:)).count == 1)
}

/// The desktop (C#) has no test for this case.
///
/// The C# code relies on `OrderBy` being a stable sort, so ties keep the order they arrived in.
/// Swift's `sort` is not stable. Without a fix, untagged files on one disc could come back in a
/// different order each time, and the same album would draw a different track list. The Swift code
/// breaks ties by original index to keep the same order. This test checks that.
@Test func untaggedTracksKeepTheOrderTheyArrivedIn() {
    let tracks = [
        T("a/b/first.flac"),
        T("a/b/second.flac"),
        T("a/b/third.flac"),
        T("a/b/fourth.flac"),
        T("a/b/fifth.flac"),
        T("a/b/numbered.flac", track: 1),
    ]

    let discs = AlbumTracklist.byDisc(tracks, discOf: AlbumGrouping.disc(of:),
                                      trackOf: AlbumGrouping.track(of:))

    #expect(discs.count == 1)
    #expect(discs[0].tracks.map(\.title)
        == ["numbered", "first", "second", "third", "fourth", "fifth"])
}

/// A work is a run of consecutive tracks. A recital that plays two nocturnes with a mazurka between them
/// gives three groups, not two.
@Test func worksAreConsecutiveRunsRatherThanEverythingThatNamesThem() {
    var chopin = CloudTrackTags(); chopin.work = "Nocturnes"
    var mazurka = CloudTrackTags(); mazurka.work = "Mazurkas"

    let rows = [("Nocturnes", 1), ("Nocturnes", 2), ("Mazurkas", 1), ("Nocturnes", 3)]
    let groups = AlbumTracklist.byWork(rows, workOf: { $0.0 })

    #expect(groups.count == 3)
    #expect(groups.map(\.work) == ["Nocturnes", "Mazurkas", "Nocturnes"])
}

/// A blank work and a nil work mean the same thing, so a blank must not start a second group.
@Test func aBlankWorkDoesNotOpenASecondGroup() {
    let rows = [("Suite", 1), ("", 2), (nil as String?, 3), ("   ", 4)]
    let groups = AlbumTracklist.byWork(rows, workOf: { $0.0 })

    #expect(groups.count == 2)
    #expect(groups[0].work == "Suite")
    #expect(groups[1].work == nil)
    #expect(groups[1].tracks.count == 3)
}
