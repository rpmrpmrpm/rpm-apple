import Foundation
import SwiftUI
import os

/// Measures how long the app takes to show something on the screen.
///
/// A slow launch has three possible causes: the process starting, the first SwiftUI frame, or
/// the first layout of the wall. Each needs a different fix, and only some are caused by the
/// app. Measuring shows which one it is.
///
/// Time zero is the process start time from the kernel, and not a static initialiser in this
/// file. A `let` here runs when this module is first used, which is already after dyld has done
/// most of the work of a slow launch.
public enum LaunchClock {
    private static let log = Logger(subsystem: "com.rpm.player", category: "launch")

    /// When the process started, taken from the kernel's record.
    public static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, ProcessInfo.processInfo.processIdentifier]

        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return Date() }

        let started = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970:
            Double(started.tv_sec) + Double(started.tv_usec) / 1_000_000)
    }()

    /// Seconds since the process started.
    public static var elapsed: TimeInterval { Date().timeIntervalSince(processStart) }

    private static let seen = OSAllocatedUnfairLock(initialState: Set<String>())

    /// Logs a milestone once. Later calls with the same name are ignored, so a view body that
    /// runs six times reports the first run and not the last.
    public static func mark(_ what: String) {
        let first = seen.withLock { seen -> Bool in
            guard !seen.contains(what) else { return false }
            seen.insert(what)
            return true
        }
        guard first else { return }

        let at = elapsed
        log.notice("\(what, privacy: .public) at \(at, format: .fixed(precision: 3))s")
    }
}

/// Shows how long the launch took on the screen for a few seconds.
///
/// It is shown on the screen and not only in the log, so the number can be read on a phone
/// without a console.
public struct LaunchReadout: View {
    @State private var showing = true
    @State private var firstFrame: TimeInterval?

    public init() {}

    public var body: some View {
        Group {
            if showing, let firstFrame {
                Text("first frame \(firstFrame, format: .number.precision(.fractionLength(2)))s")
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.6), in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .task {
            firstFrame = LaunchClock.elapsed
            LaunchClock.mark("first frame")
            try? await Task.sleep(for: .seconds(6))
            showing = false
        }
    }
}
