import AuthenticationServices
import UIKit

/// The browser part of signing in with Apple or Google.
///
/// **Uses `ASWebAuthenticationSession`, not a jump to Safari.** If the app opens Safari, the
/// app goes to the background and is suspended, so the poll that waits for the tokens stops
/// until the person comes back. In a sheet over the app, the app keeps running, the poll
/// keeps going, and the sheet closes as soon as the tokens arrive.
///
/// There is no callback scheme because there is no callback: the accounts service writes
/// the tokens to a row and the app watches that row. The session ends in one of two ways:
/// the poll finishes and dismisses it from here, or the person closes it and the poll stops.
@MainActor
final class SocialSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var closed: (() -> Void)?

    /// The window to show the sheet over, saved when the sheet is opened.
    ///
    /// It is stored instead of being looked up in `presentationAnchor`. That method is not
    /// async and cannot switch actors, so a lookup there would have to assume it runs on
    /// the main actor, whatever thread the framework calls from. That assumption is a
    /// dispatch-queue assertion, which crashes the app instead of throwing.
    private var anchor: ASPresentationAnchor?

    /// Shows the browser. `closed` is called if the person dismisses it.
    func open(_ url: URL, closed: @escaping () -> Void) {
        dismiss()

        anchor = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { _, _ in
            Task { @MainActor in self.closed?(); self.closed = nil }
        }
        session.presentationContextProvider = self

        // Not ephemeral: the button is useful because it reuses an account that is already
        // signed in to Google in Safari. An ephemeral session would ask for a password
        // every time.
        session.prefersEphemeralWebBrowserSession = false

        session.start()

        self.session = session
        self.closed = closed
    }

    /// Closes the browser. The callback is cleared first, so closing it after a successful
    /// sign-in does not also report that it was closed.
    func dismiss() {
        closed = nil
        session?.cancel()
        session = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}
