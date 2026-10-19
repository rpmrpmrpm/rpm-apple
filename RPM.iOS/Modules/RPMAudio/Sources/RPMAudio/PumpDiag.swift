import Foundation
import os

/// Diagnostics for the pump loop: what it was doing when the sound broke up.
///
/// **It answers one question: was there audio queued in front of the node when the
/// stutter happened?** If the cushion ran down, the pump was not scheduled in time and the
/// fault is in this app (thread priority, a decode that took too long, a contended lock).
/// If the cushion stayed full and the sound still broke, the pump is not the cause. The
/// problem is further down, in the render cycle, where nothing here can reach it. The two
/// cases sound the same but need opposite fixes.
///
/// **The cushion is measured in seconds, not in buffers.** `PcmEngine.ahead` counts the
/// buffers in flight (eight), which is a second and a half only while every one is full.
/// `StreamedPcm.read` returns a short buffer whenever the converter has run out of input,
/// so the same eight buffers can hold a fifth of a second and the count does not change.
/// Frames scheduled minus frames played is true whenever it is asked.
///
/// Off unless `RPM_AUDIO_DIAG` is set. The reads it needs are inside that check: the
/// node's clock costs two calls into AVAudioEngine and this runs on every turn of the
/// pump.
final class PumpDiag {
    static let on = ProcessInfo.processInfo.environment["RPM_AUDIO_DIAG"] != nil

    private static let log = Logger(subsystem: "com.rpm.player", category: "pump")

    /// A cushion thinner than this (in seconds) is logged on its own line. It is well below
    /// the second and a half a full queue holds, and well above the fifth of a second the
    /// start of a track passes through.
    private static let thin = 0.5

    /// A turn of the loop that takes longer than this (in seconds) means the pump was not
    /// run on time, because no work in a turn should take even a tenth of a second.
    private static let slow = 0.25

    private var lastTurn: Date?
    private var since = Date()

    private var thinnest = Double.infinity
    private var longestGap = 0.0
    private var turns = 0

    /// Records one turn of the pump loop. `cushion` is the seconds of audio queued in front
    /// of the node at the start of the turn. It is nil while there is no clock to ask
    /// (paused, or before the node has started). That is not a thin cushion and is not
    /// counted as one.
    func turned(cushion: Double?, inFlight: Int) {
        let now = Date()
        turns += 1

        if let was = lastTurn {
            let gap = now.timeIntervalSince(was)
            longestGap = max(longestGap, gap)

            if gap > Self.slow {
                Self.log.notice("""
                    pump not run for \(gap, format: .fixed(precision: 3))s, \
                    cushion \(cushion ?? -1, format: .fixed(precision: 3))s, \
                    \(inFlight) in flight
                    """)
            }
        }
        lastTurn = now

        if let cushion {
            thinnest = min(thinnest, cushion)

            if cushion < Self.thin {
                Self.log.notice("""
                    cushion down to \(cushion, format: .fixed(precision: 3))s, \
                    \(inFlight) in flight
                    """)
            }
        }

        guard now.timeIntervalSince(since) > 10 else { return }

        Self.log.notice("""
            10s: thinnest cushion \(self.thinnest == .infinity ? -1 : self.thinnest, format: .fixed(precision: 3))s, \
            longest gap \(self.longestGap, format: .fixed(precision: 3))s, \
            \(self.turns) turns, qos \(Thread.current.qualityOfService.rawValue)
            """)

        since = now
        thinnest = .infinity
        longestGap = 0
        turns = 0
    }

    /// Logs once at start, so a log with no pump lines can be told apart from a run where
    /// the pump was not watched.
    static func announce() {
        guard on else { return }
        log.notice("watching the pump: RPM_AUDIO_DIAG is set")
    }
}
