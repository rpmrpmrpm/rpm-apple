import Foundation
import RPMKit

/// One pass over radio listening: take in what the listener's other devices have heard, then send what
/// this phone has heard.
///
/// It is the same pass as `PlaysSync` in RPMLibrary, applied to ``RadioListens``. The pass pulls first,
/// so rows that were just taken in are not sent back. Nothing retries. What is sent is a running
/// total, so the next pass sends the same total again.
public enum StationListensSync {
    /// How many rows one pass may send. This is the store's own per-request limit.
    public static let perPass = 200

    /// - Returns: how many rows arrived from other devices, so the caller knows whether anything drawn
    ///   from the log is out of date.
    @discardableResult
    public static func run(log: RadioListens, client: RPMCloudClient) async -> Int {
        // `pass` is nil when the log could not be read this session, or when the device name cannot be
        // saved. Syncing under a name that does not persist would bring this phone's own rows back later,
        // as if they came from another device. The pass is taken before the first `await`. After that, a
        // sign-out makes everything this pass brings back, and everything it would send, do nothing.
        guard let pass = await log.pass() else { return 0 }
        let mine = pass.device

        // ── in ──
        let taken: Int
        do {
            let theirs = try await client.stationListens(since: await log.cursor)
            taken = await log.apply(theirs, in: pass)

            // The cursor moves on what arrived, not on what was taken in. Most arriving rows are this
            // phone's own rows, which are not taken in.
            if let newest = theirs.map(\.updatedAt).max() { await log.noteCursor(newest, in: pass) }
        } catch {
            // Offline, signed out, or a store that would not answer. The next pass asks again.
            return 0
        }

        // ── out ──
        let due = await log.unsent(limit: perPass, in: pass)
        guard !due.isEmpty else { return taken }

        do {
            _ = try await client.sendStationListens(deviceId: mine, rows: due)

            // The rows as they were sent. A listen noted after the read is still unsent.
            await log.noteSent(due, in: pass)
        } catch {
            // Not recorded as sent, so the same totals go again next pass.
        }

        return taken
    }
}
