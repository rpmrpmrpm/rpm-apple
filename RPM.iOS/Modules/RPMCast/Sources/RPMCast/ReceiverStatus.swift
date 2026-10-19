import Foundation

/// What a receiver says about itself.
///
/// The shape comes from a real Nest Audio, not from a specification. The decoder reads it leniently on purpose.
/// Every field is optional. A speaker with nothing running sends no `applications` key at all. A speaker that has
/// been updated can send fields that this app has never heard of.
public struct ReceiverStatus: Decodable, Sendable, Equatable {
    /// The apps the receiver is running. Empty or missing when it is idle.
    public var applications: [Application] = []

    public var volume: Volume?

    public struct Application: Decodable, Sendable, Equatable {
        /// The app. `CC1AD845` is the Default Media Receiver.
        public let appId: String

        /// This launch. It is used to stop the app, and it changes on every launch.
        public let sessionId: String

        /// **Where messages to the app are sent.** This is not `receiver-0`. Once an app is running, its media
        /// namespace is addressed to this transport. A virtual connection must be opened to it first.
        public let transportId: String

        public let displayName: String?
        public let statusText: String?

        /// The namespaces that the running app listens to. Check this, rather than assume it. An app that does not
        /// list the media namespace ignores a LOAD.
        public var namespaces: [Namespace] = []

        enum CodingKeys: String, CodingKey {
            case appId, sessionId, transportId, displayName, statusText, namespaces
        }

        public init(from decoder: any Decoder) throws {
            let fields = try decoder.container(keyedBy: CodingKeys.self)
            appId = try fields.decode(String.self, forKey: .appId)
            sessionId = try fields.decode(String.self, forKey: .sessionId)
            transportId = try fields.decode(String.self, forKey: .transportId)
            displayName = try fields.decodeIfPresent(String.self, forKey: .displayName)
            statusText = try fields.decodeIfPresent(String.self, forKey: .statusText)
            namespaces = try fields.decodeIfPresent([Namespace].self, forKey: .namespaces) ?? []
        }

        public var speaksMedia: Bool {
            namespaces.contains { $0.name == CastLink.mediaNamespace }
        }
    }

    public struct Namespace: Decodable, Sendable, Equatable {
        public let name: String
    }

    public struct Volume: Decodable, Sendable, Equatable {
        /// From 0 to 1.
        public let level: Double?
        public let muted: Bool?

        /// **Whether the room's volume can be set at all.** `master` means the speaker's own level changes.
        /// `fixed` means the device is wired to an amplifier that controls the volume. A level set on a `fixed`
        /// device does nothing, and it gives no error.
        public let controlType: String?

        /// The size of one volume step. A speaker that reports a step size should be set in multiples of it.
        public let stepInterval: Double?

        public var canBeSet: Bool { controlType != "fixed" }
    }

    enum CodingKeys: String, CodingKey { case applications, volume }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        applications = try fields.decodeIfPresent([Application].self, forKey: .applications) ?? []
        volume = try fields.decodeIfPresent(Volume.self, forKey: .volume)
    }

    /// Reads a `RECEIVER_STATUS` payload. The payload wraps the status in an envelope that holds the request it answers.
    public static func of(_ payload: String) -> ReceiverStatus? {
        struct Envelope: Decodable { let status: ReceiverStatus }

        guard let data = payload.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Envelope.self, from: data).status
    }

    /// The Default Media Receiver. This is Google's player. A music app with no receiver of its own casts through it.
    public static let defaultMediaReceiver = "CC1AD845"

    /// **RPM's own receiver**, which is published under this id. The desktop apps use it too.
    ///
    /// The stock receiver plays the stream, but it cannot send messages back. RPM's receiver supports
    /// `urn:x-cast:com.rpmrpmrpm.control`. That channel carries a next or previous press at the speaker back to
    /// the phone. If a speaker cannot launch this receiver, use the stock one. The only thing lost is those buttons.
    public static let rpmReceiver = "41BD77B1"

    /// The running Default Media Receiver, if it is the app that is running.
    public var mediaReceiver: Application? {
        applications.first { $0.appId == Self.defaultMediaReceiver }
    }
}
