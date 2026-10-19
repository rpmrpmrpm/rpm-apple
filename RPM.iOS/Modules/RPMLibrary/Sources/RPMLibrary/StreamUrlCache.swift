import Foundation
import RPMKit

/// Where a track streams from, and how long that address can be used.
///
/// A signed URL is valid only for a limited time. The two lifetimes below decide when a
/// stored URL must be discarded. If a URL is used after it expires, playback fails with
/// HTTP 403 in the middle of a song.
public final class StreamUrlCache: @unchecked Sendable {
    public struct Signed: Sendable, Equatable {
        public let url: URL

        /// The rate the store actually serves. This can differ from the rate that was
        /// requested. A free account is capped at a lower rate. A rendition that has not
        /// been made yet falls back to a lower one, so the user does not wait for a
        /// transcode.
        public let kilobits: Int

        /// Whether the URL points to a stored object or to a live encode in progress. A
        /// seek against a saved URL then uses the same method as the first request.
        public let kind: StreamKind

        public init(url: URL, kilobits: Int, kind: StreamKind) {
            self.url = url
            self.kilobits = kilobits
            self.kind = kind
        }
    }

    /// How long a URL is kept when it was served at the requested rate.
    public static let urlLife: TimeInterval = 4 * 60 * 60

    /// How long a URL is kept when it is a fallback or a live encode. It is kept for only
    /// a few minutes, so the app checks again for the real rendition.
    ///
    /// The life is a few minutes in both cases, for the same reason. A fallback is a lower
    /// rate that is served while the transcoder makes the requested rate. If it were kept
    /// for four hours, the app would keep playing the lower rate long after the requested
    /// rate was ready. A live address is served by the transcoder itself, and it stops being
    /// the right answer when its encode finishes. If it were kept for four hours, each play
    /// of that track would start another encode of a file that is already in the store.
    public static let fallbackLife: TimeInterval = 2 * 60

    /// The cache has a size limit. A phone that plays music all day must not keep one URL
    /// for every track it has ever played.
    public static let urlsKept = 400

    private struct Entry {
        let signed: Signed
        let until: Date
    }

    private let gate = NSLock()
    private var entries: [String: Entry] = [:]

    /// The clock is passed in. This lets tests check expiry without waiting four hours.
    /// It also means a phone that has been asleep is checked against the real clock. A
    /// timer would stop while the phone sleeps.
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    /// The key includes the rate as well as the track. The same track at two rates is two
    /// different objects. A cache that ignored the rate could return a URL at the wrong
    /// quality, for example one saved for a lower rate.
    private func key(_ rpmId: String, _ rate: Int) -> String { "\(rpmId)@\(rate)" }

    /// A URL that is still inside its lifetime, or `nil`.
    public func known(_ rpmId: String, rate: Int) -> Signed? {
        gate.lock()
        defer { gate.unlock() }

        guard let entry = entries[key(rpmId, rate)], entry.until > now() else { return nil }
        return entry.signed
    }

    /// Stores a new signed URL under the requested rate. Its lifetime depends on whether
    /// the store returned that same rate.
    public func note(_ rpmId: String, asked rate: Int, signed: Signed) {
        gate.lock()
        defer { gate.unlock() }

        // Entries are removed with no priority. Fetching any entry again costs the same
        // round trip.
        if entries.count >= Self.urlsKept { entries.removeAll(keepingCapacity: true) }

        // A live address is not settled, even when its rate matches the request, so it gets
        // the shorter life. Both short lives ask the same question: is the stored rendition
        // ready yet?
        let settled = signed.kilobits == rate && signed.kind == .stored
        let life = settled ? Self.urlLife : Self.fallbackLife
        entries[key(rpmId, rate)] = Entry(signed: signed, until: now().addingTimeInterval(life))
    }

    /// Called on sign-out, and when a shared shelf is removed. A URL signed for access
    /// that no longer exists fails with 403.
    public func forget() {
        gate.lock()
        entries.removeAll()
        gate.unlock()
    }

    var count: Int {
        gate.lock()
        defer { gate.unlock() }
        return entries.count
    }
}
