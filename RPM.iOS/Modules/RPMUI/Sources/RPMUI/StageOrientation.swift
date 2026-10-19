import UIKit

/// Which ways up this app will go, and who decides.
///
/// This is the counterpart of `RPM.Mobile/Presentation/StageOrientation.cs`.
///
/// **Landscape is the stage, and the stage is a record on a deck.** The library, the album pages,
/// the playlists and the player are all drawn for a phone held upright. The one screen that
/// wants the phone turned only exists while something is loaded. So turning the phone in the
/// library with nothing playing leaves the library alone (a sideways wall of covers is not a
/// designed screen), and stopping the music turns a sideways phone back.
///
/// **Two halves, and both are needed.** The policy is what the app delegate returns from
/// `supportedInterfaceOrientationsFor`, and iOS caches that answer: it asks once and then
/// rotates by it. So a change of policy does nothing until the root controller is told that its
/// answer has changed. That is the documented way, and both calls below use it in the same
/// order.
@MainActor
public enum StageOrientation {
    /// Whether there is anything to turn TO.
    private static var landscapeAllowed = false

    /// What the app supports right now. The delegate reads it every time iOS asks, which is at
    /// every rotation and every time iOS is told to ask again.
    ///
    /// Upside-down is left out. Nobody holds a phone that way while it plays something, and iOS
    /// does not offer it on phones with a notch anyway.
    public static var supported: UIInterfaceOrientationMask {
        landscapeAllowed ? [.portrait, .landscapeLeft, .landscapeRight] : .portrait
    }

    /// Says whether there is a record on the deck.
    ///
    /// Portrait is *asked for* on the way down and not only allowed, because iOS does not turn a
    /// phone back on its own just because the app stopped supporting the way it is held. Without
    /// the request, stopping the music would leave a sideways phone on a screen drawn for upright.
    public static func allow(landscape: Bool) {
        let changed = landscapeAllowed != landscape
        landscapeAllowed = landscape

        // **Not guarded on the value having changed.** The first call of the app's life says
        // "nothing is playing", which is already what this holds. A guard there would make the
        // most important case do nothing: an app opened on a phone that is already lying
        // sideways. Asking for portrait when the app is already portrait costs a no-op; not
        // asking leaves the library on its side.
        guard changed || !landscape else { return }

        if landscape { askAgain() } else { requestPortrait() }
    }

    /// Back to portrait.
    ///
    /// Tilting the phone does this too; this is the way out for somebody who wants the library
    /// back without turning the phone upright.
    ///
    /// **The order matters and is the documented one.** A scene only reconsiders which way up it
    /// should be after the view controller has been asked to update what it supports, so the
    /// request is made second. In the other order it is dropped, and the key does nothing.
    public static func requestPortrait() {
        askAgain()

        scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
    }

    /// Makes iOS ask again. Without it, the app keeps whatever it was allowed to be when the
    /// screen last turned.
    private static func askAgain() {
        scene?.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }

    private static var scene: UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
    }
}
