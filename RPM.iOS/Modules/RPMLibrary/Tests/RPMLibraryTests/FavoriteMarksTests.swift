import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// Mirrors the desktop's `RPM.Core.Tests/FavoriteMarksTests.cs`, so both apps handle marks the same way.
///
/// The important questions here are about order. A mark is sent to the server, and later a
/// catalogue that contains it is read. A read of the whole catalogue is often already in flight
/// when the user taps. So each test asks the same question from a different side: does the answer
/// depend on which of the two arrives first?

private func track(_ id: String, favorite: Bool = false, at: Int64 = 0) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.favorite = favorite
    tags.favoritedAt = at
    return CloudTrack(rpmId: id, sha256: id, title: id, tags: tags)
}

// ── what the catalogue says ──

@MainActor @Test func nothingIsLovedBeforeACatalogHasBeenRead() {
    #expect(FavoriteMarks().isMarked("a") == false)
}

@MainActor @Test func aCatalogRowMarkedAFavouriteIsLoved() {
    let marks = FavoriteMarks()
    marks.read([track("a", favorite: true), track("b")])

    #expect(marks.isMarked("a"))
    #expect(marks.isMarked("b") == false)
}

/// The desktop can clear a mark. A catalogue is always read in full, so a song that the catalogue no longer
/// marks is unmarked.
@MainActor @Test func aCatalogThatNoLongerMarksASongUnlovesIt() {
    let marks = FavoriteMarks()
    marks.read([track("a", favorite: true)])
    marks.read([track("a")])

    #expect(marks.isMarked("a") == false)
}

// ── what this phone says ──

@MainActor @Test func aMarkMadeHereIsSeenAtOnce() {
    let marks = FavoriteMarks()
    marks.note("a", favorite: true, at: 7)
    #expect(marks.isMarked("a"))
}

@MainActor @Test func clearingAMarkTheCatalogMadeIsSeenAtOnce() {
    let marks = FavoriteMarks()
    marks.read([track("a", favorite: true, at: 3)])
    marks.note("a", favorite: false, at: 0)

    #expect(marks.isMarked("a") == false)
}

// ── and which of the two wins ──

/// This ordering is why a separate type is needed. The refresh started before the tap, so its listing cannot
/// know about the tap, and it must not undo it.
@MainActor @Test func aCatalogReadBeforeTheTapDoesNotUndoTheTap() {
    let marks = FavoriteMarks()
    marks.note("a", favorite: true, at: 10)

    // The listing that was already on its way. It has "a" unmarked.
    marks.read([track("a")])

    #expect(marks.isMarked("a"))
}

@MainActor @Test func aCatalogReadBeforeAnUnmarkDoesNotBringTheMarkBack() {
    let marks = FavoriteMarks()
    marks.read([track("a", favorite: true, at: 3)])
    marks.note("a", favorite: false, at: 0)
    marks.read([track("a", favorite: true, at: 3)])

    #expect(marks.isMarked("a") == false)
}

/// Once a listing agrees with the phone, the phone has nothing more to say. The next listing is then trusted,
/// even if it shows that the desktop has cleared the mark.
@MainActor @Test func aCatalogThatHasCaughtUpTakesTheMarkBackOver() {
    let marks = FavoriteMarks()
    marks.note("a", favorite: true, at: 10)

    // The push has reached the store: this listing has it.
    marks.read([track("a", favorite: true, at: 10)])

    // And now the mark is cleared from a computer.
    marks.read([track("a")])

    #expect(marks.isMarked("a") == false)
}

// ── the stamp, which is what orders the favourites list ──

@MainActor @Test func aSongsStampIsTheOneTheCatalogCarried() {
    let marks = FavoriteMarks()
    marks.read([track("a", favorite: true, at: 42)])
    #expect(marks.markedAt("a") == 42)
}

/// A song marked a moment ago comes first in a list ordered newest first.
@MainActor @Test func aMarkMadeHereCarriesItsOwnStamp() {
    let marks = FavoriteMarks()
    marks.read([track("a", favorite: true, at: 42)])
    marks.note("b", favorite: true, at: 99)

    #expect(marks.markedAt("b") == 99)
    #expect(marks.markedAt("a") == 42)
}

@MainActor @Test func anUnlovedSongHasNoStamp() {
    let marks = FavoriteMarks()
    marks.read([track("a", favorite: true, at: 42)])
    marks.note("a", favorite: false, at: 77)

    #expect(marks.markedAt("a") == 0)
}

// ── putting one back ──

/// A refused push restores the mark the song had before, not the opposite mark. A song marked from two
/// screens at once would otherwise be put back in a state it was never in.
@MainActor @Test func whatASongWasBeforeAMarkIsTheMarkAndItsStamp() {
    let marks = FavoriteMarks()
    marks.read([track("a", favorite: true, at: 42)])

    let before = marks.markOf("a")
    marks.note("a", favorite: false, at: 0)
    marks.note("a", favorite: before.on, at: before.at)

    #expect(marks.isMarked("a"))
    #expect(marks.markedAt("a") == 42)
}

@MainActor @Test func aSongNobodyHasMarkedWasNothingAtAll() {
    #expect(FavoriteMarks().markOf("a") == FavoriteMarks.Mark(on: false, at: 0))
}

// ── being told ──
//
// There is no test here. FavoriteMarks is @Observable, so a heart redraws because it read a mark that
// changed. Nothing calls it back. Testing that would mean testing SwiftUI.

// ── signing out ──

@MainActor @Test func signingOutLeavesNothingOfEitherLayer() {
    let marks = FavoriteMarks()
    marks.read([track("a", favorite: true, at: 42)])
    marks.note("b", favorite: true, at: 99)

    marks.forget()

    #expect(marks.isMarked("a") == false)
    #expect(marks.isMarked("b") == false)
}

// ── the generated list ──

/// The list is built from the rows each time, not stored by anyone.
@MainActor
@Test func theMarkedSongsComeBackNewestMarkFirst() {
    let marks = FavoriteMarks()

    func song(_ id: String, _ title: String) -> CloudTrack {
        CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: title,
                   artist: "Talk Talk", album: "Spirit of Eden", tags: CloudTrackTags())
    }

    let album = CloudAlbum(key: "k", album: "Spirit of Eden", artist: "Talk Talk",
                           tracks: [song("a", "Desire"), song("b", "Inheritance"),
                                    song("c", "Wealth")])

    marks.note("a", favorite: true, at: 100)
    marks.note("c", favorite: true, at: 300)

    #expect(marks.marked(in: [album]).map(\.rpmId) == ["c", "a"])
}

/// Marks read from one listing all carry the same time. The list then sorts them by name, so that it keeps
/// the same order between launches.
@MainActor
@Test func marksMadeAtTheSameInstantAreOrderedByName() {
    let marks = FavoriteMarks()

    func song(_ id: String, _ title: String) -> CloudTrack {
        CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: title,
                   artist: "Talk Talk", album: "Spirit of Eden", tags: CloudTrackTags())
    }

    let album = CloudAlbum(key: "k", album: "Spirit of Eden", artist: "Talk Talk",
                           tracks: [song("a", "Wealth"), song("b", "Desire")])

    marks.note("a", favorite: true, at: 7)
    marks.note("b", favorite: true, at: 7)

    #expect(marks.marked(in: [album]).map(\.title) == ["Desire", "Wealth"])
}

@MainActor
@Test func aLibraryWithNoMarksGeneratesNothing() {
    let marks = FavoriteMarks()
    let album = CloudAlbum(key: "k", album: "a", artist: "b", tracks: [])

    #expect(marks.marked(in: [album]).isEmpty)
}
