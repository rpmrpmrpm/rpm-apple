import Foundation
import Testing
@testable import RPMKit

/// Stands in for the network, so no test in this package touches it.
///
/// The handler is looked up per SESSION rather than held in one static, because
/// Swift Testing runs tests in parallel by default and a single shared handler
/// is a race: one test can read a 200 that another test has just installed.
/// Each stubbed session carries an id in a header, and that is the key.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers:
        [String: @Sendable (URLRequest) -> (HTTPURLResponse, Data)] = [:]

    static let idHeader = "X-Stub-Id"

    /// Sessions that answer every request with a transport failure. Kept apart
    /// from the handlers because "the network is down" is not a response, and a
    /// test about it wants the URL loading system's own error rather than a
    /// status code standing in for one.
    nonisolated(unsafe) private static var failures: [String: URLError.Code] = [:]

    static func registerFailure(_ id: String, _ code: URLError.Code) {
        lock.withLock { failures[id] = code }
    }

    /// Sessions that fail a given number of times and then behave. For the retry tests:
    /// a network that drops the first request and carries the second is the whole
    /// behaviour being asserted, and a session that only ever fails cannot express it.
    nonisolated(unsafe) private static var stumbles: [String: (code: URLError.Code, left: Int)] = [:]

    static func registerStumbles(_ id: String, _ code: URLError.Code, times: Int) {
        lock.withLock { stumbles[id] = (code, times) }
    }

    private static func failure(for request: URLRequest) -> URLError.Code? {
        guard let id = request.value(forHTTPHeaderField: idHeader) else { return nil }

        return lock.withLock {
            if let standing = stumbles[id], standing.left > 0 {
                stumbles[id] = (standing.code, standing.left - 1)
                return standing.code
            }
            return failures[id]
        }
    }

    static func register(_ id: String,
                         _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)) {
        lock.withLock { handlers[id] = handler }
    }

    private static func handler(for request: URLRequest)
        -> (@Sendable (URLRequest) -> (HTTPURLResponse, Data))? {
        guard let id = request.value(forHTTPHeaderField: idHeader) else { return nil }
        return lock.withLock { handlers[id] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for r: URLRequest) -> URLRequest { r }

    override func startLoading() {
        if let code = Self.failure(for: request) {
            client?.urlProtocol(self, didFailWithError: URLError(code))
            return
        }
        guard let handler = Self.handler(for: request) else {
            // A session with no handler is a test that forgot one. Failing as a
            // network error rather than hanging is what makes that legible.
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

/// A session that answers with whatever the handler says, and nothing else.
func stubbedSession(
    _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> URLSession {
    let id = UUID().uuidString
    StubProtocol.register(id, handler)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    config.httpAdditionalHeaders = [StubProtocol.idHeader: id]
    return URLSession(configuration: config)
}

/// A session that answers every request the same way.
func replying(_ status: Int, _ json: String) -> URLSession {
    stubbedSession { request in
        (HTTPURLResponse(url: request.url!, statusCode: status,
                         httpVersion: nil, headerFields: nil)!,
         Data(json.utf8))
    }
}

/// A place for a handler to write down what it saw. A plain local `var` cannot
/// be mutated from a `@Sendable` closure under Swift 6, and the closure is what
/// the URL loading system calls.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

func ok(_ request: URLRequest, _ json: String) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: request.url!, statusCode: 200,
                     httpVersion: nil, headerFields: nil)!,
     Data(json.utf8))
}

/// A session that fails the first `times` requests and answers the rest.
func stumblingSession(_ code: URLError.Code, times: Int,
                      _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data))
    -> URLSession {
    let id = UUID().uuidString
    StubProtocol.register(id, handler)
    StubProtocol.registerStumbles(id, code, times: times)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    config.httpAdditionalHeaders = [StubProtocol.idHeader: id]
    return URLSession(configuration: config)
}

/// Counts what a stub was asked, when how many times is the assertion.
final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var seen = 0

    func mark() { lock.withLock { seen += 1 } }
    var count: Int { lock.withLock { seen } }
}

/// A session on which every request fails the way an aeroplane fails it.
func failingSession(_ code: URLError.Code = .notConnectedToInternet) -> URLSession {
    let id = UUID().uuidString
    StubProtocol.registerFailure(id, code)

    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    config.httpAdditionalHeaders = [StubProtocol.idHeader: id]
    return URLSession(configuration: config)
}

/// An in-memory stand-in for the Keychain, so no test writes to the real one.
actor MemoryStore: SecretStore {
    private var items: [String: Data] = [:]
    func read(_ key: String) async -> Data? { items[key] }
    func write(_ key: String, _ value: Data) async { items[key] = value }
    func delete(_ key: String) async { items[key] = nil }
}

struct FixedTokens: TokenSource {
    let token: String?
    func accessToken() async throws -> String? { token }
}

extension URLRequest {
    /// The body as the URL loading system actually hands it over.
    ///
    /// `httpBody` is nil inside a `URLProtocol` even when the caller set one:
    /// URLSession converts it to `httpBodyStream` on the way in. A test that
    /// reads only `httpBody` sees an empty body and passes for the wrong reason.
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

// ── the line ──

/// A network this test decides the shape of.
///
/// Every reading it is told to say goes to every stream it has handed out, so a test can
/// take the phone off the network in one line and put it back in the next.
final class FakePath: PathWatcher, @unchecked Sendable {
    private let lock = NSLock()
    private var listeners: [AsyncStream<Reach>.Continuation] = []

    /// The last thing it was told to say, replayed to anybody who subscribes afterwards.
    ///
    /// **Without this the tests race the watcher.** `begin()` subscribes on a task of its
    /// own, so a `say` on the next line can land before the subscription exists and be
    /// dropped. Replaying the standing reading makes the order of those two irrelevant,
    /// which is what the real `NWPathMonitor` does anyway: it hands a new subscriber the
    /// path as it is.
    private var standing: Reach?

    func readings() -> AsyncStream<Reach> {
        AsyncStream { continuation in
            lock.withLock {
                listeners.append(continuation)
                if let standing { continuation.yield(standing) }
            }
        }
    }

    func say(_ reading: Reach) {
        let waiting = lock.withLock { () -> [AsyncStream<Reach>.Continuation] in
            standing = reading
            return listeners
        }
        for listener in waiting { listener.yield(reading) }
    }
}

/// A reach that is watching nothing and therefore still believes the optimistic half of
/// `Reach.unknown`: there is a line until something says otherwise. What every test that
/// is not about the gate wants.
func openLine() -> NetworkReach { NetworkReach() }

/// A reach that has settled on there being no network, for the tests that are about the
/// gate. Polls rather than sleeping a fixed time: the settling is a real wait and a test
/// that guesses how long it takes is a test that fails on a busy machine.
func closedLine() async -> NetworkReach {
    let path = FakePath()
    let reach = NetworkReach(watching: path, settling: .milliseconds(1))
    reach.begin()
    path.say(.away)

    for _ in 0..<400 {
        if !reach.now.isOnline { return reach }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return reach
}
