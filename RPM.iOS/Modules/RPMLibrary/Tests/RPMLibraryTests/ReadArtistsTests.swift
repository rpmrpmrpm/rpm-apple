import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// Which artist's page a track opens from the player.
@Suite struct ArtistOfATrackTests {

    private func row(_ id: String, _ folder: String, artist: String,
                     albumArtist: String? = nil) -> CloudTrack {
        var tags = CloudTrackTags()
        tags.albumArtist = albumArtist
        return CloudTrack(rpmId: id, relativePath: "\(folder)/\(id).flac", title: id,
                          artist: artist, tags: tags)
    }

    private func find(_ track: CloudTrack, among rows: [CloudTrack]) -> String? {
        ReadArtists().artist(of: track, in: AlbumWall.group(rows))?.name
    }

    @Test func aTrackByTheRecordsOwnArtistOpensTheirPage() {
        let song = row("a1", "ABBA/Arrival", artist: "ABBA")

        #expect(find(song, among: [song, row("a2", "ABBA/Arrival", artist: "ABBA")]) == "ABBA")
    }

    /// The guest has no records of their own, so has no page. The lead act in the credit has one.
    @Test func aFeaturedCreditOpensTheLeadAct() {
        let song = row("c2", "Calvin Harris/18 Months", artist: "Calvin Harris feat. Ellie Goulding")
        let rows = [row("c1", "Calvin Harris/18 Months", artist: "Calvin Harris"), song]

        #expect(find(song, among: rows) == "Calvin Harris")
    }

    /// The full credit is looked up before its parts are split. Splitting on the comma and the
    /// ampersand would turn this band into three people nobody has heard of.
    @Test func aBandWithASeparatorInItsNameIsFoundAsItself() {
        let song = row("e1", "Earth, Wind & Fire/I Am", artist: "Earth, Wind & Fire",
                       albumArtist: "Earth, Wind & Fire")

        #expect(find(song, among: [song]) == "Earth, Wind & Fire")
    }

    /// A song on another artist's record opens the page of its singer, if that artist has a page. It
    /// does not open the page of the record's artist.
    @Test func aSongOnSomebodyElsesRecordOpensItsOwnArtist() {
        let song = row("h2", "Calvin Harris/18 Months", artist: "Rihanna",
                       albumArtist: "Calvin Harris")
        let rows = [row("h1", "Calvin Harris/18 Months", artist: "Calvin Harris",
                        albumArtist: "Calvin Harris"),
                    song,
                    row("r1", "Rihanna/Loud", artist: "Rihanna")]

        #expect(find(song, among: rows) == "Rihanna")
    }

    /// If nobody on the track has a page, the track opens the compilations page.
    @Test func aCompilationTrackByNobodyWithAPageOpensTheCompilations() {
        let song = row("v1", "Various Artists/Now 12", artist: "Some Band",
                       albumArtist: "Various")
        let rows = [song, row("v2", "Various Artists/Now 12", artist: "Other Band",
                              albumArtist: "Various")]

        #expect(find(song, among: rows) == ArtistWall.compilations)
    }
}

/// Which artist pages the artist line on an album page opens.
@Suite struct ArtistsOfAnAlbumTests {

    private func row(_ id: String, _ folder: String, artist: String,
                     albumArtist: String? = nil) -> CloudTrack {
        var tags = CloudTrackTags()
        tags.albumArtist = albumArtist
        return CloudTrack(rpmId: id, relativePath: "\(folder)/\(id).flac", title: id,
                          artist: artist, tags: tags)
    }

    private func names(_ folder: String, among rows: [CloudTrack]) throws -> [String] {
        let albums = AlbumWall.group(rows)
        let album = try #require(albums.first { album in
            album.tracks.contains { $0.relativePath?.hasPrefix(folder + "/") == true }
        })
        return ReadArtists().artists(of: album, in: albums).map(\.name)
    }

    @Test func aRecordByOneActOpensTheirPage() throws {
        let rows = [row("a1", "ABBA/Arrival", artist: "ABBA"),
                    row("a2", "ABBA/Arrival", artist: "ABBA")]

        #expect(try names("ABBA/Arrival", among: rows) == ["ABBA"])
    }

    /// A guest who sings on one track is not an artist of the record, so the album page does not link
    /// to them.
    @Test func aGuestOnOneTrackIsNotLinked() throws {
        let rows = [row("h1", "Calvin Harris/18 Months", artist: "Calvin Harris",
                        albumArtist: "Calvin Harris"),
                    row("h2", "Calvin Harris/18 Months", artist: "Rihanna",
                        albumArtist: "Calvin Harris"),
                    row("r1", "Rihanna/Loud", artist: "Rihanna")]

        #expect(try names("Calvin Harris/18 Months", among: rows) == ["Calvin Harris"])
    }

    /// Both acts have pages of their own, so the record is on both pages. They are listed in credit
    /// order, not in name order.
    @Test func aRecordTwoActsMadeLinksBothInCreditOrder() throws {
        let rows = [row("q1", "Queen/Hot Space", artist: "Queen"),
                    row("d1", "David Bowie/Low", artist: "David Bowie"),
                    row("u1", "Queen & David Bowie/Under Pressure",
                        artist: "Queen & David Bowie",
                        albumArtist: "Queen & David Bowie")]

        #expect(try names("Queen & David Bowie/Under Pressure", among: rows)
                == ["Queen", "David Bowie"])
    }

    @Test func aCompilationOpensTheCompilations() throws {
        let rows = [row("v1", "Various Artists/Now 12", artist: "Some Band", albumArtist: "Various"),
                    row("v2", "Various Artists/Now 12", artist: "Other Band", albumArtist: "Various")]

        #expect(try names("Various Artists/Now 12", among: rows) == [ArtistWall.compilations])
    }

    @Test func anAlbumNotInTheLibraryLinksNobody() {
        let rows = [row("a1", "ABBA/Arrival", artist: "ABBA")]
        let other = AlbumWall.group([row("b1", "Blur/Parklife", artist: "Blur")])[0]

        #expect(ReadArtists().artists(of: other, in: AlbumWall.group(rows)).isEmpty)
    }
}
