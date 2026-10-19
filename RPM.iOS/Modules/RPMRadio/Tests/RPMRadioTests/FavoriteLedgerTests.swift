import Foundation
import Testing
import RPMKit
@testable import RPMRadio

/// The merge rule for saved stations, which combines this device's changes with the cloud.
/// The API, the desktop (`FavoriteLedgerTests`) and the Android apps (`FavoriteLedgerTest`)
/// use the same rule. Change them together.
struct FavoriteLedgerTests {
    private func station(_ id: String) -> RadioStation {
        RadioStation(uuid: id, name: "Radio \(id)", streamUrl: "https://example.invalid/\(id)")
    }

    private func row(_ id: String, saved: Bool, at: Int64, stamp: Int64 = 1) -> CloudStationFavorite {
        CloudStationFavorite(uuid: id, saved: saved, changedAt: at,
                             station: CloudListenedStation(of: station(id)), updatedAt: stamp)
    }

    @Test func aFirstLedgerKeepsTheListInItsOrderAndSendsAllOfIt() {
        let ledger = FavoriteLedger.of([station("b"), station("a"), station("c")])
        #expect(ledger.saved.map(\.uuid) == ["b", "a", "c"])
        #expect(ledger.unsent == ["b", "a", "c"])
    }

    @Test func aSaveGoesToTheEndAndAnUnsaveTakesItOut() {
        let ledger = FavoriteLedger.of([station("a"), station("b")])
            .changed(station("c"), saved: true, now: 1000)
            .changed(station("a"), saved: false, now: 1001)
        #expect(ledger.saved.map(\.uuid) == ["b", "c"])
        #expect(!ledger.holds("a"))
        #expect(ledger.holds("C"))
    }

    @Test func aChangeIsNewerThanTheOneItReplacesWhateverTheClockSays() {
        let ledger = FavoriteLedger.empty.changed(station("a"), saved: true, now: 5000)
            .changed(station("a"), saved: false, now: 10)
        #expect(ledger.changes["a"]?.changedAt == 5001)
    }

    @Test func aNewerRowFromTheCloudReplacesWhatIsHeldAndIsNoLongerOursToSend() {
        let ledger = FavoriteLedger.of([station("a")]).taking([row("a", saved: false, at: 50, stamp: 7)])
        #expect(!ledger.holds("a"))
        #expect(ledger.unsent.isEmpty)
        #expect(ledger.cursor == 7)
    }

    @Test func anOlderRowFromTheCloudDoesNotUndoAChangeMadeHere() {
        let ledger = FavoriteLedger.empty.changed(station("a"), saved: false, now: 900)
            .taking([row("a", saved: true, at: 100)])
        #expect(!ledger.holds("a"))
        #expect(ledger.unsent == ["a"])
    }

    @Test func anotherDevicesStationIsAddedInTheOrderItWasSaved() {
        let ledger = FavoriteLedger.empty.changed(station("mine"), saved: true, now: 500)
            .taking([row("theirs", saved: true, at: 300), row("later", saved: true, at: 800)])
        #expect(ledger.saved.map(\.uuid) == ["theirs", "mine", "later"])
    }

    @Test func aChangeMadeWhileOneWasOutStaysUnsent() {
        let before = FavoriteLedger.empty.changed(station("a"), saved: true, now: 100)
        let out = before.toSend(500)
        #expect(before.changed(station("a"), saved: false, now: 200).sent(out).unsent == ["a"])
        #expect(before.sent(out).unsent.isEmpty)
    }

    @Test func anotherAccountStartsAnEmptyLedgerAndTheSameOneKeepsIt() {
        let mine = FavoriteLedger.of([station("a")]).forAccount("me")
        #expect(mine.forAccount("me").saved.map(\.uuid) == ["a"])
        let theirs = mine.forAccount("someone else")
        #expect(theirs.saved.isEmpty)
        #expect(theirs.unsent.isEmpty)
        #expect(theirs.cursor == 0)
    }

    @Test func theCursorNeverGoesBack() {
        var held = FavoriteLedger.empty
        held.cursor = 10
        #expect(held.taking([row("a", saved: true, at: 1, stamp: 4)]).cursor == 10)
    }
}
