import Foundation
import RPMKit

/// One sync pass for the play counts. It first receives the play counts from the
/// user's other devices, then sends the counts this phone has not sent yet.
///
/// **Receiving comes first.** Counts that have been received do not need to be
/// sent back from this phone. The desktop app runs its pass in the same order.
///
/// **This code does not retry, and it does not reconcile.** A pass that fails
/// leaves all the data as it was. The next pass repeats the same work, which is safe
/// because each row sent is a total: the store writes the same number again. See
/// the Lambda's `TrackPlayStore`.
public enum PlaysSync {
    /// The number of rows one pass may send. This matches the store's per-request
    /// limit.
    public static let perPass = 200

    public static func run(log: PlayLog, client: RPMCloudClient, mine: String) async {
        // The pass is taken before the first `await`. If the user signs out at any point
        // after this, everything this pass receives and everything it would send does
        // nothing. See PlayLog.Pass.
        let pass = await log.pass()

        // ── in ──
        do {
            let theirs = try await client.trackPlays(since: await log.cursor)

            // `apply` drops this phone's own rows, because they are already counted here.
            // Taking one in would count it twice. Rows for tracks this phone has never
            // seen are kept. On a cold launch the play rows arrive before the library
            // listing does.
            await log.apply(theirs, mine: mine, in: pass)

            // The cursor moves forward based on what ARRIVED, not on what was applied.
            // Most received rows are this phone's own rows, or rows it already holds. If
            // the cursor moved only for the rest, a listener with no other device would
            // request their whole history on every launch.
            if let newest = theirs.map(\.updatedAt).max() {
                await log.noteCursor(newest, in: pass)
            }
        } catch {
            // The device is offline, signed out, or the store did not answer. The counts
            // stay in the log, and the next pass asks again.
            return
        }

        // ── out ──
        let due = await log.unsent(limit: perPass, in: pass)
        guard !due.isEmpty else { return }

        do {
            _ = try await client.sendTrackPlays(deviceId: mine, rows: due)

            // The rows are marked as sent using the values that were SENT, not the current
            // values. A play counted after the read is still unsent, so it goes in the
            // next pass. See PlayLog.noteSent.
            await log.noteSent(due, in: pass)
        } catch {
            // The rows are not marked as sent. The same totals are sent again on the next
            // pass.
        }
    }
}
