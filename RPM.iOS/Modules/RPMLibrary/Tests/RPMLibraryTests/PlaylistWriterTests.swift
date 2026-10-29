import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// Writing a playlist from a phone. The desktop (C#) has no tests for this path, so these tests
/// follow what the comments in `CloudLibraryService` say it does.

private actor Store: PlaylistStore {
    var held: [CloudPlaylist]

    /// What the next write is answered with, in order. Nil is "accepted".
    var refusals: [PlaylistConflict?] = []

    private(set) var writes: [(playlist: CloudPlaylist, ifUnchangedSince: Int64?)] = []
    private(set) var listings = 0

    init(_ held: [CloudPlaylist] = []) { self.held = held }

    func refuse(with: [PlaylistConflict?]) { refusals = with }

    func playlists(_ shelf: CloudShelf) async throws -> [CloudPlaylist] {
        listings += 1
        return held
    }

    @discardableResult
    func putPlaylist(_ playlist: CloudPlaylist, ifUnchangedSince: Int64?) async throws -> Int64 {
        writes.append((playlist, ifUnchangedSince))

        if !refusals.isEmpty, let clash = refusals.removeFirst() { throw clash }

        return 12_345
    }
}

private func list(_ id: String, _ name: String, _ ids: [String],
                  folder: [String] = [], stamp: Int64 = 900) -> CloudPlaylist {
    CloudPlaylist(playlistId: id, name: name, trackIds: ids, folder: folder, updatedAt: stamp)
}

private func track(_ id: String) -> CloudTrack {
    CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: id,
               artist: "Talk Talk", album: "Spirit of Eden", tags: CloudTrackTags())
}

private func set(_ id: String, _ name: String, _ tracks: [CloudTrack],
                 missing: Int = 0, folder: [String] = [], stamp: Int64 = 900,
                 shelf: CloudShelf = .own,
                 origin: PlaylistOrigin = .stored) -> PlaylistSet {
    PlaylistSet(id: id, name: name, tracks: tracks, missing: missing,
                folder: folder, stamp: stamp, shelf: shelf, origin: origin)
}

private func writer(_ store: Store, borrowed: Set<String> = []) -> PlaylistWriter {
    PlaylistWriter(store: store,
                   shelfOf: { borrowed.contains($0) ? .of("someone-else") : .own },
                   mint: { "made-up-id" })
}

// ── making one ──

@Test func makingOneWritesItAndHandsBackWhatWasWritten() async throws {
    let store = Store()
    let made = try await writer(store).create(
        name: "  Evening  ", folder: ["Moods"], tracks: [track("a"), track("b")])

    #expect(made.playlistId == "made-up-id")
    #expect(made.name == "Evening", "the name was not trimmed")
    #expect(made.folderChain == ["Moods"])
    #expect(made.trackIds == ["a", "b"])
    #expect(made.updatedAt == 12_345, "the store's own stamp was not kept")

    let writes = await store.writes
    #expect(writes.count == 1)
    #expect(writes[0].playlist.trackIds == ["a", "b"])
}

/// Zero means "only if nothing is stored under this id". If the store reports that the id is taken,
/// the random id has clashed with an existing playlist. The write fails rather than overwriting
/// that playlist.
@Test func makingOneWritesAgainstNothing() async throws {
    let store = Store()
    _ = try await writer(store).create(name: "x", folder: [], tracks: [])

    #expect(await store.writes[0].ifUnchangedSince == 0)
}

/// A playlist names tracks by id, and those ids belong to one account. An id from another account's
/// collection resolves to nothing here. Every device that read the playlist afterwards would count
/// it as missing.
@Test func aBorrowedRecordDoesNotGoIntoAPlaylistMadeHere() async throws {
    let store = Store()
    let made = try await writer(store, borrowed: ["b"]).create(
        name: "x", folder: [], tracks: [track("a"), track("b"), track("c")])

    #expect(made.trackIds == ["a", "c"])
    #expect(await store.writes[0].playlist.trackIds == ["a", "c"])
}

// ── adding to one ──

@Test func addingPutsTheNewSongsOnTheEnd() async throws {
    let store = Store([list("p", "Evening", ["a", "b"])])
    let added = try await writer(store).add(to: set("p", "Evening", [track("a"), track("b")]),
                                            tracks: [track("c"), track("d")],
                                            whenAlreadyThere: .leaveIt)

    #expect(added.songs.map(\.rpmId) == ["c", "d"])
    #expect(await store.writes[0].playlist.trackIds == ["a", "b", "c", "d"])
    #expect(added.row?.trackIds == ["a", "b", "c", "d"])
    #expect(added.row?.updatedAt == 12_345, "the store's new stamp was not handed back")
}

/// A playlist can hold the same song twice on purpose. But when a user adds a song, they do not mean to add a
/// second copy.
@Test func aSongAlreadyInItIsNotAddedTwice() async throws {
    let store = Store([list("p", "Evening", ["a", "b"])])
    let added = try await writer(store).add(to: set("p", "Evening", [track("a")]),
                                            tracks: [track("b"), track("c")],
                                            whenAlreadyThere: .leaveIt)

    #expect(added.songs.map(\.rpmId) == ["c"])
    #expect(await store.writes[0].playlist.trackIds == ["a", "b", "c"])
}

/// An empty result is a real answer, and nothing is written for it. A round trip to say "nothing
/// changed" could fail for no reason.
@Test func addingOnlySongsThatAreAlreadyThereWritesNothing() async throws {
    let store = Store([list("p", "Evening", ["a", "b"])])
    let added = try await writer(store).add(to: set("p", "Evening", [track("a")]),
                                            tracks: [track("a"), track("b")],
                                            whenAlreadyThere: .leaveIt)

    #expect(added.songs.isEmpty)
    #expect(added.row == nil)
    #expect(await store.writes.isEmpty)
}

/// The page may have been open for a long time, so the running order it shows may be several changes behind.
@Test func addingWritesAgainstTheStoresCopyRatherThanThePagesOne() async throws {
    let store = Store([list("p", "Evening", ["a", "b", "z"], stamp: 4242)])
    _ = try await writer(store).add(to: set("p", "Evening", [track("a")], stamp: 1),
                                    tracks: [track("c")], whenAlreadyThere: .leaveIt)

    let write = await store.writes[0]
    #expect(write.playlist.trackIds == ["a", "b", "z", "c"], "the page's stale copy was written")
    #expect(write.ifUnchangedSince == 4242, "the page's stale stamp was sent")
}

@Test func addingToSomebodyElsesPlaylistIsRefused() async {
    let store = Store([list("p", "Theirs", [])])
    await #expect(throws: PlaylistWriteError.notYours) {
        try await writer(store).add(to: set("p", "Theirs", [], shelf: .of("them")),
                                    tracks: [track("a")], whenAlreadyThere: .leaveIt)
    }
}

@Test func addingToOneThatHasGoneIsRefused() async {
    let store = Store([])
    await #expect(throws: PlaylistWriteError.gone) {
        try await writer(store).add(to: set("p", "Evening", []), tracks: [track("a")],
                                    whenAlreadyThere: .leaveIt)
    }
}

// ── the conditional write ──

/// **This is what turns "their change or mine" into "both".** The refusal carries the stored copy.
/// The phone keeps the ancestor it read a moment ago. The merge does the rest, and the second write
/// uses the stamp that came with the refusal.
@Test func aRefusalIsMergedAndWrittenAgain() async throws {
    let store = Store([list("p", "Evening", ["a", "b"], stamp: 100)])
    await store.refuse(with: [
        PlaylistConflict(stored: list("p", "Evening", ["a", "b", "theirs"], stamp: 200),
                         name: "Evening"),
    ])

    let added = try await writer(store).add(to: set("p", "Evening", [track("a")]),
                                            tracks: [track("mine")],
                                            whenAlreadyThere: .leaveIt)

    #expect(added.songs.map(\.rpmId) == ["mine"])

    let writes = await store.writes
    #expect(writes.count == 2)
    #expect(writes[1].ifUnchangedSince == 200, "the second write used the old stamp")
    #expect(writes[1].playlist.trackIds == ["a", "b", "theirs", "mine"],
            "both changes did not survive: \(writes[1].playlist.trackIds)")
}

/// **The phone shows what was written, not what it asked for.** After a merge they differ. If the
/// phone kept its own order with the merged stamp, its next reorder would send that order with a stamp
/// the store accepts, and the other device's song would be lost without a refusal.
@Test func aMergedWriteHandsBackTheMergedRow() async throws {
    let store = Store([list("p", "Evening", ["a", "b"], stamp: 100)])
    await store.refuse(with: [
        PlaylistConflict(stored: list("p", "Evening", ["a", "b", "theirs"], stamp: 200),
                         name: "Evening"),
    ])
    let held = set("p", "Evening", [track("a"), track("b")], stamp: 100)

    let written = try await writer(store).reorder(held, tracks: [track("b"), track("a")])

    #expect(written.trackIds == (await store.writes[1].playlist.trackIds))
    #expect(written.trackIds.contains("theirs"))
    #expect(written.updatedAt == 12_345)
}

/// The stored name and folder are kept, not the phone's copy. Neither can be changed from a phone, so a
/// difference in either one came from a change made on a computer.
@Test func aRefusalKeepsTheirNameAndTheirFolder() async throws {
    let store = Store([list("p", "Evening", ["a"], folder: [], stamp: 100)])
    await store.refuse(with: [
        PlaylistConflict(stored: list("p", "Renamed on the computer", ["a"],
                                      folder: ["Moods"], stamp: 200),
                         name: "Evening"),
    ])

    _ = try await writer(store).add(to: set("p", "Evening", [track("a")]), tracks: [track("b")],
                                    whenAlreadyThere: .leaveIt)

    let write = await store.writes[1]
    #expect(write.playlist.name == "Renamed on the computer")
    #expect(write.playlist.folderChain == ["Moods"])
}

/// One retry, and no more. A second refusal means another device is writing in a loop. Failing is
/// better than a phone retrying forever.
@Test func twoRefusalsInARowGiveUp() async {
    let store = Store([list("p", "Evening", ["a"], stamp: 100)])
    await store.refuse(with: [
        PlaylistConflict(stored: list("p", "Evening", ["a", "x"], stamp: 200), name: "Evening"),
        PlaylistConflict(stored: list("p", "Evening", ["a", "y"], stamp: 300), name: "Evening"),
    ])

    await #expect(throws: PlaylistWriteError.beingChangedElsewhere) {
        try await writer(store).add(to: set("p", "Evening", [track("a")]), tracks: [track("b")],
                                    whenAlreadyThere: .leaveIt)
    }
}

/// A refusal that does not say what is stored leaves nothing to merge against. A blind retry would
/// overwrite the other device's change, which this code exists to prevent.
@Test func aRefusalWithNothingInItIsNotRetried() async {
    let store = Store([list("p", "Evening", ["a"], stamp: 100)])
    await store.refuse(with: [PlaylistConflict(stored: nil, name: "Evening")])

    await #expect(throws: PlaylistWriteError.beingChangedElsewhere) {
        try await writer(store).add(to: set("p", "Evening", [track("a")]), tracks: [track("b")],
                                    whenAlreadyThere: .leaveIt)
    }

    #expect(await store.writes.count == 1, "it wrote again with nothing to merge against")
}

// ── reordering ──

@Test func reorderingWritesTheWholeRunningOrder() async throws {
    let store = Store([list("p", "Evening", ["a", "b", "c"])])
    let held = set("p", "Evening", [track("a"), track("b"), track("c")], stamp: 900)

    _ = try await writer(store).reorder(held, tracks: [track("c"), track("a"), track("b")])

    let write = await store.writes[0]
    #expect(write.playlist.trackIds == ["c", "a", "b"])
    #expect(write.ifUnchangedSince == 900)
}

/// **This case would delete music.** The whole running order is sent, so a playlist that names
/// songs this phone cannot see would come back shorter every time the user moved a row.
@Test func aPlaylistWithSongsThisPhoneCannotSeeIsNotReordered() async {
    let store = Store([list("p", "Evening", ["a", "b", "unseen"])])
    let held = set("p", "Evening", [track("a"), track("b")], missing: 1)

    await #expect(throws: PlaylistWriteError.wouldDropUnseenTracks(1)) {
        try await writer(store).reorder(held, tracks: [track("b"), track("a")])
    }

    #expect(await store.writes.isEmpty)
}

@Test func reorderingSomebodyElsesPlaylistIsRefused() async {
    let store = Store()
    await #expect(throws: PlaylistWriteError.notYours) {
        try await writer(store).reorder(set("p", "Theirs", [], shelf: .of("them")), tracks: [])
    }
}

/// An old row has no stamp. A precondition made up from nothing would refuse every later write to it.
@Test func aPlaylistTheStoreNeverStampedIsWrittenUnconditionally() async throws {
    let store = Store([list("p", "Evening", ["a"], stamp: 0)])
    _ = try await writer(store).reorder(set("p", "Evening", [track("a")], stamp: 0),
                                        tracks: [track("a")])

    #expect(await store.writes[0].ifUnchangedSince == nil)
}

// ── the lists the computer cut ──

/// A generated list's id does not refer to anything in the store. A write would not change a list.
/// It would make a playlist out of a cut that the computer replaces whole on its next run. So
/// writes are refused here as well as hidden on screen.
@Test func songsCannotBeAddedToAListTheComputerCut() async throws {
    let store = Store()
    let cut = set("\u{1}mood/Calm||0", "Chill", [track("a")], origin: .generated)

    await #expect(throws: PlaylistWriteError.notYoursToCut) {
        try await writer(store).add(to: cut, tracks: [track("b")], whenAlreadyThere: .leaveIt)
    }
    #expect(await store.writes.isEmpty)
}

@Test func aListTheComputerCutCannotBeRearranged() async throws {
    let store = Store()
    let cut = set("\u{1}mood/Calm||0", "Chill", [track("a"), track("b")], origin: .generated)

    await #expect(throws: PlaylistWriteError.notYoursToCut) {
        try await writer(store).reorder(cut, tracks: [track("b"), track("a")])
    }
    #expect(await store.writes.isEmpty)
}

// ── the same song twice, on purpose ──

/// **Both answers are valid.** If the user confirms that they want a second copy, the list gets
/// one, at the end, like any other add.
@Test func aSongAlreadyInItGoesInAgainWhenThatIsWhatWasAsked() async throws {
    let store = Store([list("p", "Evening", ["a", "b"])])
    let added = try await writer(store).add(to: set("p", "Evening", [track("a"), track("b")]),
                                            tracks: [track("a")],
                                            whenAlreadyThere: .addAnother)

    #expect(added.songs.map(\.rpmId) == ["a"])
    #expect(await store.writes[0].playlist.trackIds == ["a", "b", "a"])
}

/// The answer applies to songs that are already there, not to the whole batch. A new song goes in
/// once either way.
@Test func addingAgainStillPutsTheNewSongsInOnce() async throws {
    let store = Store([list("p", "Evening", ["a"])])
    let added = try await writer(store).add(to: set("p", "Evening", [track("a")]),
                                            tracks: [track("a"), track("b")],
                                            whenAlreadyThere: .addAnother)

    #expect(added.songs.map(\.rpmId) == ["a", "b"])
    #expect(await store.writes[0].playlist.trackIds == ["a", "a", "b"])
}

// ── how many copies a list holds ──

@Test func aListSaysHowManyCopiesOfASongItHolds() {
    let held = set("p", "Evening", [track("a"), track("b"), track("a")])

    #expect(held.copies(of: track("a")) == 2)
    #expect(held.copies(of: track("b")) == 1)
    #expect(held.copies(of: track("c")) == 0)
}
