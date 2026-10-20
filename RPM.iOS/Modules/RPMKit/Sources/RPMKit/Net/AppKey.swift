import Foundation

/// The key this app sends to the RPM API. It is used for the reads that need no signed-in
/// user: metadata, artwork, and the album, artist and profile pages.
///
/// The source holds no key. A release build gets the official key from the release
/// (`RPM_APP_KEY`, see Signing.xcconfig), which puts it in Info.plist as `RPMAppKey`. A
/// contributor sets their own developer key, made at rpmrpmrpm.com/developer, in Local.xcconfig.
/// The key ships inside the app, so anyone can read it there: it filters casual traffic and says
/// whose build is asking. It is not a secret. The server accepts two official keys at once, so a
/// new key in a later build does not lock out builds that are already installed.
///
/// The matching code on the other heads is `RpmApi` in RPM.Core and `AppKey` in the Android core.
public enum AppKey {
    /// The header the API reads the key from.
    public static let header = "X-RPM-Key"

    /// The key from Info.plist, or empty when the build has none. Setting `RPM_APP_KEY` in the
    /// environment replaces it, for tests and for a debug build that points at a deployed API.
    public static var value: String {
        if let supplied = ProcessInfo.processInfo.environment["RPM_APP_KEY"], !supplied.isEmpty {
            return supplied
        }
        return (Bundle.main.object(forInfoDictionaryKey: "RPMAppKey") as? String) ?? ""
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
