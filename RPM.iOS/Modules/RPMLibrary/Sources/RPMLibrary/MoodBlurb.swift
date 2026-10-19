import Foundation
import RPMKit

/// The sentence under a mood list's name: what it sounds like, and what kind of music is in it.
///
/// This is a port of the desktop's `MoodBlurb`, which chooses the genres to name, in `RPM.Core`.
/// It is also a port of `MoodBlurbText`, which holds the wording. So the same list says the same
/// thing on both platforms. The strings are the desktop's: `Playlists_BlurbCalm` and the rest,
/// from `scripts/strings.json`.
///
/// **Only the moods get one.** "Most played" says what it is in its own title. A mood is
/// different. "Chill" is a single word, and the name does not show which part of the collection
/// it drew from.
public enum MoodBlurb {
    /// How many kinds of music one sentence names. This is the desktop's `MostGenres`.
    public static let mostGenres = 3

    /// The fewest songs of a genre that can be named: a twentieth of the list. Naming a genre
    /// that only one song in fifty has describes the exception, not the list. This is the
    /// desktop's `LeastShare`.
    public static let leastShare = 0.05

    /// The sentence for a generated list, or nil where its kind has none.
    ///
    /// - Parameters:
    ///   - kind: the cut's kind, as the computer sends it. Every kind except the five moods
    ///     gives nil.
    ///   - genres: the raw genre tag of each song on the list, in list order. These are counted
    ///     from the songs that the page shows, as the desktop counts from its rows. The page's
    ///     songs are the list. A second reading could disagree with the songs printed under the
    ///     sentence.
    public static func sentence(kind: String, genres: [String?]) -> String? {
        // Sleep names no genres. It is cut across all of them, so a list of three would describe
        // the collection, not the list.
        if kind == "Sleep" { return Loc.get("Playlists_BlurbSleep") }

        let key: String
        switch kind {
        case "Calm": key = "Playlists_BlurbCalm"
        case "Energetic": key = "Playlists_BlurbEnergetic"
        case "Danceable": key = "Playlists_BlurbDanceable"
        case "Focus": key = "Playlists_BlurbFocus"
        default: return nil
        }

        let named = spoken(genres)
        return named.isEmpty ? nil : Loc.get(key, listed(named))
    }

    /// The kinds of music worth naming, most common first, as they are said in running text.
    ///
    /// The tags go through ``Genres/match(_:)`` first. So a list holding "Deep House" and
    /// "Acid House" counts as one house list, not as two rare ones.
    public static func spoken(_ genres: [String?]) -> [String] {
        var counted: [String: Int] = [:]
        for tag in genres {
            guard let canonical = Genres.match(tag), canonical != Genres.unknown else { continue }
            counted[canonical, default: 0] += 1
        }

        let total = Double(genres.count)
        guard total > 0 else { return [] }

        return counted
            .filter { Double($0.value) >= total * leastShare }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(mostGenres)
            .map { Genres.spoken($0.key) }
    }

    /// For example: "rock", "rock and pop", "rock, pop and jazz". The last join is a localised
    /// template, because only some languages put a word there.
    public static func listed(_ names: [String]) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        default:
            return Loc.get("Playlists_GenreAnd",
                           names.dropLast().joined(separator: ", "), names[names.count - 1])
        }
    }
}
