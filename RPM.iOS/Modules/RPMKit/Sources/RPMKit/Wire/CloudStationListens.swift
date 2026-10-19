import Foundation

/// A radio station as the store carries it: the directory's own fields, enough to draw it and
/// to play it on a device that has never tuned it.
///
/// Mirrors `ListenedStation` in the Lambda's `CloudContracts.cs`. RPMKit holds no radio types,
/// so `RPMRadio` turns this into a `RadioStation`.
public struct CloudListenedStation: Codable, Hashable, Sendable {
    public let uuid: String
    public let name: String
    public let streamUrl: String
    public let homepage: String?
    public let favicon: String?
    public let country: String?
    public let countryCode: String?
    public let language: String?
    public let tags: [String]
    public let codec: String?
    public let bitrateKbps: Int
    public let isHls: Bool

    public init(uuid: String, name: String, streamUrl: String, homepage: String?, favicon: String?,
                country: String?, countryCode: String?, language: String?, tags: [String],
                codec: String?, bitrateKbps: Int, isHls: Bool) {
        self.uuid = uuid; self.name = name; self.streamUrl = streamUrl
        self.homepage = homepage; self.favicon = favicon; self.country = country
        self.countryCode = countryCode; self.language = language; self.tags = tags
        self.codec = codec; self.bitrateKbps = bitrateKbps; self.isHls = isHls
    }

    // Written out so every field but the three that make a station playable survives being
    // absent or null: the service writes nulls, and stored rows may be in an older shape.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid        = try c.decode(String.self, forKey: .uuid)
        name        = try c.decode(String.self, forKey: .name)
        streamUrl   = try c.decode(String.self, forKey: .streamUrl)
        homepage    = try c.decodeIfPresent(String.self, forKey: .homepage)
        favicon     = try c.decodeIfPresent(String.self, forKey: .favicon)
        country     = try c.decodeIfPresent(String.self, forKey: .country)
        countryCode = try c.decodeIfPresent(String.self, forKey: .countryCode)
        language    = try c.decodeIfPresent(String.self, forKey: .language)
        tags        = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        codec       = try c.decodeIfPresent(String.self, forKey: .codec)
        bitrateKbps = try c.decodeIfPresent(Int.self, forKey: .bitrateKbps) ?? 0
        isHls       = try c.decodeIfPresent(Bool.self, forKey: .isHls) ?? false
    }
}

/// One device's radio totals for one station, as the store holds them.
///
/// Mirrors `StationListensRow` in the Lambda's `CloudContracts.cs`. See its
/// `StationListenStore` for why these are totals and never amounts to add on.
public struct CloudStationListens: Codable, Hashable, Sendable {
    public let uuid: String

    /// Which log heard it. This phone's own rows come back in the listing too, and this is how
    /// they are told apart and left alone.
    public let deviceId: String

    /// That device's own total, not everybody's. A station's total is the sum of its rows.
    public let heardSeconds: Double
    public let tunes: Int

    /// That device's own clock, unix seconds. For ordering, not for deciding whose row is newer.
    public let lastHeardAt: Int64

    /// The station as that device last tuned it. Nil where it did not decode, and such a row
    /// is left out by whoever takes it in: it names nothing that could be drawn or played.
    public let station: CloudListenedStation?

    /// The store's own clock, kept as the cursor.
    public let updatedAt: Int64

    public init(uuid: String, deviceId: String, heardSeconds: Double, tunes: Int,
                lastHeardAt: Int64, station: CloudListenedStation?, updatedAt: Int64) {
        self.uuid = uuid; self.deviceId = deviceId; self.heardSeconds = heardSeconds
        self.tunes = tunes; self.lastHeardAt = lastHeardAt; self.station = station
        self.updatedAt = updatedAt
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        uuid         = try c.decode(String.self, forKey: .uuid)
        deviceId     = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        heardSeconds = try c.decodeIfPresent(Double.self, forKey: .heardSeconds) ?? 0
        tunes        = try c.decodeIfPresent(Int.self, forKey: .tunes) ?? 0
        lastHeardAt  = try c.decodeIfPresent(Int64.self, forKey: .lastHeardAt) ?? 0
        // One station that does not decode must not fail the whole listing.
        station      = try? c.decodeIfPresent(CloudListenedStation.self, forKey: .station)
        updatedAt    = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }
}

/// What this phone sends: its own totals for one station, and the station.
public struct StationListensEntry: Codable, Hashable, Sendable {
    public let uuid: String
    public let heardSeconds: Double
    public let tunes: Int
    public let lastHeardAt: Int64
    public let station: CloudListenedStation

    public init(uuid: String, heardSeconds: Double, tunes: Int, lastHeardAt: Int64,
                station: CloudListenedStation) {
        self.uuid = uuid; self.heardSeconds = heardSeconds; self.tunes = tunes
        self.lastHeardAt = lastHeardAt; self.station = station
    }
}
