import Testing
import Foundation
@testable import RPMKit

// ── the reading ──

/// The bug this whole type exists to prevent: one Bool cannot be both guesses.
@Test func whatIsBelievedBeforeTheFirstPathArrives() {
    #expect(Reach.unknown.isOnline, "a gate that begins closed refuses the app's own first request")
    #expect(Reach.unknown.costsData, "a track begun before the monitor answers must not be assumed free")
}

/// `NWPath` reports `isExpensive` as false when there is no path to be expensive, which
/// is not the same as "this is free".
@Test func aPathThatIsNotThereIsNotAFreeOne() {
    let gone = Reach.reading(satisfied: false, expensive: false, constrained: true)

    #expect(!gone.isOnline)
    #expect(gone.costsData)
    #expect(!gone.isConstrained, "there is nothing to ration")
}

@Test func aSatisfiedPathIsReadStraight() {
    let cellular = Reach.reading(satisfied: true, expensive: true, constrained: true)

    #expect(cellular.isOnline)
    #expect(cellular.costsData)
    #expect(cellular.isConstrained)
}

// ── the settling rule ──

/// Polls rather than sleeping a guessed length: the settling is a real wait and a test
/// that guesses how long it takes fails on a busy machine.
private func waitUntil(_ holds: @escaping @Sendable () -> Bool) async -> Bool {
    for _ in 0..<400 {
        if holds() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return holds()
}

@Test func aLineIsBelievedTheMomentItAppears() async {
    let path = FakePath()
    let reach = NetworkReach(watching: path, settling: .seconds(30))
    reach.begin()

    path.say(.freely)

    #expect(await waitUntil { reach.now == .freely },
            "an online reading must not wait for the settling")
}

@Test func aLineGoingHasToHoldBeforeAnybodyIsTold() async {
    let path = FakePath()
    let reach = NetworkReach(watching: path, settling: .seconds(30))
    reach.begin()

    path.say(.freely)
    _ = await waitUntil { reach.now == .freely }

    path.say(.away)
    try? await Task.sleep(for: .milliseconds(120))

    #expect(reach.now.isOnline, "an offline reading must hold for the settling first")
}

/// The handoff. This is what a banner that flashes on and off looks like from here.
@Test func aBlipIsNeverPublished() async {
    let path = FakePath()
    let reach = NetworkReach(watching: path, settling: .milliseconds(200))
    reach.begin()

    path.say(.freely)
    _ = await waitUntil { reach.now == .freely }

    path.say(.away)
    try? await Task.sleep(for: .milliseconds(40))
    path.say(.freely)

    try? await Task.sleep(for: .milliseconds(400))
    #expect(reach.now == .freely, "a moment of no path between two Wi-Fi readings is not news")
}

@Test func aLineThatStaysGoneIsPublished() async {
    let path = FakePath()
    let reach = NetworkReach(watching: path, settling: .milliseconds(30))
    reach.begin()

    path.say(.away)

    #expect(await waitUntil { !reach.now.isOnline })
}

@Test func theChangesStreamCarriesTheSettledReading() async {
    let path = FakePath()
    let reach = NetworkReach(watching: path, settling: .milliseconds(20))

    // Taken before begin, which is the order every consumer has to use.
    var readings = reach.changes.makeAsyncIterator()
    reach.begin()

    path.say(.freely)
    #expect(await readings.next() == .freely)

    path.say(.away)
    #expect(await readings.next() == .away)
}

// ── what is worth another go ──

@Test func theEdgeSayingNotNowIsWorthAnotherGoForAnyMethod() {
    for status in [408, 429, 502, 503, 504] {
        #expect(Attempts.worthAnotherGo(status: status, method: "GET"))
        #expect(Attempts.worthAnotherGo(status: status, method: "POST"))
    }
}

/// The distinction the desktop does not draw: 500 means the service ran and threw, and
/// replaying a write against that is how a review gets posted twice.
@Test func aServiceThatThrewIsRepeatedOnlyForAReadThatCannotDoHarm() {
    #expect(Attempts.worthAnotherGo(status: 500, method: "GET"))
    #expect(!Attempts.worthAnotherGo(status: 500, method: "POST"))
    #expect(!Attempts.worthAnotherGo(status: 500, method: "DELETE"))
}

@Test func anAnswerTheServerDecidedIsNews() {
    for status in [200, 400, 401, 403, 404, 409, 413] {
        #expect(!Attempts.worthAnotherGo(status: status, method: "GET"), "\(status)")
    }
}

@Test func aDroppedSocketIsWorthAnotherGoAndBeingOfflineIsNot() {
    #expect(Attempts.worthAnotherGo(URLError(.networkConnectionLost), method: "GET"))
    #expect(Attempts.worthAnotherGo(URLError(.cannotFindHost), method: "GET"))

    // Waiting four hundred milliseconds does not put a phone back on a network.
    // `NetworkReach` is what notices that, and it notices it properly.
    #expect(!Attempts.worthAnotherGo(URLError(.notConnectedToInternet), method: "GET"))
    #expect(!Attempts.worthAnotherGo(URLError(.dataNotAllowed), method: "GET"))
}

/// The case that makes a bad network look like a hang: three attempts at a failure that
/// takes the whole per-attempt limit is three times the wait and the same answer.
@Test func aTimeoutIsNotAskedAgain() {
    #expect(!Attempts.worthAnotherGo(URLError(.timedOut), method: "GET"))
    #expect(Attempts.looksLikeTheLine(URLError(.timedOut)), "it is the line, and the gate is told")
}

@Test func theLineIsToldApartFromTheServiceOnIt() {
    for code in [URLError.Code.notConnectedToInternet, .networkConnectionLost,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .timedOut] {
        #expect(Attempts.looksLikeTheLine(URLError(code)), "\(code)")
    }

    // The service talking. The line carried these perfectly well.
    for code in [URLError.Code.badServerResponse, .cancelled, .userAuthenticationRequired] {
        #expect(!Attempts.looksLikeTheLine(URLError(code)), "\(code)")
    }
    #expect(!Attempts.looksLikeTheLine(RPMError.status(500)))
}

// ── the doubt ──

/// The second half of the gate. Without it every screen discovers a dead network on its
/// own, one full timeout at a time.
@Test func oneRequestFindingTheLineDeadShutsTheDoorForEverybody() {
    let reach = NetworkReach()
    #expect(reach.now.isOnline)

    reach.doubt()

    #expect(!reach.now.isOnline, "the gate refuses")
    #expect(reach.path.isOnline, "and says nothing about the phone, because it does not know")
}

/// A captive portal that starts working produces no path update at all, so a gate that
/// stays shut until the path changes would never open again.
@Test func aDoubtLapsesOnItsOwn() async {
    let reach = NetworkReach()
    reach.doubt()
    #expect(!reach.now.isOnline)

    // Rather than waiting the real ten seconds: a path update is better evidence than
    // anything a request worked out, and settles it at once.
    let path = FakePath()
    let watched = NetworkReach(watching: path, settling: .milliseconds(10))
    watched.begin()
    watched.doubt()
    #expect(!watched.now.isOnline)

    path.say(.freely)
    #expect(await waitUntil { watched.now.isOnline }, "a path update clears the doubt")
}

/// The ordinary end of every screen somebody left. Retrying it would repeat a request
/// that a person has already walked away from.
@Test func cancellationIsNeverRetried() {
    #expect(!Attempts.worthAnotherGo(URLError(.cancelled), method: "GET"))
    #expect(!Attempts.worthAnotherGo(CancellationError(), method: "GET"))
}

@Test func aWriteIsNotReplayedAfterAFailureThatMayHaveArrived() {
    #expect(!Attempts.worthAnotherGo(URLError(.networkConnectionLost), method: "POST"))
    #expect(!Attempts.worthAnotherGo(URLError(.timedOut), method: "PUT"))
}

@Test func theWaitGrowsAndIsCapped() {
    let first = Attempts.wait(after: 1, retryAfter: nil)
    #expect(first >= .milliseconds(400) && first < .milliseconds(650))

    let second = Attempts.wait(after: 2, retryAfter: nil)
    #expect(second >= .milliseconds(800) && second < .milliseconds(1050))

    #expect(Attempts.wait(after: 9, retryAfter: nil) == Attempts.longestWait)
}

@Test func theServersOwnNumberIsPreferredAndStillCapped() {
    #expect(Attempts.wait(after: 1, retryAfter: 2) == .seconds(2))
    #expect(Attempts.wait(after: 1, retryAfter: 900) == Attempts.longestWait)
}

@Test func retryAfterIsReadOffTheHeader() {
    let url = URL(string: "https://api.example.com/x")!
    let with = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                               headerFields: ["Retry-After": "3"])!
    #expect(Attempts.retryAfter(with) == 3)

    let without = HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil,
                                  headerFields: [:])!
    #expect(Attempts.retryAfter(without) == nil)
}
