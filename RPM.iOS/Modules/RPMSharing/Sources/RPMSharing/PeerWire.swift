import Foundation
import CryptoKit

/// The encodings of the sharing protocol. They match `RPM.Core/Sharing` (`SharingProtocol`,
/// `PeerIdentity`, `Base32`) and the Android TV app's `PeerWire.kt`. Every binary value on the wire
/// is base64url without padding.
public enum PeerWire {
    public static let version = 3
    public static let serviceType = "_rpm._tcp"
    public static let sessionPurpose = "rpm-share-session"

    public static func base64Url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// The bytes, or nil for text that is not base64url.
    public static func fromBase64Url(_ text: String?) -> Data? {
        guard var plain = text?.trimmingCharacters(in: .whitespaces), !plain.isEmpty else { return nil }
        plain = plain.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while plain.count % 4 != 0 { plain += "=" }
        return Data(base64Encoded: plain)
    }

    /// A device id: base32 of the first 16 bytes of SHA-256 of the public key (SubjectPublicKeyInfo
    /// DER), 26 characters, upper case.
    public static func id(for publicKey: Data) -> String {
        base32(Data(SHA256.hash(data: publicKey)).prefix(16))
    }

    /// An account's public fingerprint: base32 of the first 12 bytes of SHA-256 of the user id, or
    /// empty when signed out. Computers compare it to tell their owner's devices from a friend's.
    public static func accountFingerprint(_ userId: String?) -> String {
        guard let userId, !userId.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        return base32(Data(SHA256.hash(data: Data(userId.utf8))).prefix(12))
    }

    /// The text that a session signature covers. The computer's device id is used exactly as the
    /// computer spells it.
    public static func sessionText(serverDeviceId: String, challenge: String) -> Data {
        Data("\(sessionPurpose)\n\(serverDeviceId)\n\(challenge)".utf8)
    }

    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// Crockford-style base32 without padding, most significant bit first. It matches the
    /// desktop's `Base32.Encode`.
    public static func base32(_ data: Data) -> String {
        var text = ""
        text.reserveCapacity((data.count * 8 + 4) / 5)
        var buffer = 0
        var bits = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bits += 8
            while bits >= 5 {
                text.append(alphabet[(buffer >> (bits - 5)) & 31])
                bits -= 5
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 { text.append(alphabet[(buffer << (5 - bits)) & 31]) }
        return text
    }

    /// Converts .NET UTC ticks (100 ns each, counted from year 1) to Unix seconds, the cloud's
    /// unit. Zero, and any value at or before the Unix epoch, gives zero.
    public static func unixSeconds(ticks: Int64) -> Int64 {
        ticks <= unixEpochTicks ? 0 : (ticks - unixEpochTicks) / 10_000_000
    }

    private static let unixEpochTicks: Int64 = 621_355_968_000_000_000
}

// ── the wire types, with the server's camelCase names ──

struct PairRequest: Encodable {
    let version: Int
    let publicKey: String
    let name: String
    let face: String
    let account: String
    let nonce: String
}

struct PairStatus: Decodable, Equatable {
    var state = ""
    var rev = 0
    var triesLeft = 0
    var expiresIn = 0

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decodeIfPresent(String.self, forKey: .state) ?? ""
        rev = try c.decodeIfPresent(Int.self, forKey: .rev) ?? 0
        triesLeft = try c.decodeIfPresent(Int.self, forKey: .triesLeft) ?? 0
        expiresIn = try c.decodeIfPresent(Int.self, forKey: .expiresIn) ?? 0
    }

    private enum CodingKeys: String, CodingKey { case state, rev, triesLeft, expiresIn }
}

struct PairOffer: Decodable {
    var deviceId = ""
    var name = ""
    var publicKey = ""
    var id = ""
    var status = PairStatus()

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        publicKey = try c.decodeIfPresent(String.self, forKey: .publicKey) ?? ""
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? ""
        status = try c.decodeIfPresent(PairStatus.self, forKey: .status) ?? PairStatus()
    }

    private enum CodingKeys: String, CodingKey { case deviceId, name, publicKey, id, status }
}

struct PairCode: Encodable {
    let id: String
    let code: String
}

struct PairId: Encodable {
    let id: String
}

struct SessionChallenge: Decodable {
    let challenge: String
}

struct SessionRedeem: Encodable {
    let publicKey: String
    let challenge: String
    let signature: String
}

struct SessionGrant: Decodable {
    let token: String
    let expiresIn: Int
}

/// One track in a computer's catalogue (`PeerTrack`). Only the fields this device reads are listed.
public struct PeerTrack: Decodable, Sendable, Equatable {
    public var rpmId: String
    public var path = ""
    public var title: String?
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var genre: String?
    public var track = 0
    public var disc = 0
    public var year = 0
    public var seconds = 0.0
    public var size: Int64 = 0
    /// .NET UTC ticks.
    public var added: Int64 = 0
    public var advisory = 0
    public var codec: String?

    public init(rpmId: String, path: String = "", title: String? = nil, artist: String? = nil,
                albumArtist: String? = nil, album: String? = nil, genre: String? = nil,
                track: Int = 0, disc: Int = 0, year: Int = 0, seconds: Double = 0,
                size: Int64 = 0, added: Int64 = 0, advisory: Int = 0, codec: String? = nil) {
        self.rpmId = rpmId; self.path = path; self.title = title; self.artist = artist
        self.albumArtist = albumArtist; self.album = album; self.genre = genre
        self.track = track; self.disc = disc; self.year = year; self.seconds = seconds
        self.size = size; self.added = added; self.advisory = advisory; self.codec = codec
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rpmId = try c.decode(String.self, forKey: .rpmId)
        path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        albumArtist = try c.decodeIfPresent(String.self, forKey: .albumArtist)
        album = try c.decodeIfPresent(String.self, forKey: .album)
        genre = try c.decodeIfPresent(String.self, forKey: .genre)
        track = try c.decodeIfPresent(Int.self, forKey: .track) ?? 0
        disc = try c.decodeIfPresent(Int.self, forKey: .disc) ?? 0
        year = try c.decodeIfPresent(Int.self, forKey: .year) ?? 0
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        size = try c.decodeIfPresent(Int64.self, forKey: .size) ?? 0
        added = try c.decodeIfPresent(Int64.self, forKey: .added) ?? 0
        advisory = try c.decodeIfPresent(Int.self, forKey: .advisory) ?? 0
        codec = try c.decodeIfPresent(String.self, forKey: .codec)
    }

    private enum CodingKeys: String, CodingKey {
        case rpmId, path, title, artist, albumArtist, album, genre, track, disc, year, seconds
        case size, added, advisory, codec
    }

    /// The file's extension, lower case, or empty.
    public var container: String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        guard let dot = name.lastIndex(of: "."), dot < name.index(before: name.endIndex) else { return "" }
        return name[name.index(after: dot)...].lowercased()
    }
}

/// A computer's catalogue: its version and every track it shares.
public struct PeerCatalog: Decodable, Sendable {
    public var version = ""
    public var name = ""
    public var tracks: [PeerTrack] = []

    public init(version: String, name: String, tracks: [PeerTrack]) {
        self.version = version; self.name = name; self.tracks = tracks
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(String.self, forKey: .version) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        tracks = try c.decodeIfPresent([PeerTrack].self, forKey: .tracks) ?? []
    }

    private enum CodingKeys: String, CodingKey { case version, name, tracks }
}
