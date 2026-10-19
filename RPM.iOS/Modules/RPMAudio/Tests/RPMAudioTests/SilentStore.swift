import Foundation
import Network
import RPMKit
import RPMLibrary
@testable import RPMAudio

/// A local HTTP server that serves silent audio. It runs on this machine.
///
/// **So that `Player` can be tested end to end.** A fake `StreamSource` that returns
/// `https://example.invalid/…` is enough to check which record comes next. It cannot check
/// playback, because nothing is fetched, decoded or played. This store returns a real
/// address on a real socket, with real bytes. So `TrackFeed` fetches, `StreamedPcm`
/// decodes, the engine plays, and the whole pipeline runs, without any sound.
///
/// Range requests are answered, because a seek asks for one.
final class SilentStore: @unchecked Sendable {

    private let lock = NSLock()
    private var listener: NWListener?
    private var lengths: [String: Double] = [:]
    private(set) var asked: [String] = []
    private var port: UInt16 = 0

    /// How long each record is. Anything not named here is `fallback` long.
    var fallback: Double = 20

    /// A pause before each answer, so a track change takes about as long as it does on a real
    /// network. On localhost a LOAD round trip takes about a millisecond, so the timing windows
    /// during a connect would never be hit. On a phone talking to a speaker, the round trip
    /// takes hundreds of milliseconds.
    var slowBy: Duration = .zero

    func start() async throws {
        let listener = try NWListener(using: .tcp)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .global())
            Task { await self?.answer(connection) }
        }

        let ready = AsyncStream<UInt16>.makeStream()
        listener.stateUpdateHandler = { state in
            if case .ready = state, let port = listener.port { ready.continuation.yield(port.rawValue) }
        }
        listener.start(queue: .global())

        for await said in ready.stream { lock.withLock { port = said }; break }
    }

    func stop() { listener?.cancel() }

    func lasts(_ seconds: Double, for rpmId: String) {
        lock.withLock { lengths[rpmId] = seconds }
    }

    func address(of rpmId: String) -> URL {
        URL(string: "http://127.0.0.1:\(lock.withLock { port })/\(rpmId).wav")!
    }

    private func answer(_ connection: NWConnection) async {
        guard let head = await read(connection) else { connection.cancel(); return }

        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let request = lines.first, request.hasPrefix("GET ") else { connection.cancel(); return }

        let path = request.dropFirst(4).prefix(while: { $0 != " " })
        let rpmId = String(path.dropFirst().replacingOccurrences(of: ".wav", with: ""))
        lock.withLock { asked.append(rpmId) }

        let waitFor = lock.withLock { slowBy }
        if waitFor > .zero { try? await Task.sleep(for: waitFor) }

        let seconds = lock.withLock { lengths[rpmId] ?? fallback }
        let whole = SilentRecord.of(seconds: seconds)

        // A seek sends a Range header that starts part way through the record. Only the
        // start offset is read.
        var from = 0
        if let range = lines.first(where: { $0.lowercased().hasPrefix("range:") }),
           let equals = range.firstIndex(of: "="),
           let dash = range.firstIndex(of: "-"), equals < dash {
            from = Int(range[range.index(after: equals)..<dash]) ?? 0
        }

        let body = whole.suffix(from: min(from, whole.count))
        var header = from > 0
            ? "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes \(from)-\(whole.count - 1)/\(whole.count)\r\n"
            : "HTTP/1.1 200 OK\r\n"
        header += "Content-Type: audio/wav\r\nAccept-Ranges: bytes\r\n"
        header += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"

        await send(connection, Data(header.utf8) + body)
        connection.cancel()
    }

    private func read(_ connection: NWConnection) async -> String? {
        var head = Data()
        while head.range(of: Data("\r\n\r\n".utf8)) == nil, head.count < 8192 {
            let piece: Data? = await withCheckedContinuation { go in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, _, _ in
                    go.resume(returning: data)
                }
            }
            guard let piece, !piece.isEmpty else { break }
            head += piece
        }
        return head.isEmpty ? nil : String(decoding: head, as: UTF8.self)
    }

    private func send(_ connection: NWConnection, _ data: Data) async {
        await withCheckedContinuation { (go: CheckedContinuation<Void, Never>) in
            connection.send(content: data, completion: .contentProcessed { _ in go.resume() })
        }
    }
}

/// Returns the silent store's address for every track, so the player fetches real bytes.
struct SilenceSigned: StreamSource {
    let store: SilentStore

    func stream(_ shelf: CloudShelf, rpmId: String,
                kilobits: Int) async throws -> (url: URL, kilobits: Int, kind: StreamKind) {
        (store.address(of: rpmId), kilobits, .stored)
    }

    func headClips(_ rpmIds: [String]) async throws -> [String: Data] { [:] }
}

struct AnyShelf: ShelfSource {
    func shelf(of rpmId: String?) -> CloudShelf { .own }
}

/// Nothing downloaded: every track is streamed.
struct NoCopies: PhoneCopies {
    func copy(of rpmId: String) -> PhoneCopy? { nil }
}

/// Tracks that the test marks as downloaded. Each one is a file of silence on disk.
final class Copies: PhoneCopies, @unchecked Sendable {
    private let lock = NSLock()
    private var held: [String: PhoneCopy] = [:]
    private let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("rpm-copies-\(UUID().uuidString)", isDirectory: true)

    /// Writes silence for a track and marks the track as downloaded.
    func hold(_ rpmId: String, seconds: Double = 20) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent(rpmId)
        try SilentRecord.of(seconds: seconds).write(to: file)
        lock.withLock { held[rpmId] = PhoneCopy(file: file, kilobits: 0) }
    }

    func copy(of rpmId: String) -> PhoneCopy? { lock.withLock { held[rpmId] } }
}

/// A network that always reads the same. The offline state is published at once. The settling
/// wait belongs to `NetworkReach` and is tested there, not here.
struct FixedLine: PathWatcher {
    let reading: Reach

    func readings() -> AsyncStream<Reach> {
        AsyncStream { $0.yield(reading) }
    }

    /// A reach that says the phone is offline, once it has settled.
    static func offline() async -> NetworkReach {
        let reach = NetworkReach(watching: FixedLine(reading: .away), settling: .zero)
        reach.begin()
        for _ in 0..<100 where reach.now.isOnline { try? await Task.sleep(for: .milliseconds(10)) }
        return reach
    }
}
