import SwiftUI
import RPMKit

/// The network state, passed down the view tree through the environment.
///
/// **Only views that fetch something read it**, and they use it to decide whether to try, not to
/// draw anything: an avatar and a station logo look the same when empty, whether the request
/// failed or was never made. The only bar that tells the user about the network is
/// ``OfflineBar``.
private struct RPMReachKey: EnvironmentKey {
    /// The optimistic default, `Reach.unknown`. A view in a preview, or one drawn before the app
    /// sets this value, must still load its pictures.
    static let defaultValue = Reach.unknown
}

extension EnvironmentValues {
    public var rpmReach: Reach {
        get { self[RPMReachKey.self] }
        set { self[RPMReachKey.self] = newValue }
    }
}
