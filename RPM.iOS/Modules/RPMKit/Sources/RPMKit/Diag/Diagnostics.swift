import Foundation
import Observation

/// The app's side of Send feedback and crash reports: the scope, the waiting crashes, the consent
/// prompt and the log copy. One per app, made by the app model.
///
/// **Nothing is sent before the scope is decided.** `start()` decides it and only then looks at the
/// waiting crashes. A crash that arrives earlier (MetricKit can deliver as soon as the app
/// subscribes) is put in the outbox and waits for `start()`; one that arrives later is looked at
/// when `crashArrived()` is called. Either order ends the same way.
@MainActor
@Observable
public final class Diagnostics {
    /// Anonymous until `start()` has decided.
    public private(set) var scope: ReportScope = .anonymous

    /// True while the consent prompt should be on screen.
    public private(set) var asksAboutCrashes = false

    /// The Apple TV's screenshot for Send feedback. Its settings are a tab, so the picture is
    /// taken when that tab opens, while the screen the tester came from is still drawn, and kept
    /// here until the feedback screen opens. Not observed: nothing on screen draws from it.
    @ObservationIgnored public var heldShot: Data?

    private let reports: RPMReportsClient
    private let outbox: CrashOutbox
    private let spool: LogSpool
    private let defaults: UserDefaults
    private let decide: @Sendable () async -> ReportScope
    private let launched = Date()
    private var decided = false

    public convenience init(transport: Transport) {
        self.init(reports: RPMReportsClient(transport: transport, facts: .current, installId: InstallId.value),
                  outbox: .shared, spool: .shared, defaults: .standard, decide: { await ReportScope.decide() })
    }

    init(reports: RPMReportsClient, outbox: CrashOutbox, spool: LogSpool, defaults: UserDefaults,
         decide: @escaping @Sendable () async -> ReportScope) {
        self.reports = reports
        self.outbox = outbox
        self.spool = spool
        self.defaults = defaults
        self.decide = decide
    }

    /// Send feedback is offered only by a build whose reports are full.
    public var offersFeedback: Bool { scope.isFull }

    /// The Send crash reports switch in the settings.
    public var sendsCrashReports: Bool {
        get { CrashConsent.read(defaults) == .send }
        set { (newValue ? CrashConsent.send : .dontSend).write(defaults) }
    }

    public func start() async {
        scope = await decide()
        decided = true
        if scope.isFull { keepTheLog() }
        await settleCrashes()
    }

    /// A crash handler put a report in the outbox.
    public func crashArrived() async {
        await settleCrashes()
    }

    /// The scene is no longer active: the log copy is brought up to date, in case the app does not
    /// come back.
    public func sceneLeftActive() {
        guard scope.isFull else { return }
        Task { await spool.flush() }
    }

    /// The answer to the consent prompt.
    public func answer(send: Bool) async {
        asksAboutCrashes = false
        sendsCrashReports = send
        if send { await sendCrashes() } else { outbox.removeAll() }
    }

    public enum Sent: Equatable, Sendable { case sent, failed, busy }

    public func sendFeedback(_ draft: FeedbackDraft) async -> Sent {
        let recent = scope.isFull ? await LogTail.current(since: launched) : nil
        do {
            _ = try await reports.sendFeedback(draft, recent: recent, scope: scope, at: Date())
            return .sent
        } catch ReportsError.busy {
            return .busy
        } catch {
            return .failed
        }
    }

    private func settleCrashes() async {
        guard decided else { return }
        switch CrashConsent.next(CrashConsent.read(defaults), waiting: outbox.pending().count) {
        case .nothing: break
        case .ask: asksAboutCrashes = true
        case .send: await sendCrashes()
        }
    }

    private func sendCrashes() async {
        let scope = scope
        await outbox.send { [reports] crash in try await reports.sendCrash(crash, scope: scope) }
    }

    /// Every 60 seconds while the app runs. A suspended app does not run the loop, which is why
    /// `sceneLeftActive()` also flushes.
    private func keepTheLog() {
        Task { [spool] in
            while !Task.isCancelled {
                await spool.flush()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
}
