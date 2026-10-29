import UIKit

extension Notification.Name {
    /// The phone was shaken. RootView opens Send feedback.
    static let rpmShake = Notification.Name("rpm.shake")
}

extension UIWindow {
    /// A shake reaches the window when nothing above it handles it. Every screen in the app is in
    /// this window, so a shake anywhere arrives here.
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            NotificationCenter.default.post(name: .rpmShake, object: nil)
        }
        super.motionEnded(motion, with: event)
    }
}
