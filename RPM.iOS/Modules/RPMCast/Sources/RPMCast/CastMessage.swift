import Foundation

/// One message on a Cast channel.
///
/// CASTV2 is protobuf over TLS. This is the only message type that either side sends. Everything else is
/// JSON inside ``payload``, on a namespace that says how to read it.
///
/// **Hand-rolled, not generated, and no protobuf library is used.** The whole schema has seven fields. This
/// app uses six of them, and two of those are constants. `cast_channel.proto` has not changed since 2014. A
/// dependency for that would be the largest thing in the package.
public struct CastMessage: Equatable, Sendable {
    /// The special ids that the platform reserves. Any other id is a session id.
    public static let sender = "sender-0"
    public static let receiver = "receiver-0"

    public var source: String
    public var destination: String

    /// **The key that multiplexes the channel.** Each namespace is its own protocol. A receiver listens on
    /// several namespaces at once.
    public var namespace: String

    /// Always JSON. The binary payload type exists in the schema, but nothing here uses it.
    public var payload: String

    public init(source: String = CastMessage.sender,
                destination: String = CastMessage.receiver,
                namespace: String,
                payload: String) {
        self.source = source
        self.destination = destination
        self.namespace = namespace
        self.payload = payload
    }

    // ── the wire ──

    private enum Field {
        static let protocolVersion = 1
        static let source = 2
        static let destination = 3
        static let namespace = 4
        static let payloadType = 5
        static let payloadUtf8 = 6
        static let payloadBinary = 7
    }

    /// Both of these are `required` in the proto2 schema. They go on the wire every time, even though both are
    /// zero. A receiver that does not find them closes the connection, and does not say why.
    private static let castv2 = 0
    private static let stringPayload = 0

    public var encoded: Data {
        var out = Protobuf.Writer()
        out.varint(Field.protocolVersion, Self.castv2)
        out.string(Field.source, source)
        out.string(Field.destination, destination)
        out.string(Field.namespace, namespace)
        out.varint(Field.payloadType, Self.stringPayload)
        out.string(Field.payloadUtf8, payload)
        return out.bytes
    }

    /// Reads a message. Returns nil if the bytes are not a message.
    ///
    /// Unknown fields are skipped, not refused. This is another party's protocol. If a receiver starts sending a
    /// field this code has never seen, the music must keep playing.
    public init?(_ data: Data) {
        var reader = Protobuf.Reader(data)

        var source = "", destination = "", namespace = "", payload = ""

        while let (field, wire) = reader.tag() {
            switch (field, wire) {
            case (Field.source, .bytes): source = reader.string() ?? ""
            case (Field.destination, .bytes): destination = reader.string() ?? ""
            case (Field.namespace, .bytes): namespace = reader.string() ?? ""
            case (Field.payloadUtf8, .bytes): payload = reader.string() ?? ""
            default: guard reader.skip(wire) else { return nil }
            }
        }

        guard !namespace.isEmpty else { return nil }

        self.source = source
        self.destination = destination
        self.namespace = namespace
        self.payload = payload
    }

    // ── the frame ──

    /// On the wire, a message is its length as four big-endian bytes, followed by the message.
    public var framed: Data {
        let body = encoded
        var frame = Data(capacity: body.count + 4)

        withUnsafeBytes(of: UInt32(body.count).bigEndian) { frame.append(contentsOf: $0) }
        frame.append(body)
        return frame
    }

    /// The length that a frame declares, or nil while fewer than four bytes have arrived.
    ///
    /// This is separate from reading the body, because **a stream does not arrive as whole messages.** The length
    /// is read first. Then the body is waited for. Both can be split across any number of reads.
    public static func length(of header: Data) -> Int? {
        guard header.count >= 4 else { return nil }

        return header.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
    }
}
