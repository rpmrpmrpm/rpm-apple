import CryptoKit
import Foundation

/// Sign-in, and the token that every other call in this package uses.
///
/// This is an actor, because two screens can ask for a token at the same moment. The refresh must run once.
public actor AuthClient: TokenSource {
    public static let sessionKey = "session"

    /// Refresh tokens from sign-outs that the server has not yet confirmed as revoked.
    public static let revocationsKey = "revocations"

    /// The app's name, sent to the accounts service. It comes back with the sign-in poll, so it must be a name
    /// that the service knows. An unknown `appId` makes sign-in fail silently. The app then gets a session with
    /// no tokens in it.
    public static let appId = "RPM"

    /// A token this close to expiry is treated as already expired. A request started now would finish after the
    /// token died. The result would be a 401 in the middle of a session that looked valid.
    private static let refreshMargin: TimeInterval = 180

    private let base: URL
    private let keychain: any SecretStore

    /// The same gate and retry path that every other call in the app uses. A sign-in with no network must fail at
    /// once, with a message, and without a name lookup. See ``Gated``.
    private let wire: Gated
    private var stored: Session?

    /// So that two callers asking at once refresh once, not twice.
    private var refreshing: Task<String?, Never>?

    /// Tokens waiting to be revoked, as this actor holds them. The keychain copy is kept in step through
    /// ``saveRevocations()``.
    private var pendingRevocations: [String] = []

    /// The poll secret of each social sign-in this client started, by session id. Only the hash goes
    /// to the server when the sign-in starts; the secret goes with each poll, so someone who has the
    /// login URL cannot collect the tokens. See `PollSecret`.
    private var pollSecrets: [String: String] = [:]

    /// The last keychain write of ``pendingRevocations``. Each write waits for the one before it, then stores the
    /// list as it is at that moment. So the keychain ends with the latest list, even when two sign-outs and a
    /// retry interleave across their awaits.
    private var revocationsWritten: Task<Void, Never>?

    /// - Parameter reach: No default. See the reason given on ``Transport/init(base:tokens:reach:session:)``.
    public init(base: URL, keychain: any SecretStore, reach: NetworkReach,
                session: URLSession = Wire.session()) {
        self.base = base
        self.keychain = keychain
        self.wire = Gated(reach: reach, session: session)
    }

    public var isSignedIn: Bool { stored != nil }
    public var current: Session? { stored }

    /// Restores a saved session at startup. This makes no network calls. The token is checked only when it is
    /// first used. So the app opens on a cold launch with no network.
    public func load() async {
        if let data = await keychain.read(Self.revocationsKey),
           let tokens = try? RPMJSON.decoder.decode([String].self, from: data) {
            pendingRevocations = tokens
        }
        // A sign-out that the server has not heard about yet, from a run that had no network.
        if !pendingRevocations.isEmpty { Task { await revokePending() } }

        guard let data = await keychain.read(Self.sessionKey) else { return }
        stored = try? RPMJSON.decoder.decode(Session.self, from: data)
    }

    // Signing in

    public func signIn(email: String, password: String) async throws {
        let said: LoginResponse
        do {
            said = try await post("auth/login", [
                "email": email.trimmingCharacters(in: .whitespacesAndNewlines),
                "password": password,
            ])
        } catch RPMError.unauthorized {
            // A 401 here means a wrong password. There is no session yet, so it is not a session error.
            throw RPMError.refused(status: 401, reason: .wrongPassword)
        } catch RPMError.refused(status: 400, _) {
            throw RPMError.refused(status: 400, reason: .notConfirmed)
        }
        guard let token = said.accessToken, !token.isEmpty else {
            throw RPMError.signInIncomplete
        }
        await adopt(said)
        revokePendingAfterSignIn()
    }

    /// Social sign-in, first step: ask the accounts service where to send the person.
    ///
    /// The app opens the browser, not this package. On iOS the right way is `ASWebAuthenticationSession`, which
    /// is a UI framework that this package does not import.
    public func startSocialSignIn(provider: String) async throws -> (url: URL, sessionId: String) {
        let secret = PollSecret.make()
        let said: SocialStart = try await post("auth/social-login", [
            "provider": provider,
            "appId": Self.appId,
            "pollHash": PollSecret.hash(of: secret),
        ])
        guard let url = URL(string: said.loginUrl), !said.sessionId.isEmpty else {
            throw RPMError.signInIncomplete
        }
        pollSecrets[said.sessionId] = secret
        return (url, said.sessionId)
    }

    /// Social sign-in, second step: poll the sign-in record that the website writes the tokens to.
    ///
    /// This polls rather than using a callback, because the accounts service offers polling. A record that is not
    /// finished yet returns a status and no tokens. The deadline is long, because the app is in the background
    /// while the browser is open.
    public func pollSocial(
        sessionId: String,
        every interval: Duration = .seconds(2),
        giveUpAfter deadline: Duration = .seconds(180)
    ) async throws {
        let started = ContinuousClock.now

        while ContinuousClock.now - started < deadline {
            try await Task.sleep(for: interval)

            let escaped = sessionId.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics) ?? sessionId
            let headers = pollSecrets[sessionId].map { [PollSecret.header: $0] } ?? [:]
            let said: SocialPoll = try await request(
                "GET", "auth/poll-session?sessionId=\(escaped)", body: nil, headers: headers)

            guard said.isComplete else { continue }
            pollSecrets[sessionId] = nil
            guard let token = said.accessToken, !token.isEmpty else {
                throw RPMError.signInIncomplete
            }

            await adopt(LoginResponse(
                userId: said.userId, email: said.email, displayName: said.displayName,
                accessToken: said.accessToken, refreshToken: said.refreshToken,
                expiresIn: said.expiresIn))
            revokePendingAfterSignIn()
            return
        }

        throw RPMError.signInTimedOut
    }

    /// Ends the session and revokes its refresh token on the server.
    ///
    /// Deleting the keychain item ends this phone's copy, but not the token. Without revoking it, the token would
    /// stay valid for up to 30 days on other devices. The token is written to storage before the request is sent,
    /// so a sign-out with no network leaves it to be sent at the next launch or sign-in. The revoke is not awaited.
    /// Signing out does not wait for the network.
    public func signOut() async {
        let leaving = stored?.refreshToken ?? ""
        stored = nil
        refreshing = nil
        await keychain.delete(Self.sessionKey)

        guard !leaving.isEmpty else { return }
        if !pendingRevocations.contains(leaving) { pendingRevocations.append(leaving) }
        await saveRevocations()
        Task { await revokePending() }
    }

    /// The tokens still waiting to be revoked. Used by the tests.
    var waitingToBeRevoked: [String] { pendingRevocations }

    /// Sends each waiting token to `auth/revoke`, and removes the ones the server answered for.
    ///
    /// Several of these can run at once. A sign-out, a launch and a sign-in can each start one. Revoking a token
    /// twice is harmless. The list removes only the tokens this run sent, so a token added by a sign-out in the
    /// meantime is kept.
    func revokePending() async {
        let tokens = pendingRevocations
        guard !tokens.isEmpty else { return }

        var answered: [String] = []
        for token in tokens {
            if await revoke(token) { answered.append(token) }
        }
        guard !answered.isEmpty else { return }

        pendingRevocations.removeAll { answered.contains($0) }
        await saveRevocations()
    }

    /// After a sign-in the network is known to work. This is the moment to send the tokens that an offline
    /// sign-out left behind.
    private func revokePendingAfterSignIn() {
        if !pendingRevocations.isEmpty { Task { await revokePending() } }
    }

    private func revoke(_ token: String) async -> Bool {
        do {
            let (_, http) = try await send("POST", "auth/revoke", body: ["refreshToken": token])
            return Self.revocationAnswered(http.statusCode)
        } catch {
            return false
        }
    }

    /// Whether the server's answer to `auth/revoke` means that nothing more needs doing. That is any 2xx, or a 4xx
    /// that sending again would not change. A 404 means an accounts service from before `auth/revoke` existed. A
    /// 5xx means Cognito or the connection failed. Both cases are sent again later.
    static func revocationAnswered(_ status: Int) -> Bool {
        switch status {
        case 200..<300: return true
        case 404: return false
        case 400..<500: return true
        default: return false
        }
    }

    private func saveRevocations() async {
        let previous = revocationsWritten
        let write = Task {
            await previous?.value
            await self.writeRevocationsNow()
        }
        revocationsWritten = write
        await write.value
    }

    private func writeRevocationsNow() async {
        let tokens = pendingRevocations
        if tokens.isEmpty {
            await keychain.delete(Self.revocationsKey)
        } else if let data = try? RPMJSON.encoder.encode(tokens) {
            await keychain.write(Self.revocationsKey, data)
        }
    }

    // Deleting the account

    /// What asking the accounts service to delete the account came to.
    public enum Deletion: Sendable, Equatable {
        /// Deleted. The server erases the cloud library within two hours. The caller then signs out.
        case deleted
        /// The typed address is not the account's verified email, or the account has no verified email.
        /// Nothing was deleted.
        case emailRefused
        /// The request did not get through, or the server failed. Nothing was deleted.
        case failed
    }

    /// Asks the accounts service to delete the signed-in account. This is only the server's part. On
    /// ``Deletion/deleted``, the caller signs out. The desktop does the same (`AccountDeletion`).
    ///
    /// - Parameter confirmEmail: The address the person typed. The server compares it with the account's verified
    ///   address, ignoring case.
    public func deleteAccount(confirmEmail: String) async -> Deletion {
        guard let token = try? await accessToken(),
              let url = URL(string: "auth/account", relativeTo: base) else { return .failed }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? RPMJSON.encoder.encode(
            ["confirmEmail": confirmEmail.trimmingCharacters(in: .whitespacesAndNewlines)])

        do {
            let (_, http) = try await wire.fetch(request, method: "DELETE")
            return Self.deletionAnswer(http.statusCode)
        } catch {
            return .failed
        }
    }

    /// What the server's answer means. 2xx means deleted. 400 means the address was refused. Any other answer
    /// means nothing was deleted.
    static func deletionAnswer(_ status: Int) -> Deletion {
        switch status {
        case 200..<300: return .deleted
        case 400: return .emailRefused
        default: return .failed
        }
    }

    // The token

    /// A valid access token. It is refreshed first if it is close to expiry.
    ///
    /// Returns nil when signed out. Nil is also returned when a refresh is refused and the user is signed out as a
    /// result. A caller that gets nil should send the user back to the sign-in screen, and should not retry.
    public func accessToken() async throws -> String? {
        guard let session = stored else { return nil }

        if session.expiresAt.timeIntervalSinceNow > Self.refreshMargin {
            return session.accessToken
        }

        // With no refresh token there is nothing to refresh with. Keep the session and return its access token.
        // The call then fails on its own terms.
        guard !session.refreshToken.isEmpty else { return session.accessToken }

        if let running = refreshing { return await running.value }

        let task = Task<String?, Never> { [refreshToken = session.refreshToken] in
            switch await refresh(refreshToken) {
            case .fresh(let said, let token):
                await adopt(said)
                return token
            case .refused:
                // The server rejected the refresh token, so the session has ended. Asking again with the same
                // token would loop. Only a new sign-in ends that loop.
                await signOut()
                return nil
            case .unavailable:
                // The token was not judged. This happens with no network, when the gate refuses, on a 5xx, or when
                // the response does not come from the accounts service. A captive portal, for example, answers 200
                // with HTML. Signing out in any of these cases would log the person out each time they open the app
                // offline, or when the service has a problem. So return the token we have. The call that needs it
                // fails on its own terms, and the next call refreshes again.
                return session.accessToken
            }
        }

        refreshing = task
        let answer = await task.value
        refreshing = nil
        return answer
    }

    // Network calls

    private func adopt(_ said: LoginResponse) async {
        let next = Session(
            userId: said.userId ?? stored?.userId ?? "",
            email: said.email ?? stored?.email ?? "",
            displayName: said.displayName ?? stored?.displayName ?? "",
            accessToken: said.accessToken ?? "",
            // A refresh does not return a new refresh token. Losing the old one here would mean one refresh per
            // session, and a sign-out an hour later.
            refreshToken: said.refreshToken ?? stored?.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(TimeInterval(said.expiresIn ?? 3600)))

        stored = next
        if let data = try? RPMJSON.encoder.encode(next) {
            await keychain.write(Self.sessionKey, data)
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await request("GET", path, body: nil)
    }

    private func post<T: Decodable>(_ path: String, _ body: [String: String]) async throws -> T {
        try await request("POST", path, body: body)
    }

    /// The result of a refresh. Only `refused` signs out.
    enum RefreshAnswer {
        case fresh(LoginResponse, token: String)
        /// The server judged the refresh token and rejected it.
        case refused
        /// The token was not judged. This says nothing about the session.
        case unavailable
    }

    /// The statuses that mean the refresh token itself was refused. 401 is the accounts service's answer for a used
    /// token. 400 is its answer for a missing one. Any other status, such as 429, a 5xx, or a proxy's 404, means the
    /// service or the connection failed. The account is not the problem.
    static func isRefusal(_ status: Int) -> Bool { [400, 401, 403].contains(status) }

    private func refresh(_ refreshToken: String) async -> RefreshAnswer {
        let data: Data
        let http: HTTPURLResponse
        do { (data, http) = try await send("POST", "auth/refresh", body: ["refreshToken": refreshToken]) }
        catch { return .unavailable }

        guard (200..<300).contains(http.statusCode) else {
            return Self.isRefusal(http.statusCode) ? .refused : .unavailable
        }
        guard let said = try? RPMJSON.decoder.decode(LoginResponse.self, from: data) else {
            return .unavailable
        }
        guard let token = said.accessToken, !token.isEmpty else { return .refused }
        return .fresh(said, token: token)
    }

    /// This makes its own requests rather than using `Transport`. None of these calls send a bearer token, and
    /// `Transport` asks this object for one. Using `Transport` here would make a refresh ask itself for a token.
    private func request<T: Decodable>(
        _ method: String, _ path: String, body: [String: String]?, headers: [String: String] = [:]
    ) async throws -> T {
        let (data, http) = try await send(method, path, body: body, headers: headers)

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw RPMError.unauthorized }
            if (400..<500).contains(http.statusCode) {
                throw RPMError.refused(status: http.statusCode, reason: nil)
            }
            throw RPMError.status(http.statusCode)
        }

        do { return try RPMJSON.decoder.decode(T.self, from: data) }
        catch { throw RPMError.decoding(error) }
    }

    private func send(
        _ method: String, _ path: String, body: [String: String]?, headers: [String: String] = [:]
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: path, relativeTo: base) else {
            throw RPMError.badAddress
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? RPMJSON.encoder.encode(body)
        }

        return try await wire.fetch(request, method: method)
    }
}

/// The secret that ties a social sign-in to the app that started it. The server side is
/// `PollSecret` in rpm.Api, and the desktop and Android apps make the same hash. Change all of them
/// together.
enum PollSecret {
    /// The header the secret is sent in when polling.
    static let header = "X-Poll-Secret"

    /// A new random secret: 32 bytes, base64url without padding.
    static func make() -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: 0...255, using: &generator) }
        return base64url(Data(bytes))
    }

    /// The hash sent for `secret`: the base64url SHA-256 of its UTF-8 bytes, without padding.
    static func hash(of secret: String) -> String {
        base64url(Data(SHA256.hash(data: Data(secret.utf8))))
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
