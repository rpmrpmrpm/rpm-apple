import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

private func track(_ id: String, seconds: Double = 100) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.durationSeconds = seconds
    return CloudTrack(rpmId: id, title: id, tags: tags)
}

private func list(_ id: String, _ name: String, _ ids: [String],
                  folder: [String]? = nil, updatedAt: Int64 = 0) -> CloudPlaylist {
    CloudPlaylist(playlistId: id, name: name, trackIds: ids,
                  folder: folder, updatedAt: updatedAt)
}

@Test func aRunningOrderResolvesToTheTracksItNames() {
    let sets = PlaylistSet.resolve(
        [list("p1", "Friday", ["a", "b"])],
        against: [track("a"), track("b"), track("c")], shelf: .own)

    #expect(sets.count == 1)
    #expect(sets[0].tracks.map(\.rpmId) == ["a", "b"])
    #expect(sets[0].missing == 0)
}

/// The order is the playlist's, not the library's.
@Test func theRunningOrderIsThePlaylistsOwn() {
    let sets = PlaylistSet.resolve(
        [list("p1", "Friday", ["c", "a", "b"])],
        against: [track("a"), track("b"), track("c")], shelf: .own)

    #expect(sets[0].tracks.map(\.rpmId) == ["c", "a", "b"])
}

/// **A playlist can be ahead of the store it plays from.** The desktop pushes the running order as
/// soon as a playlist is chosen for the cloud. The audio follows over the next hours. So a missing
/// track is a normal state, not an error.
@Test func aTrackTheLibraryDoesNotHoldIsCountedRatherThanFailedOn() {
    let sets = PlaylistSet.resolve(
        [list("p1", "Friday", ["a", "not-uploaded-yet", "b"])],
        against: [track("a"), track("b")], shelf: .own)

    #expect(sets[0].tracks.map(\.rpmId) == ["a", "b"])
    #expect(sets[0].missing == 1)
}

@Test func aPlaylistOfNothingButMissingTracksIsStillAPlaylist() {
    let sets = PlaylistSet.resolve(
        [list("p1", "Friday", ["x", "y"])], against: [track("a")], shelf: .own)

    #expect(sets.count == 1)
    #expect(sets[0].tracks.isEmpty)
    #expect(sets[0].missing == 2)
}

/// A playlist may hold the same song twice on purpose. The second copy was put there by the user.
@Test func aSongNamedTwiceAppearsTwice() {
    let sets = PlaylistSet.resolve(
        [list("p1", "Friday", ["a", "a"])], against: [track("a")], shelf: .own)

    #expect(sets[0].tracks.map(\.rpmId) == ["a", "a"])
    #expect(sets[0].missing == 0)
}

/// A duplicate id in the listing must not throw an error, because that would stop the user's playlists from
/// loading.
@Test func aDuplicateRowInTheListingDoesNotThrow() {
    let sets = PlaylistSet.resolve(
        [list("p1", "Friday", ["a"])],
        against: [track("a", seconds: 1), track("a", seconds: 2)], shelf: .own)

    #expect(sets[0].tracks.count == 1)
}

@Test func playlistsComeBackByName() {
    let sets = PlaylistSet.resolve(
        [list("p1", "zoo", []), list("p2", "Aja", []), list("p3", "Morning", [])],
        against: [], shelf: .own)

    #expect(sets.map(\.name) == ["Aja", "Morning", "zoo"])
}

@Test func aPlaylistCarriesItsWholeFolderChainEvenThoughOnlyTheLastIsShown() {
    let sets = PlaylistSet.resolve(
        [list("p1", "Friday", [], folder: ["Sets", "AC/DC night"])],
        against: [], shelf: .own)

    #expect(sets[0].folder == ["Sets", "AC/DC night"])
}

/// Playlists written before folders existed have no folder field. "No field" and "top of the tree" mean the
/// same thing.
@Test func aPlaylistWithNoFolderIsAtTheTopOfTheTree() {
    let sets = PlaylistSet.resolve([list("p1", "Friday", [])], against: [], shelf: .own)
    #expect(sets[0].folder.isEmpty)
}

/// The stamp that a write is based on. The store uses it to refuse a write made against a copy that
/// has changed since.
@Test func aPlaylistCarriesTheStampItWasReadAt() {
    let sets = PlaylistSet.resolve(
        [list("p1", "Friday", [], updatedAt: 1_756_252_800)], against: [], shelf: .own)

    #expect(sets[0].stamp == 1_756_252_800)
}

/// The owner is stored on the set, not worked out from its tracks. An empty borrowed playlist has
/// no tracks to work it out from. The owner decides whether the page that opens it shows an add (+)
/// button.
@Test func anEmptyBorrowedPlaylistStillKnowsWhoseItIs() {
    let sets = PlaylistSet.resolve([list("p1", "Theirs", [])], against: [],
                                   shelf: .of("friend"))

    #expect(sets[0].tracks.isEmpty)
    #expect(sets[0].shelf.ownerId == "friend")
}

@Test func aPlaylistKnowsHowLongItRuns() {
    let sets = PlaylistSet.resolve(
        [list("p1", "Friday", ["a", "b"])],
        against: [track("a", seconds: 90), track("b", seconds: 120)], shelf: .own)

    #expect(sets[0].duration == .seconds(210))
}

@Test func noPlaylistsResolveToNoSets() {
    #expect(PlaylistSet.resolve([], against: [track("a")], shelf: .own).isEmpty)
}
