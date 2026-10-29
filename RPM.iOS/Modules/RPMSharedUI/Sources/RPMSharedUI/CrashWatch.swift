import Foundation
import CryptoKit
import RPMKit
#if os(iOS)
import MetricKit
#endif

/// Records the app's crashes in the `CrashOutbox`, so `Diagnostics` can send them.
///
/// - iPhone: MetricKit delivers the system's crash diagnostic for an earlier run, usually at the
///   next launch. It is stored with the log of the run before this one.
/// - Both apps: an uncaught Objective-C exception is written with its name, reason and stack, and
///   this run's log, before the app ends.
/// - Apple TV: MetricKit is not available on tvOS. A run that ended while it was on screen, without
///   going to the background first, is filed at the next launch as ended unexpectedly, with that
///   run's log. A Debug build skips this, because stopping the app in Xcode ends it on screen.
public enum CrashWatch {
    /// Call once at launch, before the app's model starts. It moves the last run's log copy aside
    /// first, so every handler installed after it reads the right run. `arrived` is called on the
    /// main actor when a crash has been put in the outbox while the app runs.
    @MainActor
    public static func install(arrived: @escaping @MainActor @Sendable () -> Void) {
        LogSpool.shared.rotate()

        previousHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { exception in CrashWatch.record(exception) }

        #if os(iOS)
        let watch = MetricWatch(arrived: arrived)
        metricWatch = watch
        MXMetricManager.shared.add(watch)
        #endif

        #if os(tvOS) && !DEBUG
        if OnScreen.wasSet {
            try? CrashOutbox.shared.put(CrashDraft(
                crashId: CrashDraft.newId(), crashedAt: OnScreen.setAt ?? Date(),
                appVersion: DeviceFacts.current.appVersion,
                exception: "Ended while on screen, without going to the background first.",
                systemReport: nil, systemReportKind: nil, recent: LogSpool.shared.previousRun()))
            OnScreen.clear()
        }
        #endif
    }

    /// The scene is on screen. On the Apple TV this sets the on-screen mark.
    @MainActor
    public static func sceneBecameActive() {
        #if os(tvOS) && !DEBUG
        OnScreen.set()
        #endif
    }

    /// The scene went to the background. The mark is cleared: the system may end a background app
    /// at any time, and that is not a crash.
    @MainActor
    public static func sceneWentToBackground() {
        OnScreen.clear()
    }

    nonisolated(unsafe) private static var previousHandler: (@convention(c) (NSException) -> Void)?

    #if os(iOS)
    @MainActor private static var metricWatch: MetricWatch?
    #endif

    /// Runs on the thread that threw, while the app is ending. Only synchronous file work.
    private static func record(_ exception: NSException) {
        let stack = exception.callStackSymbols.joined(separator: "\n")
        try? CrashOutbox.shared.put(CrashDraft(
            crashId: CrashDraft.newId(), crashedAt: Date(), appVersion: DeviceFacts.current.appVersion,
            exception: "\(exception.name.rawValue): \(exception.reason ?? "")\n\(stack)",
            systemReport: nil, systemReportKind: nil, recent: LogSpool.shared.thisRun()))
        // The exception is already in the outbox, so the next launch must not file the same end again.
        OnScreen.clear()
        previousHandler?(exception)
    }
}

/// The Apple TV's mark that the app was on screen: a file that exists from the scene becoming
/// active until it goes to the background.
enum OnScreen {
    static var url: URL { LogSpool.shared.directory.appendingPathComponent("on-screen") }

    static func set() {
        try? FileManager.default.createDirectory(at: LogSpool.shared.directory, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }

    static func clear() { try? FileManager.default.removeItem(at: url) }

    static var wasSet: Bool { FileManager.default.fileExists(atPath: url.path) }

    static var setAt: Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

#if os(iOS)
/// MetricKit's crash diagnostics, as crash drafts. MetricKit calls this on a queue of its own.
private final class MetricWatch: NSObject, MXMetricManagerSubscriber, Sendable {
    private let arrived: @MainActor @Sendable () -> Void

    init(arrived: @escaping @MainActor @Sendable () -> Void) { self.arrived = arrived }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        var put = false
        for payload in payloads {
            for crash in payload.crashDiagnostics ?? [] {
                let json = crash.jsonRepresentation()
                try? CrashOutbox.shared.put(CrashDraft(
                    crashId: Self.id(json), crashedAt: payload.timeStampEnd,
                    appVersion: Self.version(crash.metaData.applicationBuildVersion),
                    exception: Self.headline(crash),
                    systemReport: String(decoding: json, as: UTF8.self), systemReportKind: "metrickit",
                    recent: LogSpool.shared.previousRun()))
                put = true
            }
        }
        if put { Task { @MainActor [arrived] in arrived() } }
    }

    /// The same diagnostic gives the same id, so the server files a second delivery as a duplicate.
    private static func id(_ json: Data) -> String {
        "crash_" + SHA256.hash(data: json).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    /// MetricKit gives the build number only. The running build's full version is used when the
    /// numbers match.
    private static func version(_ build: String) -> String {
        let current = DeviceFacts.current.appVersion
        return current.hasSuffix("(\(build))") ? current : "(\(build))"
    }

    /// One line for the queue: what the system says ended the app.
    private static func headline(_ crash: MXCrashDiagnostic) -> String {
        var parts: [String] = []
        if let type = crash.exceptionType { parts.append("exception type \(type)") }
        if let code = crash.exceptionCode { parts.append("code \(code)") }
        if let signal = crash.signal { parts.append("signal \(signal)") }
        if let reason = crash.exceptionReason {
            parts.append("\(reason.exceptionName): \(reason.composedMessage)")
        }
        if let reason = crash.terminationReason { parts.append(reason) }
        return "MetricKit crash: " + (parts.isEmpty ? "no details" : parts.joined(separator: ", "))
    }
}
#endif
