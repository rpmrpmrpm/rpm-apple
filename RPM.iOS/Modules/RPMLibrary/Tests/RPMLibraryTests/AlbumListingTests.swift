import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

private func song(_ title: String, _ artist: String, _ album: String, number: Int = 0) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.trackNumber = number
    return CloudTrack(rpmId: "\(artist)/\(album)/\(title)", relativePath: "x/\(title).flac",
                      title: title, artist: artist, album: album, tags: tags)
}

private func record(_ artist: String, _ album: String, _ titles: [String] = ["One"]) -> CloudAlbum {
    CloudAlbum(key: "\(artist)|\(album)", album: album, artist: artist,
               tracks: titles.enumerated().map { song($1, artist, album, number: $0 + 1) })
}

private func names(_ listing: AlbumListing) -> [String] {
    listing.rows.map {
        switch $0 {
        case .record(let album): album.artist + " / " + album.album
        case .song(let track, _): track.title ?? ""
        }
    }
}

/// The letter first, then the name: "(hed) p.e." is filed under H, so it must not sort ahead of
/// every A. Names with no letter go last, under "#".
@Test func byArtistTheRailsLettersRunInOrderDownTheList() {
    let listing = AlbumListing.of([record("10cc", "Sheet Music"), record("(hed) p.e.", "Broke"),
                                   record("Björk", "Debut"), record("ABBA", "Arrival")],
                                  by: .artist)

    #expect(names(listing) == ["ABBA / Arrival", "Björk / Debut", "(hed) p.e. / Broke",
                               "10cc / Sheet Music"])
    #expect(listing.firstUnder["A"] == "record:ABBA|Arrival")
    #expect(listing.firstUnder["H"] == "record:(hed) p.e.|Broke")
    #expect(listing.firstUnder["#"] == "record:10cc|Sheet Music")
    #expect(listing.firstUnder["C"] == nil)
}

@Test func byArtistOneArtistsRecordsAreInTitleOrder() {
    let listing = AlbumListing.of([record("Talk Talk", "Spirit of Eden"),
                                   record("Talk Talk", "Laughing Stock"),
                                   record("talk talk", "Colour of Spring")], by: .artist)

    #expect(names(listing) == ["talk talk / Colour of Spring", "Talk Talk / Laughing Stock",
                               "Talk Talk / Spirit of Eden"])
}

@Test func accentsAndCaseDoNotSeparateNames() {
    let listing = AlbumListing.of([record("Emilie Simon", "B"), record("Émilie Simon", "A"),
                                   record("EMILIE SIMON", "C")], by: .artist)

    #expect(names(listing) == ["Émilie Simon / A", "Emilie Simon / B", "EMILIE SIMON / C"])
    #expect(listing.firstUnder.keys.sorted() == ["E"])
}

@Test func byAlbumTheRecordsNameLeads() {
    let listing = AlbumListing.of([record("Air", "Moon Safari"), record("Blur", "13"),
                                   record("Portishead", "Dummy")], by: .album)

    #expect(names(listing) == ["Portishead / Dummy", "Air / Moon Safari", "Blur / 13"])
    #expect(listing.firstUnder["D"] == "record:Portishead|Dummy")
    #expect(listing.firstUnder["#"] == "record:Blur|13")
}

/// In track order every song is its own row, by title, with the record it is on.
@Test func byTrackEverySongIsARowByTitle() {
    let listing = AlbumListing.of([record("Air", "Moon Safari", ["Sexy Boy", "All I Need"]),
                                   record("Blur", "13", ["Tender", "Bugman"])], by: .track)

    #expect(names(listing) == ["All I Need", "Bugman", "Sexy Boy", "Tender"])
    if case .song(_, let on) = listing.rows[1] { #expect(on.album == "13") } else { Issue.record() }
    #expect(Set(listing.rows.map(\.id)).count == 4)
    #expect(listing.firstUnder.keys.sorted() == ["A", "B", "S", "T"])
}

/// Two songs with one title: the artist, then the record, decide.
@Test func byTrackTheSameTitleIsOrderedByArtistThenRecord() {
    let listing = AlbumListing.of([record("Nina Simone", "Live", ["Feeling Good"]),
                                   record("Muse", "Origin", ["Feeling Good"]),
                                   record("Nina Simone", "Baltimore", ["Feeling Good"])],
                                  by: .track)

    let on = listing.rows.compactMap { row -> String? in
        if case .song(_, let album) = row { return album.artist + " / " + album.album }
        return nil
    }
    #expect(on == ["Muse / Origin", "Nina Simone / Baltimore", "Nina Simone / Live"])
}

@Test func nothingListsNothing() {
    let listing = AlbumListing.of([], by: .track)
    #expect(listing.rows.isEmpty)
    #expect(listing.firstUnder.isEmpty)
}
