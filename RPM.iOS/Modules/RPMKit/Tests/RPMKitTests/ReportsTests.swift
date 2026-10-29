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
    await first.begin()
    await first.write("the run that crashed")

    let next = LogSpool(directory: dir, launched: Date())
    #expect(await next.previousRun() == nil)
    await next.begin()

    #expect(await next.previousRun() == "the run that crashed")
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
