import Foundation

/// The name a country is shown under, and the countries the country picker offers.
///
/// Ported from `RPM.Core/Radio/RadioCountries.cs`, with the same tests. Change both, or the phone
/// and the desktop app will list different countries under different names.
///
/// Radio Browser files countries under their formal ISO names, such as "The United Kingdom Of
/// Great Britain And Northern Ireland" or "The Republic Of Korea". Two rules make them readable.
/// A country whose common name is a different word from its formal name is looked up by ISO code
/// in ``common``. Every other name is tidied: the leading "The" is removed, and the joining words
/// are made lower case.
///
/// The code identifies the country, and the directory is queried with it. The name is only shown.
/// So shortening the name cannot change which stations are listed.
public enum RadioCountries {
    /// How many countries the country picker offers.
    public static let offered = 80

    /// The countries the country picker offers: the ``offered`` countries with the most stations,
    /// under their short names, sorted A to Z.
    ///
    /// The countries are chosen by station count. A list of two hundred entries, half of them with
    /// three stations each, is not worth scrolling. The list is shown A to Z, because the count is
    /// not visible to the reader. The sort uses the current locale's comparison, so "Türkiye" is
    /// filed under T.
    ///
    /// The names are shortened before the sort. A country is filed under the letter its shown
    /// name starts with, so "The Netherlands" goes under N, not T.
    ///
    /// There is one entry per code. The directory lists Brazil and Italy a second time, under the
    /// lowercase codes "br" and "it", with one station each. The client uppercases every code. Two
    /// entries with one code would also be two rows with one id in the menu.
    ///
    /// Ties on station count are decided by code. So the cut does not depend on the order in
    /// which the directory answered.
    public static func forPicker(_ countries: [RadioFacet]) -> [RadioFacet] {
        var byCode: [String: [RadioFacet]] = [:]
        for country in countries {
            byCode[country.code.trimmingCharacters(in: .whitespaces).uppercased(), default: []]
                .append(country)
        }

        let merged = byCode.map { code, same in
            // The name of the entry with the most stations. Ties go to the first listed, which is
            // what the stable sort in the desktop app does.
            let named = same.enumerated().max {
                $0.element.stationCount != $1.element.stationCount
                    ? $0.element.stationCount < $1.element.stationCount
                    : $0.offset > $1.offset
            }!.element

            return RadioFacet(name: named.name, code: code,
                              stationCount: same.reduce(0) { $0 + $1.stationCount })
        }

        return merged
            .sorted {
                $0.stationCount != $1.stationCount
                    ? $0.stationCount > $1.stationCount
                    : $0.code < $1.code
            }
            .prefix(offered)
            .map { RadioFacet(name: short($0.name, $0.code), code: $0.code, stationCount: $0.stationCount) }
            .sorted {
                switch $0.name.localizedCompare($1.name) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: $0.code < $1.code
                }
            }
    }

    /// The name to show for this country: its common name where that differs from the formal name,
    /// otherwise the formal name, tidied.
    ///
    /// - Parameter name: what the directory calls the country.
    /// - Parameter code: its ISO 3166-1 alpha-2 code, which ``common`` is keyed by. An entry with
    ///   no code gets only the tidying.
    public static func short(_ name: String?, _ code: String?) -> String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }

        let key = (code ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        if let known = common[key] { return known }

        return tidy(name.trimmingCharacters(in: .whitespaces))
    }

    /// The countries whose common name is not a shortening of the formal name. Keyed by code,
    /// because the formal name is the part that varies between entries.
    private static let common: [String: String] = [
        "GB": "United Kingdom",
        "US": "United States",
        "RU": "Russia",
        "KR": "South Korea",
        "KP": "North Korea",
        "TW": "Taiwan",
        "VE": "Venezuela",
        "IR": "Iran",
        "SY": "Syria",
        "TZ": "Tanzania",
        "MD": "Moldova",
        "MK": "North Macedonia",
        "LA": "Laos",
        "CD": "DR Congo",
        "CG": "Congo",
        "PS": "Palestine",
        "VA": "Vatican City",
        "FM": "Micronesia",
        "BN": "Brunei",
        "CV": "Cape Verde",
        "SH": "Saint Helena",
        "MF": "Saint Martin",
        "SX": "Sint Maarten",
        "FK": "Falkland Islands",
        "CC": "Cocos Islands",
        "UM": "U.S. Outlying Islands",
        "VI": "U.S. Virgin Islands",
        "VG": "British Virgin Islands",
        "IO": "British Indian Ocean Territory",
        "SJ": "Svalbard",
    ]

    /// The formal name without a leading "The", with the joining words in lower case:
    /// "Trinidad And Tobago" becomes "Trinidad and Tobago". Other words are kept as they are.
    private static func tidy(_ name: String) -> String {
        var name = name
        if name.lowercased().hasPrefix("the ") {
            name = String(name.dropFirst(4)).trimmingCharacters(in: .whitespaces)
        }

        var words = name.split(separator: " ").map(String.init)

        // The first word is never lower-cased, so a name always begins with a capital.
        for i in words.indices.dropFirst() where joining.contains(words[i].lowercased()) {
            words[i] = words[i].lowercased()
        }

        return words.joined(separator: " ")
    }

    private static let joining: Set<String> = ["and", "of", "the", "da", "de"]
}
