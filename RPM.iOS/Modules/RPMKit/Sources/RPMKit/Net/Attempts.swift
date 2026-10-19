import Foundation

/// Tells a brief service problem apart from a real error, and sets the wait before the next try.
///
/// This is the Swift version of `RPM.Core/Net/TransientRetryHandler.cs`. Every request that rpm makes
/// to its own service goes through one Lambda behind CloudFront. That pair can say "not now" in several
/// ways that have nothing to do with the request. Examples are a cold container that starts too slowly,
/// a 502 from the edge, and a socket dropped when a phone comes out of a pocket. Without retries, each of
/// these reaches the screen as a failure. Most of them succeed on the second attempt.
///
/// **The phone is stricter than the desktop about sending a write again, on purpose.** A `GET` may be sent
/// twice, because sending it twice has the same effect as sending it once. A `POST` may be sent again only
/// when the response shows that the request never ran. A 502, 503, 504, 408 or 429 means the edge did not
/// pass the request on. A 500 means the service received it and failed. Sending a 500 request again can
/// post a review twice.
public enum Attempts {
    /// The total number of attempts, including the first.
    public static let most = 3

    /// The first wait, before the second attempt. The wait doubles after each attempt. A little random
    /// jitter is added, so a phone that has just come back online does not send all its queued requests
    /// at the same moment.
    public static let firstWait = Duration.milliseconds(400)

    /// The longest wait, even when `Retry-After` asks for more. The caller is a screen that a person is
    /// looking at, not a background job.
    public static let longestWait = Duration.seconds(5)

    /// The longest a whole fetch may take, counting every attempt and every wait.
    ///
    /// **Three attempts at a request that always times out take three times as long and gain nothing.**
    /// That is why a bad network made every screen appear to hang. A retry starts only when a full attempt
    /// still fits in this budget, so the limit is enforced and not just stated.
    public static let budget = Duration.seconds(25)

    /// Whether sending this method twice has the same effect as sending it once.
    public static func mayBeSentAgain(_ method: String) -> Bool {
        let named = method.uppercased()
        return named == "GET" || named == "HEAD"
    }

    /// Status codes that mean the request never reached the service.
    private static let neverArrived: Set<Int> = [408, 429, 502, 503, 504]

    /// The service received the request and failed. It is only safe to retry when a repeat cannot cause harm.
    private static let itThrew: Set<Int> = [500]

    /// Whether a response with this status is worth another attempt.
    public static func worthAnotherGo(status: Int, method: String) -> Bool {
        if neverArrived.contains(status) { return true }
        return itThrew.contains(status) && mayBeSentAgain(method)
    }

    /// Whether a failure that produced no status code is worth another attempt.
    ///
    /// Network-down errors such as `.notConnectedToInternet` are not retried. Waiting 400 milliseconds does
    /// not fix them. `NetworkReach` notices when the connection returns. Cancellation is never retried,
    /// because it happens whenever the user leaves a screen.
    public static func worthAnotherGo(_ error: any Error, method: String) -> Bool {
        guard mayBeSentAgain(method) else { return false }
        guard let url = error as? URLError else { return false }

        switch url.code {
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
             .dnsLookupFailed, .badServerResponse, .secureConnectionFailed:
            return true

        // **A timeout is not retried.** It is the one failure that has already used the full per-attempt
        // limit. Another try would cost the same time and most likely give the same result. A timeout means
        // the line is not carrying traffic. ``looksLikeTheLine`` handles that case.
        default:
            return false
        }
    }

    /// Whether a failure means the network line is down, not that the service has a problem.
    ///
    /// `NetworkReach.doubt()` acts on this. A path can say `.satisfied` for hotel Wi-Fi that drops every
    /// packet, or for a router whose internet line is down. These errors show that: nothing resolved,
    /// nothing connected, nothing came back. A service error, a bad status, or a body that cannot be
    /// decoded means the service answered, so the line was working.
    public static func looksLikeTheLine(_ error: any Error) -> Bool {
        guard let url = error as? URLError else { return false }

        switch url.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .timedOut, .dataNotAllowed,
             .internationalRoamingOff:
            return true
        default:
            return false
        }
    }

    /// How long to wait after attempt number `attempt` fails. Attempts are numbered from one.
    ///
    /// The server's `Retry-After` value is used when it is given, because the server knows its load
    /// better than this code does.
    public static func wait(after attempt: Int, retryAfter: TimeInterval?) -> Duration {
        if let retryAfter, retryAfter > 0 {
            return min(.milliseconds(Int(retryAfter * 1000)), longestWait)
        }

        let doubled = 400.0 * pow(2.0, Double(max(1, attempt) - 1))
        let jitter = Double.random(in: 0..<250)
        return min(.milliseconds(Int(doubled + jitter)), longestWait)
    }

    /// Reads `Retry-After` as a number of seconds, which is the form the rpm edge sends. The date form is
    /// not read. Nothing in this app's request path sends a date, and a date parser that silently returns
    /// nil for what it cannot read would hide problems.
    public static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let said = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(said.trimmingCharacters(in: .whitespaces)),
              seconds > 0
        else { return nil }
        return seconds
    }
}
