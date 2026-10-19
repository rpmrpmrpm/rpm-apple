import Foundation

/// Which of the home screen's questions a featured card is answering.
///
/// The banner shows one card at a time. The kind is shown on the card's kicker line. A card
/// that did not name its question would be an album picture with no reason to be on screen.
public enum HomeFeatureKind: Sendable, Hashable {
    /// The record that was playing last. On the first opening of a session, this is the
    /// record that was playing when the app was closed. It is the same fact as ``listened``,
    /// but it is asked for one record rather than twenty. It has its own card because
    /// "carry on" is a different offer from "here is something you played lately".
    ///
    /// It opens the record. It does not resume a position, because nothing saves where in a
    /// track playback had got to.
    case `continue`

    /// The newest record on the shelf.
    case added

    /// One of the lists that the computer builds from what has been played.
    case madeForYou

    /// A record that the ranking chose from recent listening.
    case suggested

    /// A record with the most plays.
    case played

    /// A record played recently.
    case listened

    /// A radio station. This is the one card in the strip that is not on the shelf at all.
    case radio
}

/// One card in the featured banner: which question put it there, and what it opens.
///
/// The key is an album key for every kind except ``HomeFeatureKind/madeForYou``, where it is
/// the list's own name, and ``HomeFeatureKind/radio``, where it is the station's uuid.
public struct HomeFeature: Sendable, Equatable {
    public let kind: HomeFeatureKind
    public let key: String

    public init(kind: HomeFeatureKind, key: String) {
        self.kind = kind; self.key = key
    }
}

/// The banner at the top of the home screen: a few cards, one shown at a time, stepped through.
///
/// A port of `HomeFeatures` in `RPM.Core/Library/HomeShelf.cs`.
public enum HomeFeatures {
    /// How many cards the banner holds. There is one card per question the screen asks. More
    /// cards would make a strip that nobody reaches the end of. The rows below are where a
    /// collection is browsed.
    public static let count = 7

    /// The featured cards, in the order that the banner steps through them.
    ///
    /// **One card from each question before a second card from any of them.** The banner is
    /// the one place on this screen that mixes the rows. A strip of five records that all
    /// arrived last week would be the Recently added row, drawn twice as large. Sources with
    /// nothing in them are skipped, and the strip fills from the rest. A new collection needs
    /// this.
    ///
    /// **A record is featured once.** The most played record is often also a recent listen.
    /// The same cover twice in one strip makes the banner look stuck. Lists and stations are
    /// counted apart from records, because their keys cannot collide with album keys.
    ///
    /// - Parameter continued: The record that was playing last, or empty. This is one entry,
    ///   not a list, because there is only one last record. It is dealt first, so this card
    ///   gets the record rather than another question that could also answer with it.
    /// - Parameter stations: The stations heard most, by uuid. They are dealt last. A
    ///   collection that can answer every other question keeps all six records it had, and
    ///   gains a seventh card instead of giving one up.
    /// - Parameter isVariousArtists: Whether the record at an album key is filed under
    ///   Various Artists. Those records are never featured, on any card, including
    ///   ``HomeFeatureKind/continue``. A card is drawn on the artist's photograph. A
    ///   compilation has no artist to photograph, so its card would be a blank plate. This is
    ///   required rather than defaulted, so that a caller cannot forget it.
    public static func strip(continued: [String], added: [String], lists: [String],
                             suggested: [String], played: [String], listened: [String],
                             stations: [String], isVariousArtists: (String) -> Bool,
                             count wanted: Int) -> [HomeFeature] {
        guard wanted > 0 else { return [] }

        // Records are filtered before dealing, not skipped while dealing. A question whose
        // first answer is a compilation then offers its next answer, instead of losing its turn.
        func records(_ keys: [String]) -> [String] { keys.filter { !isVariousArtists($0) } }

        let sources: [(kind: HomeFeatureKind, keys: [String])] = [
            (.continue, records(continued)),
            (.added, records(added)),
            (.madeForYou, lists),
            (.suggested, records(suggested)),
            (.played, records(played)),
            (.listened, records(listened)),
            (.radio, stations),
        ]

        var strip: [HomeFeature] = []
        var taken: Set<String> = []

        // How far each source has been read. This is kept per source, not as one round number.
        // A source whose next entry is already featured is moved past, instead of losing its turn.
        var cursor = [Int](repeating: 0, count: sources.count)

        for _ in 0..<wanted {
            if strip.count >= wanted { break }
            var addedThisRound = false

            for (i, source) in sources.enumerated() {
                if strip.count >= wanted { break }

                while cursor[i] < source.keys.count
                        && taken.contains(mark(source.kind, source.keys[cursor[i]])) {
                    cursor[i] += 1
                }
                if cursor[i] >= source.keys.count { continue }

                let key = source.keys[cursor[i]]
                cursor[i] += 1
                taken.insert(mark(source.kind, key))
                strip.append(HomeFeature(kind: source.kind, key: key))
                addedThisRound = true
            }

            // Every source has been read to the end. Without this check, the loop would run
            // forever on a collection too small to fill the strip. Every new collection is that small.
            if !addedThisRound { break }
        }

        return strip
    }

    /// What counts as "already featured". A list's name, a station's uuid and an album key
    /// are three separate namespaces. A list with the same name as a record must not remove
    /// that record from the strip.
    private static func mark(_ kind: HomeFeatureKind, _ key: String) -> String {
        switch kind {
        case .madeForYou: return "list\n" + key.lowercased()
        case .radio: return "station\n" + key.lowercased()
        default: return "album\n" + key.lowercased()
        }
    }
}
