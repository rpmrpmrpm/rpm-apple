import Foundation

/// A signed-in account, as this app holds it.
public struct Session: Codable, Sendable, Equatable {
    /// The user's Cognito `sub`. This is the same id that RPM's wall uses to sign a review.
    /// A page uses it to tell the reader's own review from other people's. A cloud library
    /// is keyed by it too.
    public let userId: String

    public let email: String
    public let displayName: String
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(userId: String, email: String, displayName: String,
                accessToken: String, refreshToken: String, expiresAt: Date) {
        self.userId = userId; self.email = email; self.displayName = displayName
        self.accessToken = accessToken; self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

/// The response from `auth/login`, `auth/refresh` and a finished `auth/poll-session`.
/// All three carry the same fields. The poll response has a `status` field as well, so
/// it has its own type, `SocialPoll`.
struct LoginResponse: Decodable {
    let userId: String?
    let email: String?
    let displayName: String?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?
}

/// The URL to open in the browser, the session id, and for a TV the code to show.
struct SocialStart: Decodable {
    let loginUrl: String
    let sessionId: String
    let userCode: String?
}

/// How a social sign-in comes back to the app. The accounts service keeps it with the session, so a changed
/// login URL cannot change it.
public enum SocialReturn: String, Sendable {
    /// The browser sheet on the phone brings back a one-time code (`AuthClient.finishSocialSignIn`).
    case app
    /// The sign-in happens on another device; the TV polls (`AuthClient.pollSocial`) and shows a code
    /// that the phone's sign-in page shows too.
    case device
}

/// A social sign-in that was started: the URL to open, its session id, and for a TV the code to show
/// (two groups of four letters).
public struct SocialStarted: Sendable {
    public let url: URL
    public let sessionId: String
    public let userCode: String?
}

/// A social sign-in attempt that is still in progress.
///
/// `status` is the only field that is always present. An unfinished attempt has no
/// tokens. That is not an error, so do not treat it as one.
struct SocialPoll: Decodable {
    let status: String?
    let userId: String?
    let email: String?
    let displayName: String?
    let accessToken: String?
    let refreshToken: String?
    let expiresIn: Int?

    var isComplete: Bool { status == "complete" }
}
