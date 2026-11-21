import Foundation

/// Which language the Wikipedia texts on the artist and album pages are read in.
///
/// The phone's own language by default. The reader can choose one of the larger Wikipedias
/// instead (``offered``), where most acts and records have an article. Where the chosen one has
/// no article, the English one is read, as ``Encyclopedia/languages(preferred:)`` says.
///
/// The Android phone keeps the same choice under the same key, with the same codes.
public enum ArticleLanguages {
    /// Where the choice is kept, in the standard user defaults: a Wikipedia code ("nl"), or empty
    /// for the phone's own language.
    public static let key = "papers.language"

    /// The languages offered, by their Wikipedia codes, in the order the picker shows them.
    public static let offered = ["en", "nl", "de", "fr", "es", "it", "pt", "sv", "pl", "ja", "zh"]

    /// The Wikipedias to read, best first, for the stored choice.
    ///
    /// - Parameter chosen: what ``key`` holds. Empty, or a code this build does not offer, means
    ///   the phone's own language.
    /// - Parameter phone: the phone's languages, best first (`Locale.preferredLanguages`).
    public static func wikipedias(chosen: String, phone: [String]) -> [String] {
        let code = Encyclopedia.baseLanguage(chosen)
        guard offered.contains(code) else { return Encyclopedia.languages(preferred: phone) }
        return Encyclopedia.languages(preferred: [code])
    }

    /// The Wikipedias to read for the choice stored in `store`.
    public static func wikipedias(in store: UserDefaults, phone: [String]) -> [String] {
        wikipedias(chosen: store.string(forKey: key) ?? "", phone: phone)
    }

    /// The phone's own language, as a Wikipedia code ("nl"), or "en" when the phone names none.
    public static func phoneLanguage(_ phone: [String]) -> String {
        let own = phone.first.map(Encyclopedia.baseLanguage) ?? ""
        return own.isEmpty ? "en" : own
    }

    /// A language's name in that language, with a capital first letter, as a language picker
    /// names them: "Nederlands", "English", "日本語". The code itself where the system has no
    /// name for it.
    public static func name(of code: String) -> String {
        let locale = Locale(identifier: code)
        guard let name = locale.localizedString(forLanguageCode: code), !name.isEmpty else {
            return code
        }
        return name.prefix(1).uppercased(with: locale) + name.dropFirst()
    }
}
