import Foundation

/// A speaker on the network.
public struct CastDevice: Identifiable, Hashable, Sendable {
    /// What makes a device the same device. It is not the address. See ``CastDeviceIdentity``.
    public let id: String

    /// The name the person gave the speaker. This is the `fn` field of its mDNS record.
    public let name: String

    /// What the device says it is, for example `Google Home Mini`, `Chromecast Ultra`, or `Google Cast Group`.
    public let model: String

    public let host: String
    public let port: Int

    /// True for a speaker group or a stereo pair, rather than a single speaker.
    ///
    /// **Google does not allow casting to a speaker that is in a group or a stereo pair.** A launch
    /// is always answered with `NOT_ALLOWED`, whatever is asked for. The group is the only device that can be cast to.
    public let isGroup: Bool

    public init(id: String, name: String, model: String,
                host: String, port: Int, isGroup: Bool) {
        self.id = id
        self.name = name
        self.model = model
        self.host = host
        self.port = port
        self.isGroup = isGroup
    }

    /// Builds a device from what a Cast service advertises over mDNS.
    ///
    /// Returns nil for a service with no address. That means the resolve has not finished yet. It
    /// does not mean there is no speaker.
    public static func from(txt: [String: String], host: String?, port: Int) -> CastDevice? {
        guard let host, !host.isEmpty else { return nil }

        let model = txt[Keys.model] ?? ""
        let advertised = txt[Keys.name] ?? ""
        let name = advertised.trimmingCharacters(in: .whitespaces).isEmpty ? host : advertised

        return CastDevice(
            id: CastDeviceIdentity.of(advertised: txt[Keys.id], host: host, port: port),
            name: name,
            model: model,
            host: host,
            port: port,
            // A group and a stereo pair both advertise a model that contains the word "group".
            isGroup: model.range(of: "group", options: .caseInsensitive) != nil)
    }

    /// The keys in the Cast TXT record: the friendly name the person gave the speaker, its model,
    /// and a device id. The id stays the same when the address changes.
    enum Keys {
        static let name = "fn"
        static let model = "md"
        static let id = "id"
    }
}

/// What makes a Cast device the same device.
///
/// This matches `RPM.Core/Audio/CastDeviceIdentity.cs`, so both apps identify devices the same way.
///
/// **A speaker group runs on one of its member speakers, at that member's address, on a different
/// port.** So one household can have three entries: a speaker and two groups, all with the same
/// address. Keying on the address would merge them and drop the other two. The groups are the entries
/// that matter, because they are the only devices that can be cast to.
public enum CastDeviceIdentity {
    /// The stable key. This is the id that the device advertises over mDNS. If there is none, the key
    /// is `host:port`. That is unique on the network, but a reboot may change it.
    public static func of(advertised: String?, host: String, port: Int) -> String {
        guard let advertised, !advertised.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "\(host):\(port)"
        }
        return advertised.trimmingCharacters(in: .whitespaces)
    }
}
