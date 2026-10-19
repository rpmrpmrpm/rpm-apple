import Foundation

/// Where an access token comes from.
///
/// A protocol rather than a closure so the clients can be built before
/// `AuthClient` exists, and so a test can pass in a fixed one.
public protocol TokenSource: Sendable {
    func accessToken() async throws -> String?
}

/// The one place a request is made.
///
/// An actor because the token source is shared and a refresh must not run twice
/// at the same time. Every client goes through here, so the bearer header, the error
/// mapping and the JSON coders are set in one place and not at forty call
/// sites.
public actor Transport {
    /// Where the API is, so a caller can build the absolute address of something
    /// that is fetched OUTSIDE this actor, such as a picture that an image view
    /// fetches for itself. It can be read without `await` because it never changes.
    public let base: URL
    private let tokens: any TokenSource

    /// The path to the network, through the gate. A `URLSession` is deliberately not held beside
    /// it: with one here, a call written in the ordinary way would reach the network without the
    /// gate, and there must be no way to do that. See ``Gated``.
    private let wire: Gated

    /// - Parameter reach: **no default.** The compiler names every place a client is built, and
    ///   each one says which network state it relies on. A default of "always online" would be a
    ///   gate that somebody forgets to set, not one that somebody decided against.
    public init(base: URL, tokens: any TokenSource, reach: NetworkReach,
                session: URLSession = Wire.session()) {
        self.base = base
        self.tokens = tokens
        self.wire = Gated(reach: reach, session: session)
    }

    public func get<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await send("GET", path, body: nil, as: type)
    }

    /// The header that the RPM API sets on an answer that is only part of the full answer: a source
    /// could not be asked, or had not answered when the API's wait ran out. The API finishes the
    /// answer in the background, and the next read is served the rest.
    public static let partialHeader = "X-RPM-Partial"

    /// A GET whose answer may be only part of the full answer, with the API's mark read from it. The
    /// caller shows a partial answer and does not keep it anywhere: if it were kept, it would be
    /// used as the whole answer for as long as the caller keeps its data.
    public func getMarked<T: Decodable>(_ path: String, as type: T.Type) async throws -> (value: T, partial: Bool) {
        let (data, http) = try await performResponding("GET", path, body: nil)
        do {
            return (try RPMJSON.decoder.decode(T.self, from: data),
                    http.value(forHTTPHeaderField: Self.partialHeader) != nil)
        } catch {
            throw RPMError.decoding(error)
        }
    }

    public func send<T: Decodable>(
        _ method: String, _ path: String, body: (any Encodable)? = nil, as type: T.Type
    ) async throws -> T {
        let data = try await perform(method, path, body: body)

        // A route that answers 200 with an empty body is not a decoding failure,
        // it is a route with nothing to say. `sendVoid` is the usual way to call
        // one; this method is for callers that want a value back anyway.
        if let empty = EmptyResponse() as? T, data.isEmpty { return empty }

        do {
            return try RPMJSON.decoder.decode(T.self, from: data)
        } catch {
            throw RPMError.decoding(error)
        }
    }

    public func sendVoid(_ method: String, _ path: String, body: (any Encodable)? = nil) async throws {
        _ = try await perform(method, path, body: body)
    }

    /// A request whose refusal is for the **caller** to read.
    ///
    /// Everything else goes through `send`, which turns anything that is not a
    /// success into an error and throws the body away. A playlist write is the one
    /// exception in this app: its refusal is an *answer*, carrying the copy that is
    /// actually stored, and a merge needs that copy and not a sentence about it.
    ///
    /// Only the network itself throws here. A status is a value. A station logo's 404 is
    /// the other case: it means "no logo" and is not a failure.
    ///
    /// - Parameter cache: whether a stored answer may be used. **Every caller states it**,
    ///   because the answers here carry the server's own cache headers and one of them
    ///   (`radio/state`) must be read past the store once per launch.
    public func raw(_ method: String, _ path: String, body: (any Encodable)? = nil,
                    cache: URLRequest.CachePolicy) async throws -> (status: Int, data: Data) {
        guard let url = URL(string: path, relativeTo: base) else {
            throw RPMError.badAddress
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = cache
        request.setValue(AppKey.value, forHTTPHeaderField: AppKey.header)

        if let token = try await tokens.accessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do { request.httpBody = try RPMJSON.encoder.encode(body) }
            catch { throw RPMError.decoding(error) }
        }

        let (data, response) = try await wire.fetch(request, method: method)
        return (response.statusCode, data)
    }

    /// Raw bytes, for the routes that answer with an image or a clip and not
    /// with JSON.
    public func data(_ path: String) async throws -> Data {
        try await perform("GET", path, body: nil)
    }

    /// A fetch that carries no credential, for the second request of a two-request read.
    ///
    /// The store signs a URL and the bytes come from S3. A presigned URL is
    /// signed for exactly the request it describes, so an added Authorization
    /// header makes it a different request and S3 refuses it.
    public func unauthenticated<T: Decodable>(_ url: URL, as type: T.Type) async throws -> T {
        let data = try await unauthenticatedData(url)
        do { return try RPMJSON.decoder.decode(T.self, from: data) }
        catch { throw RPMError.decoding(error) }
    }

    /// The same second request, for the routes where the second part is a picture and not
    /// more JSON.
    ///
    /// Nothing is cached at this level. A presigned URL carries its signature in
    /// the query, so it is a different address every time it is signed and a
    /// URL cache could never answer from it. It would only fill up with covers
    /// that will never be asked for again. What keeps a cover off the network
    /// twice is the artwork store's own cache, which is keyed on the album and
    /// its version and not on an address that changes every hour.
    public func unauthenticatedData(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, http) = try await wire.fetch(request, method: "GET")

        guard (200..<300).contains(http.statusCode) else {
            throw RPMError.status(http.statusCode)
        }

        return data
    }

    private func perform(_ method: String, _ path: String, body: (any Encodable)?) async throws -> Data {
        try await performResponding(method, path, body: body).data
    }

    private func performResponding(_ method: String, _ path: String,
                                   body: (any Encodable)?) async throws -> (data: Data, http: HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: base) else {
            throw RPMError.badAddress
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(AppKey.value, forHTTPHeaderField: AppKey.header)

        // Only when there is one. A header reading "Bearer " is a malformed
        // credential and not an absent one, and the two come back as
        // different errors.
        if let token = try await tokens.accessToken(), !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do { request.httpBody = try RPMJSON.encoder.encode(body) }
            catch { throw RPMError.decoding(error) }
        }

        let (data, http) = try await wire.fetch(request, method: method)

        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw RPMError.unauthorized
            case 413, 507: throw RPMError.quotaExceeded
            case 400..<500: throw RPMError.refused(status: http.statusCode, reason: nil)
            default: throw RPMError.status(http.statusCode)
            }
        }

        return (data, http)
    }
}
