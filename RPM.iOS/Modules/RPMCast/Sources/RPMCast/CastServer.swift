import Foundation
import Network
import os

/// The phone, as something that a speaker can fetch audio from.
///
/// **A receiver pulls. It is never pushed to.** The only thing that the Cast protocol accepts is a URL. So for as
/// long as the music plays, this app acts as a web server. It answers with a WAV file whose length it never reaches,
/// and it keeps writing until stop is pressed.
///
/// The desktop apps use the same design. The engine has one source and one sink, and this server is the sink. A queue
/// advances because the engine advances it. Nothing above this type needs to know that the sound is leaving the device.
public actor CastServer {
    private static let log = Logger(subsystem: "com.rpm.player", category: "cast")

    public enum Trouble: Error, Equatable {
        case noPort
        case noAddress
    }

    /// The audio that waits between the engine and the speaker.
    private let ring: PcmRing

    private var listener: NWListener?
    private var serving: [ObjectIdentifier: Task<Void, Never>] = [:]

    /// How much is written at once. This is a fifth of a second of stereo at 44.1 kHz. That is small enough for a stop
    /// to be heard quickly, and large enough that each write is not a system call for every millisecond.
    private static let bite = 35_280

    public init(ring: PcmRing) {
        self.ring = ring
    }

    /// The address that a **speaker** can fetch from. This is not localhost.
    public private(set) var url: URL?

    /// The only stream that this server answers.
    ///
    /// **Any other request is refused.** That is the whole point of putting the name in the address. A track change
    /// creates a new name (see ``nowServing(_:)``). A receiver that still holds the last song's URL gets a 404, not the
    /// new song's bytes. Without this, the speaker keeps playing the audio it has already buffered from the old song.
    /// On a Chromecast, that can go on for about half a minute.
    private var live = ""

    /// Whether anyone has actually fetched the stream that is live now.
    ///
    /// **A LOAD that the receiver accepts does not mean the receiver will fetch the stream.** With a bad address, or a
    /// speaker that has gone quiet, the receiver can answer the LOAD and then never open the connection. From this side,
    /// that looks the same as a room that is buffering. Nothing else notices. The pacer waits for a position that the room
    /// has never reported. That is the one state its stall watch cannot see. So the pump waits on a full ring, and the
    /// music is silent with no error.
    ///
    /// The desktop's `RPM.Core/Audio/CastSink.LoadAsync` checks this with a 20-second watch on the same fact. This property is that fact.
    public private(set) var fetched = false

    public func start() async throws -> URL {
        stop()
        fetched = false

        guard let listener = try? NWListener(using: .tcp) else { throw Trouble.noPort }

        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.serve(connection) }
        }
        self.listener = listener

        let port = try await Self.portOf(listener)

        guard let host = Self.ownAddress() else { throw Trouble.noAddress }
        self.host = host
        self.port = port

        guard let url = address(for: Self.name()) else { throw Trouble.noAddress }

        self.url = url
        Self.log.notice("serving at \(url.absoluteString, privacy: .public)")
        return url
    }

    private var host = ""
    private var port: UInt16 = 0

    /// Starts a new stream on the same port. The address changes, the audio that is served changes with it, and any
    /// receiver that holds the old address stops being answered.
    ///
    /// The same socket is used on purpose. A new port would mean a new listener. Each LOAD hands the receiver an address,
    /// and a new listener would mean a new check that the speaker can reach the phone. That check is the slow part.
    public func nowServing(_ id: String = CastServer.name()) -> URL? {
        guard listener != nil, let url = address(for: id) else { return nil }

        // **Done before the address is answered for.** That way nothing is written to the old connection from a ring
        // that now holds a different track.
        cutTheStream()

        // A new name means nobody has fetched it yet, whoever fetched the last one.
        fetched = false

        self.url = url
        Self.log.notice("now serving \(url.absoluteString, privacy: .public)")
        return url
    }

    /// A name that no receiver can already hold.
    public static func name() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "") }

    // ── the cover, which the receiver fetches ──

    /// The picture for the record that is playing, and the type of that picture.
    ///
    /// These are held here rather than passed with each request, because **the receiver fetches the cover on its own
    /// schedule**. The address goes out with the LOAD, which happens before anything has read a picture. So whatever is
    /// in hand when the request arrives is what gets sent. The desktop server holds the same two fields for the same reason.
    private var cover: Data?
    private var coverType = "image/jpeg"

    /// A cover has been promised, but it has not been supplied yet.
    ///
    /// **The wait is the point.** The cover is read on another task, so the LOAD does not wait for the picture. For the
    /// first moment of each track, there is no answer ready. An answer from an empty field would say "this record has no
    /// cover" about a record that does have one. The desktop's `CastSink.ExpectArtwork` does the same thing.
    private var coverPromised = false

    /// Connections that are held open until the promised cover arrives.
    private var waitingForCover: [CheckedContinuation<Void, Never>] = []

    /// Says that a cover is coming, so that a fetch which arrives first waits for it.
    ///
    /// Call this before the LOAD that publishes the address. **Every promise must be kept.** That includes the case where
    /// the picture cannot be read. Call ``nowShowing(_:type:)`` with nil instead, which means this record has no cover.
    public func expectCover() {
        coverPromised = true
        cover = nil
    }

    /// The cover itself, or nil for a record that has none. Both are answers, and both release any waiting requests.
    public func nowShowing(_ bytes: Data?, type: String = "image/jpeg") {
        cover = bytes
        coverType = type
        coverPromised = false

        for waiting in waitingForCover { waiting.resume() }
        waitingForCover = []
    }

    /// Where a receiver fetches the cover from.
    ///
    /// **The name belongs to the picture, not to the track.** It must change when the cover changes. Otherwise a receiver
    /// keeps showing the first cover for the rest of the playlist, because it has already fetched that address and has no
    /// reason to ask again. The route ignores everything after the prefix, so the caller chooses the name. Naming it after
    /// the contents works well. Every track on an album uses the same sleeve, so they all share one address. The receiver can
    /// then draw it from its own cache.
    public func coverAddress(named key: String) -> URL? {
        guard !host.isEmpty, port > 0 else { return nil }
        return URL(string: "http://\(host):\(port)/art/\(key).jpg")
    }

    /// Whether a request line asks for a cover, and not for the stream.
    static func asksForCover(_ request: String) -> Bool {
        guard let line = request.split(separator: "\r\n", maxSplits: 1).first else { return false }
        return line.contains("/art/")
    }

    /// Answers a request for the cover. If a cover has been promised and has not arrived yet, this waits first.
    private func answerWithCover(_ connection: NWConnection, headOnly: Bool) async {
        if coverPromised {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                waitingForCover.append(continuation)
            }
        }

        guard let cover, !cover.isEmpty else {
            // **A record with no cover gets a 404. That is the correct answer.** The receiver then shows the screen it
            // uses for a track without a cover. Holding the connection open would leave the previous record's cover on
            // screen over another song.
            _ = await send(connection, Data(Self.headers("404 Not Found", length: 0).utf8))
            return
        }

        let head = Self.headers("200 OK", type: coverType, length: cover.count,
                                cache: Self.forever)

        guard await send(connection, Data(head.utf8)) else { return }
        guard !headOnly else { return }

        _ = await send(connection, cover)
    }

    /// Covers are named by their contents, so they can be cached indefinitely. A different cover has a different
    /// address. See ``coverAddress(named:)``.
    private static let forever = "public, max-age=31536000, immutable"

    /// A response header. It includes the CORS header that the receiver needs in order to **read** the pixels.
    ///
    /// **The cross-origin header is required here.** The receiver reads a small square of the cover to colour the
    /// background behind the record. An image fetched from another origin without this header marks the canvas as tainted.
    /// The fetch succeeds and the image draws, but the read then throws. Google's documentation mentions CORS only for
    /// adaptive streams, so it is easy to leave out. The desktop server sends it on every response.
    private static func headers(_ status: String, type: String? = nil,
                                length: Int? = nil,
                                cache: String = "no-cache, no-store") -> String {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Connection: close\r\n"
        head += "Cache-Control: \(cache)\r\n"
        head += "Accept-Ranges: none\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Access-Control-Allow-Methods: GET, HEAD, OPTIONS\r\n"
        head += "Access-Control-Allow-Headers: Content-Type, Accept-Encoding, Range\r\n"
        if let type { head += "Content-Type: \(type)\r\n" }
        if let length { head += "Content-Length: \(length)\r\n" }
        return head + "\r\n"
    }

    private func address(for id: String) -> URL? {
        guard !host.isEmpty, port > 0 else { return nil }
        live = id
        return URL(string: "http://\(host):\(port)/\(id).wav")
    }

    /// Returns the port that the system assigned. **It waits for the answer. It does not poll.**
    ///
    /// This does not poll with `usleep`. `usleep` blocks its thread.
    /// Swift's cooperative pool has about one thread per core, and the engine's pump runs as a task on that same pool.
    /// Blocking one thread on a phone stops the pump. The buffer then runs dry, and the music stutters. This happens when
    /// the user picks a speaker, which is when this function runs. The problem cannot be reproduced in the simulator.
    private static func portOf(_ listener: NWListener) async throws -> UInt16 {
        let answer = Answer()

        return try await withCheckedThrowingContinuation { continuation in
            answer.hold(continuation)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue, port != 0 else {
                        answer.give(.failure(Trouble.noPort))
                        return
                    }
                    answer.give(.success(port))

                case .failed, .cancelled:
                    answer.give(.failure(Trouble.noPort))

                default:
                    break
                }
            }

            listener.start(queue: .global(qos: .userInitiated))

            // A listener that never reports anything. Nothing observed does this. A cast that hangs forever on a
            // button press is worse than one that reports that it could not start.
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                answer.give(.failure(Trouble.noPort))
            }
        }
    }

    /// A single answer, from whichever of several callbacks arrives first.
    ///
    /// Resuming a continuation twice crashes. There are three ways to leave the wait above.
    private final class Answer: @unchecked Sendable {
        private let gate = NSLock()
        private var waiting: CheckedContinuation<UInt16, any Error>?

        func hold(_ continuation: CheckedContinuation<UInt16, any Error>) {
            gate.withLock { waiting = continuation }
        }

        func give(_ result: Result<UInt16, any Error>) {
            let waiting = gate.withLock { () -> CheckedContinuation<UInt16, any Error>? in
                defer { self.waiting = nil }
                return self.waiting
            }
            waiting?.resume(with: result)
        }
    }

    public func stop() {
        streaming = nil

        // **A promise that this server will not keep.** A receiver can be waiting inside
        // ``answerWithCover(_:headOnly:)`` for a picture that was read on a task that this teardown is cancelling.
        // A continuation that is never resumed is a leak. It shows up as a connection that never closes. Nil is a valid answer.
        nowShowing(nil)

        for (_, task) in serving { task.cancel() }
        serving = [:]

        listener?.cancel()
        listener = nil
        url = nil
    }

    // ── one speaker's connection ──

    private func serve(_ connection: NWConnection) {
        let key = ObjectIdentifier(connection)

        serving[key] = Task { [weak self] in
            connection.start(queue: .global(qos: .userInitiated))

            await self?.answer(connection)
            connection.cancel()
            await self?.forget(key)
        }
    }

    /// The connection that is being written to right now, so that it can be cut off.
    ///
    /// **Refusing the old address is not enough on its own.** A 404 only affects new requests. A connection that is already
    /// open keeps writing from the same ring, and the ring now holds the new track. So a receiver that has not yet asked for
    /// the new address is given the new song after the old song's buffer. It plays the buffered seconds of the old song
    /// first. The cut-over is faster than it would be otherwise, but it is still not immediate.
    ///
    /// Only one connection may read the audio at a time. A new connection replaces the old one.
    private var streaming: NWConnection?

    private func nowTheOne(_ connection: NWConnection) {
        let previous = streaming
        streaming = connection
        if previous !== connection { previous?.cancel() }
    }

    /// Cuts off the connection that is being written to.
    ///
    /// **The ring has one reader.** Two connections that read from it do not each get a copy. They take turns, a piece
    /// each. The speaker then plays the track in fragments that jump and stutter. So the old connection must be closed
    /// before the new track's audio goes into the ring.
    ///
    /// This is private on purpose. Cutting is only half of what a caller needs. The other half is that the player must
    /// stop believing the room holds any audio. From here until the next LOAD, the room holds none, and the player must
    /// say so. Otherwise it looks like a stop that was pressed at the speaker. ``nowServing(_:)`` is the only public way
    /// in. `RoomStream` handles the other half.
    private func cutTheStream() {
        streaming?.cancel()
        streaming = nil
    }

    private func forget(_ key: ObjectIdentifier) {
        serving[key] = nil
    }

    /// Whether a request line names the live stream.
    ///
    /// The name is read from the first line, not parsed. This server answers one request shape from one kind of client.
    /// A URL parser would be too much code for the question "is this name in the request".
    static func asksFor(_ id: String, in request: String) -> Bool {
        guard !id.isEmpty else { return true }   // No name yet: answer any request.
        guard let line = request.split(separator: "\r\n", maxSplits: 1).first else { return false }
        return line.contains("/\(id).wav")
    }

    /// Reads enough of the request to know what was asked for. Then it writes until the music stops or the speaker goes away.
    private func answer(_ connection: NWConnection) async {
        guard let request = await read(connection) else { return }

        // Some firmware sends HEAD before GET. A HEAD response has no body. A body would start a stream that the
        // receiver does not expect.
        let headOnly = request.hasPrefix("HEAD")

        // **A cover request is answered before the stream name is checked.** A cover request is not a stream request,
        // so it must not be refused for not being the stream. Its own name is ignored. See ``coverAddress(named:)``.
        guard !Self.asksForCover(request) else {
            await answerWithCover(connection, headOnly: headOnly)
            return
        }

        // **Only the stream that was asked for is answered.** A receiver with the previous song's address must be refused,
        // not given the new song's bytes. It would play them after the audio it has already buffered. That is the
        // cut-over, arriving about half a minute after the key was pressed.
        guard Self.asksFor(live, in: request) else {
            Self.log.notice("refused a request for a stream that is not the live one")
            _ = await send(connection, Data("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n".utf8))
            return
        }

        var headers = "HTTP/1.1 200 OK\r\n"
        headers += "Content-Type: audio/wav\r\n"
        headers += "Accept-Ranges: none\r\n"
        headers += "Cache-Control: no-cache, no-store\r\n"
        headers += "Connection: close\r\n\r\n"

        guard await send(connection, Data(headers.utf8)) else { return }
        guard !headOnly else { return }

        // **The receiver needs its full head start, so the ring keeps its depth.** A receiver does not start playing until
        // it has buffered a few seconds. Audio rendered in real time can never get ahead to supply that. At normal speed,
        // the buffer fills only as fast as it drains, so the speaker waits forever. A buffer of two seconds leaves the
        // speaker in BUFFERING, so it never starts. The ring's depth is the delay between the phone's playhead and the room.
        // That delay is corrected for, not removed. See `CastSink.behind`.

        // **The format header is sent once, at the front.** A receiver reads the format from it and never reads it again.
        // That is why the sizes in it are a promise that nobody keeps. From this point, this connection owns the stream,
        // and any earlier connection is cut off.
        nowTheOne(connection)

        // **Set here, not at the top of this function.** A HEAD is a probe, not a fetch. A receiver that only probes would
        // fail without any error. That is the case that ``fetched`` exists to catch.
        fetched = true

        guard await send(connection, WavHeader.of()) else { return }

        // **One buffer per connection, reused for every write.** The ring's lock is one that the audio thread waits on.
        // So nothing on this side may allocate while holding it. A `malloc` here would make the audio thread wait, and
        // that can be heard. It is a local variable and not a field, because two receivers can be served at once, and
        // they must not share it.
        var pail = [UInt8](repeating: 0, count: Self.bite)

        while !Task.isCancelled {
            let took = pail.withUnsafeMutableBytes { ring.read(into: $0) }

            guard took > 0 else {
                // The engine is between buffers. **This is not the end.** Closing here would drop the speaker every time
                // a track changes.
                try? await Task.sleep(for: .milliseconds(20))
                continue
            }

            guard await send(connection, Data(pail[0..<took])) else { return }
        }
    }

    private func read(_ connection: NWConnection) async -> String? {
        await withCheckedContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                continuation.resume(returning: data.map { String(decoding: $0, as: UTF8.self) })
            }
        }
    }

    private func send(_ connection: NWConnection, _ data: Data) async -> Bool {
        await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { failed in
                continuation.resume(returning: failed == nil)
            })
        }
    }

    // ── where this phone is ──

    /// This device's address on the network that the speaker is on.
    ///
    /// **Not localhost, and not just the first address that is found.** A phone has several: loopback, the cellular
    /// interface, and sometimes a hotspot. Only the Wi-Fi address can be reached from a speaker in the same house.
    public static func ownAddress() -> String? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }

        var found: String?

        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            guard interface.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.pointee.ifa_name)
            // en0 is Wi-Fi on a phone and on a Mac. Other names are a guess.
            guard name == "en0" || name == "en1" else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(interface.pointee.ifa_addr,
                              socklen_t(interface.pointee.ifa_addr.pointee.sa_len),
                              &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }

            let address = String(cString: host)
            if name == "en0" { return address }
            found = found ?? address
        }

        return found
    }
}
