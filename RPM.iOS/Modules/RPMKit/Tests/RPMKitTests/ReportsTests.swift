import Testing
import Foundation
@testable import RPMKit

private let api = URL(string: "https://api.example.com")!
private let facts = DeviceFacts(head: "ios", appVersion: "0.1.0 (7)", platform: "iOS 18.1; iPhone15,2",
                                architecture: "arm64")
private let draft = FeedbackDraft(kind: "problem", area: "playback", message: "The record keeps spinning.",
                                  screenshotPng: Data([0x89, 0x50]), replyTo: "tester@example.com")
private let crash = CrashDraft(crashId: "crash_0123456789abcdef01234567",
                               crashedAt: Date(timeIntervalSince1970: 1_800_000_000), appVersion: "0.1.0 (6)",
                               exception: "NSInvalidArgumentException: boom", systemReport: "{}",
                               systemReportKind: "metrickit", recent: "12:00:00.000 N player: started")

private func reports(_ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)) -> RPMReportsClient {
    RPMReportsClient(
        transport: Transport(base: api, tokens: FixedTokens(token: nil), reach: openLine(),
                             session: stubbedSession(handler)),
        facts: facts, installId: "install-1")
}

private func json(_ value: some Encodable) throws -> [String: Any] {
    try JSONSerialization.jsonObject(with: RPMJSON.encoder.encode(value)) as! [String: Any]
}

// ── the log tail ──

@Test func trimKeepsTheEndAndStartsOnALine() {
    let text = "first line\nsecond line\nthird line"

    #expect(LogTail.trim(text, maxCharacters: 100) == text)
    #expect(LogTail.trim(text, maxCharacters: 15) == "third line")
}

@Test func formatWritesOneLinePerEntry() {
    let lines = [
        LogTail.Line(date: Date(timeIntervalSince1970: 0), level: .notice, category: "player", message: "started"),
        LogTail.Line(date: Date(timeIntervalSince1970: 1.5), level: .error, category: "net", message: "status 500"),
    ]

    #expect(LogTail.format(lines) == "00:00:00.000 N player: started\n00:00:01.500 E net: status 500")
}

@Test func theSpoolHandsTheLastRunToTheNextLaunch() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: dir) }

    let first = LogSpool(directory: dir, launched: Date())
    first.rotate()
    await first.write("the run that crashed")
    #expect(first.thisRun() == "the run that crashed")

    let next = LogSpool(directory: dir, launched: Date())
    #expect(next.previousRun() == nil)
    next.rotate()

    #expect(next.previousRun() == "the run that crashed")
    #expect(next.thisRun() == nil)
}

// ── what a report carries ──

@Test func anAnonymousFeedbackBodyHasNoLogPictureOrReplyAddress() throws {
    let body = try json(RPMReportsClient.feedbackBody(
        draft, recent: "the log", scope: .anonymous, at: Date(), facts: facts, installId: "install-1"))

    #expect(body["recent"] == nil)
    #expect(body["screenshotPng"] == nil)
    #expect(body["replyTo"] == nil)
    #expect(body["scope"] == nil)
    #expect(body["message"] as? String == "The record keeps spinning.")
    #expect(body["installId"] as? String == "install-1")
}

@Test func aFullFeedbackBodyHasAllOfItAndSaysSo() throws {
    let body = try json(RPMReportsClient.feedbackBody(
        draft, recent: "the log", scope: .full, at: Date(), facts: facts, installId: "install-1"))

    #expect(body["recent"] as? String == "the log")
    #expect(body["screenshotPng"] as? String == "iVA=")
    #expect(body["replyTo"] as? String == "tester@example.com")
    #expect(body["scope"] as? String == "full")
    #expect(body["head"] as? String == "ios")
    #expect(body["platform"] as? String == "iOS 18.1; iPhone15,2")
}

/// The names are the server's `CrashReportRequest`. A name that does not match is dropped by the
/// server without an error, so the crash would arrive without its stack.
@Test func aCrashBodyUsesTheServersNames() throws {
    let body = try json(RPMReportsClient.crashBody(crash, scope: .full, facts: facts, installId: "install-1"))

    #expect(Set(body.keys) == ["crashId", "head", "appVersion", "platform", "architecture",
                               "crashedAtUtcTicks", "installId", "exception", "systemReport",
                               "systemReportKind", "recent", "scope"])
    #expect(body["appVersion"] as? String == "0.1.0 (6)")
    #expect(body["crashedAtUtcTicks"] as? Int64 == 639_355_968_000_000_000)
}

@Test func anAnonymousCrashKeepsTheStackButNotTheLog() throws {
    let body = try json(RPMReportsClient.crashBody(crash, scope: .anonymous, facts: facts, installId: "install-1"))

    #expect(body["recent"] == nil)
    #expect(body["scope"] == nil)
    #expect(body["exception"] as? String == "NSInvalidArgumentException: boom")
}

@Test func aCrashIdHasTheServersShape() {
    let id = CrashDraft.newId()

    #expect(id.wholeMatch(of: /crash_[0-9a-f]{24}/) != nil)
    #expect(id != CrashDraft.newId())
}

@Test func theInstallIdIsMadeOnceAndKept() {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!

    let first = InstallId.value(in: defaults)

    #expect(!first.isEmpty)
    #expect(InstallId.value(in: defaults) == first)
}

@Test func onlyTheAppStoreIsAnonymous() {
    #expect(ReportScope.of(.production) == .anonymous)
    #expect(ReportScope.of(.sandbox) == .full)
    #expect(ReportScope.of(.xcode) == .full)
}

@Test func anEmptyMessageCannotBeSent() {
    var empty = draft
    empty.message = "  \n "

    #expect(!empty.isSendable)
    #expect(draft.isSendable)
}

// ── sending ──

@Test func feedbackIsPostedAndAnswersItsId() async throws {
    let seen = Box<URLRequest>()
    let client = reports { request in
        seen.value = request
        return ok(request, #"{"errorId":"fb_1"}"#)
    }

    let id = try await client.sendFeedback(draft, recent: nil, scope: .full, at: Date())

    #expect(id == "fb_1")
    #expect(seen.value?.url?.path == "/errors/feedback")
    #expect(seen.value?.httpMethod == "POST")
}

/// A second press of Send while the first is on its way must not file the same words twice.
@Test func aSecondSendWhileTheFirstIsOnItsWayIsBusy() async throws {
    let calls = Tally()
    let client = reports { request in
        calls.mark()
        Thread.sleep(forTimeInterval: 0.3)
        return ok(request, #"{"errorId":"fb_1"}"#)
    }

    async let first = client.sendFeedback(draft, recent: nil, scope: .full, at: Date())
    try await Task.sleep(for: .milliseconds(50))
    await #expect(throws: ReportsError.busy) {
        _ = try await client.sendFeedback(draft, recent: nil, scope: .full, at: Date())
    }

    #expect(try await first == "fb_1")
    #expect(calls.count == 1)
}

// ── the crash outbox ──

private func outbox() -> CrashOutbox {
    CrashOutbox(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
}

private func crash(_ n: Int) -> CrashDraft {
    CrashDraft(crashId: CrashDraft.newId(), crashedAt: Date(timeIntervalSince1970: Double(n)),
               appVersion: "0.1.0 (6)", exception: "boom \(n)", systemReport: nil, systemReportKind: nil,
               recent: nil)
}

@Test func aPutCrashIsPendingUntilItIsSent() async throws {
    let box = outbox()
    try box.put(crash(1))
    try box.put(crash(2))

    #expect(box.pending().map(\.exception) == ["boom 1", "boom 2"])

    await box.send { _ in }

    #expect(box.pending().isEmpty)
}

@Test func aRefusedCrashIsRemovedBecauseItWouldBeRefusedAgain() async throws {
    let box = outbox()
    try box.put(crash(1))

    await box.send { _ in throw RPMError.refused(status: 400, reason: nil) }

    #expect(box.pending().isEmpty)
}

@Test func offlineOrAServerErrorKeepsTheCrashForTheNextLaunch() async throws {
    let box = outbox()
    try box.put(crash(1))

    await box.send { _ in throw RPMError.offline }
    #expect(box.pending().count == 1)

    await box.send { _ in throw RPMError.status(503) }
    #expect(box.pending().count == 1)
}

@Test func aCrashAtEveryLaunchKeepsOnlyTheNewest() throws {
    let box = outbox()
    for n in 1...(CrashOutbox.mostKept + 3) { try box.put(crash(n)) }

    let kept = box.pending()
    #expect(kept.count == CrashOutbox.mostKept)
    #expect(kept.first?.exception == "boom 4")
}

@Test func dontSendRemovesEverything() throws {
    let box = outbox()
    try box.put(crash(1))

    box.removeAll()

    #expect(box.pending().isEmpty)
}

@Test func consentIsAskedOnceThenFollowed() {
    #expect(CrashConsent.next(.unasked, waiting: 1) == .ask)
    #expect(CrashConsent.next(.unasked, waiting: 0) == .nothing)
    #expect(CrashConsent.next(.send, waiting: 2) == .send)
    #expect(CrashConsent.next(.dontSend, waiting: 2) == .nothing)
}

// ── the order of a launch ──

@MainActor
private func diagnostics(_ box: CrashOutbox, sent: Tally, scope: ReportScope = .full,
                         consent: CrashConsent = .unasked) -> Diagnostics {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    consent.write(defaults)
    let client = reports { request in
        sent.mark()
        return ok(request, "{}")
    }
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return Diagnostics(reports: client, outbox: box, spool: LogSpool(directory: dir, launched: Date()),
                       defaults: defaults, decide: { scope })
}

/// MetricKit can deliver before the scope is decided. Nothing is asked or sent until it is.
@MainActor
@Test func aCrashBeforeTheScopeIsDecidedWaitsForIt() async throws {
    let box = outbox()
    let sent = Tally()
    let diag = diagnostics(box, sent: sent, consent: .send)
    try box.put(crash(1))

    await diag.crashArrived()
    #expect(sent.count == 0)
    #expect(box.pending().count == 1)

    await diag.start()
    #expect(sent.count == 1)
    #expect(box.pending().isEmpty)
}

@MainActor
@Test func waitingCrashesAskOnceWhenNobodyHasAnswered() async throws {
    let box = outbox()
    let sent = Tally()
    let diag = diagnostics(box, sent: sent)
    try box.put(crash(1))

    await diag.start()
    #expect(diag.asksAboutCrashes)
    #expect(sent.count == 0)

    await diag.answer(send: false)
    #expect(!diag.asksAboutCrashes)
    #expect(!diag.sendsCrashReports)
    #expect(box.pending().isEmpty)
}

@MainActor
@Test func anAppStoreBuildOffersNoFeedback() async {
    let diag = diagnostics(outbox(), sent: Tally(), scope: .anonymous)
    #expect(!diag.offersFeedback)

    await diag.start()

    #expect(!diag.offersFeedback)
}

// ── the window's choices ──

@Test func theAreasStartWithOtherAndUseTheDesktopsValues() {
    #expect(FeedbackChoices.phoneAreas.map(\.value) ==
            ["other", "playback", "library", "downloads", "cloud", "radio", "casting", "interface"])
    #expect(FeedbackChoices.tvAreas.map(\.value) == ["other", "playback", "library", "radio", "interface"])
    #expect(FeedbackChoices.kinds.first?.value == "problem")
    #expect(FeedbackChoices.placeholderKey(kind: "idea") == "Feedback_PlaceholderIdea")
}

/// Every key the window shows is in the string table, so none appears on screen as its own name.
@Test func everyChoiceHasAString() {
    for choice in FeedbackChoices.kinds + FeedbackChoices.phoneAreas + FeedbackChoices.tvAreas {
        #expect(Loc.get(choice.key) != choice.key, "\(choice.key)")
    }
}

@Test func aScreenshotIsScaledToItsLongEdge() {
    #expect(ShotFit.scale(width: 1179, height: 2556, maxEdge: 1600) == 1600.0 / 2556)
    #expect(ShotFit.scale(width: 3840, height: 2160, maxEdge: 1600) == 1600.0 / 3840)
    #expect(ShotFit.scale(width: 1000, height: 800, maxEdge: 1600) == 1)
}
