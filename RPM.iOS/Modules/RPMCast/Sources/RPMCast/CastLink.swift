import Foundation
import Network
import os

/// The conversation with one speaker.
///
/// CASTV2 is a TLS socket that carries length-prefixed protobuf messages, grouped by namespace. This type
/// owns the socket and the two namespaces that every other namespace depends on. The connection namespace
/// must be opened before a receiver listens to anything. The heartbeat must be answered, or the speaker
/// closes the connection.
public actor CastLink {
    private static let log = Logger(subsystem: "com.rpm.player", category: "cast")

    /// Every namespace is this prefix plus a suffix.
    public static func namespace(_ suffix: String) -> String {
        "urn:x-cast:com.google.cast.\(suffix)"
    }

    public static let connectionNamespace = namespace("tp.connection")
    public static let heartbeatNamespace = namespace("tp.heartbeat")
    public static let receiverNamespace = namespace("receiver")
    public static let mediaNamespace = namespace("media")

    /// **Ours, and shared with nobody.** Only RPM's own receiver sends on it. The stock receiver does
    /// not know it exists. Messages that arrive on it are next or previous presses at the speaker.
    public static let controlNamespace = "urn:x-cast:com.rpmrpmrpm.control"

    public enum Trouble: Error, Equatable {
        /// The socket never came up. The speaker is off, or it is on another network.
        case unreachable

        /// The socket came up and then closed. This is normal on a home network.
        case dropped

        /// A request was sent and no answer came. This is not the same as a refusal. A receiver that will
        /// not do something answers, and says so.
        case silent
    }

    private let device: CastDevice
    private var socket: NWConnection?

    /// Messages that are not answers to a request. An example is a status that the receiver sends
    /// because its state changed. There is one stream. The caller sorts messages by namespace. A stream
    /// for each channel would mean four readers competing for one socket.
    private var told: AsyncStream<CastMessage>.Continuation?
    private var reading: Task<Void, Never>?

    /// The requests that are waiting for an answer, keyed by request number.
    ///
    /// **The protocol matches answers by `requestId` only.** Two requests can be in flight at once, and their
    /// answers can arrive in either order. Taking "the next message on this namespace" as the answer gives the
    /// wrong reply under load. For example, a volume request could receive the reply to a different request.
    private var waiting: [Int: CheckedContinuation<CastMessage, any Error>] = [:]
    private var asked = 0

    public init(to device: CastDevice) {
        self.device = device
    }

    /// The speaker's name, for a sentence that someone reads.
    public nonisolated var name: String { device.name }

    /// Whether the speaker is a group. A refusal has to point at the group, not at the speaker.
    public nonisolated var isGroup: Bool { device.isGroup }

    /// Opens the socket and sends CONNECT.
    ///
    /// **CONNECT is required.** A receiver drops every message on any other namespace until it has
    /// received CONNECT. It does this silently. That looks exactly like a speaker that ignores you.
    public func open() async throws -> AsyncStream<CastMessage> {
        let socket = NWConnection(
            host: .init(device.host), port: .init(rawValue: UInt16(device.port))!,
            using: .init(tls: Self.tls))

        self.socket = socket
        try await bring(socket, up: true)

        let (stream, continuation) = AsyncStream<CastMessage>.makeStream()
        told = continuation
        reading = Task { await self.read(socket) }

        try await connect(to: CastMessage.receiver)
        return stream
    }

    /// Opens a virtual connection to one endpoint.
    ///
    /// **This is needed once per endpoint, and an app's transport is an endpoint of its own.** A receiver
    /// drops every message sent to a destination it is not connected to, and it does so silently. It looks
    /// exactly like a speaker that ignores you. This is the step that is easy to miss.
    public func connect(to destination: String) async throws {
        try await send(CastMessage(destination: destination,
                                   namespace: Self.connectionNamespace,
                                   payload: #"{"type":"CONNECT"}"#))
    }

    /// Sends a request, and waits for the answer to that request.
    ///
    /// `payload` is the JSON without a `requestId`. This link adds the number itself, because the number
    /// is how the answer is matched to the request.
    public func ask(_ payload: String,
                    namespace: String,
                    of destination: String = CastMessage.receiver,
                    within: Duration = .seconds(8)) async throws -> CastMessage {
        asked += 1
        let id = asked

        guard let stamped = Self.stamp(payload, with: id) else { throw Trouble.dropped }

        let giveUp = Task { [weak self] in
            try? await Task.sleep(for: within)
            await self?.giveUpOn(id)
        }
        defer { giveUp.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            // **Registered before sending.** A speaker on the same Wi-Fi can answer before `send` returns.
            // An answer that nobody is waiting for is passed to the messages stream, and it is lost there.
            waiting[id] = continuation

            Task {
                do {
                    try await send(CastMessage(destination: destination,
                                               namespace: namespace, payload: stamped))
                } catch {
                    waiting.removeValue(forKey: id)?.resume(throwing: error)
                }
            }
        }
    }

    private func giveUpOn(_ id: Int) {
        waiting.removeValue(forKey: id)?.resume(throwing: Trouble.silent)
    }

    /// Adds the request number to a payload that was written without one.
    private static func stamp(_ payload: String, with id: Int) -> String? {
        guard let data = payload.data(using: .utf8),
              var fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        fields["requestId"] = id

        guard let out = try? JSONSerialization.data(withJSONObject: fields) else { return nil }
        return String(decoding: out, as: UTF8.self)
    }

    /// The request number that a message answers, if it answers a request.
    private static func answers(_ payload: String) -> Int? {
        guard let data = payload.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return fields["requestId"] as? Int
    }

    public func send(_ message: CastMessage) async throws {
        guard let socket else { throw Trouble.dropped }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            socket.send(content: message.framed, completion: .contentProcessed { failed in
                if failed != nil { continuation.resume(throwing: Trouble.dropped) }
                else { continuation.resume() }
            })
        }
    }

    public func close() {
        // A courtesy that costs nothing, and saves the speaker a timeout. The answer is not waited for,
        // because the socket is closed either way.
        if socket != nil {
            Task { try? await send(CastMessage(namespace: Self.connectionNamespace,
                                               payload: #"{"type":"CLOSE"}"#)) }
        }

        reading?.cancel()
        reading = nil
        told?.finish()
        told = nil
        socket?.cancel()
        socket = nil
    }

    // ── the socket ──

    /// **Any certificate on the local network is accepted.** Every Cast sender does this. A Chromecast
    /// presents a certificate signed by Google's cast authority, and that authority is not in the system
    /// trust store. The real check on the device's identity is the auth challenge in `DeviceAuthMessage`,
    /// not the certificate chain. Nothing here is secret. The payloads are a track title and a URL that is
    /// already signed.
    private static var tls: NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()

        sec_protocol_options_set_verify_block(
            options.securityProtocolOptions,
            { _, _, complete in complete(true) },
            .global(qos: .userInitiated))

        return options
    }

    private func bring(_ socket: NWConnection, up: Bool) async throws {
        let answered = OSAllocatedUnfairLock(initialState: false)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            @Sendable func answer(_ trouble: Trouble?) {
                let first = answered.withLock { done -> Bool in
                    guard !done else { return false }
                    done = true
                    return true
                }
                guard first else { return }

                if let trouble { continuation.resume(throwing: trouble) }
                else { continuation.resume() }
            }

            socket.stateUpdateHandler = { state in
                switch state {
                case .ready: answer(nil)
                case .failed, .cancelled: answer(.unreachable)
                default: break
                }
            }

            socket.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Reads frames until the socket closes.
    ///
    /// **A stream does not arrive as whole messages.** The length is four bytes, and the body is as long as
    /// the length says. Either one can be split across any number of reads. So both are read by exact size,
    /// not by taking whatever arrives.
    private func read(_ socket: NWConnection) async {
        while !Task.isCancelled {
            guard let header = await take(socket, exactly: 4),
                  let length = CastMessage.length(of: header),
                  length > 0, length < 1 << 20,
                  let body = await take(socket, exactly: length)
            else { break }

            guard let message = CastMessage(body) else { continue }

            // Answered here, not passed on. It is not news for the caller. A caller that forgot to answer
            // would lose the speaker, and nothing would explain why.
            if message.namespace == Self.heartbeatNamespace {
                if message.payload.contains(#""PING""#) {
                    try? await send(CastMessage(namespace: Self.heartbeatNamespace,
                                                payload: #"{"type":"PONG"}"#))
                }
                continue
            }

            if let id = Self.answers(message.payload),
               let waiter = waiting.removeValue(forKey: id) {
                waiter.resume(returning: message)
                continue
            }

            told?.yield(message)
        }

        // Anyone still waiting is waiting on a socket that has closed.
        for (_, waiter) in waiting { waiter.resume(throwing: Trouble.dropped) }
        waiting = [:]
        told?.finish()
    }

    private func take(_ socket: NWConnection, exactly count: Int) async -> Data? {
        await withCheckedContinuation { continuation in
            socket.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, failed in
                continuation.resume(returning: failed == nil ? data : nil)
            }
        }
    }
}
