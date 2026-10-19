import Foundation

/// The newest change to one saved radio station, as the store holds it: saved or unsaved, when
/// (unix milliseconds, by the clock of the device that made it), and the station.
///
/// Mirrors `StationFavoriteRow` in the Lambda's `CloudContracts.cs`. `RPMRadio` takes these in
/// through `FavoriteLedger`.
public struct CloudStationFavorite: Codable, Hashable, Sendable {
    public let uuid: String
    public let saved: Bool
    public let changedAt: Int64
    public let station: CloudListenedStation?

    /// The store's own clock, kept as the cursor.
    public let updatedAt: Int64

    public init(uuid: String, saved: Bool, changedAt: Int64, station: CloudListenedStation?, updatedAt: Int64) {
        self.uuid = uuid; self.saved = saved; self.changedAt = changedAt
        self.station = station; self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case uuid, saved, changedAt, station, updatedAt }

    /// Lenient, as ``CloudStationListens`` is: a row whose station does not decode comes back
    /// without one and is left out by whoever takes it in, rather than failing the whole listing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid      = try c.decodeIfPresent(String.self, forKey: .uuid) ?? ""
        saved     = try c.decodeIfPresent(Bool.self, forKey: .saved) ?? false
        changedAt = try c.decodeIfPresent(Int64.self, forKey: .changedAt) ?? 0
        station   = try? c.decodeIfPresent(CloudListenedStation.self, forKey: .station)
        updatedAt = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }
}

/// One change this phone made to the saved stations, as it is sent.
public struct StationFavoriteEntry: Codable, Hashable, Sendable {
    public let uuid: String
    public let saved: Bool
    public let changedAt: Int64
    public let station: CloudListenedStation

    public init(uuid: String, saved: Bool, changedAt: Int64, station: CloudListenedStation) {
        self.uuid = uuid; self.saved = saved; self.changedAt = changedAt; self.station = station
    }
}
