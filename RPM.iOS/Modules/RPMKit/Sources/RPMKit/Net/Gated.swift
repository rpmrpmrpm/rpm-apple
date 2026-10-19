import Foundation

/// The network socket, with the reachability gate in front and the retries behind it. **This is
/// the only way out of the app.** `Transport` and `AuthClient` each hold one of these. Neither
/// holds a `URLSession` it could use directly.
///
/// The desktop applies the same two rules as a pair of `HttpClient` handlers. See
/// `RPM.Core/Net/Wire.cs`. `URLSession` has no handler chain, so on this side both rules are in
/// this one type.
public struct Gated: Sendable {
    private let session: URLSession
    private let reach: NetworkReach

    public init(reach: NetworkReach, session: URLSession = Wire.session()) {
        self.reach = reach
        self.session = session
    }

    /// **The gate runs first, before any retry.** When the gate refuses, the app has decided not to
    /// open a socket at all. That is not a temporary failure, so it is not retried. No name lookup,
    /// no connection and no exception happen. The failure costs nothing, and the screen gets its
    /// answer at once.
    ///
    /// - Parameter method: The HTTP method. It decides whether a retry is safe. Pass it in rather
    ///   than reading it from the request. A request built without a method is a `GET` to
    ///   `URLSession`, and would be treated as safe to replay without anyone choosing that.
    public func fetch(_ request: URLRequest,
                      method: String) async throws -> (Data, HTTPURLResponse) {
        guard reach.now.isOnline else { throw RPMError.offline }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: Attempts.budget)

        /// Whether there is time for another full attempt. **Only a full attempt counts.** A retry
        /// started with four seconds of budget left would run past the limit it was checked
        /// against, and that limit is what this code exists to enforce.
        func roomForAnother() -> Bool {
            clock.now.advanced(by: .seconds(Wire.requestTimeout)) < deadline
        }

        for attempt in 1...Attempts.most {
            let last = attempt == Attempts.most

            let data: Data, response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                guard !last, roomForAnother(), Attempts.worthAnotherGo(error, method: method)
                else {
                    // **Report the failure once, so that other requests do not each wait for the
                    // same timeout.** The path can say `.satisfied` on a network that carries no
                    // traffic. Until something reports it, every screen finds this out on its own,
                    // each after a full timeout.
                    if Attempts.looksLikeTheLine(error) { reach.doubt() }
                    throw RPMError.transport(error)
                }
                try await Task.sleep(for: Attempts.wait(after: attempt, retryAfter: nil))
                continue
            }

            guard let http = response as? HTTPURLResponse else { throw RPMError.status(0) }

            guard !last, roomForAnother(),
                  Attempts.worthAnotherGo(status: http.statusCode, method: method)
            else { return (data, http) }

            try await Task.sleep(for: Attempts.wait(after: attempt,
                                                    retryAfter: Attempts.retryAfter(http)))
        }

        // Not reachable. The last pass through the loop always returns or throws, but Swift cannot
        // see that. A fatal error here would crash the app where a plain failure would do.
        throw RPMError.status(0)
    }
}
