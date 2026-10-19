import Foundation

/// One page of a catalogue listing.
///
/// `owner` is not decoration. A server that does not know shared collections drops an
/// unbound `?owner=` and answers a listing for another account with the CALLER's own
/// rows under a 200, and the client would then work on the wrong library without any
/// sign of trouble. `RPMCloudClient.list` checks this field before it keeps a
/// single row.
public struct CloudListPage: Codable, Sendable {
    public let files: [CloudTrack]
    public let cursor: String?
    public let owner: String?
}

/// The shared JSON coders. One place, so a date or a key strategy cannot be set
/// differently on two calls: the wire is camelCase already, and
/// `.convertFromSnakeCase` would silently mangle `mbReleaseId`.
public enum RPMJSON {
    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }()
}

/// For routes that answer with nothing worth decoding.
public struct EmptyResponse: Decodable, Sendable {
    public init() {}
}
