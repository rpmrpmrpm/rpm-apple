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

/// The URL to open in the browser, and the session id to poll while the user signs in.
struct SocialStart: Decodable {
    let loginUrl: String
    let sessionId: String
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
