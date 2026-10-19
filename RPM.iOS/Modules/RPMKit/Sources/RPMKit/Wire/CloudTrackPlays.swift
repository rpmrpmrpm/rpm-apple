import Foundation

/// One device's play total for one track, as the cloud holds it.
///
/// Per device, and a total rather than a count to add on: this phone writes its own row
/// and nobody else's, so sending the same row twice changes nothing. A track's total is
/// the sum of its rows, which is arithmetic the caller does.
public struct CloudTrackPlays: Codable, Hashable, Sendable {
    public let rpmId: String

    /// Which device played them. This phone's own rows come back in the listing too, and
    /// this is how they are told from the other devices' and left alone.
    public let deviceId: String

    public let plays: Int64

    /// That device's own clock, unix seconds. For ordering what has been listened to, not
    /// for deciding whose row is newer.
    public let lastPlayedAt: Int64

    /// The store's own clock. What a puller compares against the stamp it last took in, so
    /// no two devices ever have to agree about the time.
    public let updatedAt: Int64

    public init(rpmId: String, deviceId: String, plays: Int64,
                lastPlayedAt: Int64, updatedAt: Int64 = 0) {
        self.rpmId = rpmId; self.deviceId = deviceId; self.plays = plays
        self.lastPlayedAt = lastPlayedAt; self.updatedAt = updatedAt
    }

    // Written out because every field but the id has to survive being absent, as in
    // `CloudTrack`: stored rows may be in an older shape.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rpmId        = try c.decode(String.self, forKey: .rpmId)
        deviceId     = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        plays        = try c.decodeIfPresent(Int64.self, forKey: .plays) ?? 0
        lastPlayedAt = try c.decodeIfPresent(Int64.self, forKey: .lastPlayedAt) ?? 0
        updatedAt    = try c.decodeIfPresent(Int64.self, forKey: .updatedAt) ?? 0
    }
}

/// What this phone sends: its own total for one track.
public struct TrackPlaysEntry: Codable, Hashable, Sendable {
    public let rpmId: String
    public let plays: Int64
    public let lastPlayedAt: Int64

    public init(rpmId: String, plays: Int64, lastPlayedAt: Int64) {
        self.rpmId = rpmId; self.plays = plays; self.lastPlayedAt = lastPlayedAt
    }
}
