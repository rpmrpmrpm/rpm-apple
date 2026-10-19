import Foundation

/// The English Wikipedia article that describes each genre the app shelves by: the desktop's table
/// (`EncyclopediaLookup.Encyclopedias`, RPM.Core/Metadata/Providers/EncyclopediaLookup.cs) as the Android
/// `GenreArticles.kt` copies it. A genre is never searched for by name: "Club" or "World" would find the
/// wrong page. The two shelves that are not kinds of music, and any genre added to the app without an
/// entry here, have no article.
public enum GenreArticles {
    private static let byGenre: [String: String] = Dictionary(uniqueKeysWithValues: [
        ("Rock", "Rock music"),
        ("Indie", "Indie rock"),
        ("Pop", "Pop music"),
        ("Disco", "Disco"),
        ("Funk", "Funk"),
        ("Soul", "Soul music"),
        ("R&B", "Contemporary R&B"),
        ("Rap", "Hip hop music"),
        ("Trap", "Trap music"),
        ("Old School Hip Hop", "Old-school hip hop"),
        ("Hip-Hop / Rap", "Hip hop music"),
        ("House", "House music"),
        ("Techno", "Techno"),
        ("Club", "Club music"),
        ("Electronic / Dance", "Electronic dance music"),
        ("Jazz", "Jazz"),
        ("Blues", "Blues"),
        ("Country", "Country music"),
        ("Folk", "Folk music"),
        ("Classical", "Classical music"),
        ("Neo-Classical", "Neoclassicism (music)"),
        ("Opera", "Opera"),
        ("Metal", "Heavy metal music"),
        ("Punk", "Punk rock"),
        ("Noise", "Noise music"),
        ("Avant-Garde", "Avant-garde music"),
        ("Reggae", "Reggae"),
        ("Latin", "Latin music"),
        ("World", "World music"),
        ("Religious", "Religious music"),
        ("Soundtrack", "Film score"),
        ("Video Game", "Video game music"),
        ("Musical", "Musical theatre"),
        ("Spoken Word", "Spoken word"),
    ].map { ($0.0.lowercased(), $0.1) })

    /// The article's title for `genre`, matched without regard to case or surrounding spaces; nil where
    /// there is none.
    public static func title(_ genre: String) -> String? {
        byGenre[genre.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
    }
}
