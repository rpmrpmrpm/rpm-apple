import Foundation
import RPMKit

/// One pass over the saved stations: take in what the listener's other devices changed, then
/// send what this device changed. Pull first, as ``StationListensSync`` does. The rule is
/// the one in ``FavoriteLedger``, which the desktop and Android apps also use.
public enum FavoritesSync {
    /// The most changes one pass may send. This is the store's limit per request.
    public static let perPass = 500

    @MainActor
    public static func run(favorites: RadioFavorites, client: RPMCloudClient, userId: String) async {
        favorites.forAccount(userId)

        // ── in ──
        do {
            let rows = try await client.stationFavorites(since: favorites.cursor)
            favorites.take(rows)
        } catch {
            // Offline, signed out, or the store did not answer. The next pass asks again.
            return
        }

        // ── out ──
        let due = favorites.toSend(perPass)
        guard !due.isEmpty else { return }

        do {
            _ = try await client.sendStationFavorites(due.values.map {
                StationFavoriteEntry(uuid: $0.station.uuid, saved: $0.saved, changedAt: $0.changedAt,
                                     station: CloudListenedStation(of: $0.station))
            })

            // Mark the changes as they were sent. A favourite changed after the read stays unsent.
            favorites.noteSent(due)
        } catch {
            // Not marked as sent, so the same changes are sent again on the next pass.
        }
    }
}
