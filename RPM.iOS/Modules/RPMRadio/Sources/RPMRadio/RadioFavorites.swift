import Foundation
import Observation
import RPMKit

/// The listener's saved stations, kept in step with their other devices (``FavoritesSync``,
/// `cloud/station-favorites`).
///
/// Ported from `RPM.Core/Radio/RadioFavorites.cs`.
///
/// **The whole station is stored, not just its id.** The directory is run by volunteers, and
/// stations are removed from it every day. A saved station that kept only an id would go silent
/// as soon as its entry was pruned. Keeping the URL means a preset plays for as long as the
/// station broadcasts, with or without the directory.
///
/// **Held as a ``FavoriteLedger``.** The ledger records every save and unsave, with the time each
/// was made. The sync sends and merges these. The ledger has its own file. The list is still
/// written to `radio-favorites.json` as a plain array, because that is the format this app used
/// before the ledger. A device's first ledger is made from that list. The list is in the order the
/// stations were saved, which is the same on every device.
///
/// `@Observable` and `@MainActor`, with no lock and no change event. A heart is a view of this
/// class, and SwiftUI redraws a view when the state it reads changes. `FavoriteMarks` works the
/// same way.
@MainActor
@Observable
public final class RadioFavorites {
    /// The saved stations, in the order they were saved.
    public private(set) var stations: [RadioStation] = []

    private var ledger = FavoriteLedger.empty

    private let file: URL?
    private let ledgerFile: URL?

    /// False when a file exists but could not be read this session. Nothing is written then.
    /// A write would replace every saved station with the empty list in memory. See ``StoreFile``.
    private var mayWrite = true

    /// - Parameter directory: where the files go. Use Application Support, not Caches. The system
    ///   can take back files in Caches, and then a saved station would quietly disappear.
    public init(directory: URL? = RadioFavorites.applicationSupport) {
        file = directory?.appendingPathComponent("radio-favorites.json")
        ledgerFile = directory?.appendingPathComponent("radio-favorites-sync.json")
        load()
    }

    /// Application Support, or Caches on tvOS. See `KeptFiles`.
    public static var applicationSupport: URL? { KeptFiles.folder }

    public func contains(_ uuid: String) -> Bool { ledger.holds(uuid) }

    /// Saves a station, or refreshes one that is already saved with the directory's current
    /// details. A station that was renamed or moved keeps its place in the list.
    public func add(_ station: RadioStation) {
        settle(ledger.holds(station.uuid) ? ledger.refreshed(station) : ledger.changed(station, saved: true, now: Self.now()))
    }

    public func remove(_ uuid: String) {
        guard let held = ledger.changes[FavoriteLedger.key(uuid)], held.saved else { return }
        settle(ledger.changed(held.station, saved: false, now: Self.now()))
    }

    /// Saves or unsaves the station, and returns whether it is now saved. This is all the heart
    /// needs.
    @discardableResult
    public func toggle(_ station: RadioStation) -> Bool {
        guard !contains(station.uuid) else {
            remove(station.uuid)
            return false
        }
        add(station)
        return true
    }

    // ── the sync's view ──

    /// The server stamp up to which every change has been taken in.
    public var cursor: Int64 { ledger.cursor }

    /// Claims the ledger for the signed-in account. Another account's ledger is started afresh.
    public func forAccount(_ userId: String) { settle(ledger.forAccount(userId)) }

    /// Takes in what the cloud listed. See ``FavoriteLedger/taking(_:)``.
    public func take(_ rows: [CloudStationFavorite]) { settle(ledger.taking(rows)) }

    /// The changes that the cloud has not accepted yet, at most `most`.
    public func toSend(_ most: Int) -> [String: FavoriteChange] { ledger.toSend(most) }

    /// The changes as they were SENT, now accepted. A change made again since then stays unsent.
    public func noteSent(_ sent: [String: FavoriteChange]) { settle(ledger.sent(sent)) }

    private static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    private func settle(_ next: FavoriteLedger) {
        guard next != ledger else { return }
        ledger = next
        stations = next.saved
        save()
    }

    // ── the files ──

    /// A file that does not parse is moved aside, and the list starts empty. A file that could not
    /// be read is left alone, and nothing is written this session. Writing an empty list over an
    /// unread file would delete every saved station.
    private func load() {
        guard let file, let ledgerFile else { return }

        let kept = StoreFile.load(ledgerFile) { try JSONDecoder().decode(FavoriteLedger.self, from: $0) }
        if let held = kept.value {
            mayWrite = kept.mayWrite
            ledger = held
            stations = held.saved
            return
        }

        let read = StoreFile.load(file) { try JSONDecoder().decode([RadioStation].self, from: $0) }
        mayWrite = kept.mayWrite && read.mayWrite
        var list = read.value ?? []

        #if os(tvOS)
        // No file. On a TV this means the system emptied Caches. The copy in the user defaults,
        // which is written next to the file on every change, restores the stations.
        if read.value == nil, read.mayWrite,
           let copy = UserDefaults.standard.data(forKey: Self.keptKey),
           let saved = try? JSONDecoder().decode([RadioStation].self, from: copy) {
            list = saved
        }
        #endif

        ledger = FavoriteLedger.of(list)
        stations = ledger.saved
    }

    #if os(tvOS)
    /// Where the TV keeps a second copy of the list. An Apple TV app has no folder that the system
    /// will not empty (see `KeptFiles`). The user defaults are kept, up to about 500 KB. A few
    /// dozen stations take a few dozen KB.
    private static let keptKey = "rpm.radio.favorites"
    #endif

    /// Written whole on every change. The list is a few dozen small records. A format that can be
    /// appended to can be left half-written, so the whole file is rewritten instead.
    private func save() {
        guard let file, let ledgerFile, mayWrite,
              let list = try? JSONEncoder().encode(stations),
              let changes = try? JSONEncoder().encode(ledger) else { return }
        try? changes.write(to: ledgerFile, options: .atomic)
        try? list.write(to: file, options: .atomic)
        #if os(tvOS)
        UserDefaults.standard.set(list, forKey: Self.keptKey)
        #endif
    }
}
