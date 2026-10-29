import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// Reads and writes of one shelf's playlists, ending in every order. Each test names the order and
/// says which knowledge must win.
struct HeldPlaylistsTests {
    private func track(_ id: String) -> CloudTrack {
        CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: id,
                   artist: "Talk Talk", album: "Spirit of Eden", tags: CloudTrackTags())
    }

    private func row(_ id: String, _ ids: [String], stamp: Int64) -> CloudPlaylist {
        CloudPlaylist(playlistId: id, name: id, trackIds: ids, folder: [], updatedAt: stamp)
    }

    private func cut(computedAt: Int64) -> CloudMoodLists {
        CloudMoodLists(recipe: 4, computedAt: computedAt,
                       lists: [CloudMoodList(kind: "RightNow", trackIds: ["a"])])
    }

    private let listing = ["a", "b", "c", "d"]

    /// The stored playlists as a screen would show them, by id, as track ids.
    private func shown(_ held: HeldPlaylists) -> [String: [String]] {
        let sets = held.sets(against: listing.map(track), readings: [:])
        return Dictionary(uniqueKeysWithValues: sets.filter { $0.origin == .stored }
            .map { ($0.id, $0.tracks.map(\.rpmId)) })
    }

    /// A read that starts and lands with nothing in between.
    private func readNow(_ held: inout HeldPlaylists, rows: [CloudPlaylist],
                         cut: HeldPlaylists.CutAnswer) {
        let ticket = held.startRead()
        _ = held.land(ticket, rows: rows, cut: cut)
    }

    private func hasCut(_ held: HeldPlaylists) -> Bool {
        held.sets(against: listing.map(track), readings: [:]).contains { $0.origin == .generated }
    }

    // ── two reads ──

    @Test func anEarlierReadLandingLastDoesNotReplaceANewerRow() {
        var held = HeldPlaylists(shelf: .own)
        let first = held.startRead()
        let second = held.startRead()

        let laterLanded = held.land(second, rows: [row("p", ["a", "b"], stamp: 200)], cut: .none)
        let earlierLanded = held.land(first, rows: [row("p", ["a"], stamp: 100)], cut: .none)
        #expect(laterLanded && earlierLanded)

        #expect(shown(held) == ["p": ["a", "b"]])
    }

    @Test func anEarlierReadLandingLastDoesNotRemoveARowALaterReadBrought() {
        var held = HeldPlaylists(shelf: .own)
        let first = held.startRead()
        let second = held.startRead()

        _ = held.land(second, rows: [row("p", ["a"], stamp: 100), row("q", ["b"], stamp: 150)],
                      cut: .none)
        _ = held.land(first, rows: [row("p", ["a"], stamp: 100)], cut: .none)

        #expect(shown(held) == ["p": ["a"], "q": ["b"]])
    }

    /// The store no longer has it, and nothing this device learned after the read says otherwise.
    @Test func aRowThatALaterReadDoesNotHoldGoes() {
        var held = HeldPlaylists(shelf: .own)
        let first = held.startRead()
        _ = held.land(first, rows: [row("p", ["a"], stamp: 100), row("q", ["b"], stamp: 150)],
                      cut: .none)

        let second = held.startRead()
        _ = held.land(second, rows: [row("p", ["a"], stamp: 100)], cut: .none)

        #expect(shown(held) == ["p": ["a"]])
    }

    // ── a read and a write ──

    @Test func aReadThatStartedBeforeAWriteDoesNotUndoIt() {
        var held = HeldPlaylists(shelf: .own)
        let reading = held.startRead()

        let adding = held.startWrite()
        held.end(adding, wrote: row("p", ["a", "b", "c"], stamp: 300))
        let making = held.startWrite()
        held.end(making, wrote: row("new", ["d"], stamp: 310))

        _ = held.land(reading, rows: [row("p", ["a", "b"], stamp: 100)], cut: .none)

        #expect(shown(held) == ["p": ["a", "b", "c"], "new": ["d"]])
    }

    @Test func aReadThatStartedAfterAWriteRemovesARowTheStoreNoLongerHas() {
        var held = HeldPlaylists(shelf: .own)
        let making = held.startWrite()
        held.end(making, wrote: row("new", ["d"], stamp: 310))

        let reading = held.startRead()
        _ = held.land(reading, rows: [], cut: .none)

        #expect(shown(held).isEmpty)
    }

    /// A write that ends after another device wrote a newer version does not replace it.
    @Test func aWriteDoesNotReplaceANewerRow() {
        var held = HeldPlaylists(shelf: .own)
        let writing = held.startWrite()
        readNow(&held, rows: [row("p", ["a", "b", "c", "d"], stamp: 400)],
                      cut: .none)
        held.end(writing, wrote: row("p", ["a", "b"], stamp: 300))

        #expect(shown(held) == ["p": ["a", "b", "c", "d"]])
    }

    // ── a reorder in flight ──

    @Test func aReorderShowsItsOrderUntilItEnds() {
        var held = HeldPlaylists(shelf: .own)
        readNow(&held, rows: [row("p", ["a", "b", "c"], stamp: 100)], cut: .none)

        let moving = held.startWrite(showing: ["c", "a", "b"], of: "p")
        #expect(shown(held) == ["p": ["c", "a", "b"]])

        held.end(moving, wrote: row("p", ["c", "a", "b"], stamp: 200))
        #expect(shown(held) == ["p": ["c", "a", "b"]])
    }

    /// The failure shows what the store holds now, not the copy from before the reorder.
    @Test func aFailedReorderShowsTheLatestRead() {
        var held = HeldPlaylists(shelf: .own)
        readNow(&held, rows: [row("p", ["a", "b", "c"], stamp: 100)], cut: .none)

        let moving = held.startWrite(showing: ["c", "a", "b"], of: "p")
        readNow(&held, rows: [row("p", ["a", "b", "c", "d"], stamp: 200)],
                      cut: .none)
        #expect(shown(held) == ["p": ["c", "a", "b"]])

        held.end(moving, wrote: nil)
        #expect(shown(held) == ["p": ["a", "b", "c", "d"]])
    }

    /// The id, name and folder come from the computer, and nothing on a phone may change them. The
    /// stamp stays the stored copy's until the write ends, because the write is made against it.
    @Test func aReorderInFlightKeepsEverythingButItsOrder() throws {
        var held = HeldPlaylists(shelf: .own)
        readNow(&held, rows: [CloudPlaylist(playlistId: "p", name: "Evening", trackIds: ["a", "b"],
                                            folder: ["Moods"], updatedAt: 900)], cut: .none)

        _ = held.startWrite(showing: ["b", "a"], of: "p")

        let moving = try #require(held.sets(against: listing.map(track), readings: [:]).first)
        #expect(moving.id == "p")
        #expect(moving.name == "Evening")
        #expect(moving.folder == ["Moods"])
        #expect(moving.shelf == .own)
        #expect(moving.stamp == 900)
        #expect(moving.tracks.map(\.rpmId) == ["b", "a"])
    }

    @Test func anEarlierReorderEndingDoesNotRemoveALaterOne() {
        var held = HeldPlaylists(shelf: .own)
        readNow(&held, rows: [row("p", ["a", "b", "c"], stamp: 100)], cut: .none)

        let first = held.startWrite(showing: ["b", "a", "c"], of: "p")
        _ = held.startWrite(showing: ["c", "b", "a"], of: "p")
        held.end(first, wrote: nil)

        #expect(shown(held) == ["p": ["c", "b", "a"]])
    }

    // ── the cut ──

    /// A failed request is not an answer of "no cut".
    @Test func aFailedCutReadKeepsTheCut() {
        var held = HeldPlaylists(shelf: .own)
        readNow(&held, rows: [], cut: .cut(cut(computedAt: 10)))
        readNow(&held, rows: [], cut: .failed)

        #expect(hasCut(held))
    }

    @Test func anOlderCutDoesNotReplaceANewerOne() {
        var held = HeldPlaylists(shelf: .own)
        let first = held.startRead()
        let second = held.startRead()
        _ = held.land(second, rows: [], cut: .cut(cut(computedAt: 20)))
        _ = held.land(first, rows: [], cut: .cut(cut(computedAt: 10)))

        #expect(held.moodLists?.computedAt == 20)
    }

    @Test func noCutFromAnEarlierReadKeepsTheCutALaterOneFound() {
        var held = HeldPlaylists(shelf: .own)
        let first = held.startRead()
        let second = held.startRead()
        _ = held.land(second, rows: [], cut: .cut(cut(computedAt: 20)))
        _ = held.land(first, rows: [], cut: .none)

        #expect(hasCut(held))

        readNow(&held, rows: [], cut: .none)
        #expect(!hasCut(held))
    }

    // ── another shelf, another account ──

    /// A collection switch or a sign-out makes a new value. The user's own shelf before a sign-out
    /// and the next account's own shelf are both `.own`.
    @Test func aTicketFromAnotherValueDoesNotLand() {
        var before = HeldPlaylists(shelf: .own)
        let reading = before.startRead()
        let writing = before.startWrite()

        var after = HeldPlaylists(shelf: .own)
        let read = after.land(reading, rows: [row("p", ["a"], stamp: 100)], cut: .none)
        let wrote = after.end(writing, wrote: row("q", ["b"], stamp: 100))
        #expect(!read)
        #expect(!wrote)

        #expect(!after.answered)
        #expect(!after.holds(reading))
        #expect(shown(after).isEmpty)
    }

    @Test func aWriteDoesNotLandOnABorrowedShelf() {
        var held = HeldPlaylists(shelf: .of("them"))
        let making = held.startWrite()
        held.end(making, wrote: row("mine", ["a"], stamp: 100))

        #expect(shown(held).isEmpty)
    }
}
