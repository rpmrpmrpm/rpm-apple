import SwiftUI
import UIKit
import RPMUI
import RPMLibrary
import RPMSharedUI

/// The entry point of the native Swift app.
///
/// It installs as `com.rpm.player`, the main phone app. The Uno app uses
/// `com.rpm.player.uno`, so both can be installed on one phone and the id shows which is which.
@main
struct RPMApp: App {
    /// **SwiftUI has no API for this.** The supported screen orientations come only from the
    /// application delegate, and there is no scene modifier for them. The delegate exists
    /// for that and for background download wake-ups.
    @UIApplicationDelegateAdaptor(RPMDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView(model: delegate.model)
        }
    }
}

/// Answers two UIKit questions: which orientations the app supports (the policy is
/// ``StageOrientation``), and what to do when the system wakes the app for finished downloads.
///
/// **The model is created here, not by the screen.** The system can launch the app in the
/// background for the download session without creating any scene. The session hands over
/// its finished files only to a session created again under the same name. Created here, the
/// model and its session exist on every launch, whether or not a window appears.
@MainActor
final class RPMDelegate: NSObject, UIApplicationDelegate {
    let model = AppModel()

    /// The crash handlers are installed first, so a crash anywhere after this point is recorded.
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil)
        -> Bool {
        CrashWatch.install(arrived: { [model] in Task { await model.diagnostics.crashArrived() } })
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        StageOrientation.supported
    }

    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier == AlbumDownloads.sessionName else { completionHandler(); return }

        AlbumDownloads.wokenFor = completionHandler
        Task { await model.wokenForDownloads() }
    }
}
