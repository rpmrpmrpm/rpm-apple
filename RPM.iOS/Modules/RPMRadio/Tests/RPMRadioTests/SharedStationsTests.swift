import Foundation
import Testing
import RPMKit
@testable import RPMRadio

/// Whose saved stations the radio shows: the listener's own, or a shared library's owner's.
@MainActor
struct SharedStationsTests {
    private struct Down: Error {}

    private func station(_ id: String) -> RadioStation {
        RadioStation(uuid: id, name: "Radio \(id)", streamUrl: "https://example.invalid/\(id)")
    }

    private func row(_ id: String, saved: Bool = true, at: Int64) -> CloudStationFavorite {
        CloudStationFavorite(uuid: id, saved: saved, changedAt: at,
                             station: CloudListenedStation(of: station(id)), updatedAt: 1)
    }

    private let owner = CloudShelf.of("owner-1")

    @Test func theListenersOwnLibraryShowsTheirOwnStations() {
        let shared = SharedStations()
        let saved = shared.saved(on: .own, account: "me", own: [station("a")])
        #expect(saved == .mine([station("a")]))
        #expect(saved.mayChange)
    }

    @Test func aSharedLibraryNotReadYetIsReading() {
        let shared = SharedStations()
        let saved = shared.saved(on: owner, account: "me", own: [station("a")])
        #expect(saved == .reading)
        #expect(!saved.mayChange)
        #expect(saved.stations.isEmpty)
    }

    /// The owner's saved ones, in the order they were saved; an unsaved one is left out.
    @Test func aSharedLibraryShowsItsOwnersSavedStationsInTheOrderTheyWereSaved() async {
        let shared = SharedStations()
        await shared.read(owner, account: "me") { _ in
            [self.row("c", at: 30), self.row("a", at: 10), self.row("b", saved: false, at: 20)]
        }

        let saved = shared.saved(on: owner, account: "me", own: [station("x")])
        #expect(saved == .owners([station("a"), station("c")]))
        #expect(!saved.mayChange)
    }

    /// A read that failed is not a library with no saved stations.
    @Test func aReadThatFailedIsNotAnEmptyList() async {
        let shared = SharedStations()
        await shared.read(owner, account: "me") { _ in throw Down() }
        #expect(shared.saved(on: owner, account: "me", own: []) == .unreadable)
    }

    /// A later read that fails keeps the stations an earlier one found.
    @Test func aFailedReadKeepsWhatWasReadBefore() async {
        let shared = SharedStations()
        await shared.read(owner, account: "me") { _ in [self.row("a", at: 1)] }
        await shared.read(owner, account: "me") { _ in throw Down() }
        #expect(shared.saved(on: owner, account: "me", own: []) == .owners([station("a")]))
    }

    @Test func anOwnerWhoSavedNothingIsAnEmptyList() async {
        let shared = SharedStations()
        await shared.read(owner, account: "me") { _ in [] }
        #expect(shared.saved(on: owner, account: "me", own: []) == .owners([]))
    }

    /// The read asks of the library it is for, and is filed under it: a read that lands after
    /// another library was opened is not shown for that one.
    @Test func aReadIsFiledUnderTheLibraryItWasFor() async {
        let shared = SharedStations()
        let other = CloudShelf.of("owner-2")
        var asked: [String] = []
        await shared.read(owner, account: "me") { shelf in
            asked.append(shelf.ownerId)
            return [self.row("a", at: 1)]
        }

        #expect(asked == ["owner-1"])
        #expect(shared.saved(on: other, account: "me", own: []) == .reading)
        #expect(shared.saved(on: owner, account: "me", own: []) == .owners([station("a")]))
    }

    /// Filed under the account that read them, so the next account to sign in on this phone is not
    /// shown them.
    @Test func aReadIsNotShownToAnotherAccount() async {
        let shared = SharedStations()
        await shared.read(owner, account: "me") { _ in [self.row("a", at: 1)] }
        #expect(shared.saved(on: owner, account: "someone-else", own: []) == .reading)
    }

    /// Whether a station is on the list shown, by uuid in any case.
    @Test func holdsAsksByUuidInAnyCase() async {
        let shared = SharedStations()
        await shared.read(owner, account: "me") { _ in [self.row("Ab", at: 1)] }
        let saved = shared.saved(on: owner, account: "me", own: [])
        #expect(saved.holds("aB"))
        #expect(!saved.holds("c"))
        #expect(!SavedStations.reading.holds("ab"))
    }

    /// Asking for the listener's own library reads nothing: their own stations are the ledger's.
    @Test func theOwnLibraryIsNeverRead() async {
        let shared = SharedStations()
        var asked = 0
        await shared.read(.own, account: "me") { _ in asked += 1; return [] }
        #expect(asked == 0)
    }
}
