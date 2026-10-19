import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// The orders in which concurrent events can reach the cloud library. There is one test per order.
/// Each test fails if the reason that order is safe stops being true.
///
/// The source is a gate, not a network. The test controls the order of events, so no result depends on
/// timing.

/// A listing source that answers exactly when the test opens it.
private actor Gate: LibrarySource {
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var calls = 0
    private var answers: [String: [CloudTrack]] = [:]
    private var failing = false
    private var open = true

    func answer(_ shelf: CloudShelf, with tracks: [CloudTrack]) { answers[shelf.ownerId] = tracks }
    func fail() { failing = true }
    func shut() { open = false }

    /// Lets exactly one waiting call through.
    func release() {
        open = true
        guard !waiting.isEmpty else { return }
        waiting.removeFirst().resume()
    }

    func list(_ shelf: CloudShelf) async throws -> [CloudTrack] {
        calls += 1

        if !open {
            await withCheckedContinuation { waiting.append($0) }
        }

        if failing { throw RPMError.transport(URLError(.notConnectedToInternet)) }
        return answers[shelf.ownerId] ?? []
    }
}

private func rows(_ titles: [String], artist: String = "Artist", album: String = "Album")
    -> [CloudTrack] {
    titles.enumerated().map { i, title in
        var tags = CloudTrackTags()
        tags.trackNumber = i + 1
        return CloudTrack(rpmId: "id-\(title)", relativePath: "\(artist)/\(album)/\(i).flac",
                          title: title, artist: artist, album: album, tags: tags)
    }
}

/// Built here, not at each call site. `FavoriteMarks` is main-actor, so creating one needs a hop to the
/// main actor, and every test needs the same three objects.
@MainActor
private func library(_ source: Gate, root: URL, now: @escaping @Sendable () -> Date = { Date() })
    -> (CloudLibrary, FavoriteMarks, TrackShelves) {
    let marks = FavoriteMarks()
    let shelves = TrackShelves()
    return (CloudLibrary(source: source, shelves: shelves, marks: marks,
                         storeRoot: root, now: now), marks, shelves)
}

/// Waits for the next shelf to come down the stream, or gives up.
private func nextChange(_ library: CloudLibrary, within nanos: UInt64 = 2_000_000_000)
    async -> CloudShelf? {
    await withTaskGroup(of: CloudShelf?.self) { group in
        group.addTask { for await shelf in library.changes { return shelf }; return nil }
        group.addTask { try? await Task.sleep(nanoseconds: nanos); return nil }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

private func scratch() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("rpm-lib-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// ── the ordinary path ──

@Test func aFirstReadGoesToTheCloudAndGroupsWhatItGets() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.own, with: rows(["One", "Two"]))

    let (library, _, shelves) = await library(gate, root: root)
    let albums = await library.albums(.own)

    #expect(albums.count == 1)
    #expect(albums[0].tracks.map(\.title) == ["One", "Two"])
}

@Test func aSecondReadIsAnsweredFromMemory() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.own, with: rows(["One"]))

    let (library, _, shelves) = await library(gate, root: root)
    _ = await library.albums(.own)
    _ = await library.albums(.own)

    let calls = await gate.calls
    #expect(calls == 1)
}

/// A failed refresh keeps the library the phone already holds, so the user still sees their music offline.
@Test func aFailedReadKeepsWhatIsAlreadyHeld() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.own, with: rows(["One"]))

    let (library, _, shelves) = await library(gate, root: root)
    _ = await library.albums(.own)

    await gate.fail()
    let again = await library.albums(.own, refresh: true)

    #expect(again.count == 1, "a failed refresh threw the library away")
}

// ── a read in flight when the user signs out ──

/// **This is what `era` is for.** A listing that arrives after sign-out would put the catalogue back in
/// memory and on disk, after sign-out had removed it from both.
@Test func aReadThatLandsAfterSignOutIsDiscarded() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.own, with: rows(["One", "Two"]))
    await gate.shut()

    let (library, _, shelves) = await library(gate, root: root)

    let read = Task { await library.albums(.own) }
    while await gate.calls == 0 { await Task.yield() }

    // Signed out while the listing is still in flight.
    await library.forget()
    await gate.release()

    let answered = await read.value
    let held = await library.heldShelves
    #expect(answered.isEmpty, "a read from a dead era answered with a library")
    #expect(held.isEmpty, "a read from a dead era wrote itself back in")
}

/// The disk copy must not come back either. Preventing that leak is the purpose of signing out.
@Test func aReadThatLandsAfterSignOutLeavesNothingOnDisk() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.own, with: rows(["One"]))
    await gate.shut()

    let (library, _, shelves) = await library(gate, root: root)
    let read = Task { await library.albums(.own) }
    while await gate.calls == 0 { await Task.yield() }

    await library.forget()
    await gate.release()
    _ = await read.value

    #expect(LibraryStore(shelf: .own, root: root).load() == nil,
            "signing out was undone by a round trip that was slow")
}

@Test func signingOutBumpsTheEraBeforeItClearsAnything() async {
    let (library, _, _) = await library(Gate(), root: scratch())
    let before = await library.currentEra
    await library.forget()
    let after = await library.currentEra
    #expect(after == before + 1)
}

// ── two tabs asking at once ──

/// Without the guard, both calls would fetch the whole catalogue, about twenty round trips each.
@Test func twoTabsAskingAtOnceFetchTheCatalogOnce() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.own, with: rows(["One"]))
    await gate.shut()

    let (library, _, shelves) = await library(gate, root: root)

    let wall = Task { await library.albums(.own) }
    let playlists = Task { await library.albums(.own) }

    while await gate.calls == 0 { await Task.yield() }
    await gate.release()

    let a = await wall.value
    let b = await playlists.value

    let calls = await gate.calls
    #expect(a.count == 1)
    #expect(b.count == 1)
    #expect(calls == 1, "the catalog was fetched \(calls) times")
}

// ── the shelf on screen changes mid-read ──

/// A result is filed under its own shelf, never under the shelf on screen.
@Test func aReadIsFiledUnderItsOwnShelfNotTheOneOnScreen() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.of("friend"), with: rows(["Theirs"]))
    await gate.shut()

    let (library, _, shelves) = await library(gate, root: root)

    let read = Task { await library.albums(.of("friend")) }
    while await gate.calls == 0 { await Task.yield() }

    // The user steps back to their own records before the friend's listing lands.
    await gate.release()
    _ = await read.value

    let held = await library.heldShelves
    #expect(held == ["friend"])
    #expect(shelves.shelf(of: "id-Theirs").ownerId == "friend")
}

// ── the cache hit and the refresh behind it ──

@Test func aWarmLaunchDrawsTheDiskCopyAndAsksBehindIt() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    LibraryStore(shelf: .own, root: root).save(rows(["Cached"]))

    let gate = Gate()
    await gate.answer(.own, with: rows(["Cached"]))

    let (library, _, shelves) = await library(gate, root: root)
    let albums = await library.albums(.own)

    #expect(albums[0].tracks.map(\.title) == ["Cached"], "the disk copy was not drawn")

    // The refresh behind it is fire-and-forget; give it a turn.
    while await gate.calls == 0 { await Task.yield() }
    let calls = await gate.calls
    #expect(calls == 1)
}

/// Opening the app twice in one evening must not rebuild a wall of a thousand covers when the library has
/// not changed.
@Test func aRefreshThatFoundTheSameLibrarySaysNothing() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.own, with: rows(["One"]))

    let (library, _, _) = await library(gate, root: root)
    _ = await library.albums(.own)
    await library.refreshBehind(.own)

    #expect(await nextChange(library, within: 200_000_000) == nil)
}

@Test func aRefreshThatFoundADifferentLibrarySaysWhichShelf() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.own, with: rows(["One"]))

    let (library, _, _) = await library(gate, root: root)
    _ = await library.albums(.own)

    await gate.answer(.own, with: rows(["One", "Two"]))
    Task { await library.refreshBehind(.own) }

    let changed = await nextChange(library)
    #expect(changed?.isOwn == true)
}

/// It reports which shelf changed and leaves the decision to the reader. A wall showing a friend's records
/// must ignore a change to the user's own shelf. This object does not know what is on screen.
@Test func theStreamNamesTheShelfRatherThanDecidingWhoCares() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.of("friend"), with: rows(["Theirs"]))

    let (library, _, _) = await library(gate, root: root)
    _ = await library.albums(.of("friend"))

    await gate.answer(.of("friend"), with: rows(["Theirs", "More"]))
    Task { await library.refreshBehind(.of("friend")) }

    let changed = await nextChange(library)
    #expect(changed?.ownerId == "friend")
}

// ── a refresh that lands after sign-out ──

@Test func aRefreshThatLandsAfterSignOutIsDiscarded() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.own, with: rows(["One"]))

    let (library, _, shelves) = await library(gate, root: root)
    await gate.shut()

    let refresh = Task { await library.refreshBehind(.own) }
    while await gate.calls == 0 { await Task.yield() }

    await library.forget()
    await gate.release()
    await refresh.value

    let held = await library.heldShelves
    #expect(held.isEmpty)
}

// ── a share taken back ──

@Test func aRevokedShelfLeavesMemoryAndDisk() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.own, with: rows(["Mine"]))
    await gate.answer(.of("friend"), with: rows(["Theirs"]))

    let (library, _, shelves) = await library(gate, root: root)
    _ = await library.albums(.own)
    _ = await library.albums(.of("friend"))

    await library.forgetShelvesOtherThan([])

    let held = await library.heldShelves
    #expect(held == [""], "the borrowed shelf is still held")
    #expect(LibraryStore(shelf: .of("friend"), root: root).load() == nil)
    #expect(LibraryStore(shelf: .own, root: root).load() != nil, "the user's own went too")
}

/// **Deliberate.** A record that is still playing from a shelf that has just been closed must not stop
/// halfway through. The server decides access, and it refuses the next signature when access ends.
@Test func aRevokedShelfsTracksKeepTheirShelfSoPlaybackDoesNotBreak() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.of("friend"), with: rows(["Theirs"]))

    let (library, _, shelves) = await library(gate, root: root)
    _ = await library.albums(.of("friend"))

    await library.forgetShelvesOtherThan([])

    #expect(shelves.shelf(of: "id-Theirs").ownerId == "friend")
}

@Test func aShelfStillSharedIsKept() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let gate = Gate()
    await gate.answer(.of("friend"), with: rows(["Theirs"]))

    let (library, _, shelves) = await library(gate, root: root)
    _ = await library.albums(.of("friend"))

    await library.forgetShelvesOtherThan(["friend"])

    let held = await library.heldShelves
    #expect(held == ["friend"])
}

// ── coming back to the foreground ──

private final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var at = Date(timeIntervalSince1970: 1_000_000)
    var now: Date { lock.withLock { at } }
    func advance(_ seconds: TimeInterval) { lock.withLock { at += seconds } }
}

/// A phone that was in the background for a short time has missed nothing, so no refresh is made.
@Test func comingBackAfterAMomentAsksNothing() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let clock = Clock()
    let gate = Gate()
    await gate.answer(.own, with: rows(["One"]))

    let (library, _, _) = await library(gate, root: root, now: { clock.now })
    _ = await library.albums(.own)

    clock.advance(60)
    await library.refreshOnResume()
    await Task.yield()

    let calls = await gate.calls
    #expect(calls == 1)
}

@Test func comingBackAfterAWhileAsksAgain() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }
    let clock = Clock()
    let gate = Gate()
    await gate.answer(.own, with: rows(["One"]))

    let (library, _, _) = await library(gate, root: root, now: { clock.now })
    _ = await library.albums(.own)

    clock.advance(CloudLibrary.resumeInterval + 1)
    await library.refreshOnResume()

    while await gate.calls < 2 { await Task.yield() }
    let calls = await gate.calls
    #expect(calls == 2)
}

// ── the marks arrive with the listing ──

/// One call returns both, because the catalogue and the marks are one fact. A screen with the catalogue but
/// not the marks would show a heart that disagrees with the library.
@Test func anOwnShelfListingCarriesTheMarksInWithIt() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }

    var loved = CloudTrackTags(); loved.favorite = true; loved.favoritedAt = 42
    let tracks = [CloudTrack(rpmId: "loved", relativePath: "A/B/1.flac",
                             title: "Loved", artist: "A", album: "B", tags: loved)]

    let gate = Gate()
    await gate.answer(.own, with: tracks)

    let (library, marks, _) = await library(gate, root: root)
    _ = await library.albums(.own)

    #expect(await marks.isMarked("loved"))
    #expect(await marks.markedAt("loved") == 42)
}

/// A borrowed shelf's rows carry another listener's marks. Those marks must not become this listener's marks.
@Test func aBorrowedListingDoesNotBringSomebodyElsesMarks() async {
    let root = scratch(); defer { try? FileManager.default.removeItem(at: root) }

    var loved = CloudTrackTags(); loved.favorite = true
    let tracks = [CloudTrack(rpmId: "theirs", relativePath: "A/B/1.flac",
                             title: "Theirs", artist: "A", album: "B", tags: loved)]

    let gate = Gate()
    await gate.answer(.of("friend"), with: tracks)

    let (library, marks, _) = await library(gate, root: root)
    _ = await library.albums(.of("friend"))

    #expect(await marks.isMarked("theirs") == false)
}
