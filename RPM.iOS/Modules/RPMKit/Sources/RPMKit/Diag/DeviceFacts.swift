import Foundation

/// What a report says about the app and the device: which head, which build, which OS on which
/// model. The server has no separate field for the model, so it travels in `platform`.
public struct DeviceFacts: Sendable, Equatable {
    /// "ios" or "tvos", the server's names for the two Apple heads.
    public let head: String
    /// "short version (build)", the same text the About screen shows.
    public let appVersion: String
    /// For example "iOS 18.1; iPhone15,2".
    public let platform: String
    /// "arm64" on every device the apps run on.
    public let architecture: String

    public init(head: String, appVersion: String, platform: String, architecture: String) {
        self.head = head
        self.appVersion = appVersion
        self.platform = platform
        self.architecture = architecture
    }

    /// This process.
    public static let current: DeviceFacts = {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let version = os.patchVersion > 0
            ? "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
            : "\(os.majorVersion).\(os.minorVersion)"
        #if os(tvOS)
        let (head, osName) = ("tvos", "tvOS")
        #elseif os(iOS)
        let (head, osName) = ("ios", "iOS")
        #else
        let (head, osName) = ("ios", "macOS")
        #endif
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x64"
        #endif
        return DeviceFacts(
            head: head, appVersion: "\(short) (\(build))",
            platform: "\(osName) \(version); \(machine())", architecture: architecture)
    }()

    /// The model identifier, for example "iPhone15,2" or "AppleTV14,1".
    private static func machine() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}

/// A random id for this installation, used only to tell machines apart in the report queue. Unlike
/// `PlayDevice` it is kept across sign-outs, because crashes from a signed-out phone must still
/// count as one machine.
public enum InstallId {
    static let key = "diag.install"

    public static var value: String { value(in: .standard) }

    static func value(in defaults: UserDefaults) -> String {
        if let known = defaults.string(forKey: key), !known.isEmpty { return known }
        let made = UUID().uuidString.lowercased()
        defaults.set(made, forKey: key)
        return made
    }
}
