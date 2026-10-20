import Foundation
import RPMKit

/// The state of the sign-in screen.
enum SignInState: Equatable, Sendable {
    case starting
    /// One code per provider. Each code is the address where that provider's sign-in starts.
    case codes([SignInCode])
    /// The accounts service could not be reached to start. The request is retried every 10 seconds.
    case unreachable
}

struct SignInCode: Equatable, Sendable, Identifiable {
    let provider: String
    let url: URL
    let sessionId: String
    /// The code the phone's sign-in page shows before it goes on to Apple or Google, two groups of four
    /// letters. The person compares the two.
    let userCode: String?
    var id: String { provider }
}

/// Sign-in on a TV: one QR code per provider. Each code is a `loginUrl` from `auth/social-login`.
/// The person scans one code and signs in on their phone. This side polls `auth/poll-session` for
/// all providers until one of them finishes. The Android TV app uses the same flow (`SignInFlow`).
///
/// The codes are not replaced while the screen waits. The accounts service keeps a TV's pending
/// sign-in for 24 hours. Each QR code has a user code under it, which the phone's sign-in page shows
/// too: a person who was sent someone else's QR code sees that it is not their TV.
struct SignInFlow {
    let auth: AuthClient

    static let providers = ["Google", "Apple"]

    /// Runs until a sign-in finishes (true), or until cancelled (false).
    func run(show: @MainActor (SignInState) -> Void) async -> Bool {
        await show(.starting)

        var codes: [SignInCode] = []
        while codes.isEmpty {
            do {
                for provider in Self.providers {
                    let started = try await auth.startSocialSignIn(provider: provider, returnTo: .device)
                    codes.append(SignInCode(provider: provider, url: started.url,
                                            sessionId: started.sessionId, userCode: started.userCode))
                }
            } catch {
                codes = []
                if Task.isCancelled { return false }
                await show(.unreachable)
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { return false }
            }
        }
        await show(.codes(codes))

        // Poll every 2 seconds for the first 5 minutes, then every 10 seconds. This reduces the
        // load on the accounts service when a screen is left open. A failed poll is retried. It
        // does not end the sign-in.
        let shown = ContinuousClock.now
        return await withTaskGroup(of: Bool.self) { group in
            for code in codes {
                group.addTask {
                    while !Task.isCancelled {
                        let early = ContinuousClock.now - shown < .seconds(300)
                        do {
                            try await auth.pollSocial(sessionId: code.sessionId,
                                                      every: early ? .seconds(2) : .seconds(10),
                                                      giveUpAfter: early ? .seconds(300) : .seconds(3600))
                            return true
                        } catch is CancellationError {
                            return false
                        } catch {
                            try? await Task.sleep(for: .seconds(2))
                        }
                    }
                    return false
                }
            }
            for await finished in group where finished {
                group.cancelAll()
                return true
            }
            return false
        }
    }
}
