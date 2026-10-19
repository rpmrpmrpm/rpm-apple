import Foundation
import RPMKit

/// The orders a wall of albums can be put in.
///
/// Persisted BY NAME, because the desktop remembers the wall's order in
/// settings.json: stored as a number, inserting an ordering would silently
/// re-point everybody's saved choice at its neighbour.
public enum AlbumOrdering: String, Sendable, CaseIterable, Codable {
    /// By whose record it is, then by its name. The order a shelf is in, and the
    /// default.
    case artist = "Artist"

    /// By the record's own name, whoever made it.
    case album = "Album"

    /// Most recently added first: what is new in the library.
    case added = "Added"

    /// Newest release first. Records with no year fall to the end rather than to
    /// 1900.
    case year = "Year"

    /// Most played first. Records never played fall to the end.
    case plays = "Plays"
}

/// What an ordering needs to know about one album, whatever type is holding it.
public struct AlbumFacts: Sendable, Equatable {
    public let album: String
    public let artist: String

    /// When the album joined, in whatever unit the head keeps time in: unix
    /// seconds from the cloud store, UTC ticks from the desktop's mirror. Only
    /// ever compared, never read, so the unit is the caller's business as long as
    /// it is consistent within one wall.
    public let addedAt: Int64

    /// Zero when nothing on the record is tagged with one.
    public let year: Int

    public let plays: Int

    public init(album: String, artist: String, addedAt: Int64 = 0, year: Int = 0, plays: Int = 0) {
        self.album = album; self.artist = artist
        self.addedAt = addedAt; self.year = year; self.plays = plays
    }
}

/// Putting a wall of albums in an order somebody asked for.
///
/// Here rather than beside the wall because every one of these has a tie to break
/// and a missing value to place, and those are the parts that are silently wrong:
/// sort by year and the untagged half of a library collects at the front
/// as if it were from 1900; sort by plays and everything never played arrives
/// first in whatever order the listing happened to be in. Each order below falls
/// back to artist and album, so a wall never reshuffles between two runs that
/// agree.
public enum AlbumSort {
    /// - Parameter factsOf: what the caller knows about each album. Generic
    ///   because the album type belongs to whichever head is drawing the wall, and
    ///   the rules do not.
    public static func by<T>(
        _ albums: [T], _ ordering: AlbumOrdering, factsOf: (T) -> AlbumFacts
    ) -> [T] {
        // Read once per album rather than once per comparison: for plays that is a
        // walk of the album's tracks, and a comparison sort would do it a few
        // thousand times over.
        let wall = albums.map { (album: $0, facts: factsOf($0)) }

        return wall.sorted { a, b in
            switch ordering {
            case .album:
                if let answer = name(a.facts.album, b.facts.album) { return answer }
                if let answer = name(a.facts.artist, b.facts.artist) { return answer }

            case .added:
                if a.facts.addedAt != b.facts.addedAt { return a.facts.addedAt > b.facts.addedAt }

            case .year:
                // Untagged LAST, and not merely sorted low: a library half of
                // which has no year would otherwise open on its own unlabelled
                // half every time.
                let aUntagged = a.facts.year == 0, bUntagged = b.facts.year == 0
                if aUntagged != bUntagged { return !aUntagged }
                if a.facts.year != b.facts.year { return a.facts.year > b.facts.year }

            case .plays:
                if a.facts.plays != b.facts.plays { return a.facts.plays > b.facts.plays }

            case .artist:
                break
            }

            // Every order falls back to the shelf order, so a wall never
            // reshuffles between two runs that agree.
            if let answer = name(a.facts.artist, b.facts.artist) { return answer }
            if let answer = name(a.facts.album, b.facts.album) { return answer }
            return false
        }
        .map(\.album)
    }

    /// When an album arrived: the newest of its tracks.
    ///
    /// Newest rather than oldest, because an album is added over the minutes or
    /// hours its tracks take to upload, and a record still going up should not sit
    /// below one that finished yesterday. It also does the right thing for a record
    /// somebody completed later: a missing track added this week makes the album
    /// this week's.
    public static func addedOf(_ tracks: [CloudTrack]) -> Int64 {
        tracks.reduce(Int64(0)) { Swift.max($0, $1.addedAt) }
    }

    /// The record's year: the one most of its tracks agree on.
    ///
    /// Most rather than first or highest. A compilation carries the year of each
    /// original recording on the track that came from it, and both the first row
    /// and the highest are then a year the record was not released in, while the
    /// tag the reissue actually carries is on most of the rows. Zero when nothing
    /// on it is tagged.
    public static func yearOf(_ tracks: [CloudTrack]) -> Int {
        var seen: [Int: Int] = [:]
        for track in tracks {
            guard let year = track.tags?.year, year > 0 else { continue }
            seen[year, default: 0] += 1
        }
        return yearFrom(seen.map { ($0.key, $0.value) })
    }

    /// The same rule, from years already counted: what a database can hand over
    /// without the caller walking a million track rows to re-count them. One
    /// implementation, so the wall on the desktop and the wall in the iOS app cannot
    /// disagree about what year a record is from.
    ///
    /// - Parameter counts: year to how many of the album's tracks carry it. An
    ///   empty sequence is an album nothing on which is tagged.
    public static func yearFrom(_ counts: [(year: Int, count: Int)]) -> Int {
        var best = 0
        var most = 0

        // Iterated in a fixed order, because the input may come from a dictionary
        // and Swift randomises that per process: without this, a genuine tie would
        // resolve differently on two runs of the same library.
        for (year, count) in counts.sorted(by: { $0.year < $1.year }) {
            guard year > 0 else { continue }

            // The earlier year wins a tie: a reissue tagged half one year and half
            // another is the record it was, not the pressing it came on.
            if count > most || (count == most && year < best) {
                best = year
                most = count
            }
        }

        return best
    }

    /// Case-insensitive and locale-aware, matching the `CurrentCultureIgnoreCase`
    /// the desktop orders a wall with. Nil where the two read the same, so the
    /// caller falls through to its next key.
    private static func name(_ a: String, _ b: String) -> Bool? {
        switch a.compare(b, options: .caseInsensitive, range: nil, locale: .current) {
        case .orderedAscending: return true
        case .orderedDescending: return false
        case .orderedSame: return nil
        }
    }
}
