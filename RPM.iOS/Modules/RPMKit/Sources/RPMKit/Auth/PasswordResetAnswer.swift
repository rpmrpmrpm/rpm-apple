import Foundation

/// How a step of resetting a password ended (`auth/forgot-password`, `auth/reset-password`). The same
/// closed set as ``SignUpAnswer``: no case carries the service's English sentence.
public enum PasswordResetAnswer: Sendable, Equatable {
    case done

    /// The accounts service said no, with its own code: "invalid_email", "too_many", "invalid_code",
    /// "code_expired", "weak_password", or "refused" when the answer had no code.
    case refused(code: String)

    /// The gate refused: there is no network, and nothing was sent.
    case offline

    /// The request was sent and did not complete, or the service failed.
    case failed

    /// Reads a refusal's body. The code is taken, and the sentence beside it is left out.
    static func refusal(_ body: Data) -> PasswordResetAnswer {
        struct Said: Decodable { let code: String? }
        if let said = try? JSONDecoder().decode(Said.self, from: body), let code = said.code, !code.isEmpty {
            return .refused(code: code)
        }
        return .refused(code: "refused")
    }

    /// What the reset card shows after asking for a code (``AuthClient/forgotPassword(email:)``), or nil
    /// when there is nothing to say.
    public var saidOnSend: String? { said(otherwise: "Reset_SendFailed") }

    /// What the reset card shows after sending the code and the new password
    /// (``AuthClient/resetPassword(email:code:password:)``), or nil when there is nothing to say.
    public var saidOnSave: String? { said(otherwise: "Reset_Failed") }

    /// The sentence for this answer. `otherwise` is the key for a failure that has no sentence of its own.
    private func said(otherwise: String) -> String? {
        switch self {
        case .done: return nil
        case .offline: return Loc.get("Rpm_Net_Offline")
        case .failed: return Loc.get(otherwise)
        case .refused(let code):
            switch code {
            case "too_many": return Loc.get("SignUp_TooMany")
            case "invalid_code": return Loc.get("SignUp_InvalidCode")
            case "code_expired": return Loc.get("Reset_CodeExpired")
            case "weak_password": return Loc.get("SignUp_WeakPassword")
            case "invalid_email": return Loc.get("SignUp_InvalidEmail")
            default: return Loc.get(otherwise)
            }
        }
    }
}
