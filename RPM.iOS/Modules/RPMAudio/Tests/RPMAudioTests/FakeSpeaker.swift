import Foundation
import Network
import RPMCast

/// A simulated Chromecast that runs in this process and makes no sound.
///
/// Cast faults are hard to reproduce without a real speaker. This type lets a test press a key
/// and check, directly, whether the key reached the speaker.
///
/// This is a speaker: a TLS listener on this machine that speaks the real Cast protocol through
/// the real `CastLink`, over the real framing. It fetches the stream over real HTTP from the real
/// `CastServer`. Nothing is stubbed between the player and this type. It keeps a media session,
/// a player state and a clock. It answers `GET_STATUS` as a receiver does, and it **records every
/// key it was told**.
///
/// It plays by reading the stream and discarding the bytes, at the rate the header says they
/// should be used. That makes an underrun visible. A room that pulls faster than the pump can
/// fill empties the ring, and `starved` counts that.
final class FakeSpeaker: @unchecked Sendable {

    // ── what the test asks it ──

    /// Every media key it was told, in order. `["LOAD", "PAUSE", "PLAY"]`.
    private(set) var heard: [String] = []

    /// The state it reports now: `PLAYING`, `PAUSED`, `IDLE` or `BUFFERING`.
    private(set) var playerState = "IDLE"

    /// Seconds into the stream, as it would report them.
    private(set) var currentTime: Double = 0

    /// How many times it ran out of audio. That is, the ring was empty when it tried to read.
    private(set) var starved = 0

    /// Bytes pulled off the stream.
    private(set) var fetched = 0

    /// How many `GET_STATUS` requests it received. This is the poll's own heartbeat.
    private(set) var polls = 0

    /// Every message on the RPM control channel, in order, as raw JSON.
    ///
    /// **Only the RPM receiver handles this channel.** A stock receiver does not know the
    /// namespace, so a fake that stands in for one records nothing here, however much is sent.
    /// The tests check this.
    private(set) var told: [String] = []

    /// Whether this speaker runs the RPM receiver when it is asked for one.
    ///
    /// The two receivers look like different speakers to the code above. The RPM receiver
    /// supports the control channel. The stock receiver supports only the media namespace. Set
    /// this before ``start``.
    var runsRpmsReceiver = false

    /// The device to hand `Player.cast(to:)`.
    private(set) var device: CastDevice!

    private let lock = NSLock()
    private var listener: NWListener?
    private var socket: NWConnection?
    /// The media session it handed out for the current stream.
    private(set) var session = 0

    /// The cover address from the last LOAD, or nil if the LOAD had none.
    ///
    /// The LOAD message is the only way a stock receiver gets a cover. It has no other channel
    /// that can receive image bytes.
    private(set) var artworkUrl: String?
    private var loadedURL: URL?
    private var draining: Task<Void, Never>?
    private var closed = false

    func what<T>(_ read: (FakeSpeaker) -> T) -> T { lock.withLock { read(self) } }

    // ── standing it up ──

    func start(named: String = "woonkamer") async throws {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(options.securityProtocolOptions,
                                                try SelfSigned.identity())

        let listener = try NWListener(using: .init(tls: options))
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            self?.take(connection)
        }

        let ready = AsyncStream<UInt16>.makeStream()
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port { ready.continuation.yield(port.rawValue) }
        }
        listener.start(queue: .global())

        var port: UInt16 = 0
        for await said in ready.stream { port = said; break }

        device = CastDevice(id: "fake-\(port)", name: named, model: "a fake speaker",
                            host: "127.0.0.1", port: Int(port), isGroup: false)
    }

    func stop() {
        lock.withLock { closed = true }
        draining?.cancel()
        socket?.cancel()
        listener?.cancel()
    }

    /// Tells the app that the receiver could not load the cover from its address.
    ///
    /// This is the only message that asks for the cover as bytes. The address is sent with the
    /// record, and the receiver fetches it. If the receiver cannot, it sends this message. It is
    /// the only route to the control channel's `art` message.
    func couldNotFetchTheCover() {
        Task { [weak self] in
            guard let self, let socket = self.lock.withLock({ self.socket }) else { return }
            await self.send(#"{"type":"artfail"}"#, to: socket,
                            from: "fake-transport", at: CastMessage.sender)
        }
    }

    /// Simulates a person pressing a key on the speaker.
    ///
    /// A receiver sends a status update when this happens, and this type does the same. It is the
    /// only way the phone learns about the key press. `RoomStream` reads that update.
    func somebodyPressed(_ key: String) {
        lock.withLock {
            heard.append("ROOM_\(key)")
            playerState = key == "PAUSE" ? "PAUSED" : (key == "PLAY" ? "PLAYING" : "IDLE")
        }
        guard let connection = lock.withLock({ socket }) else { return }
        Task { await send(mediaStatus(id: 0), to: connection,
                          from: "fake-transport", at: CastMessage.sender) }
    }

    // ── the protocol ──

    private func take(_ connection: NWConnection) {
        lock.withLock { socket = connection }
        connection.start(queue: .global())
        Task { await read(connection) }
    }

    private func read(_ connection: NWConnection) async {
        while !(lock.withLock { closed }) {
            guard let header = await receive(connection, exactly: 4),
                  let length = CastMessage.length(of: header), length > 0, length < 1 << 20,
                  let body = await receive(connection, exactly: length),
                  let message = CastMessage(body)
            else { return }

            await answer(message, on: connection)
        }
    }

    private func answer(_ message: CastMessage, on connection: NWConnection) async {
        let id = Self.requestId(message.payload)

        switch message.namespace {
        case CastLink.connectionNamespace:
            return                                   // CONNECT and CLOSE are not answered

        case CastLink.receiverNamespace:
            if message.payload.contains(#""LAUNCH""#) || message.payload.contains(#""GET_STATUS""#) {
                await send(receiverStatus(id: id), to: connection,
                           from: CastMessage.receiver, at: message.source)
            }
            if message.payload.contains(#""STOP""#) {
                lock.withLock { playerState = "IDLE"; heard.append("STOP_APP") }
                await send(#"{"type":"RECEIVER_STATUS","requestId":\#(id),"status":{"applications":[]}}"#,
                           to: connection, from: CastMessage.receiver, at: message.source)
            }
            if message.payload.contains(#""SET_VOLUME""#) {
                await send(receiverStatus(id: id), to: connection,
                           from: CastMessage.receiver, at: message.source)
            }

        case CastLink.mediaNamespace:
            if message.payload.contains(#""GET_STATUS""#) { lock.withLock { polls += 1 } }
            await media(message, id: id, on: connection)

        case CastLink.controlNamespace:
            // Recorded but not answered. Nothing on this channel asks a question. Track details
            // and the cover are sent on this channel. Next and previous come from the receiver, in
            // the other direction.
            lock.withLock { told.append(message.payload) }

        default:
            return
        }
    }

    private func media(_ message: CastMessage, id: Int, on connection: NWConnection) async {
        let payload = message.payload

        if payload.contains(#""LOAD""#) {
            let url = Self.string(payload, "contentId") ?? Self.string(payload, "url")
            let art = Self.firstImage(in: payload)
            lock.withLock {
                session += 1
                heard.append("LOAD")
                playerState = "BUFFERING"
                currentTime = 0
                loadedURL = url.flatMap(URL.init(string:))
                artworkUrl = art
            }
            await send(mediaStatus(id: id), to: connection,
                       from: message.destination, at: message.source)
            drain()
            return
        }

        if payload.contains(#""PAUSE""#) {
            lock.withLock { heard.append("PAUSE"); playerState = "PAUSED" }
        } else if payload.contains(#""PLAY""#) {
            lock.withLock { heard.append("PLAY"); playerState = "PLAYING" }
        } else if payload.contains(#""STOP""#) {
            lock.withLock { heard.append("STOP"); playerState = "IDLE" }
            draining?.cancel()
        } else if payload.contains(#""SEEK""#) {
            lock.withLock { heard.append("SEEK") }
        }

        await send(mediaStatus(id: id), to: connection,
                   from: message.destination, at: message.source)
    }

    /// Reads the stream and discards it, at the rate a speaker would.
    ///
    /// **This is where an underrun is detected.** A room that pulls faster than the pump fills
    /// empties the ring. The server then answers with a short response, and that counts as one
    /// starve. The count is kept so a test can check it.
    private func drain() {
        draining?.cancel()
        guard let url = lock.withLock({ loadedURL }) else { return }

        draining = Task { [weak self] in
            guard let self else { return }

            var request = URLRequest(url: url)

            // **This is a stream, not a short request.** A receiver keeps the connection open for
            // the whole record. A short timeout would make every long cast look like an underrun,
            // so the timeout is one hour.
            request.timeoutInterval = 3600

            guard let (bytes, _) = try? await URLSession.shared.bytes(for: request) else { return }
            self.lock.withLock { if self.playerState == "BUFFERING" { self.playerState = "PLAYING" } }

            // The sink serves 16-bit stereo at 44.1 kHz. The rate only has to match the rate that
            // the ring is filled at, so the two can be compared.
            let perSecond = 44_100 * 2 * 2
            var run = 0
            var began = ContinuousClock.now

            do {
              for try await _ in bytes {
                if Task.isCancelled { return }

                // **When paused, it stops reading.** A real receiver keeps its buffered audio and
                // plays it on resume. This fake has no buffer. If it kept reading while paused, the
                // queued audio would be discarded, the clock would stick on resume, and the cast
                // would come home about thirty seconds later. That would be a fault in this
                // harness, not in the player.
                while self.lock.withLock({ self.playerState == "PAUSED" }) {
                    if Task.isCancelled { return }
                    try? await Task.sleep(for: .milliseconds(50))
                    began = .now
                }

                run += 1
                self.lock.withLock { self.fetched += 1 }

                if run >= perSecond / 20 {                       // 0.05 s of audio
                    run = 0
                    self.lock.withLock {
                        if self.playerState == "PLAYING" { self.currentTime += 0.05 }
                    }

                    // Real time, so the ring is under the same pressure as on a real speaker.
                    // Without this delay, the fake would read the whole record at once, and every
                    // cast would look like an underrun.
                    let due = began.advanced(by: .milliseconds(50))
                    if ContinuousClock.now < due { try? await Task.sleep(until: due) }
                    began = .now
                }
              }
            } catch {
                // The server answered short, so the ring was empty when the room tried to read.
                // **That is an underrun.** It is counted as a fact, not guessed.
                self.lock.withLock { self.starved += 1 }
                return
            }

            self.lock.withLock { self.starved += 1 }
        }
    }

    // ── what it says ──

    private func receiverStatus(id: Int) -> String {
        let ours = lock.withLock { runsRpmsReceiver }

        // **The app id decides which receiver the player thinks it has.** The namespace list
        // decides what it can use. A fake that stands in for a stock receiver answers with
        // neither. The player then falls back to the stock receiver, as it does in a room where
        // the RPM receiver will not launch.
        let appId = ours ? ReceiverStatus.rpmReceiver : ReceiverStatus.defaultMediaReceiver
        let name = ours ? "RPM" : "Default Media Receiver"
        let namespaces = ours
            ? #"{"name":"\#(CastLink.mediaNamespace)"},{"name":"\#(CastLink.controlNamespace)"}"#
            : #"{"name":"\#(CastLink.mediaNamespace)"}"#

        return #"""
        {"type":"RECEIVER_STATUS","requestId":\#(id),"status":{"applications":[{\#
        "appId":"\#(appId)","sessionId":"fake-session","transportId":"fake-transport",\#
        "displayName":"\#(name)","statusText":"Ready",\#
        "namespaces":[\#(namespaces)]}],\#
        "volume":{"level":0.35,"muted":false,"controlType":"attenuation","stepInterval":0.05}}}
        """#
    }

    private func mediaStatus(id: Int) -> String {
        let (session, state, at) = lock.withLock { (self.session, playerState, currentTime) }
        return #"""
        {"type":"MEDIA_STATUS","requestId":\#(id),"status":[{"mediaSessionId":\#(session),\#
        "playerState":"\#(state)","currentTime":\#(at)}]}
        """#
    }

    // ── the wire ──

    private func send(_ payload: String, to connection: NWConnection,
                      from source: String, at destination: String) async {
        // The channel is found from the payload. A real receiver knows which channel it sends
        // on. This fake works it out from the payload, in the same way that the sender reads it
        // back.
        let namespace = if payload.contains("RECEIVER_STATUS") { CastLink.receiverNamespace }
                        else if payload.contains(#""artfail""#) { CastLink.controlNamespace }
                        else { CastLink.mediaNamespace }

        let message = CastMessage(source: source, destination: destination,
                                  namespace: namespace, payload: payload)

        await withCheckedContinuation { (go: CheckedContinuation<Void, Never>) in
            connection.send(content: message.framed, completion: .contentProcessed { _ in go.resume() })
        }
    }

    private func receive(_ connection: NWConnection, exactly count: Int) async -> Data? {
        await withCheckedContinuation { (go: CheckedContinuation<Data?, Never>) in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, _ in
                go.resume(returning: data)
            }
        }
    }

    private static func requestId(_ payload: String) -> Int {
        Int(string(payload, "requestId") ?? "") ?? 0
    }

    /// Reads the cover address from a LOAD's metadata, at `media.metadata.images[0].url`.
    ///
    /// The payload is parsed as JSON, not searched as text. A text search fails on escaped
    /// characters. JSON writes a forward slash as `\/`, so a search would return a URL that does
    /// not resolve. The nesting is part of what is checked.
    private static func firstImage(in payload: String) -> String? {
        guard let fields = (try? JSONSerialization.jsonObject(with: Data(payload.utf8)))
                as? [String: Any],
              let media = fields["media"] as? [String: Any],
              let metadata = media["metadata"] as? [String: Any],
              let images = metadata["images"] as? [[String: Any]]
        else { return nil }

        return images.first?["url"] as? String
    }

    private static func string(_ payload: String, _ key: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        if let here = top[key] { return "\(here)" }
        if let media = top["media"] as? [String: Any], let here = media[key] { return "\(here)" }
        return nil
    }
}
