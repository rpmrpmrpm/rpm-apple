import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

private func track(_ id: String, title: String, artist: String? = nil) -> CloudTrack {
    CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: title,
               artist: artist, album: nil, tags: CloudTrackTags())
}

private func album(_ name: String, by artist: String, _ tracks: [CloudTrack]) -> CloudAlbum {
    CloudAlbum(key: name, album: name, artist: artist, tracks: tracks)
}

private let library = [
    album("Spirit of Eden", by: "Talk Talk",
          [track("a", title: "The Rainbow"), track("b", title: "Desire")]),
    album("Hex", by: "Bark Psychosis",
          [track("c", title: "The Loom"), track("d", title: "Absent Friend")]),
]

@Test func aSongIsFoundByItsTitle() {
    #expect(SongSearch.through(library, for: "rainbow").map(\.track.rpmId) == ["a"])
}

@Test func aSongIsFoundByTheRecordItIsOn() {
    #expect(SongSearch.through(library, for: "hex").map(\.track.rpmId) == ["c", "d"])
}

/// On a compilation the track's artist and the record's artist differ. A search matches either one.
@Test func aSongIsFoundByTheRecordsArtistAsWellAsItsOwn() {
    let mixed = [album("Now 42", by: "Various",
                       [track("x", title: "Song", artist: "Erasure")])]

    #expect(SongSearch.through(mixed, for: "erasure").count == 1)
    #expect(SongSearch.through(mixed, for: "various").count == 1)
}

@Test func caseIsNotPartOfTheQuestion() {
    #expect(SongSearch.through(library, for: "TALK talk").count == 2)
}

@Test func typingNothingFindsNothingRatherThanEverything() {
    #expect(SongSearch.through(library, for: "   ").isEmpty)
}

/// A search returns at most `SongSearch.ceiling` rows. Showing every match would make the list too long
/// to be useful.
@Test func aSearchStopsAtTheCeiling() {
    let many = (0..<500).map { track("t\($0)", title: "Song \($0)") }
    #expect(SongSearch.through([album("Big", by: "Somebody", many)], for: "song").count
            == SongSearch.ceiling)
}

// ── the records themselves ──

/// This is a separate search, not a filter on the song search. Song results already cover "everything
/// on Hex". A record result is a different kind of row, which opens the record's page.
@Test func aRecordIsFoundByItsName() {
    #expect(SongSearch.records(library, for: "hex").map(\.album) == ["Hex"])
}

@Test func aRecordIsFoundByItsArtist() {
    #expect(SongSearch.records(library, for: "talk talk").map(\.album) == ["Spirit of Eden"])
}

/// A record is not listed just because one of its songs matches. Such a row would look like a wrong
/// result.
@Test func aRecordIsNotFoundByWhatIsOnIt() {
    #expect(SongSearch.records(library, for: "rainbow").isEmpty)
}

@Test func typingNothingFindsNoRecordsEither() {
    #expect(SongSearch.records(library, for: " ").isEmpty)
}

@Test func recordsStopAtTheirOwnCeiling() {
    let many = (0..<200).map { album("Record \($0)", by: "Somebody", []) }

    #expect(SongSearch.records(many, for: "record").count == SongSearch.recordCeiling)
}

@Test func theRecordASongCameOffIsFoundByItsId() {
    #expect(SongSearch.albumOf(track("c", title: "The Loom"), in: library).album == "Hex")
}

/// A song whose record is not in the library gets a one-track record built from its own tags.
/// Returning nil would force every caller to write the same fallback.
@Test func aSongWithNoRecordHereAnswersWithOneOfItsOwn() {
    let orphan = CloudTrack(rpmId: "z", relativePath: "x/z.flac", title: "Stray",
                            artist: "Nobody", album: "Nowhere", tags: CloudTrackTags())

    let found = SongSearch.albumOf(orphan, in: library)
    #expect(found.album == "Nowhere")
    #expect(found.tracks.map(\.rpmId) == ["z"])
}

// ── the words moving on ──

/// Each keystroke starts a walk of the whole library. If a walk cannot be stopped, one walk per keystroke
/// runs at once on the thread pool. Both walks check for cancellation, so they stop when their task is
/// cancelled.
@Test func aSongSearchStopsWhenTheWordsMoveOn() async {
    let walk = Task { () -> [SongSearch.SongHit] in
        while !Task.isCancelled { await Task.yield() }
        return SongSearch.through(library, for: "the")
    }

    walk.cancel()
    #expect(await walk.value.isEmpty)
}

@Test func aRecordSearchStopsWhenTheWordsMoveOn() async {
    let walk = Task { () -> [CloudAlbum] in
        while !Task.isCancelled { await Task.yield() }
        return SongSearch.records(library, for: "hex")
    }

    walk.cancel()
    #expect(await walk.value.isEmpty)
}
