import Foundation

/// Whether a station carries advertising, and whether it is running an ad right now.
///
/// Ported from `RPM.Core/Radio/RadioAds.cs`, with the same tests. Change both, or the phone
/// and the desktop app will mark different stations.
///
/// Radio Browser has no field for advertising. The only signal is the station's own tags, and
/// few stations have any. So ``carriesAds(tags:name:homepage:)`` falls back to
/// ``RadioBroadcasters``. A station that gives no signal and is not on that list is not marked
/// either way.
///
/// Public is not the same as ad-free. NPO carries STER advertising, and NPR carries sponsorship.
/// Only tags that say so explicitly ("non-commercial", "no ads") take a station out.
public enum RadioAds {
    /// Whether this station carries advertising. The station's tags are read first. If they
    /// say nothing, the broadcaster is checked.
    ///
    /// An ad-free tag is read first and wins. So a station tagged both "public radio" and
    /// "non-commercial" is not marked, even when its broadcaster is on the list.
    public static func carriesAds(tags: [String], name: String?, homepage: String?) -> Bool {
        var carries = false

        for raw in tags {
            let tag = fold(raw)
            if tag.isEmpty { continue }

            if adFree.contains(where: { tag.contains($0) }) { return false }

            carries = carries || advertised.contains(where: { tag.contains($0) })
        }

        return carries || RadioBroadcasters.carriesAds(name: name, homepage: homepage)
    }

    /// Whether the station is announcing an ad break rather than a record.
    ///
    /// Stations put a marker in the title field when a break starts: "Advertisement",
    /// "Reclame", "Werbung". The whole line must be the marker. Containing it is not enough,
    /// because "Commercial" also appears in song titles and band names.
    public static func isAdBreak(_ announced: String?) -> Bool {
        let line = fold(announced ?? "")
        return !line.isEmpty && breaks.contains(line)
    }

    /// Whether the station is announcing the end of a break. Nothing is printed for it, because
    /// no record has been named yet. Only the marker from iHeart is known.
    public static func isBreakOver(_ announced: String?) -> Bool {
        let line = fold(announced ?? "")
        return !line.isEmpty && overs.contains(line)
    }

    /// Lower case, with the few accents these words use taken off. Each run of punctuation or
    /// space becomes one space: "- Werbung -" becomes "werbung", and "public-radio" becomes
    /// "public radio".
    private static func fold(_ text: String) -> String {
        var folded = ""
        for c in text.lowercased() {
            let letter = deaccent(c)
            if letter.isLetter || letter.isNumber {
                folded.append(letter)
            } else if let last = folded.last, last != " " {
                folded.append(" ")
            }
        }
        while folded.last == " " { folded.removeLast() }
        return folded
    }

    private static func deaccent(_ c: Character) -> Character {
        switch c {
        case "é", "è", "ê", "ë": "e"
        case "à", "â", "á", "ä": "a"
        case "í", "ì", "î", "ï": "i"
        case "ó", "ò", "ô", "ö": "o"
        case "ú", "ù", "û", "ü": "u"
        default: c
        }
    }

    /// Tags that say a station carries advertising. "government" and "public service" name
    /// broadcasters that almost always run spots.
    private static let advertised = [
        "commercial", "public radio", "public service", "public broadcast", "offentlich rechtlich",
        "government", "state radio",
    ]

    /// Tags that say a station carries no advertising. These are read first, so "non commercial",
    /// which contains "commercial", is never read as its opposite.
    private static let adFree = [
        "non commercial", "noncommercial", "no ads", "no advert", "ad free", "advert free",
        "werbefrei", "sans pub",
    ]

    /// What a station puts in the title field while a break runs. It must match the whole line.
    private static let breaks: Set<String> = [
        "ad", "ads", "advert", "adverts", "advertisement", "advertisements", "advertising",
        "ad break", "adbreak", "commercial", "commercials", "commercial break",
        "reclame", "reklame", "reclames", "werbung", "werbepause",
        "publicite", "publicidad", "publicidade", "pubblicita", "anuncios", "spot publicitario",

        // The marker from iHeart, once its ids are removed (see IcyTitle).
        "spot block", "spot block start",
    ]

    /// The marker that says a break has just finished. See ``isBreakOver(_:)``.
    private static let overs: Set<String> = [
        "spot block end",
    ]
}
