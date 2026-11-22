import Foundation

/// One finished listen, as the store's listening log keeps it (`cloud/listens`).
///
/// Every app sends its listens so the store can cut the lists that read the log: On repeat,
/// Rediscover, Late night, First listens, and the hourly lean of Your mix. Play totals still
/// travel separately (``TrackPlaysEntry``), and the store does not add these to them.
public struct CloudListen: Codable, Hashable, Sendable {
    /// Made on this device when the listen ended. A listen sent twice is stored once.
    public let listenId: String
    public let rpmId: String
    /// When the listen ended, unix seconds.
    public let at: Int64
    /// Audio actually heard, across seeks.
    public let heardSeconds: Double
    public let lengthSeconds: Double
    /// Whether it counted as a play. False is a skip.
    public let counted: Bool
    /// 0 to 23 on this device's clock at that moment. The store cannot work this out later,
    /// because people travel.
    public let localHour: Int
    /// 0 = Sunday, on the same clock.
    public let localDayOfWeek: Int

    public init(listenId: String, rpmId: String, at: Int64, heardSeconds: Double,
                lengthSeconds: Double, counted: Bool, localHour: Int, localDayOfWeek: Int) {
        self.listenId = listenId; self.rpmId = rpmId; self.at = at
        self.heardSeconds = heardSeconds; self.lengthSeconds = lengthSeconds
        self.counted = counted; self.localHour = localHour; self.localDayOfWeek = localDayOfWeek
    }
}

/// A new reading of one generated list, cut by the store for a press of "Generate new".
public struct CloudListReading: Codable, Hashable, Sendable {
    /// The list's id, as the cut names it.
    public let id: String
    /// The songs, by RPM id, in the order they play.
    public let trackIds: [String]
    /// How many songs one list of this kind shows.
    public let shows: Int

    public init(id: String, trackIds: [String], shows: Int) {
        self.id = id; self.trackIds = trackIds; self.shows = shows
    }
}
