import Testing
import Foundation
@testable import RPMKit

/// The album key is a contract between two programs that never speak to each
/// other: a computer hashes it to decide where to put a cover, a phone hashes it
/// to decide where to ask for one, and nothing carries it between them. If the two
/// ever disagree, no cover is ever found and nothing anywhere reports an error.
/// The wall simply stays empty.

@Test func theSameAlbumHashesTheSameHoweverItIsWritten() {
    let canonical = AlbumArtKey.of(.cover, albumArtist: "Manu Chao", album: "Clandestino")

    #expect(AlbumArtKey.of(.cover, albumArtist: "manu chao", album: "clandestino") == canonical)
    #expect(AlbumArtKey.of(.cover, albumArtist: "  Manu Chao  ", album: "Clandestino ") == canonical)
    #expect(AlbumArtKey.of(.cover, albumArtist: "MANU CHAO", album: "CLANDESTINO") == canonical)
}

@Test func differentAlbumsDoNotCollide() {
    #expect(AlbumArtKey.of(.cover, albumArtist: "Manu Chao", album: "Clandestino")
            != AlbumArtKey.of(.cover, albumArtist: "Manu Chao", album: "Próxima Estación"))

    // One title by two artists is two records.
    #expect(AlbumArtKey.of(.cover, albumArtist: "Weezer", album: "Greatest Hits")
            != AlbumArtKey.of(.cover, albumArtist: "Queen", album: "Greatest Hits"))
}

/// It ends up as one component of a path under somebody's own prefix, so a record
/// called "../../etc" must not be able to reach out of it. Hashing is what
/// guarantees that, rather than escaping.
@Test func theKeyIsSafeAsAPathComponentWhateverTheRecordIsCalled() {
    let awkward = ["../../../etc/passwd", "AC/DC", "Album: The \"Deluxe\" Edition",
                   "\u{202E}reversed", "🎵 emoji 🎵", ""]

    for name in awkward {
        let key = AlbumArtKey.of(.cover, albumArtist: "Artist", album: name)

        #expect(key.count == 32)
        #expect(key.allSatisfy { $0.isHexDigit && !$0.isUppercase },
                "\(key) is not lower-case hex, from \(name)")
    }
}

@Test func aMissingArtistOrAlbumStillProducesAKey() {
    // Unknown albums are real, and they still want one cover between them.
    #expect(AlbumArtKey.of(.cover, albumArtist: nil, album: nil).count == 32)
    #expect(AlbumArtKey.of(.cover, albumArtist: "", album: "   ")
            == AlbumArtKey.of(.cover, albumArtist: nil, album: nil))
}

/// **The single most valuable test in this file.** Changing the derivation orphans
/// every cover already stored, for every user, silently. The value is the one the
/// desktop's own test pins, so a failure here is these two programs having stopped
/// agreeing.
@Test func theHashIsPinnedToWhatTheDesktopWrites() {
    #expect(AlbumArtKey.of(.cover, albumArtist: "Manu Chao", album: "Clandestino")
            == "d90d382db82e7ba38c335b59ae3eaf33")
}

// ── which artist names the record ──

/// A tag that is present but blank is not an album artist. This is the trap the
/// fallback lives in one place for: `??` files the record under the empty string.
@Test func aBlankAlbumArtistIsNotAnAlbumArtist() {
    #expect(AlbumArtKey.forTrack(.cover, albumArtist: "   ", artist: "Someone", album: "Record")
            == AlbumArtKey.of(.cover, albumArtist: "Someone", album: "Record"))

    #expect(AlbumArtKey.forTrack(.cover, albumArtist: nil, artist: "Someone", album: "Record")
            == AlbumArtKey.of(.cover, albumArtist: "Someone", album: "Record"))
}

@Test func anAlbumBelongsToItsAlbumArtistWhereThereIsOne() {
    #expect(AlbumArtKey.forTrack(.cover, albumArtist: "Various Artists", artist: "Snap!", album: "Now 22")
            == AlbumArtKey.of(.cover, albumArtist: "Various Artists", album: "Now 22"))
}

// ── both spellings ──

/// A compilation is filed under "Various Artists" by whoever uploaded it and under
/// the track artist by a catalogue that has no album artist on it yet. Asking under
/// both is the difference between a sleeve and a placeholder.
@Test func aCompilationIsAskedAboutUnderBothNames() {
    let keys = AlbumArtKey.spellings(.cover, albumArtist: "Various Artists", artist: "Snap!", album: "Now 22")

    #expect(keys.count == 2)
    #expect(keys[0] == AlbumArtKey.of(.cover, albumArtist: "Various Artists", album: "Now 22"))
    #expect(keys[1] == AlbumArtKey.of(.cover, albumArtist: "Snap!", album: "Now 22"))
}

@Test func anOrdinaryRecordIsOneSpelling() {
    #expect(AlbumArtKey.spellings(.cover, albumArtist: "Nick Drake", artist: "Nick Drake",
                                  album: "Pink Moon").count == 1)
    #expect(AlbumArtKey.spellings(.cover, albumArtist: nil, artist: "Nick Drake",
                                  album: "Pink Moon").count == 1)
}

/// A set ripped in two sittings can carry the album artist on half its files, and
/// the cover was uploaded under whichever of them the desktop happened to hold.
@Test func aRecordIsAskedAboutUnderEverySpellingItsTracksKnow() {
    func track(_ id: String, albumArtist: String?) -> CloudTrack {
        var tags = CloudTrackTags()
        tags.albumArtist = albumArtist
        return CloudTrack(rpmId: id, relativePath: "x/\(id).flac",
                          title: id, artist: "Snap!", album: "Now 22", tags: tags)
    }

    let keys = AlbumArtKey.spellings(.cover, for: [track("a", albumArtist: nil),
                                           track("b", albumArtist: "Various Artists")])

    #expect(keys.contains(AlbumArtKey.of(.cover, albumArtist: "Snap!", album: "Now 22")))
    #expect(keys.contains(AlbumArtKey.of(.cover, albumArtist: "Various Artists", album: "Now 22")))
}

@Test func aSpellingIsOnlyAskedAboutOnce() {
    func track(_ id: String) -> CloudTrack {
        CloudTrack(rpmId: id, relativePath: "x/\(id).flac",
                   title: id, artist: "Nick Drake", album: "Pink Moon")
    }

    let keys = AlbumArtKey.spellings(.cover, for: [track("a"), track("b"), track("c")])
    #expect(keys.count == 1)
}

/// The order is the order they were met, so the same record asks in the same order
/// every time. A store that answered two of them would otherwise hand back a
/// different picture on different runs.
@Test func theSpellingsComeOutInAFixedOrder() {
    func track(_ id: String, artist: String) -> CloudTrack {
        CloudTrack(rpmId: id, relativePath: "x/\(id).flac",
                   title: id, artist: artist, album: "Now 22")
    }

    let tracks = (0..<12).map { track("t\($0)", artist: "Artist \($0)") }
    let once = AlbumArtKey.spellings(.cover, for: tracks)

    for _ in 0..<10 {
        #expect(AlbumArtKey.spellings(.cover, for: tracks) == once)
    }
}

// ── the record's own picture ──

/// The label printed on the disc is a second picture of the same album, stored beside
/// the cover under one prefix. It must never land on the cover's key: whichever was
/// written second would be the one both screens showed.
@Test func aDiscLabelIsNotFiledWhereTheCoverIs() {
    #expect(AlbumArtKey.of(.cover, albumArtist: "Manu Chao", album: "Clandestino")
            != AlbumArtKey.of(.disc, albumArtist: "Manu Chao", album: "Clandestino"))
}

/// **The one test that says the phone and the desktop agree.** This literal is the
/// desktop's own, asserted in `AlbumArtTests.The_disc_hash_is_pinned`, and the two
/// programs arrive at it without ever exchanging it. Changing either side orphans
/// every disc label already stored, silently, for everyone.
@Test func theDiscHashIsPinnedToTheDesktops() {
    #expect(AlbumArtKey.of(.disc, albumArtist: "Manu Chao", album: "Clandestino")
            == "ee1067d65d84ffa7e4c8b433b457284d")
}

/// The store checks nothing about a key but its shape, so a disc key that is anything
/// but thirty-two lower-case hex characters is a 400 rather than a picture.
@Test func aDiscKeyHasTheShapeTheStoreAccepts() {
    let key = AlbumArtKey.of(.disc, albumArtist: "AC/DC", album: "Back in Black 🎵")

    #expect(key.count == 32)
    #expect(key.allSatisfy { $0.isHexDigit && !$0.isUppercase })
}

/// The same normalisation and the same album-artist-then-artist fallback the cover
/// follows: the two pictures of one record have to agree about whose record it is, or
/// one program stores the label where the other will not look for it.
@Test func aDiscLabelFollowsTheCoversRulesAboutWhoseRecordItIs() {
    #expect(AlbumArtKey.of(.disc, albumArtist: "  MANU CHAO ", album: "clandestino")
            == AlbumArtKey.of(.disc, albumArtist: "Manu Chao", album: "Clandestino"))

    #expect(AlbumArtKey.forTrack(.disc, albumArtist: "Various Artists",
                                 artist: "Snap!", album: "Now 22")
            == AlbumArtKey.of(.disc, albumArtist: "Various Artists", album: "Now 22"))

    // A blank album artist is not an album artist: the same trap `forTrack` exists for.
    #expect(AlbumArtKey.forTrack(.disc, albumArtist: "   ", artist: "Someone", album: "Record")
            == AlbumArtKey.of(.disc, albumArtist: "Someone", album: "Record"))
}

/// A record filed under two spellings has its disc label under two as well. The
/// desktop uploads whichever the track it was holding spelled it as, so a phone that
/// asked under only one would find the sleeve and miss the record.
@Test func aDiscLabelIsAskedForUnderBothSpellingsToo() {
    var tags = CloudTrackTags()
    tags.albumArtist = "Various Artists"

    let track = CloudTrack(rpmId: "a", relativePath: "x/a.flac",
                           title: "a", artist: "Snap!", album: "Now 22", tags: tags)

    let keys = AlbumArtKey.spellings(.disc, for: [track])

    #expect(keys.count == 2)
    #expect(keys[0] == AlbumArtKey.of(.disc, albumArtist: "Various Artists", album: "Now 22"))
    #expect(keys[1] == AlbumArtKey.of(.disc, albumArtist: "Snap!", album: "Now 22"))

    // And none of them is a cover's.
    #expect(Set(keys).isDisjoint(with: Set(AlbumArtKey.spellings(.cover, for: [track]))))
}

/// Transparency is the disc's whole shape: it is cut round out of a photograph, and
/// the corners of the photograph are made transparent. The store keeps a picture in
/// whatever format this says, so a wrong answer here shows a rectangle around the
/// turning disc.
@Test func onlyTheDiscKeepsItsTransparency() {
    #expect(RecordPicture.disc.keepsAlpha)
    #expect(!RecordPicture.cover.keepsAlpha)
}
