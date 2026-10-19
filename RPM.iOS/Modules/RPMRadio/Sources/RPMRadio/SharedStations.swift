import Foundation
import Observation
import RPMKit

/// The saved stations the radio shows for the library on screen.
///
/// The case says whether the hearts may change them, so a view cannot offer a heart on a list
/// that is not the listener's.
public enum SavedStations: Equatable, Sendable {
    /// The listener's own (``RadioFavorites``), which the hearts change.
    case mine([RadioStation])

    /// A shared library's owner's, read from the cloud. Read only.
    case owners([RadioStation])

    /// A shared library whose owner's stations have not been read yet.
    case reading

    /// A shared library whose owner's stations could not be read, and none were read before.
    case unreadable

    /// The stations to list, empty while reading or unreadable.
    public var stations: [RadioStation] {
        switch self {
        case .mine(let stations), .owners(let stations): return stations
        case .reading, .unreadable: return []
        }
    }

    /// The same answer with each station carrying the admin's edits, for drawing.
    public func edited(by rules: StationRules) -> SavedStations {
        switch self {
        case .mine(let stations): .mine(stations.map(rules.edited))
        case .owners(let stations): .owners(stations.map(rules.edited))
        case .reading, .unreadable: self
        }
    }

    /// Whether the station with this uuid is on the list, in any case.
    public func holds(_ uuid: String) -> Bool {
        stations.contains { $0.uuid.caseInsensitiveCompare(uuid) == .orderedSame }
    }

    /// Whether the hearts change these stations: only the listener's own.
    public var mayChange: Bool {
        if case .mine = self { return true }
        return false
    }
}

/// A shared library's owner's saved stations, read from `cloud/station-favorites?owner=` so the
/// radio shows them while that library is open. The Android apps' `SharedStations.kt`.
///
/// **Filed by the account that read them and the owner they are of**, and looked up by both, so a
/// read that lands after another library was opened, or after a sign-out, is shown only for the
/// library and the account it was made for. A read that fails is kept apart from an owner with no
/// saved stations, and does not replace a list an earlier read found.
///
/// `@Observable` and `@MainActor`, as ``RadioFavorites`` is.
@MainActor
@Observable
public final class SharedStations {
    private enum Held: Equatable {
        case read([RadioStation])
        case failed
    }

    /// By `<account>|<owner>`.
    private var held: [String: Held] = [:]

    public init() {}

    /// What the radio shows on `shelf` for `account`. The listener's own library shows `own`.
    public func saved(on shelf: CloudShelf, account: String, own: [RadioStation]) -> SavedStations {
        guard !shelf.isOwn else { return .mine(own) }
        switch held[Self.key(account, shelf)] {
        case .read(let stations): return .owners(stations)
        case .failed: return .unreadable
        case nil: return .reading
        }
    }

    /// Reads the owner's saved stations for `shelf` and files them under `account`. Nothing is
    /// read for the listener's own library.
    public func read(_ shelf: CloudShelf, account: String,
                     asking: (CloudShelf) async throws -> [CloudStationFavorite]) async {
        guard !shelf.isOwn else { return }
        let key = Self.key(account, shelf)

        let rows: [CloudStationFavorite]
        do {
            rows = try await asking(shelf)
        } catch {
            if held[key] == nil { held[key] = .failed }
            return
        }

        // In the order they were saved, as the ledger lists the listener's own.
        held[key] = .read(rows.filter(\.saved)
            .sorted { $0.changedAt < $1.changedAt }
            .compactMap { row in row.station.flatMap { RadioStation(listened: $0) } })
    }

    /// Everything read, for a sign-out.
    public func forget() { held = [:] }

    private static func key(_ account: String, _ shelf: CloudShelf) -> String {
        "\(account)|\(shelf.ownerId)"
    }
}
