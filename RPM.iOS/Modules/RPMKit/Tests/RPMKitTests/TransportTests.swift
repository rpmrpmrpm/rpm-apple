import Testing
import Foundation
@testable import RPMKit

private func transport(_ session: URLSession, token: String? = "abc",
                       reach: NetworkReach = openLine()) -> Transport {
    Transport(base: URL(string: "https://api.example.com")!,
              tokens: FixedTokens(token: token),
              reach: reach,
              session: session)
}

/// Asserts the call threw the RPMError the matcher accepts, and says what it got
/// otherwise. Written once because seven tests want it and a hand-rolled
/// do/catch is a place to forget the `Issue.record` on the success path.
private func expectError(
    _ matches: @escaping (RPMError) -> Bool,
    _ what: Comment,
    _ call: () async throws -> Void
) async {
    do {
        try await call()
        Issue.record("expected \(what), but the call succeeded")
    } catch let error as RPMError {
        #expect(matches(error), "expected \(what), got \(error)")
    } catch {
        Issue.record("expected \(what), got a non-RPMError: \(error)")
    }
}

@Test func getSendsTheBearerTokenAndDecodes() async throws {
    let seen = Box<URLRequest>()
    let session = stubbedSession { request in
        seen.value = request
        return ok(request, #"{"usedBytes":1,"quotaBytes":2,"fileCount":3}"#)
    }

    let quota = try await transport(session).get("cloud/quota", as: CloudQuota.self)

    #expect(quota.fileCount == 3)
    #expect(seen.value?.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    #expect(seen.value?.url?.absoluteString == "https://api.example.com/cloud/quota")
}

/// A call made with no session must not send an empty bearer. A header reading
/// "Bearer " is a malformed credential rather than an absent one, and the two
/// come back as different errors.
@Test func noTokenMeansNoAuthorizationHeader() async throws {
    let seen = Box<URLRequest>()
    let session = stubbedSession { request in
        seen.value = request
        return ok(request, #"{"usedBytes":0,"quotaBytes":0,"fileCount":0}"#)
    }

    _ = try await transport(session, token: nil).get("cloud/quota", as: CloudQuota.self)
    #expect(seen.value?.value(forHTTPHeaderField: "Authorization") == nil)
}

/// 401 is its own case rather than a status code, because it is the one error a
/// screen must not show as text: it means sign in again, and every caller
/// handles it the same way.
@Test func unauthorizedIsItsOwnCase() async {
    let t = transport(replying(401, "{}"))
    await expectError({ if case .unauthorized = $0 { true } else { false } }, ".unauthorized") {
        _ = try await t.get("cloud/quota", as: CloudQuota.self)
    }
}

@Test func forbiddenIsAlsoUnauthorized() async {
    let t = transport(replying(403, "{}"))
    await expectError({ if case .unauthorized = $0 { true } else { false } }, ".unauthorized") {
        _ = try await t.get("cloud/quota", as: CloudQuota.self)
    }
}

@Test func quotaExceededIsItsOwnCase() async {
    let t = transport(replying(507, #"{"message":"Out of space"}"#))
    await expectError({ if case .quotaExceeded = $0 { true } else { false } }, ".quotaExceeded") {
        _ = try await t.get("cloud/quota", as: CloudQuota.self)
    }
}

/// The server's sentences are English in every locale, so a refusal does not carry
/// one: the screen says what it was doing.
@Test func aRefusalSaysWhatTheScreenWasDoingAndNotWhatTheServerWrote() async {
    let t = transport(replying(400, #"{"message":"That name is taken."}"#))
    await expectError({
        if case .refused(status: 400, reason: nil) = $0 {
            $0.userMessage(refused: "Your review could not be saved.") == "Your review could not be saved."
        } else { false }
    }, ".refused(400) saying the screen's sentence") {
        _ = try await t.get("cloud/quota", as: CloudQuota.self)
    }
}

/// A 404 from the API is a refusal like any other 4xx, so a caller that treats
/// "not there" as nil catches it as one.
@Test func aMissingThingIsARefusalWithItsStatus() async {
    let t = transport(replying(404, #"{"error":"Not found."}"#))
    await expectError({ if case .refused(status: 404, _) = $0 { true } else { false } }, ".refused(404)") {
        _ = try await t.get("cloud/quota", as: CloudQuota.self)
    }
}

@Test func aBodyThatIsNotTheExpectedShapeIsADecodingFailure() async {
    let t = transport(replying(200, #"{"unexpected":true}"#))
    await expectError({ if case .decoding = $0 { true } else { false } }, ".decoding") {
        _ = try await t.get("cloud/list", as: CloudListPage.self)
    }
}

@Test func aServerFailureKeepsItsStatus() async {
    let t = transport(replying(503, "{}"))
    await expectError({ if case .status(503) = $0 { true } else { false } }, ".status(503)") {
        _ = try await t.get("cloud/quota", as: CloudQuota.self)
    }
}

/// No dashes anywhere a person can read one, checked here rather than by review:
/// these strings are written once and never looked at again.
@Test func noUserMessageCarriesADash() {
    let cases: [RPMError] = [
        .unauthorized, .quotaExceeded, .offline,
        .refused(status: 400, reason: nil), .refused(status: 401, reason: .wrongPassword),
        .refused(status: 400, reason: .notConfirmed),
        .notServed(ownerId: "y"), .status(500),
        .transport(URLError(.timedOut)), .decoding(URLError(.timedOut)),
        .badAddress, .signInIncomplete, .signInTimedOut,
    ]
    for error in cases {
        let said = error.userMessage(refused: "That could not be done.")
        #expect(!said.contains("\u{2014}"))
        #expect(!said.contains("\u{2013}"))
        #expect(!said.isEmpty)
    }
}

// ── the gate ──

/// The point of the gate is not that the call fails. It is that **no socket is opened**:
/// no name lookup, no connection, no exception, and an answer immediately rather than
/// after a timeout.
@Test func nothingIsSentWhileThereIsNoNetwork() async {
    let tally = Tally()
    let session = stubbedSession { request in
        tally.mark()
        return ok(request, #"{"usedBytes":0,"quotaBytes":0,"fileCount":0}"#)
    }

    let closed = await closedLine()
    await expectError({ if case .offline = $0 { true } else { false } }, ".offline") {
        _ = try await transport(session, reach: closed).get("cloud/quota", as: CloudQuota.self)
    }

    #expect(tally.count == 0, "the gate must refuse before the session is touched")
}

// ── the retries ──

@Test func theEdgeSayingNotNowIsAskedAgain() async throws {
    let tally = Tally()
    let session = stubbedSession { request in
        tally.mark()
        guard tally.count > 1 else {
            return (HTTPURLResponse(url: request.url!, statusCode: 503,
                                    httpVersion: nil, headerFields: nil)!, Data())
        }
        return ok(request, #"{"usedBytes":1,"quotaBytes":2,"fileCount":3}"#)
    }

    let quota = try await transport(session).get("cloud/quota", as: CloudQuota.self)

    #expect(quota.fileCount == 3)
    #expect(tally.count == 2)
}

@Test func aServiceThatKeepsSayingNotNowIsGivenUpOn() async {
    let tally = Tally()
    let session = stubbedSession { request in
        tally.mark()
        return (HTTPURLResponse(url: request.url!, statusCode: 503,
                                httpVersion: nil, headerFields: nil)!, Data())
    }

    await expectError({ if case .status(503) = $0 { true } else { false } }, ".status(503)") {
        _ = try await transport(session).get("cloud/quota", as: CloudQuota.self)
    }

    #expect(tally.count == Attempts.most)
}

/// A refusal the server decided is news. Burying a 404 under three attempts hides a real
/// fault and takes a second and a half to do it.
@Test func anAnswerTheServerMeantIsNotAskedAgain() async {
    let tally = Tally()
    let session = stubbedSession { request in
        tally.mark()
        return (HTTPURLResponse(url: request.url!, statusCode: 404,
                                httpVersion: nil, headerFields: nil)!, Data())
    }

    await expectError({ if case .refused(status: 404, _) = $0 { true } else { false } }, ".refused(404)") {
        _ = try await transport(session).get("cloud/quota", as: CloudQuota.self)
    }

    #expect(tally.count == 1)
}

/// A 500 is the service saying it ran and threw. Sending the write again is how a
/// playlist gets made twice.
@Test func aWriteIsNotReplayedAfterTheServiceThrew() async {
    let tally = Tally()
    let session = stubbedSession { request in
        tally.mark()
        return (HTTPURLResponse(url: request.url!, statusCode: 500,
                                httpVersion: nil, headerFields: nil)!, Data())
    }

    await expectError({ if case .status(500) = $0 { true } else { false } }, ".status(500)") {
        try await transport(session).sendVoid("POST", "cloud/playlists", body: ["a": "b"])
    }

    #expect(tally.count == 1)
}

@Test func aReadIsReplayedAfterTheServiceThrew() async {
    let tally = Tally()
    let session = stubbedSession { request in
        tally.mark()
        return (HTTPURLResponse(url: request.url!, statusCode: 500,
                                httpVersion: nil, headerFields: nil)!, Data())
    }

    await expectError({ if case .status(500) = $0 { true } else { false } }, ".status(500)") {
        _ = try await transport(session).get("cloud/quota", as: CloudQuota.self)
    }

    #expect(tally.count == Attempts.most)
}

/// The socket dropping under a read is a phone coming out of a pocket, not a fault.
@Test func aDroppedSocketUnderAReadIsPickedUpAgain() async throws {
    let tally = Tally()
    let session = stumblingSession(.networkConnectionLost, times: 1) { request in
        tally.mark()
        return ok(request, #"{"usedBytes":1,"quotaBytes":2,"fileCount":7}"#)
    }

    let quota = try await transport(session).get("cloud/quota", as: CloudQuota.self)

    #expect(quota.fileCount == 7)
    #expect(tally.count == 1, "the first attempt never reached the handler")
}

/// The one that must not happen: a write sent twice because the answer to the first was
/// lost on the way back.
@Test func aWriteIsNotReplayedAfterADroppedSocket() async {
    let session = stumblingSession(.networkConnectionLost, times: 1) { request in
        ok(request, "{}")
    }

    await expectError({ if case .transport = $0 { true } else { false } }, ".transport") {
        try await transport(session).sendVoid("POST", "cloud/playlists", body: ["a": "b"])
    }
}
