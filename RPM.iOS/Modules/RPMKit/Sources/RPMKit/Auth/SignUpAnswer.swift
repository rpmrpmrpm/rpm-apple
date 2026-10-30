import Foundation

/// How a step of signing up ended (`auth/register`, `auth/confirm`, `auth/resend-code`). The same
/// closed set as the desktop's `SignUpAnswer`: no case carries the service's English sentence.
public enum SignUpAnswer: Sendable, Equatable {
    case done

    /// The accounts service said no, with its own code: "already_registered", "social_account",
    /// "weak_password", "invalid_email", "invalid_name", "invalid_code", "code_expired",
    /// "code_resent", "too_many", or "refused" when the answer had no code.
    case refused(code: String)

    /// The gate refused: there is no network, and nothing was sent.
    case offline

    /// The request was sent and did not complete, or the service failed.
    case failed

    /// Reads a refusal's body. The code is taken, and the sentence beside it is left out.
    static func refusal(_ body: Data) -> SignUpAnswer {
        struct Said: Decodable { let code: String? }
        if let said = try? JSONDecoder().decode(Said.self, from: body), let code = said.code, !code.isEmpty {
            return .refused(code: code)
        }
        return .refused(code: "refused")
    }

    /// What the sign-up screen shows, or nil when there is nothing to say.
    public var said: String? {
        switch self {
        case .done: return nil
        case .offline: return Loc.get("Rpm_Net_Offline")
        case .failed: return Loc.get("SignUp_Failed")
        case .refused(let code):
            switch code {
            case "already_registered": return Loc.get("SignUp_AlreadyRegistered")
            case "social_account": return Loc.get("SignUp_SocialAccount")
            case "weak_password": return Loc.get("SignUp_WeakPassword")
            case "invalid_email": return Loc.get("SignUp_InvalidEmail")
            case "invalid_name": return Loc.get("SignUp_InvalidName")
            case "invalid_code": return Loc.get("SignUp_InvalidCode")
            case "code_expired", "code_resent": return Loc.get("SignUp_CodeResent")
            case "too_many": return Loc.get("SignUp_TooMany")
            default: return Loc.get("SignUp_Failed")
            }
        }
    }
}
