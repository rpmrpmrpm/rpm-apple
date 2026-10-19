import Foundation

/// Tracks whose rendition the store has not made yet, and when to ask about each one
/// again.
///
/// A track is signed (a playable URL is requested for it) at a rate the store has not
/// made before. In that case the store answers with a live encode, served by the
/// transcoder while it sends. That is correct for playback and wrong for a download.
/// A live encode that stops part way has already returned success. The download would
/// then save a cut-off track as if it were complete. So a download never uses a live
/// address. It asks the store to make the rendition, asks again after a delay that
/// grows, and downloads the stored object once the store has it. The store lists a
/// rate as made only after the whole object is in place.
///
/// This type only does bookkeeping. The time is passed in, so it can be tested
/// without a session. It is owned by ``AlbumDownloads`` on the main actor.
struct RenditionWait {
    /// What the store said about one track, as far as the caller needs to act on it.
    enum Said: Equatable {
        /// The track has not been waited on before at this rate. The caller signs the
        /// next tracks straight away instead of waiting for the delay.
        case new

        /// Still being made, and still inside the time allowed.
        case waiting

        /// Waited longer than ``giveUp``. The caller counts this as a failed attempt.
        /// The wait starts again and the store is asked again, in case the first
        /// request was lost.
        case overdue
    }

    /// The first repeat ask comes after this many seconds. Each following delay is
    /// double the one before, up to ``longest``. An album of twelve tracks takes the
    /// transcoder about a minute. Asking every fifteen seconds at first finds the
    /// rendition soon after it is ready.
    static let first: TimeInterval = 15
    static let longest: TimeInterval = 60

    /// How long one track may wait before the wait counts as failed. The time is
    /// measured on the wall clock, so time the app spends suspended is included. A
    /// track that is still not made after this long is one the transcoder is failing
    /// on.
    static let giveUp: TimeInterval = 600

    private struct Entry {
        let kilobits: Int
        var since: Date
        var next: Date
        var gap: TimeInterval

        /// Whether the store has been asked to make it at ``kilobits`` since the wait
        /// began.
        var asked: Bool
    }

    private var entries: [String: Entry] = [:]

    /// Tracks the store was asked to make before their own sign request answered, with
    /// the rate for each. A track in here that then answers with a live encode starts
    /// its wait already marked as asked.
    private var ahead: [String: Int] = [:]

    /// Whether to sign this track now at this rate. A track waited on at a different
    /// rate is due at once. The rate setting has changed, so the old wait says nothing
    /// about the new rate.
    func isDue(_ rpmId: String, kilobits: Int, now: Date) -> Bool {
        guard let entry = entries[rpmId], entry.kilobits == kilobits else { return true }
        return now >= entry.next
    }

    /// Whether a track is waiting for the store at any rate. This is what makes an album
    /// show as preparing rather than downloading.
    func isWaiting(_ rpmId: String) -> Bool { entries[rpmId] != nil }

    /// Whether anything is waiting at all.
    var isEmpty: Bool { entries.isEmpty }

    /// The store answered a sign request for this track with a live encode.
    mutating func stillMaking(_ rpmId: String, kilobits: Int, now: Date) -> Said {
        guard var entry = entries[rpmId], entry.kilobits == kilobits else {
            entries[rpmId] = Entry(kilobits: kilobits, since: now,
                                   next: now.addingTimeInterval(Self.first),
                                   gap: Self.first, asked: ahead[rpmId] == kilobits)
            return .new
        }

        if now.timeIntervalSince(entry.since) > Self.giveUp {
            entry.since = now
            entry.gap = Self.first
            entry.next = now.addingTimeInterval(Self.first)
            entry.asked = false
            entries[rpmId] = entry
            return .overdue
        }

        entry.gap = min(entry.gap * 2, Self.longest)
        entry.next = now.addingTimeInterval(entry.gap)
        entries[rpmId] = entry
        return .waiting
    }

    /// The tracks the store has not yet been asked to make, grouped by rate. One ask
    /// names one rate only, so the tracks are grouped by rate.
    var unasked: [Int: [String]] {
        var byRate: [Int: [String]] = [:]
        for (rpmId, entry) in entries where !entry.asked {
            byRate[entry.kilobits, default: []].append(rpmId)
        }
        return byRate.mapValues { $0.sorted() }
    }

    /// The store accepted the ask for these tracks at this rate. If a track's wait was
    /// dropped, or restarted at another rate while the ask was in progress, its entry is
    /// left unchanged.
    mutating func asked(_ rpmIds: [String], kilobits: Int) {
        for rpmId in rpmIds where entries[rpmId]?.kilobits == kilobits {
            entries[rpmId]?.asked = true
        }
    }

    /// Whether the store has been asked to make this track at this rate, either through
    /// its own wait or ahead of it.
    func wasAsked(_ rpmId: String, kilobits: Int) -> Bool {
        if let entry = entries[rpmId], entry.kilobits == kilobits, entry.asked { return true }
        return ahead[rpmId] == kilobits
    }

    /// The store accepted an ask for tracks that have not yet answered a sign request
    /// themselves.
    mutating func askedAhead(_ rpmIds: [String], kilobits: Int) {
        for rpmId in rpmIds { ahead[rpmId] = kilobits }
    }

    /// The store has the rendition, the track is no longer wanted, or it is being
    /// retried from the start. The wait for it ends, and so does any earlier ask made
    /// ahead for it.
    mutating func forget<S: Sequence>(_ rpmIds: S) where S.Element == String {
        for rpmId in rpmIds {
            entries[rpmId] = nil
            ahead[rpmId] = nil
        }
    }

    mutating func forgetAll() {
        entries = [:]
        ahead = [:]
    }

    /// When the next track is due to be asked about. `nil` when nothing is waiting.
    var nextCheck: Date? { entries.values.map(\.next).min() }
}
