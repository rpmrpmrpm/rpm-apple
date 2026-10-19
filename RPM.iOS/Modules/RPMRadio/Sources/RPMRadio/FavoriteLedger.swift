import Foundation
import RPMKit

/// The newest change to one station's place in the saved stations: saved or not, when (unix
/// milliseconds, by the clock of the device that made it), and the station itself.
public struct FavoriteChange: Codable, Hashable, Sendable {
    public var saved: Bool
    public var changedAt: Int64
    public var station: RadioStation
}

/// The saved stations as changes, so they can be kept in step with the listener's other devices
/// through `cloud/station-favorites`. There is one change per station, keyed by its id in lower
/// case. Each one is the newest of all the changes made to that station on any device. The rules
/// are the same as in the API's store, the desktop app's `RPM.Core.Radio.FavoriteLedger` and the
/// Android apps:
///
/// - The newest change to a station stands, by the clocks of the devices that made them. An
///   unsave is kept as a change too. Then it reaches the other devices and is not undone by their
///   copies.
/// - The saved stations are listed in the order they were saved. This order is the same on every
///   device.
/// - A device's first ledger is its list as it was, at its places (0, 1, 2, and so on). These
///   changes are
///   older than any real change.
/// - A ledger belongs to one account. When another account signs in, it starts an empty ledger.
///   The last account's stations are stored in the cloud under that account, and they are not
///   handed to the next account.
public struct FavoriteLedger: Codable, Hashable, Sendable {
    /// The account this ledger belongs to, or nil before anyone has synced it.
    public var account: String?

    /// The server stamp up to which every change has been taken in.
    public var cursor: Int64

    public var changes: [String: FavoriteChange]

    /// The stations whose change the cloud has not accepted yet, in the order they were made.
    public var unsent: [String]

    public static let empty = FavoriteLedger(account: nil, cursor: 0, changes: [:], unsent: [])

    /// A device's first ledger: its list as it was, oldest first, at its places. None of it is
    /// sent yet.
    public static func of(_ list: [RadioStation]) -> FavoriteLedger {
        var ledger = FavoriteLedger.empty
        for (at, station) in list.enumerated() {
            let key = Self.key(station.uuid)
            guard ledger.changes[key] == nil else { continue }
            ledger.changes[key] = FavoriteChange(saved: true, changedAt: Int64(at), station: station)
            ledger.unsent.append(key)
        }
        return ledger
    }

    /// The saved stations, in the order they were saved.
    public var saved: [RadioStation] {
        changes.filter { $0.value.saved }
            .sorted { $0.value.changedAt != $1.value.changedAt ? $0.value.changedAt < $1.value.changedAt : $0.key < $1.key }
            .map(\.value.station)
    }

    public func holds(_ uuid: String) -> Bool { changes[Self.key(uuid)]?.saved == true }

    /// The station saved or unsaved here at `now`. If `now` is not newer than the change it
    /// replaces, the new change is set just after that change. So it is always the newer one,
    /// whatever this phone's clock says.
    public func changed(_ station: RadioStation, saved: Bool, now: Int64) -> FavoriteLedger {
        let key = Self.key(station.uuid)
        var next = self
        next.changes[key] = FavoriteChange(saved: saved,
                                           changedAt: max(now, (changes[key]?.changedAt ?? -1) + 1),
                                           station: station)
        next.unsent.removeAll { $0 == key }
        next.unsent.append(key)
        return next
    }

    /// Refreshes the details of a saved station, for example after the directory renamed or moved
    /// it. The station keeps its place and its change. This is not a change to the list, so there
    /// is nothing to send.
    public func refreshed(_ station: RadioStation) -> FavoriteLedger {
        let key = Self.key(station.uuid)
        guard let held = changes[key], held.saved else { return self }
        var next = self
        next.changes[key]?.station = station
        return next
    }

    /// The ledger that `userId` syncs. This is this ledger when nobody has synced it yet, or when
    /// that account did. Where another account did, it is an empty ledger.
    public func forAccount(_ userId: String) -> FavoriteLedger {
        switch account {
        case nil:
            var next = self
            next.account = userId
            return next
        case userId?:
            return self
        default:
            var next = FavoriteLedger.empty
            next.account = userId
            return next
        }
    }

    /// Takes in the rows the cloud listed. A row replaces the held change only when it is newer,
    /// and then it is no longer this device's to send. The cursor moves to the newest row that
    /// arrived.
    public func taking(_ rows: [CloudStationFavorite]) -> FavoriteLedger {
        var next = self
        for row in rows {
            guard let wire = row.station, let station = RadioStation(listened: wire),
                  !row.uuid.isEmpty else { continue }
            let key = Self.key(row.uuid)
            if let held = next.changes[key], held.changedAt >= row.changedAt { continue }
            next.changes[key] = FavoriteChange(saved: row.saved, changedAt: row.changedAt, station: station)
            next.unsent.removeAll { $0 == key }
        }
        if let newest = rows.map(\.updatedAt).max() { next.cursor = max(cursor, newest) }
        return next
    }

    /// The changes to send: the unsent ones, at most `most`.
    public func toSend(_ most: Int) -> [String: FavoriteChange] {
        var out: [String: FavoriteChange] = [:]
        for key in unsent where out.count < most {
            if let change = changes[key] { out[key] = change }
        }
        return out
    }

    /// Marks `sent` as accepted by the cloud. Each one leaves the unsent list, unless it was
    /// changed again while it was being sent.
    public func sent(_ sent: [String: FavoriteChange]) -> FavoriteLedger {
        var next = self
        next.unsent.removeAll { key in
            guard let out = sent[key], let now = changes[key] else { return false }
            return now.changedAt == out.changedAt
        }
        return next
    }

    static func key(_ uuid: String) -> String { uuid.lowercased() }
}
