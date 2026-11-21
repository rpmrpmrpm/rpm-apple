import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

private func song(_ id: String, advisory: Int) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.advisory = advisory
    return CloudTrack(rpmId: id, relativePath: "Act/Record/\(id).flac", title: id,
                      artist: "Act", album: "Record", tags: tags)
}

/// A record wears the E when any of its songs is explicit, as the desktop decides.
@Test func aRecordWithOneExplicitSongIsExplicit() {
    let album = CloudAlbum(key: "k", album: "Record", artist: "Act",
                           tracks: [song("a", advisory: 0), song("b", advisory: 1)])
    #expect(album.isExplicit)
}

/// Two means somebody said the song is clean. Only one shows the E.
@Test func aRecordOfCleanAndUnknownSongsIsNotExplicit() {
    let album = CloudAlbum(key: "k", album: "Record", artist: "Act",
                           tracks: [song("a", advisory: 0), song("b", advisory: 2)])
    #expect(!album.isExplicit)
}
