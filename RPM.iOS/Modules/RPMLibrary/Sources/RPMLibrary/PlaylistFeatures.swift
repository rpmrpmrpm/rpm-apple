import Foundation
import RPMKit

/// Who is on a list, and how many more there are than were named.
public struct Featured: Sendable, Equatable {
    /// The acts with the most songs on the list, most first. Ties are broken by name. This is
    /// empty where no song on the list has a credit at all.
    public let named: [String]

    /// How many other acts are on the list. These are the ones there was no room to name.
    public let more: Int
}

/// Who a playlist is made of, for the line under its name. This is a port of the desktop's
/// `PlaylistFeatures`, and of the line that `PlaylistView.ShowFeatured` builds from it. It uses
/// the same strings, so one list reads the same on both platforms.
///
/// **Counted by act, not by credit.** "Kanye West", "Kanye West & Ty Dolla $ign" and "Jay-Z &
/// Kanye West" are one artist with three songs, not three artists with one.
/// ``ArtistCredit/split(_:)`` cuts on separators that also occur inside real names. "Earth,
/// Wind & Fire" comes out as three. This is accepted, as on the desktop, because this is one
/// decorative line and nothing is filed under it.
public enum PlaylistFeatures {
    /// How many acts the line names. This is the desktop's `FeaturedNamed`.
    public static let named = 3

    /// The acts on a list, most songs first.
    ///
    /// - Parameters:
    ///   - credits: one credit per song, in the list's own order. Nils and blanks name nobody.
    ///   - most: how many to name. The caller states this, because how many fit is a fact about the line.
    public static func of(_ credits: [String?], most: Int) -> Featured {
        // Counted case-blind, and kept with the FIRST spelling seen. "Blur" and "BLUR" are one
        // act to a reader. The list's own order is the only order that is not arbitrary, so it
        // decides which spelling is printed.
        var songs: [String: Int] = [:]
        var spelling: [String: String] = [:]

        for credit in credits {
            for name in ArtistCredit.split(credit) {
                let key = name.lowercased()
                songs[key, default: 0] += 1
                if spelling[key] == nil { spelling[key] = name }
            }
        }

        guard !songs.isEmpty else { return Featured(named: [], more: 0) }

        // Most songs first, then by name, so that the line is the same every time it is drawn.
        let named = songs
            .sorted {
                $0.value != $1.value
                    ? $0.value > $1.value
                    : $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            .prefix(max(0, most))
            .compactMap { spelling[$0.key] }

        return Featured(named: named, more: songs.count - named.count)
    }

    /// The line under a list's name: the mood sentence where the list has one, then who is on
    /// it. This is nil where there is neither.
    ///
    /// **The sentence comes first and the credits follow it,** as on the desktop. What the list
    /// IS matters more than who is on it, and a reader who wants the names reads on. Where the
    /// songs credit nobody, the sentence is shown alone. What a mood list sounds like does not
    /// depend on the tags being filled in.
    ///
    /// - Parameters:
    ///   - blurb: the mood sentence, from ``MoodBlurb/sentence(kind:genres:)``, or nil.
    ///   - credits: one credit per song, in the list's order.
    public static func line(blurb: String?, credits: [String?]) -> String? {
        let featured = of(credits, most: named)
        guard !featured.named.isEmpty else { return blurb }

        let names = featured.named.joined(separator: ", ")
        let featuring = featured.more > 0
            ? Loc.get("Playlists_FeaturingMore", names, featured.more)
            : Loc.get("Playlists_Featuring", names)

        guard let blurb else { return featuring }
        return blurb + " " + featuring
    }
}
