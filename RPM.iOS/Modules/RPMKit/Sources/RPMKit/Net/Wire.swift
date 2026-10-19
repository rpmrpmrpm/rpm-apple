import Foundation

/// How a session that leaves this phone is built. All of them are built here, so the network policy
/// is in one place and not spread across `URLSession.shared` calls with different settings.
///
/// Every option is set explicitly. Some values happen to match the defaults, but they are stated
/// anyway. A reader can then see this app's network policy without working out which defaults were
/// meant and which were forgotten.
public enum Wire {
    /// The limit for one request. `URLSession` counts this as idle time, not total time, so a large
    /// catalogue that keeps arriving is never cut off. If the data stops arriving, the request is
    /// abandoned after this many seconds. Twelve seconds is long enough for a Lambda that has to start
    /// cold, and short enough that someone waiting for the screen is not left waiting too long.
    public static let requestTimeout: TimeInterval = 12

    /// The limit for a whole exchange, including redirects.
    public static let resourceTimeout: TimeInterval = 30

    /// The app's own session.
    ///
    /// **`waitsForConnectivity` is off. This is a decision, not an oversight.** When it is on,
    /// `URLSession` holds a request until a network path exists, for up to `timeoutIntervalForResource`.
    /// That suits work that can wait. Every request here is for a screen that someone is looking at.
    /// Holding one for the full resource timeout would show a spinner that never resolves. The honest
    /// answer, "no internet connection", is available at once. The wall is still drawn from the disk
    /// underneath it. `NetworkReach` answers immediately, and `AppModel` asks again as soon as the
    /// connection returns. The outcome is the same, and the screen tells the truth while it waits.
    ///
    /// **`allowsConstrainedNetworkAccess` is on.** Low Data Mode is not a request to stop working.
    /// If this were off, a library would fail to load instead of loading at a lower rate. The lower
    /// audio rate is chosen by `AudioLadder.RateOffer.settles(on:reach:)`.
    public static func session() -> URLSession {
        let settings = URLSessionConfiguration.default

        settings.timeoutIntervalForRequest = requestTimeout
        settings.timeoutIntervalForResource = resourceTimeout
        settings.waitsForConnectivity = false
        settings.allowsExpensiveNetworkAccess = true
        settings.allowsConstrainedNetworkAccess = true

        // The store's answers carry their own cache headers, and presigned reads use a new address each
        // time. Following the protocol's cache rules is correct. A custom policy here would decide how
        // fresh a user's own library is, which the server should decide.
        settings.requestCachePolicy = .useProtocolCachePolicy

        return URLSession(configuration: settings)
    }
}
