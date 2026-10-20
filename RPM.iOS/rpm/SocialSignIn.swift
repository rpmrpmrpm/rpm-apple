import AuthenticationServices
import UIKit

/// The browser part of signing in with Apple or Google.
///
/// **Uses `ASWebAuthenticationSession`, not a jump to Safari.** The sheet stays over the app, and it
/// catches the website's redirect to `rpm://auth?sessionId=…&code=…` itself, so the app needs no URL
/// scheme of its own and no other app can receive the code. The app then collects the tokens with the
/// code and its poll secret (`AuthClient.finishSocialSignIn`).
@MainActor
final class SocialSignIn: NSObject, ASWebAuthenticationPresentationContextProviding {
    /// The scheme the website sends the browser back to when the sign-in is done.
    static let callbackScheme = "rpm"

    private var session: ASWebAuthenticationSession?

    /// The window to show the sheet over, saved when the sheet is opened.
    ///
    /// It is stored instead of being looked up in `presentationAnchor`. That method is not
    /// async and cannot switch actors, so a lookup there would have to assume it runs on
    /// the main actor, whatever thread the framework calls from. That assumption is a
    /// dispatch-queue assertion, which crashes the app instead of throwing.
    private var anchor: ASPresentationAnchor?

    /// Shows the browser and returns the URL the website sent it back to. Throws `CancellationError`
    /// when the person closes the sheet or the task is cancelled, and the sheet's own error when it
    /// fails in another way.
    func authenticate(_ url: URL) async throws -> URL {
        dismiss()

        anchor = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<URL, Error>) in
                let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { back, error in
                    if let back {
                        done.resume(returning: back)
                    } else if let error, (error as? ASWebAuthenticationSessionError)?.code != .canceledLogin {
                        done.resume(throwing: error)
                    } else {
                        done.resume(throwing: CancellationError())
                    }
                }
                session.presentationContextProvider = self

                // Not ephemeral: the button is useful because it reuses an account that is already
                // signed in to Google in Safari. An ephemeral session would ask for a password
                // every time.
                session.prefersEphemeralWebBrowserSession = false

                self.session = session
                if !session.start() {
                    self.session = nil
                    done.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            Task { @MainActor in self.dismiss() }
        }
    }

    /// Closes the browser. A sheet that is still open finishes with a cancelled-login error, which
    /// `authenticate` reports as `CancellationError`.
    func dismiss() {
        session?.cancel()
        session = nil
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor ?? ASPresentationAnchor()
    }
}
