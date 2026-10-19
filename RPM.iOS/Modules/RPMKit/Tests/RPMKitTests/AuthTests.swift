import Testing
import Foundation
@testable import RPMKit

private let accounts = URL(string: "https://accounts.example.com/")!

private func auth(_ session: URLSession, _ store: MemoryStore = MemoryStore()) -> AuthClient {
    AuthClient(base: accounts, keychain: store, reach: openLine(), session: session)
}

private func stored(_ store: MemoryStore, _ session: Session) async throws {
    await store.write(AuthClient.sessionKey, try RPMJSON.encoder.encode(session))
}

private func session(
    access: String, refresh: String = "ref", expiresIn: TimeInterval
) -> Session {
    Session(userId: "u1", email: "a@example.com", displayName: "Placeholder",
            accessToken: access, refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(expiresIn))
}

private let loginBody = #"""
{"userId":"u1","email":"a@example.com","displayName":"Placeholder",
 "accessToken":"tok","refreshToken":"ref","expiresIn":3600}
"""#

// ── sign in ──

@Test func signInStoresTheSessionAndAnswersWithTheToken() async throws {
    let client = auth(replying(200, loginBody))
    try await client.signIn(email: " a@example.com ", password: "pw")

    #expect(await client.isSignedIn)
    #expect(await client.current?.userId == "u1")
    #expect(try await client.accessToken() == "tok")
}

@Test func signInSendsATrimmedEmail() async throws {
    let seen = Box<Data>()
    let client = auth(stubbedSession { request in
        seen.value = request.bodyData
        return ok(request, loginBody)
    })

    try await client.signIn(email: "  a@example.com  ", password: "pw")
    let sent = String(data: seen.value ?? Data(), encoding: .utf8) ?? ""
    #expect(sent.contains("\"a@example.com\""))
    #expect(!sent.contains("  a@example.com"))
}

/// The accounts service answers a wrong password with 401, which on any other call
/// means the session is gone. The sentence is chosen from the status of this call, as
/// the desktop does, and not taken from the server's English, so a mistyped password
/// never says "Your session has expired".
@Test func aWrongPasswordSaysSoAndNotThatTheSessionExpired() async {
    let client = auth(replying(401, #"{"error":"Incorrect email or password."}"#))
    do {
        try await client.signIn(email: "a@example.com", password: "wrong")
        Issue.record("expected a throw")
    } catch let error as RPMError {
        guard case .refused(status: 401, reason: .wrongPassword) = error else {
            Issue.record("expected a wrong password, got \(error)")
            return
        }
        #expect(error.userMessage(refused: "unused") == Loc.get("Login_WrongPassword"))
    } catch {
        Issue.record("expected an RPMError, got \(error)")
    }
    #expect(await client.isSignedIn == false)
}

/// 400 from the login is an address that was never confirmed.
@Test func anUnconfirmedAddressIsToldApartFromAWrongPassword() async {
    let client = auth(replying(400, #"{"error":"User is not confirmed."}"#))
    do {
        try await client.signIn(email: "a@example.com", password: "right")
        Issue.record("expected a throw")
    } catch let error as RPMError {
        guard case .refused(status: 400, reason: .notConfirmed) = error else {
            Issue.record("expected an unconfirmed address, got \(error)")
            return
        }
    } catch {
        Issue.record("expected an RPMError, got \(error)")
    }
}

// ── the refresh margin ──

/// The margin is the whole point. A token that expires in one minute is treated
/// as already expired, because a request started now finishes after it dies, and
/// the failure is a 401 in the middle of a working session.
@Test func aTokenInsideTheMarginIsRefreshedBeforeItIsUsed() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "old", expiresIn: 60))

    let client = auth(replying(200, #"""
    {"userId":"u1","email":"a@example.com","displayName":"Placeholder",
     "accessToken":"fresh","refreshToken":"ref2","expiresIn":3600}
    """#), store)
    await client.load()

    #expect(try await client.accessToken() == "fresh")
}

@Test func aTokenOutsideTheMarginIsUsedAsIs() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "good", expiresIn: 3600))

    // Any request at all would be a bug here: nothing should be sent.
    let asked = Box<Bool>()
    let client = auth(stubbedSession { request in
        asked.value = true
        return ok(request, loginBody)
    }, store)
    await client.load()

    #expect(try await client.accessToken() == "good")
    #expect(asked.value == nil, "a valid token was refreshed anyway")
}

/// A session with nothing to refresh with is not a session to throw away. It is
/// handed back as it is and the call fails on its own terms.
@Test func aSessionWithNoRefreshTokenIsNotRefreshed() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "only", refresh: "", expiresIn: -10))

    let asked = Box<Bool>()
    let client = auth(stubbedSession { request in
        asked.value = true
        return ok(request, loginBody)
    }, store)
    await client.load()

    #expect(try await client.accessToken() == "only")
    #expect(asked.value == nil)
}

/// A refused refresh signs the user out rather than retrying. Retrying a token
/// the server has rejected is a loop, and the only thing that ends it is a
/// person signing in again.
@Test func aRefusedRefreshSignsOut() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "old", expiresIn: -10))

    let client = auth(replying(401, "{}"), store)
    await client.load()

    #expect(try await client.accessToken() == nil)
    #expect(await client.isSignedIn == false)
    #expect(await store.read(AuthClient.sessionKey) == nil)
}

/// The one that separates a dead session from a dead network. A refresh that
/// could not be sent at all is not a rejection: signing out here logs a person
/// out of their own app every time they open it underground.
@Test func aNetworkFailureDuringRefreshDoesNotSignOut() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "stale", expiresIn: -10))

    let client = auth(failingSession(), store)
    await client.load()

    #expect(try await client.accessToken() == "stale")
    #expect(await client.isSignedIn)
    #expect(await store.read(AuthClient.sessionKey) != nil)
}

/// Only a status that judges the token signs out. A 5xx, a throttle or a proxy's
/// 404 is the service or the line; signing out on those would log people out for no
/// reason.
@Test(arguments: [(400, true), (401, true), (403, true),
                  (404, false), (429, false), (500, false), (502, false), (503, false), (504, false)])
func onlyARefusalStatusSignsOut(status: Int, refusal: Bool) {
    #expect(AuthClient.isRefusal(status) == refusal)
}

/// The accounts service answers 503 with an error body when Cognito is down. That
/// body must not be read as a refusal of the token.
@Test func aServerErrorDuringRefreshDoesNotSignOut() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "stale", expiresIn: -10))

    let client = auth(replying(503, #"{"error":"Sign-in service unavailable."}"#), store)
    await client.load()

    #expect(try await client.accessToken() == "stale")
    #expect(await client.isSignedIn)
    #expect(await store.read(AuthClient.sessionKey) != nil)
}

/// A captive portal answers 200 with its own HTML. That is not the accounts
/// service saying anything about the token.
@Test func aPageThatIsNotTheServiceDoesNotSignOut() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "stale", expiresIn: -10))

    let client = auth(replying(200, "<html>Log in to the hotel wifi</html>"), store)
    await client.load()

    #expect(try await client.accessToken() == "stale")
    #expect(await client.isSignedIn)
}

// ── social ──

/// Two halves, because the middle is a browser and this package has no UI in it.
@Test func socialSignInHandsBackTheUrlAndTheSessionToPoll() async throws {
    let client = auth(replying(200,
        #"{"loginUrl":"https://accounts.example.com/go?x=1","sessionId":"sess-1"}"#))

    let start = try await client.startSocialSignIn(provider: "Apple")
    #expect(start.url.absoluteString == "https://accounts.example.com/go?x=1")
    #expect(start.sessionId == "sess-1")
}

/// The website writes the tokens back to a session row, so the app polls for
/// them. A row that is not finished yet answers with a status and no tokens,
/// which is not a failure and must not be read as one.
@Test func pollingKeepsAskingUntilTheRowIsComplete() async throws {
    let calls = Box<Int>()
    let store = MemoryStore()
    let client = auth(stubbedSession { request in
        let n = (calls.value ?? 0) + 1
        calls.value = n
        return ok(request, n < 3
            ? #"{"status":"pending"}"#
            : #"""
              {"status":"complete","userId":"u1","email":"a@example.com",
               "displayName":"Placeholder","accessToken":"social-tok",
               "refreshToken":"social-ref","expiresIn":3600}
              """#)
    }, store)

    try await client.pollSocial(sessionId: "sess-1", every: .milliseconds(1), giveUpAfter: .seconds(5))

    #expect(await client.isSignedIn)
    #expect(try await client.accessToken() == "social-tok")
    #expect(calls.value == 3)
}

/// The poll secret ties the sign-in to this client: the start sends only the hash, and every poll
/// sends the secret whose hash that is.
@Test func socialSignInSendsTheHashAndPollsWithTheSecret() async throws {
    let started = Box<[String: String]>()
    let polled = Box<String>()
    let client = auth(stubbedSession { request in
        if request.url?.path.hasSuffix("social-login") == true {
            started.value = (try? JSONSerialization.jsonObject(with: request.bodyData)) as? [String: String]
            return ok(request, #"{"loginUrl":"https://accounts.example.com/go","sessionId":"sess-1"}"#)
        }
        polled.value = request.value(forHTTPHeaderField: "X-Poll-Secret")
        return ok(request, #"""
            {"status":"complete","userId":"u1","email":"a@example.com","accessToken":"tok",
             "refreshToken":"ref","expiresIn":3600}
            """#)
    }, MemoryStore())

    _ = try await client.startSocialSignIn(provider: "Apple")
    try await client.pollSocial(sessionId: "sess-1", every: .milliseconds(1), giveUpAfter: .seconds(5))

    let hash = try #require(started.value?["pollHash"])
    let secret = try #require(polled.value)
    #expect(PollSecret.hash(of: secret) == hash)
    #expect(hash.count == 43)
}

/// Must match the server and the other apps (rpm.Api `PollSecret.HashOf`).
@Test func pollHashIsTheUnpaddedBase64urlSha256() {
    #expect(PollSecret.hash(of: "abc") == "ungWv48Bz-pBQUDeXa4iI7ADYaOWF3qctBD_YfIAFa0")
}

@Test func pollingGivesUpRatherThanSpinningForever() async {
    let client = auth(replying(200, #"{"status":"pending"}"#))
    do {
        try await client.pollSocial(
            sessionId: "sess-1", every: .milliseconds(1), giveUpAfter: .milliseconds(20))
        Issue.record("expected a throw")
    } catch let error as RPMError {
        guard case .signInTimedOut = error else {
            Issue.record("expected a timeout, got \(error)")
            return
        }
    } catch {
        Issue.record("expected an RPMError, got \(error)")
    }
    #expect(await client.isSignedIn == false)
}

// ── sign out ──

@Test func signOutForgetsTheStoredSession() async throws {
    let store = MemoryStore()
    let client = auth(replying(200, loginBody), store)
    try await client.signIn(email: "a@example.com", password: "pw")
    await client.signOut()

    #expect(await client.isSignedIn == false)
    #expect(try await client.accessToken() == nil)
    #expect(await store.read(AuthClient.sessionKey) == nil)
}

// ── the reason this is an actor ──

/// Two screens can want a token at the same moment. Refreshing twice spends the
/// refresh token twice, and a rotating store invalidates the first answer as it
/// issues the second, so the loser gets a token that is already dead.
@Test func simultaneousCallersRefreshOnlyOnce() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "old", expiresIn: -10))

    let calls = Box<Int>()
    let client = auth(stubbedSession { request in
        calls.value = (calls.value ?? 0) + 1
        return ok(request, #"""
        {"userId":"u1","email":"a@example.com","displayName":"Placeholder",
         "accessToken":"fresh","refreshToken":"ref2","expiresIn":3600}
        """#)
    }, store)
    await client.load()

    let answers = try await withThrowingTaskGroup(of: String?.self) { group in
        for _ in 0..<8 { group.addTask { try await client.accessToken() } }
        var all: [String?] = []
        for try await answer in group { all.append(answer) }
        return all
    }

    #expect(answers.allSatisfy { $0 == "fresh" })
    #expect(calls.value == 1, "refreshed \(calls.value ?? 0) times, expected once")
}

// ── deleting the account ──

@Test func onlyASuccessDeletesAndA400IsTheAddressRefused() {
    #expect(AuthClient.deletionAnswer(204) == .deleted)
    #expect(AuthClient.deletionAnswer(200) == .deleted)
    #expect(AuthClient.deletionAnswer(400) == .emailRefused)
    #expect(AuthClient.deletionAnswer(401) == .failed)
    #expect(AuthClient.deletionAnswer(500) == .failed)
}

/// The accounts service reads the address from the body and the account from the bearer; a
/// deletion sent without either would be refused, or worse, refused for the wrong reason.
@Test func deletingSendsTheTypedAddressWithTheSessionsToken() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "tok", expiresIn: 3600))

    let seen = Box<URLRequest>()
    let body = Box<Data>()
    let client = auth(stubbedSession { request in
        seen.value = request
        body.value = request.bodyData
        return (HTTPURLResponse(url: request.url!, statusCode: 204, httpVersion: nil, headerFields: nil)!, Data())
    }, store)
    await client.load()

    let answer = await client.deleteAccount(confirmEmail: "  a@example.com ")

    #expect(answer == .deleted)
    #expect(seen.value?.httpMethod == "DELETE")
    #expect(seen.value?.url?.path == "/auth/account")
    #expect(seen.value?.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    let sent = String(data: body.value ?? Data(), encoding: .utf8) ?? ""
    #expect(sent.contains("\"confirmEmail\":\"a@example.com\""))
}

@Test func deletingWhileSignedOutSendsNothing() async {
    let tally = Tally()
    let client = auth(stubbedSession { request in
        tally.mark()
        return ok(request, "{}")
    })

    #expect(await client.deleteAccount(confirmEmail: "a@example.com") == .failed)
    #expect(tally.count == 0)
}

// ── revoking on sign-out ──

/// The paths a test session's requests went to, in order.
private final class Paths: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [String] = []
    func add(_ path: String) { lock.withLock { seen.append(path) } }
    var all: [String] { lock.withLock { seen } }
}

/// The revocation runs on its own task, so a test waits for the state it is about.
private func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(25))
    }
    return await condition()
}

private func answering(_ status: Int, into paths: Paths) -> URLSession {
    stubbedSession { request in
        paths.add(request.url?.path ?? "")
        return (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, Data())
    }
}

/// Deleting the keychain item ends this phone's copy; the revocation ends the token.
@Test func signingOutRevokesTheRefreshToken() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "tok", refresh: "leaving", expiresIn: 3600))
    let paths = Paths()
    let client = auth(answering(204, into: paths), store)
    await client.load()

    await client.signOut()

    #expect(await eventually { paths.all.contains("/auth/revoke") })
    #expect(await eventually { await client.waitingToBeRevoked.isEmpty })
    #expect(await eventually { await store.read(AuthClient.revocationsKey) == nil })
    #expect(await client.isSignedIn == false)
}

/// No network at sign-out: the token stays in the keychain, and the next launch sends it.
@Test func aRevocationWithNoNetworkIsSentAtTheNextLaunch() async throws {
    let store = MemoryStore()
    try await stored(store, session(access: "tok", refresh: "leaving", expiresIn: 3600))
    let offline = auth(failingSession(), store)
    await offline.load()

    await offline.signOut()
    try? await Task.sleep(for: .milliseconds(200))
    #expect(await offline.waitingToBeRevoked == ["leaving"])

    let paths = Paths()
    let nextLaunch = auth(answering(204, into: paths), store)
    await nextLaunch.load()

    #expect(await nextLaunch.isSignedIn == false)
    #expect(await eventually { paths.all.contains("/auth/revoke") })
    #expect(await eventually { await nextLaunch.waitingToBeRevoked.isEmpty })
    #expect(await eventually { await store.read(AuthClient.revocationsKey) == nil })
}

@Test func whichRevocationAnswersLeaveNothingToSend() {
    #expect(AuthClient.revocationAnswered(204))
    #expect(AuthClient.revocationAnswered(400))
    #expect(AuthClient.revocationAnswered(401))
    #expect(!AuthClient.revocationAnswered(404))
    #expect(!AuthClient.revocationAnswered(503))
    #expect(!AuthClient.revocationAnswered(500))
}
