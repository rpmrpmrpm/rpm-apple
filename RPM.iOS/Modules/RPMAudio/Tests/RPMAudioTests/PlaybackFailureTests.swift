import Foundation
import Testing
import RPMKit
@testable import RPMAudio

/// What a failed start reports. The most important distinction is this: a start that was
/// abandoned, because a second record was tapped, reports nothing. A start that timed out
/// reports a message.
@Suite("Reading a start that did not happen")
struct PlaybackFailureTests {

    @Test func nothingAtAllIsNothingToSay() {
        #expect(PlaybackFailure.read(nil) == .none)
        #expect(PlaybackFailure.none.said == nil)
    }

    @Test func aStartThatWasAbandonedIsNotAFault() {
        #expect(PlaybackFailure.read(CancellationError()) == .none)
        #expect(PlaybackFailure.read(URLError(.cancelled)) == .none)
    }

    @Test func aTimeoutIsNotACancellation() {
        #expect(PlaybackFailure.read(URLError(.timedOut)) == .timeout)
        #expect(PlaybackFailure.read(URLError(.timedOut)).said != nil)
    }

    @Test(arguments: [URLError.Code.notConnectedToInternet,
                      .networkConnectionLost,
                      .cannotFindHost,
                      .cannotConnectToHost,
                      .dnsLookupFailed,
                      .dataNotAllowed])
    func everyWayOfHavingNoNetworkReadsTheSame(code: URLError.Code) {
        #expect(PlaybackFailure.read(URLError(code)) == .offline)
    }

    @Test func aRefusedSessionSaysToSignInAgain() {
        #expect(PlaybackFailure.read(RPMError.unauthorized) == .signedIn)
        #expect(PlaybackFailure.read(RPMError.status(401)) == .signedIn)
        #expect(PlaybackFailure.read(RPMError.status(403)) == .signedIn)
    }

    @Test func anythingElseTheStoreSaidIsTheStore() {
        #expect(PlaybackFailure.read(RPMError.status(500)) == .store)
        #expect(PlaybackFailure.read(RPMError.refused(status: 400, reason: nil)) == .store)
    }

    /// Without unwrapping, these would be read as `.unknown`. The client wraps the error thrown by
    /// the session, so the network error is one level down.
    @Test func aWrappedNetworkErrorIsStillANetworkError() {
        #expect(PlaybackFailure.read(RPMError.transport(URLError(.notConnectedToInternet))) == .offline)
        #expect(PlaybackFailure.read(RPMError.transport(URLError(.timedOut))) == .timeout)
        #expect(PlaybackFailure.read(RPMError.transport(URLError(.cancelled))) == .none)
    }

    // ── a record that stopped rather than ended ──

    @Test func arecordThatStoppedInTheFirstSecondsNeverReallyStarted() {
        #expect(PlaybackFailure.ended(heard: 0.5) == .unreachable)
        #expect(PlaybackFailure.ended(heard: PlaybackFailure.started) == .unreachable)
    }

    @Test func aRecordThatStoppedMinutesInWasArrivingUntilItWasNot() {
        #expect(PlaybackFailure.ended(heard: 120) == .dropped)
    }

    /// Every failure that is shown has a message. An empty error line is worse than no line.
    @Test(arguments: [PlaybackFailure.offline, .timeout, .signedIn, .store,
                      .unreachable, .dropped, .notPlayable, .unknown])
    func everyFailureWorthSayingHasASentence(failure: PlaybackFailure) {
        #expect(failure.said?.isEmpty == false)
    }

    /// Messages must not contain em or en dashes. Such a dash is easy to add by copying text from
    /// a comment.
    @Test(arguments: [PlaybackFailure.offline, .timeout, .signedIn, .store,
                      .unreachable, .dropped, .notPlayable, .unknown])
    func noSentenceCarriesADash(failure: PlaybackFailure) {
        let said = failure.said ?? ""
        #expect(!said.contains("—"))
        #expect(!said.contains("–"))
    }
}

/// When the gate refuses to open a socket, the user sees "no internet connection". It must not
/// read as a broken track.
@Test func theGateRefusingIsOffline() {
    #expect(PlaybackFailure.read(RPMError.offline) == .offline)
}

/// Decides whether the player starts again when the network returns. Every case is named in the
/// switch. A new failure must be added to the switch on purpose, so it cannot fall into the
/// "waiting will fix it" group by default. A file that the decoder refuses will be refused again.
@Test func onlyTheFailuresWaitingCanUndoBlameTheNetwork() {
    #expect(PlaybackFailure.offline.blamesTheNetwork)
    #expect(PlaybackFailure.timeout.blamesTheNetwork)
    #expect(PlaybackFailure.unreachable.blamesTheNetwork)
    #expect(PlaybackFailure.dropped.blamesTheNetwork)

    #expect(!PlaybackFailure.none.blamesTheNetwork)
    #expect(!PlaybackFailure.signedIn.blamesTheNetwork)
    #expect(!PlaybackFailure.store.blamesTheNetwork)
    #expect(!PlaybackFailure.notPlayable.blamesTheNetwork)
    #expect(!PlaybackFailure.unknown.blamesTheNetwork)
}
