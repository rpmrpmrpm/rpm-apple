import Foundation
import RPMKit

/// One line of an album's tracklist: a disc divider, the heading of a work, or a
/// song.
///
/// Ported from the desktop's `AlbumTrackItem.Build`, so the two heads draw a
/// classical record the same way: a list of works, each with its movements under
/// it, and the pieces that are a work on their own at the same level as the work
/// headings.
public enum AlbumLine: Sendable, Equatable, Identifiable {
    /// "Disc 2", in front of each disc of a set. Never on a single-disc record.
    case disc(UInt)

    /// The line that opens a work of more than one track. Not a song: nothing plays
    /// from it.
    case work(AlbumWorkHeading)

    /// A song.
    case song(AlbumSongLine)

    public var id: String {
        switch self {
        case .disc(let number): return "disc:\(number)"
        case .work(let heading): return heading.id
        case .song(let line): return line.track.rpmId
        }
    }
}

/// A work's heading: its name, who wrote it, and how long the whole piece runs.
public struct AlbumWorkHeading: Sendable, Equatable {
    public let title: String

    /// Nil when the tracks under it name no composer, or disagree. A pasticcio and a
    /// badly tagged box both disagree, and printing the first track's answer for all
    /// of them would be the list making something up.
    public let composer: String?

    public let duration: Duration

    /// The first movement's id, which no other line carries in this form.
    public let id: String
}

/// Which level of the listing a song is on.
public enum AlbumSongLevel: Sendable, Equatable {
    /// An ordinary record's song.
    case plain

    /// A whole piece on a classical record: a track that is part of no work, or the
    /// only track of one. Drawn at the level and weight of a work heading, because
    /// that is what it is.
    case piece

    /// One movement of the work heading above it. Indented, and named by the
    /// movement alone.
    case movement
}

public struct AlbumSongLine: Sendable, Equatable {
    public let track: CloudTrack

    /// What the line says: the movement alone under a work heading, the file's
    /// title everywhere else.
    public let title: String

    /// The small line under the title. The composer on a classical piece, nil on a
    /// movement (the heading has said it), and left to the page on a plain record.
    public let subtitle: String?

    public let level: AlbumSongLevel
}

public enum AlbumLines {
    /// A record's lines in reading order: disc by disc, with a divider in front of
    /// each disc of a set.
    ///
    /// - Parameter classical: whether the listener marked the record classical.
    ///   **No default.** A record is drawn as works because somebody said it is
    ///   classical, never because its tags look the part: MusicBrainz names a work
    ///   for most pop songs too.
    public static func build(_ tracks: [CloudTrack], classical: Bool) -> [AlbumLine] {
        let discs = AlbumTracklist.byDisc(tracks, discOf: AlbumGrouping.disc(of:),
                                          trackOf: AlbumGrouping.track(of:))
        var lines: [AlbumLine] = []

        for disc in discs {
            if discs.count > 1 { lines.append(.disc(disc.discNumber)) }

            if classical {
                lines.append(contentsOf: works(disc.tracks))
            } else {
                lines.append(contentsOf: disc.tracks.map {
                    .song(AlbumSongLine(track: $0, title: $0.title ?? "", subtitle: nil, level: .plain))
                })
            }
        }

        return lines
    }

    /// One disc of a classical record: works with their movements under them, and
    /// the pieces that are a work on their own.
    private static func works(_ tracks: [CloudTrack]) -> [AlbumLine] {
        var lines: [AlbumLine] = []

        for group in AlbumTracklist.byWork(tracks, workOf: { $0.tags?.work }) {
            // A one-track work has no heading: the track's own line already says the
            // whole name, and a heading over a single line repeats what it heads.
            guard let work = group.work, group.tracks.count > 1 else {
                lines.append(contentsOf: group.tracks.map {
                    .song(AlbumSongLine(track: $0, title: $0.title ?? "",
                                        subtitle: composer(of: $0), level: .piece))
                })
                continue
            }

            lines.append(.work(AlbumWorkHeading(
                title: work,
                composer: agreed(group.tracks.map(composer(of:))),
                duration: .seconds(group.tracks.reduce(0.0) { $0 + ($1.tags?.durationSeconds ?? 0) }),
                id: "work:" + group.tracks[0].rpmId)))

            lines.append(contentsOf: group.tracks.map {
                .song(AlbumSongLine(track: $0, title: movement(of: $0, in: work) ?? $0.title ?? "",
                                    subtitle: nil, level: .movement))
            })
        }

        return lines
    }

    /// What a movement's own line says, under a work that has already said the rest.
    ///
    /// A file's title carries the whole name, "Sonata In C Major, KV. 330: Allegretto",
    /// because everything that has never heard of a work reads that field. Under the
    /// heading it would say the sonata's name three times over, so the movement is
    /// shown alone: the tag where the file has one, and otherwise whatever the title
    /// has left once the work in front of it is taken off. Nil when neither says, and
    /// the caller shows the whole title.
    static func movement(of track: CloudTrack, in work: String) -> String? {
        if let named = track.tags?.movementName, !isBlank(named) { return named }

        guard let title = track.title,
              let prefix = title.range(of: work, options: [.caseInsensitive, .anchored])
        else { return nil }

        // Cut at the end of the match rather than at the work's length: a
        // case-insensitive match need not be the same number of characters.
        let rest = title[prefix.upperBound...]
            .drop { " :-\u{2013}\u{2014}".contains($0) }
        return rest.isEmpty ? nil : String(rest)
    }

    private static func composer(of track: CloudTrack) -> String? {
        guard let named = track.tags?.composer, !isBlank(named) else { return nil }
        return named
    }

    /// The one answer every track gives, ignoring case, or nil.
    private static func agreed(_ answers: [String?]) -> String? {
        guard let first = answers.first, let first else { return nil }
        let all = answers.allSatisfy { $0?.caseInsensitiveCompare(first) == .orderedSame }
        return all ? first : nil
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
