import Foundation
import Testing
import RPMKit
import RPMLibrary
import RPMRadio
@testable import RPMSession

/// The playlists, the library listing and the playlist writes arrive in any order. These tests check
/// that the playlists on screen are what the store holds, resolved against the shelf's tracks,
/// whichever arrives first.
///
/// At launch the order is not fixed. ``LibrarySession/show(_:whenUp:)`` reads the library, and the
/// app coming to the foreground reads the playlists. A large library can take longer to arrive
/// than the playlists.
@MainActor
struct PlaylistReadOrderTests {
    /// The ids the generated list names. All of them are in the library.
    private let ids = ["t0", "t1", "t2"]

    // ── the listing ──

    @Test func playlistsReadBeforeTheLibraryArrivesAreResolvedWhenItDoes() async throws {
        let source = HeldSource(tracks: ids.map(track))
        let cloud = StubCloud()
        let session = try makeSession(source: source, cloud: cloud)

        // The library read starts and waits for its listing.
        let showing = Task { await session.show(.nextLaunch) {} }
        await source.entered()

        // The app comes to the foreground, and the playlists land before the listing.
        await session.rereadPlaylists()
        #expect(session.playlistStanding == .showing)

        await source.release()
        await showing.value

        let mix = try #require(session.playlists.first { $0.origin == .generated })
        #expect(mix.tracks.map(\.rpmId) == ids)
        #expect(mix.missing == 0)
    }

    /// The reload key brings in tracks that arrived in the cloud after the playlists were read.
    @Test func aReloadResolvesThePlaylistsAgainstTheNewListing() async throws {
        let source = HeldSource(tracks: [track("t0")])
        await source.release()
        let session = try makeSession(source: source, cloud: StubCloud())

        await session.show(.nextLaunch) {}
        try await listsArrived(session)

        let before = try #require(session.playlists.first { $0.origin == .generated })
        #expect(before.tracks.map(\.rpmId) == ["t0"])
        #expect(before.missing == 2)

        await source.hand(ids.map(track))
        await session.refresh()

        let after = try #require(session.playlists.first { $0.origin == .generated })
        #expect(after.tracks.map(\.rpmId) == ids)
        #expect(after.missing == 0)
    }

    /// On the TV a computer on the home network adds tracks to the own shelf. A computer that
    /// joins after the playlists were read adds its tracks to them too.
    @Test func additionsThatChangeAreResolvedIntoThePlaylists() async throws {
        let source = HeldSource(tracks: [track("t0")])
        await source.release()

        let home = HomeNetwork()
        let session = try makeSession(source: source, cloud: StubCloud()) { own in
            own + AlbumWall.group(home.tracks)
        }

        await session.show(.nextLaunch) {}
        try await listsArrived(session)
        #expect(session.playlists.first { $0.origin == .generated }?.missing == 2)

        home.tracks = ["t1", "t2"].map(track)
        await session.additionsChanged()

        let after = try #require(session.playlists.first { $0.origin == .generated })
        #expect(Set(after.tracks.map(\.rpmId)) == Set(ids))
        #expect(after.missing == 0)
    }

    // ── the cut ──

    /// A request for the cut that fails is not an answer of "no cut".
    @Test func aCutThatFailsToReadKeepsTheGeneratedLists() async throws {
        let source = HeldSource(tracks: ids.map(track))
        await source.release()
        let cloud = StubCloud()
        let session = try makeSession(source: source, cloud: cloud)

        await session.show(.nextLaunch) {}
        try await listsArrived(session)
        #expect(session.playlists.contains { $0.origin == .generated })

        cloud.cutStatus = 500
        await session.rereadPlaylists()

        #expect(session.playlists.contains { $0.origin == .generated })
    }

    // ── writing ──

    /// **The order shown after a write is the one the store holds.** Another device added a song
    /// first, so the store refused, the writer merged, and the merged order was written.
    @Test func aReorderThatWasMergedShowsTheMergedOrder() async throws {
        let source = HeldSource(tracks: ids.map(track))
        await source.release()
        let cloud = StubCloud()
        cloud.playlists = #"[{"playlistId":"p","name":"Evening","trackIds":["t0","t1"],"updatedAt":100}]"#
        cloud.conflict = #"{"playlistId":"p","name":"Evening","trackIds":["t0","t1","t2"],"updatedAt":200}"#
        let session = try makeSession(source: source, cloud: cloud)

        await session.show(.nextLaunch) {}
        try await listsArrived(session)

        let evening = try #require(session.playlists.first { $0.id == "p" })
        let said = await session.reorderPlaylist(evening, from: 0, to: 1)
        #expect(said == nil)

        let after = try #require(session.playlists.first { $0.id == "p" })
        #expect(after.tracks.map(\.rpmId) == cloud.lastWritten)
        #expect(after.tracks.map(\.rpmId).contains("t2"), "the other device's song is not shown")
        #expect(after.stamp == 300)
    }

    @Test func aRefusedReorderShowsTheStoredOrder() async throws {
        let source = HeldSource(tracks: ids.map(track))
        await source.release()
        let cloud = StubCloud()
        cloud.playlists = #"[{"playlistId":"p","name":"Evening","trackIds":["t0","t1"],"updatedAt":100}]"#
        cloud.putStatus = 403
        let session = try makeSession(source: source, cloud: cloud)

        await session.show(.nextLaunch) {}
        try await listsArrived(session)

        let evening = try #require(session.playlists.first { $0.id == "p" })
        let said = await session.reorderPlaylist(evening, from: 0, to: 1)
        #expect(said != nil)

        let after = try #require(session.playlists.first { $0.id == "p" })
        #expect(after.tracks.map(\.rpmId) == ["t0", "t1"])
        #expect(after.stamp == 100)
    }

    // ── the session and its doubles ──

    /// Waits for the playlist read that ``LibrarySession/show(_:whenUp:)`` starts on its own task.
    ///
    /// A test does not start a read of its own here, so the only read in flight is that one.
    private func listsArrived(_ session: LibrarySession) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while session.playlistStanding == .reading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(session.playlistStanding == .showing)
    }

    private func track(_ id: String) -> CloudTrack {
        CloudTrack(rpmId: id, relativePath: "x/\(id).flac", title: id,
                   artist: "Talk Talk", album: "Spirit of Eden", tags: CloudTrackTags())
    }

    private func makeSession(
        source: HeldSource, cloud: StubCloud,
        additions: @escaping LibrarySession.Additions = LibrarySession.nothingAdded
    ) throws -> LibrarySession {
        let base = URL(string: "https://api.example.com")!
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rpm-session-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let wire = stubbedSession { cloud.answer($0) }
        let transport = Transport(base: base, tokens: FixedTokens(), reach: NetworkReach(),
                                  session: wire)
        let defaults = UserDefaults(suiteName: "rpm.tests.\(UUID().uuidString)")!

        return LibrarySession(
            auth: AuthClient(base: base, keychain: MemoryStore(), reach: NetworkReach(),
                             session: wire),
            cloud: RPMCloudClient(transport: transport),
            community: RPMCommunityClient(transport: transport),
            library: CloudLibrary(source: source, marks: FavoriteMarks(), storeRoot: root),
            plays: PlayLog(inMemory: true),
            radioListens: RadioListens(file: nil),
            playDevice: PlayDevice(store: defaults),
            additions: additions)
    }
}

/// The tracks that only a computer on the home network holds, as the TV adds them.
@MainActor
private final class HomeNetwork {
    var tracks: [CloudTrack] = []
}

/// A listing that is handed over when the test says so.
private actor HeldSource: LibrarySource {
    private var tracks: [CloudTrack]
    private var released = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var watchers: [CheckedContinuation<Void, Never>] = []

    init(tracks: [CloudTrack]) { self.tracks = tracks }

    func list(_ shelf: CloudShelf) async throws -> [CloudTrack] {
        if !released {
            for watcher in watchers { watcher.resume() }
            watchers = []
            await withCheckedContinuation { waiting.append($0) }
        }
        return tracks
    }

    /// Returns once a read is waiting for the listing.
    func entered() async {
        guard waiting.isEmpty else { return }
        await withCheckedContinuation { watchers.append($0) }
    }

    func release() {
        released = true
        for reader in waiting { reader.resume() }
        waiting = []
    }

    /// The listing that the next read is given.
    func hand(_ tracks: [CloudTrack]) { self.tracks = tracks }
}

// ── the network ──

/// The playlist endpoints, answered from what the test set. Everything else is answered 404.
private final class StubCloud: @unchecked Sendable {
    private let lock = NSLock()
    private var _playlists = "[]"
    private var _cutStatus = 200
    private var _putStatus = 200
    private var _conflict: String?
    private var _lastWritten: [String] = []

    /// The stored playlists, as the JSON array the store sends.
    var playlists: String {
        get { lock.withLock { _playlists } }
        set { lock.withLock { _playlists = newValue } }
    }

    /// The status of the cut's answer. 200 sends a cut with one list naming t0, t1 and t2.
    var cutStatus: Int {
        get { lock.withLock { _cutStatus } }
        set { lock.withLock { _cutStatus = newValue } }
    }

    /// The status of a playlist write.
    var putStatus: Int {
        get { lock.withLock { _putStatus } }
        set { lock.withLock { _putStatus = newValue } }
    }

    /// The stored copy that the next write is refused with, once.
    var conflict: String? {
        get { lock.withLock { _conflict } }
        set { lock.withLock { _conflict = newValue } }
    }

    /// The running order of the last write the store accepted.
    var lastWritten: [String] { lock.withLock { _lastWritten } }

    private static let cut = #"{"recipe":4,"computedAt":1,"lists":[{"kind":"RightNow","decade":0,"#
        + #""folder":[],"trackIds":["t0","t1","t2"],"shows":50}]}"#

    func answer(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""

        if request.httpMethod == "GET", path.hasSuffix("/cloud/playlists") {
            return reply(request, 200, #"{"playlists":\#(playlists)}"#)
        }
        if request.httpMethod == "GET", path.hasSuffix("/cloud/moodlists") {
            let status = cutStatus
            return reply(request, status, status == 200 ? Self.cut : "{}")
        }
        if request.httpMethod == "PUT", path.contains("/cloud/playlist/") {
            return write(request)
        }
        return reply(request, 404, "{}")
    }

    private func write(_ request: URLRequest) -> (HTTPURLResponse, Data) {
        let refusal = lock.withLock { () -> String? in
            defer { _conflict = nil }
            return _conflict
        }
        if let refusal { return reply(request, 409, refusal) }

        let status = putStatus
        guard status == 200 else { return reply(request, status, "{}") }

        struct Body: Decodable { let trackIds: [String] }
        let body = try? JSONDecoder().decode(Body.self, from: request.bodyData)
        lock.withLock { _lastWritten = body?.trackIds ?? [] }

        return reply(request, 200, #"{"updatedAt":300}"#)
    }
}

/// Answers every request of a session with the handler that the session was made with.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers:
        [String: @Sendable (URLRequest) -> (HTTPURLResponse, Data)] = [:]

    static let idHeader = "X-Stub-Id"

    static func register(_ id: String,
                         _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)) {
        lock.withLock { handlers[id] = handler }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.idHeader) ?? ""
        guard let handler = Self.lock.withLock({ Self.handlers[id] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedSession(
    _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> URLSession {
    let id = UUID().uuidString
    StubProtocol.register(id, handler)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    config.httpAdditionalHeaders = [StubProtocol.idHeader: id]
    return URLSession(configuration: config)
}

private func reply(_ request: URLRequest, _ status: Int, _ json: String) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
     Data(json.utf8))
}

private extension URLRequest {
    /// The body as the URL loading system hands it over. Inside a `URLProtocol` the body is a
    /// stream, and `httpBody` is nil.
    var bodyData: Data {
        if let body = httpBody { return body }
        guard let stream = httpBodyStream else { return Data() }

        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private struct FixedTokens: TokenSource {
    func accessToken() async throws -> String? { "token" }
}

private actor MemoryStore: SecretStore {
    private var items: [String: Data] = [:]
    func read(_ key: String) async -> Data? { items[key] }
    func write(_ key: String, _ value: Data) async { items[key] = value }
    func delete(_ key: String) async { items[key] = nil }
}
