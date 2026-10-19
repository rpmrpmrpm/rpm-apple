import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// Which shelf a track belongs to. Streaming, artwork and every write ask this, so a write never
/// lands in another shelf's storage.
///
/// The shelf on screen is not tested here, because it is not stored in this type. It is view state,
/// and keeping it apart from the data shelves is the rule that this split enforces.

private func track(_ id: String) -> CloudTrack { CloudTrack(rpmId: id, title: id) }

@Test func aTrackNobodyHasHeardOfIsTheUsersOwn() {
    #expect(TrackShelves().shelf(of: "unknown").isOwn)
    #expect(TrackShelves().shelf(of: nil).isOwn)
    #expect(TrackShelves().shelf(of: "").isOwn)
}

@Test func aTrackOffABorrowedShelfRemembersWhoseItIs() {
    let shelves = TrackShelves()
    shelves.hold(.of("friend"), tracks: [track("a"), track("b")])

    #expect(shelves.shelf(of: "a").ownerId == "friend")
    #expect(shelves.shelf(of: "b").ownerId == "friend")
}

/// Holding a second shelf keeps the first one. A record that is still playing must not become
/// unplayable because another shelf was held.
@Test func holdingASecondShelfDoesNotForgetTheFirst() {
    let shelves = TrackShelves()
    shelves.hold(.of("one"), tracks: [track("a")])
    shelves.hold(.of("two"), tracks: [track("b")])

    #expect(shelves.shelf(of: "a").ownerId == "one")
    #expect(shelves.shelf(of: "b").ownerId == "two")
}

/// The user's own tracks are the default answer. Storing an "own" entry for each one would copy
/// the whole library into the map and add nothing.
@Test func theUsersOwnListingIsNotWrittenDown() {
    let shelves = TrackShelves()
    shelves.hold(.own, tracks: [track("a")])
    #expect(shelves.shelf(of: "a").isOwn)
}

@Test func anAlbumTakesItsShelfFromItsTracks() {
    let shelves = TrackShelves()
    shelves.hold(.of("friend"), tracks: [track("a"), track("b")])

    let album = CloudAlbum(key: "k", album: "A", artist: "B", tracks: [track("a"), track("b")])
    #expect(shelves.shelf(ofAlbum: album).ownerId == "friend")
}

/// An album with no tracks belongs to nobody and reports the user's own shelf, which is the safe answer.
@Test func anEmptyAlbumIsNobodys() {
    let empty = CloudAlbum(key: "k", album: "A", artist: "B", tracks: [])
    #expect(TrackShelves().shelf(ofAlbum: empty).isOwn)
    #expect(TrackShelves().shelf(ofAlbum: nil).isOwn)
}

@Test func signingOutLeavesNothingOfTheMap() {
    let shelves = TrackShelves()
    shelves.hold(.of("friend"), tracks: [track("a")])
    shelves.forget()

    #expect(shelves.shelf(of: "a").isOwn)
}

/// Reads from the audio path can run while a listing is being stored. The lock makes this safe.
/// The type is not an actor because the player must not suspend to ask.
@Test func askingWhileAListingLandsIsSafe() async {
    let shelves = TrackShelves()

    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            for batch in 0..<50 {
                shelves.hold(.of("friend"),
                             tracks: (0..<100).map { track("t-\(batch)-\($0)") })
            }
        }
        for _ in 0..<4 {
            group.addTask {
                for _ in 0..<5_000 { _ = shelves.shelf(of: "t-0-0") }
            }
        }
    }

    #expect(shelves.shelf(of: "t-49-99").ownerId == "friend")
}
