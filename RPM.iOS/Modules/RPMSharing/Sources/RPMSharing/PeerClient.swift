import Foundation
import RPMKit

/// The computer answered 401: the token is no longer valid, after a restart, an expiry, or because
/// the computer forgot this device. Or it answered 403: the computer no longer trusts this device.
public struct PeerRefused: Error, Equatable, Sendable {
    public let status: Int
}

/// Any other answer that was not the one the request needed (for example a different status).
public struct PeerFailed: Error, Sendable {
    public let what: String
}

/// HTTP to the computers on the home network. All requests use one session. For TLS, the session
/// asks ``PeerPins``: a pinned address must present the key it advertised. Every other host is
/// checked the normal way.
final class PeerClient: NSObject, URLSessionDelegate, @unchecked Sendable {
    private var session: URLSession!

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let (disposition, credential) = PeerPins.shared.answer(challenge)
        completionHandler(disposition, credential)
    }

    /// Sends a GET, or a POST with a JSON body when `body` is set. Returns the response body for
    /// 200 and nil for 204. Throws ``PeerRefused`` for 401 and 403, and ``PeerFailed`` for other
    /// statuses.
    func call(_ url: String, body: (any Encodable)? = nil, token: String?) async throws -> Data? {
        guard let address = URL(string: url) else { throw PeerFailed(what: "bad address") }
        var request = URLRequest(url: address)
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200: return data
        case 204: return nil
        case 401, 403: throw PeerRefused(status: status)
        default: throw PeerFailed(what: "computer answered \(status)")
        }
    }

    func read<T: Decodable>(_ type: T.Type, _ url: String, body: (any Encodable)? = nil,
                            token: String?) async throws -> T? {
        guard let data = try await call(url, body: body, token: token) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
