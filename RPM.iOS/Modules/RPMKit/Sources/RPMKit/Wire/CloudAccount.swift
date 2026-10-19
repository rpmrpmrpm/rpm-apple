import Foundation

public struct CloudQuota: Codable, Hashable, Sendable {
    public let usedBytes: Int64
    public let quotaBytes: Int64
    public let fileCount: Int

    /// No ceiling, which is what supporting rpm buys. False when the server does not send the
    /// field, and then the quota is the free account's 100 GB.
    public let unlimited: Bool

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        usedBytes  = try c.decodeIfPresent(Int64.self, forKey: .usedBytes) ?? 0
        quotaBytes = try c.decodeIfPresent(Int64.self, forKey: .quotaBytes) ?? 0
        fileCount  = try c.decodeIfPresent(Int.self, forKey: .fileCount) ?? 0
        unlimited  = try c.decodeIfPresent(Bool.self, forKey: .unlimited) ?? false
    }

    public init(usedBytes: Int64, quotaBytes: Int64, fileCount: Int, unlimited: Bool = false) {
        self.usedBytes = usedBytes; self.quotaBytes = quotaBytes
        self.fileCount = fileCount; self.unlimited = unlimited
    }
}

/// One install of RPM the account has signed in on.
///
/// What makes automatic sharing between a person's own computers possible: a
/// machine cannot vouch for itself, so the account holds the keys it has been
/// signed in with, and a peer presenting one of them is one of theirs.
public struct CloudDevice: Codable, Hashable, Sendable, Identifiable {
    public let deviceId: String
    public let publicKey: String
    public let name: String
    public let lastSeenAt: Int64

    public var id: String { deviceId }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceId   = try c.decode(String.self, forKey: .deviceId)
        publicKey  = try c.decodeIfPresent(String.self, forKey: .publicKey) ?? ""
        name       = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        lastSeenAt = try c.decodeIfPresent(Int64.self, forKey: .lastSeenAt) ?? 0
    }
}

/// One account letting another hear its cloud-stored records.
public struct CloudShare: Codable, Hashable, Sendable {
    public let ownerId: String
    public let granteeId: String
    public let granteeName: String
    public let createdAt: Int64

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ownerId     = try c.decodeIfPresent(String.self, forKey: .ownerId) ?? ""
        granteeId   = try c.decodeIfPresent(String.self, forKey: .granteeId) ?? ""
        granteeName = try c.decodeIfPresent(String.self, forKey: .granteeName) ?? ""
        createdAt   = try c.decodeIfPresent(Int64.self, forKey: .createdAt) ?? 0
    }

    public init(ownerId: String, granteeId: String, granteeName: String, createdAt: Int64) {
        self.ownerId = ownerId
        self.granteeId = granteeId
        self.granteeName = granteeName
        self.createdAt = createdAt
    }
}

/// Both directions at once: who this account shares with, and who shares with it.
public struct CloudShares: Codable, Hashable, Sendable {
    public let granted: [CloudShare]
    public let received: [CloudShare]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        granted  = try c.decodeIfPresent([CloudShare].self, forKey: .granted) ?? []
        received = try c.decodeIfPresent([CloudShare].self, forKey: .received) ?? []
    }
}
