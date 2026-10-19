import Foundation

/// The id this install reports when it reports what it has played.
///
/// Created on the first read and stored in `UserDefaults`. This is not the device identity used
/// on the home network, which carries a key and a trust relationship. A play count needs neither.
public struct PlayDevice: @unchecked Sendable {
    private let store: UserDefaults
    private static let key = "plays.device"

    public init(store: UserDefaults) {
        self.store = store
    }

    public var id: String {
        if let held = store.string(forKey: Self.key), !held.isEmpty { return held }

        let made = UUID().uuidString
        store.set(made, forKey: Self.key)
        return made
    }

    /// Removes the stored id, for signing out. The next account gets a new id, so play counts
    /// cannot be linked between two accounts that used the same device.
    public func forget() {
        store.removeObject(forKey: Self.key)
    }
}
