import Foundation

/// The key this app sends to the RPM API. It is used for the reads that need no signed-in
/// user: metadata, artwork, and the album, artist and profile pages.
///
/// The key is stored inside the app, so anyone can read it there. It filters out casual
/// traffic. It is not a secret. The API's cost is limited by its reserved concurrency and by
/// the edge cache in front of it, not by this value. The server accepts two keys at once, so
/// changing the key in a later build does not lock out builds that are already installed.
///
/// The matching constant on the other heads is `RpmApi` in RPM.Core.
public enum AppKey {
    /// The header the API reads the key from.
    public static let header = "X-RPM-Key"

    /// The value stored in Secrets Manager under RPM/AppKey as Current. Setting `RPM_APP_KEY`
    /// in the environment replaces it. Use this for a debug build that points at a deployed API.
    public static var value: String {
        if let supplied = ProcessInfo.processInfo.environment["RPM_APP_KEY"], !supplied.isEmpty {
            return supplied
        }
        return "rpm_live_FEvcaWAmKYVQIOi8EbDUD98kgpkpbT9r"
    }

    /// The host name of the deployed API.
    static let apiHost = "api.rpmrpmrpm.com"

    /// Whether a URL points at the RPM API. A fetch made outside the API's own transport, such
    /// as a picture loaded from a URL (for example a shelf owner's photo), adds the key only when
    /// this is true. The key is therefore never sent to any other host. The API answers 401 to
    /// such a fetch when the key is missing. The matching check on the other heads is
    /// `RpmApi.Owns` in RPM.Core.
    public static func owns(_ url: URL) -> Bool {
        url.host?.lowercased() == apiHost
    }
}
