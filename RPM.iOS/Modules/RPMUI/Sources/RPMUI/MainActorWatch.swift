import Foundation
import os

/// Reports when the main actor was blocked, and for how long.
///
/// **A stall can only be measured from the main actor itself.** This sleeps in a loop on
/// the main actor and logs how late each wake-up was. That one number separates "the main
/// actor was blocked" from "the main actor was free and something else was slow".
///
/// It cannot say what blocked the main actor. It says when and for how long, which tells
/// you where to point Instruments.
///
/// Off unless `RPM_MAIN_DIAG` is set. It costs one wake-up every 50 ms on the main actor,
/// which is small next to a frame, but it is not free.
@MainActor
public enum MainActorWatch {
    private static let log = Logger(subsystem: "com.rpm.player", category: "mainactor")

    /// How late a wake-up must be (in seconds) before it is logged. It is well above one
    /// dropped frame, because a single dropped frame is normal and a stall is not.
    private static let late = 0.15

    private static var running = false

    /// The gap between wake-ups. Short enough that a stall is logged while the gesture that
    /// caused it is still going on.
    private static let beat = Duration.milliseconds(50)

    public static func start() {
        guard ProcessInfo.processInfo.environment["RPM_MAIN_DIAG"] != nil else { return }
        guard !running else { return }
        running = true

        log.notice("watching the main actor: RPM_MAIN_DIAG is set")

        Task { @MainActor in
            var worst = 0.0
            var since = Date()

            while true {
                let asked = Date()
                try? await Task.sleep(for: beat)

                // Any time beyond the 50 ms that was asked for is time the main actor
                // was not free to run this task.
                let over = Date().timeIntervalSince(asked) - 0.05
                worst = max(worst, over)

                if over > late {
                    log.notice("main actor blocked \(over, format: .fixed(precision: 3))s")
                }

                guard Date().timeIntervalSince(since) > 10 else { continue }
                log.notice("10s: worst block \(worst, format: .fixed(precision: 3))s")
                worst = 0
                since = Date()
            }
        }
    }

    /// Logs what one search cost, and **how many times the wall had to be sorted to serve
    /// it**.
    ///
    /// The sort is the one step on this screen that is O(library size) and runs on the main
    /// actor. `SortedWall` is meant to sort once, so the count should not rise while the
    /// user types. A count that rises with every keystroke means a locale-aware compare
    /// per pair of records on the main actor.
    public static func searched(albums: Int, hits: Int, records: Int,
                                took: Double, sorts: Int) {
        guard ProcessInfo.processInfo.environment["RPM_MAIN_DIAG"] != nil else { return }

        let again = sorts - lastSorts
        lastSorts = sorts

        log.notice("""
            search of \(albums, privacy: .public) records took \(took, format: .fixed(precision: 3))s, \
            \(records) sleeves and \(hits) songs, wall re-sorted \(again) times
            """)
    }

    private static var lastSorts = 0
}
