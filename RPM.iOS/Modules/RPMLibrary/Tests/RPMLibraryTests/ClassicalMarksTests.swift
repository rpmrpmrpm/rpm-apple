import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// Which records are marked classical, on each shelf. The album page and the player ask this.

private func track(_ artist: String, _ album: String, albumArtist: String? = nil) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.albumArtist = albumArtist
    return CloudTrack(rpmId: "\(artist)-\(album)", relativePath: "\(artist)/\(album)/1.flac",
                      title: "1", artist: artist, album: album, tags: tags)
}

private func mark(_ key: String, classical: Bool?) -> CloudAlbumMark {
    CloudAlbumMark(albumKey: key, favorite: false, classical: classical)
}

private let uchida = track("Mitsuko Uchida", "Piano Sonatas")
private let uchidaKey = AlbumArtKey.of(.cover, albumArtist: "Mitsuko Uchida", album: "Piano Sonatas")

@MainActor
@Test func aRecordMarkedClassicalOnItsShelfIsClassical() {
    let marks = ClassicalMarks()
    marks.file([mark(uchidaKey, classical: true)], for: .own)

    #expect(marks.isClassical(uchida, on: .own))
}

/// A record marked `false` and a record with no mark (`nil`) are both ordinary records.
@MainActor
@Test func onlyATrueAnswerIsClassical() {
    let marks = ClassicalMarks()
    marks.file([mark(uchidaKey, classical: false)], for: .own)
    #expect(!marks.isClassical(uchida, on: .own))

    marks.file([mark(uchidaKey, classical: nil)], for: .own)
    #expect(!marks.isClassical(uchida, on: .own))
}

/// A borrowed shelf uses its owner's answer. The user's own mark on the same record does not
/// apply to the friend's copy, and the reverse is also true.
@MainActor
@Test func eachShelfHasItsOwnAnswer() {
    let marks = ClassicalMarks()
    marks.file([mark(uchidaKey, classical: true)], for: .of("friend"))

    #expect(marks.isClassical(uchida, on: .of("friend")))
    #expect(!marks.isClassical(uchida, on: .own))
}

/// The desktop builds a mark's key from whichever album artist its tags hold. A track whose album
/// artist tag is spelt differently is still found under the track artist's spelling.
@MainActor
@Test func aRecordIsFoundUnderEitherSpellingOfItsKey() {
    let marks = ClassicalMarks()
    marks.file([mark(uchidaKey, classical: true)], for: .own)

    let tagged = track("Mitsuko Uchida", "Piano Sonatas", albumArtist: "Uchida, Mitsuko")
    #expect(marks.isClassical(tagged, on: .own))
}

/// A key from the wall's grouping is not a marks key, and must never match one.
@MainActor
@Test func theWallsGroupingKeyIsNotAMarksKey() {
    let marks = ClassicalMarks()
    marks.file([mark(AlbumGrouping.key(for: uchida), classical: true)], for: .own)

    #expect(!marks.isClassical(uchida, on: .own))
}

@MainActor
@Test func forgettingDropsEveryShelf() {
    let marks = ClassicalMarks()
    marks.file([mark(uchidaKey, classical: true)], for: .own)
    marks.file([mark(uchidaKey, classical: true)], for: .of("friend"))

    marks.forget()

    #expect(!marks.isClassical(uchida, on: .own))
    #expect(!marks.isClassical(uchida, on: .of("friend")))
}
