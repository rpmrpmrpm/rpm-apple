import Foundation

/// What a person wrote in the Send feedback window, before it is sent.
public struct FeedbackDraft: Sendable, Equatable {
    /// "problem" or "idea" (`FeedbackKinds`).
    public var kind: String
    /// One of the values in `FeedbackAreas`.
    public var area: String
    public var message: String
    /// The screen as it was when the window opened, PNG. Nil when the person turned it off.
    public var screenshotPng: Data?
    /// The address a reply goes to, when the person is signed out and typed one.
    public var replyTo: String?

    public init(kind: String, area: String, message: String, screenshotPng: Data?, replyTo: String?) {
        self.kind = kind
        self.area = area
        self.message = message
        self.screenshotPng = screenshotPng
        self.replyTo = replyTo
    }

    /// Only a report with words in it can be sent: the server refuses an empty one.
    public var isSendable: Bool { !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// One crashed run, kept on disk by `CrashOutbox` until it is sent.
public struct CrashDraft: Codable, Sendable, Equatable {
    /// "crash_" and 24 hex digits, the server's shape. Made when the crash is recorded, so a second
    /// send of the same crash is recognised as a duplicate.
    public let crashId: String
    public let crashedAt: Date
    /// The build that crashed, which may not be the build that sends the report.
    public let appVersion: String
    public let exception: String?
    public let systemReport: String?
    /// "metrickit", or nil for a run that only ended without going to the background.
    public let systemReportKind: String?
    /// The crashed run's log, when a full-scope build had one.
    public let recent: String?

    public init(crashId: String, crashedAt: Date, appVersion: String, exception: String?,
                systemReport: String?, systemReportKind: String?, recent: String?) {
        self.crashId = crashId
        self.crashedAt = crashedAt
        self.appVersion = appVersion
        self.exception = exception
        self.systemReport = systemReport
        self.systemReportKind = systemReportKind
        self.recent = recent
    }

    public static func newId() -> String {
        var bytes = [UInt8](repeating: 0, count: 12)
        for i in bytes.indices { bytes[i] = UInt8.random(in: 0...255) }
        return "crash_" + bytes.map { String(format: "%02x", $0) }.joined()
    }
}

public enum ReportsError: Error, Equatable {
    /// A feedback report is already on its way. A second press of Send waits for that one instead
    /// of sending the same words twice.
    case busy
}

/// `POST /errors/feedback` and `POST /errors/crash`. Both take the app key alone, so a tester whose
/// sign-in is the broken thing can still report it; the token is sent when there is one.
///
/// Every send takes the `ReportScope`. An anonymous report has its log, screenshot and reply
/// address removed here, before anything is encoded.
public actor RPMReportsClient {
    private let transport: Transport
    private let facts: DeviceFacts
    private let installId: String
    private var sendingFeedback = false

    public init(transport: Transport, facts: DeviceFacts, installId: String) {
        self.transport = transport
        self.facts = facts
        self.installId = installId
    }

    /// Sends one feedback report and returns its id. Throws `ReportsError.busy` while another is on
    /// its way, and the transport's error when the server did not take it.
    public func sendFeedback(_ draft: FeedbackDraft, recent: String?, scope: ReportScope,
                             at: Date) async throws -> String {
        guard !sendingFeedback else { throw ReportsError.busy }
        sendingFeedback = true
        defer { sendingFeedback = false }

        let answer = try await transport.send(
            "POST", "errors/feedback", body: Self.feedbackBody(draft, recent: recent, scope: scope, at: at,
                                                              facts: facts, installId: installId),
            as: Filed.self)
        return answer.errorId
    }

    /// Sends one crash. Throws the transport's error when the server did not take it; the caller
    /// (`CrashOutbox`) decides from the error whether to keep the file.
    public func sendCrash(_ crash: CrashDraft, scope: ReportScope) async throws {
        try await transport.sendVoid(
            "POST", "errors/crash", body: Self.crashBody(crash, scope: scope, facts: facts, installId: installId))
    }

    struct Filed: Decodable { let errorId: String }

    /// The server's `FeedbackReportRequest`.
    struct FeedbackBody: Encodable, Equatable {
        let kind, area, message, head, appVersion, platform, architecture, installId: String
        let recent: String?
        let screenshotPng: String?
        let atUtcTicks: Int64
        let replyTo: String?
        let scope: String?
    }

    /// The server's `CrashReportRequest`.
    struct CrashBody: Encodable, Equatable {
        let crashId, head, appVersion, platform, architecture: String
        let crashedAtUtcTicks: Int64
        let installId: String
        let exception, systemReport, systemReportKind, recent, scope: String?
    }

    static func feedbackBody(_ d: FeedbackDraft, recent: String?, scope: ReportScope, at: Date,
                             facts: DeviceFacts, installId: String) -> FeedbackBody {
        let full = scope.isFull
        return FeedbackBody(
            kind: d.kind, area: d.area, message: d.message, head: facts.head, appVersion: facts.appVersion,
            platform: facts.platform, architecture: facts.architecture, installId: installId,
            recent: full ? recent : nil,
            screenshotPng: full ? d.screenshotPng?.base64EncodedString() : nil,
            atUtcTicks: ticks(at),
            replyTo: full ? d.replyTo : nil,
            scope: scope.wire)
    }

    static func crashBody(_ c: CrashDraft, scope: ReportScope, facts: DeviceFacts,
                          installId: String) -> CrashBody {
        CrashBody(
            crashId: c.crashId, head: facts.head, appVersion: c.appVersion, platform: facts.platform,
            architecture: facts.architecture, crashedAtUtcTicks: ticks(c.crashedAt), installId: installId,
            exception: c.exception, systemReport: c.systemReport, systemReportKind: c.systemReportKind,
            recent: scope.isFull ? c.recent : nil, scope: scope.wire)
    }

    /// .NET ticks (100 ns since 0001-01-01 UTC), which is how the server reads times from clients.
    static func ticks(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 10_000_000).rounded()) + 621_355_968_000_000_000
    }
}
