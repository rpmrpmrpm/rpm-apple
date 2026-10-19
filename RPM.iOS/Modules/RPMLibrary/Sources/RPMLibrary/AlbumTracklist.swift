import Foundation

/// One disc of a record, and the rows on it in reading order.
public struct AlbumDiscSection<T>: Sendable where T: Sendable {
    public let discNumber: UInt
    public let tracks: [T]
}

/// How a record comes apart into discs.
///
/// One rule, shared by both heads, so they cannot disagree about where disc 2
/// starts. An unknown track position sorts last inside its own disc, not at the end
/// of the whole record, because the desktop lists the same rows that way.
public enum AlbumTracklist {
    /// Sections a record by disc, each disc in track order.
    ///
    /// An untagged disc reads as disc **1**, the same as an untagged file on the
    /// desktop. An untagged track sorts **last inside its own disc** rather than in
    /// front of track 1. The sort is stable, so ties keep the order the caller
    /// handed over.
    public static func byDisc<T: Sendable>(
        _ tracks: [T], discOf: (T) -> UInt, trackOf: (T) -> UInt
    ) -> [AlbumDiscSection<T>] {
        var byNumber: [UInt: [T]] = [:]
        for track in tracks {
            let disc = discOf(track) == 0 ? 1 : discOf(track)
            byNumber[disc, default: []].append(track)
        }

        return byNumber.keys.sorted().map { disc in
            // Swift's sort is NOT stable, so ties are broken on the original
            // index explicitly. Without it a disc of untagged files comes back in
            // whatever order the sort happened to leave them, which is a track
            // list that reshuffles itself between two draws of the same album.
            let rows = byNumber[disc]!
            let ordered = rows.enumerated()
                .sorted { a, b in
                    let ta = trackOf(a.element) == 0 ? UInt.max : trackOf(a.element)
                    let tb = trackOf(b.element) == 0 ? UInt.max : trackOf(b.element)
                    return ta == tb ? a.offset < b.offset : ta < tb
                }
                .map(\.element)

            return AlbumDiscSection(discNumber: disc, tracks: ordered)
        }
    }

    /// A disc's tracks as the runs of one work they are: a classical listing is
    /// not a list of tracks but a list of works, each with its movements under it.
    ///
    /// A run of CONSECUTIVE tracks, never everything that names the work. A recital
    /// that plays two nocturnes with a mazurka between them is three groups and not
    /// two, and a symphony whose last movement is on the next disc of a box is two
    /// groups, which is what the discs physically are.
    ///
    /// Tracks naming no work answer a group whose work is nil, so a record with no
    /// works in it at all is one anonymous group and a caller can take one shape
    /// for both. Call it per disc section: works do not span discs.
    public static func byWork<T: Sendable>(
        _ tracks: [T], workOf: (T) -> String?
    ) -> [(work: String?, tracks: [T])] {
        var groups: [(work: String?, tracks: [T])] = []

        for track in tracks {
            // Blank and nil are the same statement, "this is not part of
            // anything", and a listing that writes one where it means the other
            // must not open a second group.
            let named = workOf(track)
            let work = (named?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                ? nil : named

            if groups.isEmpty || groups[groups.count - 1].work != work {
                groups.append((work, []))
            }
            groups[groups.count - 1].tracks.append(track)
        }

        return groups
    }
}
