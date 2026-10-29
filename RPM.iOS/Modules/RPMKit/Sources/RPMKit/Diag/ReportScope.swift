import Foundation
import StoreKit

/// Whether a feedback or crash report carries the person who sent it.
///
/// A full report carries the app's recent log, the screenshot and the reply address, and the
/// server keeps the account. An anonymous report carries the message or the stack, the version, the
/// OS, the device model and the install id, and nothing else. The server applies the same rule to
/// the `scope` field: a report that arrives without "full" is stored anonymously whatever it carries.
///
/// The phone and TV apps decide it from the build: a TestFlight build is full, an App Store build is
/// anonymous. Decide it once at launch with `decide()` and build every report through it
/// (`RPMReportsClient` takes it on every send).
public enum ReportScope: Sendable, Equatable {
    case full
    case anonymous

    /// The value of the request's `scope` field.
    public var wire: String? { self == .full ? "full" : nil }

    public var isFull: Bool { self == .full }

    /// Full for a TestFlight build and for a build run from Xcode, anonymous for the App Store.
    /// When the system cannot say (no `AppTransaction`, for example offline on the first launch),
    /// the answer is anonymous, and the next launch asks again.
    public static func decide() async -> ReportScope {
        #if DEBUG
        return .full
        #else
        do {
            switch try await AppTransaction.shared {
            case .verified(let transaction), .unverified(let transaction, _):
                return of(transaction.environment)
            }
        } catch {
            return .anonymous
        }
        #endif
    }

    /// TestFlight is the sandbox environment; Xcode is the developer's own build.
    static func of(_ environment: AppStore.Environment) -> ReportScope {
        environment == .production ? .anonymous : .full
    }
}
