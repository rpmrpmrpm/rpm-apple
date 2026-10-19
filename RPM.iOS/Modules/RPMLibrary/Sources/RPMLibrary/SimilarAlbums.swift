import Foundation
import RPMKit

/// A record on the shelf, as the ranking reads it.
public struct AlbumTraits: Sendable, Equatable {
    public let key: String
    public let album: String
    public let artist: String
    public let genres: [String]
    public let year: Int

    public init(key: String, album: String, artist: String, genres: [String], year: Int) {
        self.key = key; self.album = album; self.artist = artist
        self.genres = genres; self.year = year
    }
}

/// Why a record is suggested. The reasons are in order of how much they explain. The
/// first one that applies is the reason shown on the card.
public enum SimilarBecause: Sendable {
    /// A different act with similar music. Their catalogues are filed under the same
    /// genres.
    case likeTheArtist
    /// The two records share a genre, whoever made them.
    case sameGenre
    /// The only link is the year. This is the weakest reason, and the card says so.
    case sameEra
    /// There is nothing to compare. Neither record has genres, and neither has a year.
    case justOnTheShelf
}

/// One card in a similar-albums row: a record on this shelf, and the reason it was
/// picked.
public struct SimilarAlbum: Sendable, Equatable {
    public let title: String
    public let artist: String
    public let key: String
    /// The reason the record is in the row. This is not a score. A reader does not
    /// need a number, and a number cannot be checked by looking at the row.
    public let why: SimilarBecause
}

/// The records to show under an album. These are other records **on this shelf**
/// that the listener may want to play next.
///
/// This is the same rule set as the desktop app's `RPM.Core/Metadata/SimilarAlbums.cs`.
/// The key is the album key, not the folder.
///
/// **Three axes, weighted and added.** Each axis is used only when both records can
/// answer it. The axes are: the genres of the two records, the genres of the two acts
/// pooled over everything they made, and the era. A record with no year is not
/// treated as being from a distant era. Its era is unknown, so the era axis is not
/// used for it. Scoring it as zero would rank records by how completely they are
/// tagged.
///
/// **Look somewhere else, not at more of the same.** The act whose record is open is
/// left out of its own row. No act appears twice while another act is still waiting
/// to be shown.
public enum SimilarAlbums {
    public static let defaultCount = 9

    /// The number of records one act may have in the row before every other act has
    /// had one.
    public static let preferredPerAct = 1

    /// The gap between two years at which the era axis reaches 0.
    public static let eraSpan = 25

    private static let artistGenreWeight = 1.5
    private static let albumGenreWeight = 2.0
    private static let eraWeight = 1.0

    public static func pick(subject: AlbumTraits, library: [AlbumTraits],
                            count: Int) -> [SimilarAlbum] {
        guard count > 0 else { return [] }

        let subjectKey = fold(subject.artist)
        var byArtist = poolGenresByArtist(library)

        // The subject's own genres are added to its act's pool here. They are normally
        // on the shelf already. Adding them here keeps the similar-artists axis working
        // for callers that leave the subject out of the list. Without this, the axis
        // would silently do nothing for those callers.
        if !subject.genres.isEmpty {
            byArtist[subjectKey, default: []].formUnion(subject.genres)
        }

        let subjectArtistGenres = byArtist[subjectKey] ?? []

        var seen: Set<String> = [identity(subject.artist, subject.album)]
        var scored: [(album: AlbumTraits, score: Double, why: SimilarBecause)] = []

        for other in library {
            if other.album.trimmingCharacters(in: .whitespaces).isEmpty { continue }

            // Skip the subject's own act. A listener who opened this record wants to go
            // somewhere else. The rest of the act's records are one tap away on their page.
            if fold(other.artist) == subjectKey { continue }

            // The same album can be on the shelf twice, for example when it was imported
            // and also downloaded. That is still one record.
            if !seen.insert(identity(other.artist, other.album)).inserted { continue }

            let otherArtistGenres = byArtist[fold(other.artist)] ?? []

            scored.append((
                other,
                score(subject, other, subjectArtistGenres, otherArtistGenres),
                because(subject, other, subjectArtistGenres, otherArtistGenres)))
        }

        // Highest score first. The key breaks ties, so opening the same record twice gives
        // the same row.
        scored.sort { a, b in
            a.score == b.score ? a.album.key < b.album.key : a.score > b.score
        }

        // Two rounds are used, not one counter. Round one takes the best record of each
        // act, in the order the acts appear. Round two fills any places left on a short
        // shelf, best first, with no limit per act. With one counter, an act would take a
        // second card as soon as its first was added. An act with three near-identical
        // records could then fill three cards.
        //
        // Taken records are tracked by key, not by act. If they were tracked by act, round
        // two would pick again every record that round one had already picked.
        var picked: [SimilarAlbum] = []
        var acts: [String: Int] = [:]
        var taken: Set<String> = []

        for round in 0..<2 {
            if picked.count >= count { break }

            for entry in scored {
                if picked.count >= count { break }
                if taken.contains(entry.album.key) { continue }

                let act = fold(entry.album.artist)
                let already = acts[act] ?? 0
                if round == 0 && already >= preferredPerAct { continue }

                acts[act] = already + 1
                taken.insert(entry.album.key)
                picked.append(SimilarAlbum(title: entry.album.album, artist: entry.album.artist,
                                           key: entry.album.key, why: entry.why))
            }
        }

        return picked
    }

    /// How alike two records are, from 0 to 1.
    ///
    /// Each axis is used only when both records can answer it. The total is divided
    /// by the weight of the axes that were used. This stops a record with missing tags
    /// from being scored lower only because its data is missing.
    ///
    /// There is no mood term. A mood term would have to score 0 when the records have no
    /// mood data, and 0 means the two records feel nothing alike. The app has no basis
    /// for that claim.
    private static func score(_ subject: AlbumTraits, _ other: AlbumTraits,
                              _ subjectArtistGenres: Set<String>,
                              _ otherArtistGenres: Set<String>) -> Double {
        var total = 0.0
        var asked = 0.0

        func ask(_ weight: Double, _ value: Double) {
            total += weight * value
            asked += weight
        }

        if !subjectArtistGenres.isEmpty && !otherArtistGenres.isEmpty {
            ask(artistGenreWeight, overlap(subjectArtistGenres, otherArtistGenres))
        }
        if !subject.genres.isEmpty && !other.genres.isEmpty {
            ask(albumGenreWeight, overlap(Set(subject.genres), Set(other.genres)))
        }
        if subject.year > 0 && other.year > 0 {
            ask(eraWeight, era(subject.year, other.year))
        }

        return asked > 0 ? total / asked : 0
    }

    /// The reason shown on a card. This is the first axis that applies, checked from
    /// the strongest down. It is separate from the score, because a reason is not a
    /// threshold on the total.
    private static func because(_ subject: AlbumTraits, _ other: AlbumTraits,
                                _ subjectArtistGenres: Set<String>,
                                _ otherArtistGenres: Set<String>) -> SimilarBecause {
        if !subject.genres.isEmpty, !other.genres.isEmpty,
           overlap(Set(subject.genres), Set(other.genres)) > 0 {
            return .sameGenre
        }
        if !subjectArtistGenres.isEmpty, !otherArtistGenres.isEmpty,
           overlap(subjectArtistGenres, otherArtistGenres) > 0 {
            return .likeTheArtist
        }
        if subject.year > 0, other.year > 0, era(subject.year, other.year) > 0 {
            return .sameEra
        }
        return .justOnTheShelf
    }

    /// The overlap of two sets of genres: the shared genres divided by all the genres
    /// in either set. Sharing one of two genres scores higher than sharing one of nine.
    private static func overlap(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }

        let union = a.union(b)
        return union.isEmpty ? 0 : Double(a.intersection(b).count) / Double(union.count)
    }

    /// How close two years are, from 0 to 1. The value falls in a straight line to 0
    /// at ``eraSpan`` years apart.
    private static func era(_ a: Int, _ b: Int) -> Double {
        max(0, 1 - Double(abs(a - b)) / Double(eraSpan))
    }

    /// Every genre each act has been filed under, pooled across its whole catalogue.
    /// This drives the similar-artists axis. Pooling lets a tagged record pass its
    /// genres to the untagged records by the same act.
    private static func poolGenresByArtist(_ library: [AlbumTraits]) -> [String: Set<String>] {
        var pooled: [String: Set<String>] = [:]

        for album in library where !album.genres.isEmpty {
            pooled[fold(album.artist), default: []].formUnion(album.genres)
        }

        return pooled
    }

    private static func identity(_ artist: String, _ album: String) -> String {
        "\(fold(artist))|\(fold(album))"
    }

    /// Normalises a name before two names are compared. Case, accents, punctuation
    /// and a leading "the" are ignored, because they do not make two names different.
    ///
    /// This function is used for both a played credit and an album's artist tag. Using
    /// one function for both means the two are always compared the same way.
    public static func fold(_ text: String?) -> String {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }

        var out = ""
        var pendingSpace = false

        for scalar in text.trimmingCharacters(in: .whitespaces).decomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.properties.isDiacritic || CharacterSet.nonBaseCharacters.contains(scalar) {
                continue
            }

            if CharacterSet.alphanumerics.contains(scalar) {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(Character(scalar).lowercased())
            } else {
                pendingSpace = true
            }
        }

        let folded = out.precomposedStringWithCanonicalMapping
        return folded.hasPrefix("the ") ? String(folded.dropFirst(4)) : folded
    }
}

// ── the row under a record ──

extension SimilarAlbums {
    /// The records to suggest under `album`, highest score first, at most
    /// ``defaultCount``. This matches the Similar albums row on the desktop album page
    /// (`AlbumDetailView.LoadSimilarAsync`).
    ///
    /// This reads every track on the shelf, so it must be run off the main actor.
    public static func row(for album: CloudAlbum, on shelf: [CloudAlbum]) -> [CloudAlbum] {
        var matched: [String: String?] = [:]
        let library = shelf.map { traits(of: $0, matched: &matched) }

        // The subject is read the same way as the shelf, so both are scored by the same
        // rules. A record that is not on the shelf, for example one opened while the
        // shelf is being reloaded, is read the same way on its own.
        let subject = library.first { $0.key == album.key } ?? traits(of: album, matched: &matched)

        let byKey = Dictionary(shelf.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return pick(subject: subject, library: library, count: defaultCount).compactMap { byKey[$0.key] }
    }

    /// Reads an album the way the desktop app reads its shelf
    /// (`AlbumDetailView.ReadShelfTraits`). The genres are every genre its tracks
    /// carry, matched to the app's own genre list. The year is the year most of its
    /// tracks agree on.
    ///
    /// A tag that matches none of the app's genres is dropped. Two records that share
    /// an unknown tag do not prove that they are alike.
    public static func traits(of album: CloudAlbum) -> AlbumTraits {
        var matched: [String: String?] = [:]
        return traits(of: album, matched: &matched)
    }

    private static func traits(of album: CloudAlbum,
                               matched: inout [String: String?]) -> AlbumTraits {
        AlbumTraits(key: album.key, album: album.album, artist: album.artist,
                    genres: Genres.of(album.tracks, readings: &matched),
                    year: AlbumSort.yearOf(album.tracks))
    }
}
