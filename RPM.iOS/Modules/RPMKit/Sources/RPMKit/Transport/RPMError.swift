import Foundation

/// Everything this package throws.
///
/// One type rather than six, because a screen that has to tell six error shapes
/// apart can easily handle one of them wrongly. `userMessage` is the sentence
/// to show; nothing above this has to decide what an error means.
public enum RPMError: Error, Sendable {
    /// The token is gone or refused. The only error a caller acts on rather than
    /// displays: it means sign in again.
    case unauthorized

    case quotaExceeded

    /// The gate refused: there is no network, and no socket was opened. Kept apart from
    /// ``transport`` because the two need different sentences and different answers: this one is
    /// a fact about the phone, and the other is a request that was sent and failed.
    case offline

    /// The server said no, with a 4xx.
    ///
    /// **What the server wrote is not kept.** Its sentences are English in every locale,
    /// so showing them would show English on a French phone. The screen says
    /// what it was doing instead (see ``userMessage(refused:)``), unless `reason` names
    /// a refusal that this app has its own sentence for.
    case refused(status: Int, reason: Refusal?)

    /// A shared collection that the store would not serve as itself. See `CloudShelf`.
    case notServed(ownerId: String)

    /// A status that is not a refusal: a 5xx, or a response that was not HTTP.
    case status(Int)
    case transport(any Error)
    case decoding(any Error)

    /// An address this app could not build. A defect here, not the server's answer.
    case badAddress

    /// Sign-in answered without a session, or could not start.
    case signInIncomplete

    /// A browser sign-in that did not finish within its deadline.
    case signInTimedOut

    /// What a screen shows.
    ///
    /// - Parameter refused: what the screen was doing, written as a failure ("Your review
    ///   could not be saved."), for a refusal whose reason this app has no sentence of its
    ///   own for. It has no default value: a generic sentence is the one a screen
    ///   would forget to replace, and it tells the person nothing about what failed.
    public func userMessage(refused: String) -> String {
        switch self {
        case .unauthorized:
            return Loc.get("Rpm_Error_SessionExpired")
        case .quotaExceeded:
            return Loc.get("Rpm_Error_StorageFull")
        case .offline:
            return Loc.get("Rpm_Net_Offline")
        case .refused(_, let reason?):
            return reason.said
        case .refused(_, nil):
            return refused
        case .notServed:
            return Loc.get("Rpm_Error_ShareUnavailable")
        case .status(let code):
            return Loc.get("Rpm_Error_Status", code)
        case .transport:
            return Loc.get("Rpm_Net_Failed")
        case .decoding:
            return Loc.get("Rpm_Error_Unreadable")
        case .badAddress:
            return Loc.get("Fault_Unknown")
        case .signInIncomplete:
            return Loc.get("Login_Unable")
        case .signInTimedOut:
            return Loc.get("Login_BrowserTimedOut")
        }
    }
}

/// A reason for a refusal that this app has its own sentence for. It is read from the
/// status of the one call it belongs to, in the same way as the desktop app
/// (`SignInOutcome.FromLoginStatus`), because the accounts service sends no code for it.
public enum Refusal: Sendable, Equatable {
    /// `auth/login` answered 401.
    case wrongPassword

    /// `auth/login` answered 400: the address was never confirmed.
    case notConfirmed

    var said: String {
        switch self {
        case .wrongPassword: return Loc.get("Login_WrongPassword")
        case .notConfirmed: return Loc.get("Login_NotConfirmed")
        }
    }
}
