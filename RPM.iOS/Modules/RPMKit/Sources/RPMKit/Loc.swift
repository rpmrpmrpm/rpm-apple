import Foundation

/// The one place display strings come from.
///
/// **`scripts/strings.json` is the source for both heads.** Each entry has one key, five locales,
/// and a comment that says where the string appears. Running `python3 scripts/gen_locales.py`
/// turns it into the desktop's `Resources.resw` and this module's `Localizable.strings`. Never
/// edit either file by hand. They are overwritten on each run, and a key that is not in the JSON
/// is silently dropped from both.
///
/// **This lives in `RPMKit` because every other part of the app depends on it.** A sentence about
/// a track that will not play belongs to the player, and the name of a sort order belongs to the
/// wall. This module holds both and has no dependencies of its own.
///
/// A key with no translation renders as the key itself. This is intended, and it matches the
/// desktop. A missing string should be visible where it is missing. Falling back to English would
/// hide the gap, because four of the five locales would then show English without anyone noticing.
///
/// **The user can choose the app's language** (``chosenKey``), on the settings page and in the
/// welcome. Without a choice the strings follow the phone's language, as the system picks it.
public enum Loc {
    /// The bundle that holds the string table.
    ///
    /// `Bundle.module` is generated for each module. Inside a test it points at the test's bundle,
    /// which has no locales. Every lookup would then return the English fallback without any error.
    /// This property always points at the bundle that has the table.
    static var module: Bundle { .module }

    /// The table the strings are read from: the chosen language's, or the phone's.
    static var table: Bundle {
        Chosen.shared.bundle(for: chosen, in: module) ?? module
    }

    /// The app's languages, as the desktop offers them (`AppLanguage.Offered`).
    public static let offered = ["en", "fr", "es", "de", "zh-Hans"]

    /// Where the user's choice of language is kept: one of ``offered``, or empty for the phone's.
    public static let chosenKey = "app.language"

    /// The language the user chose, or empty for the phone's. A stored code this build does not
    /// offer counts as empty.
    public static var chosen: String {
        let stored = UserDefaults.standard.string(forKey: chosenKey) ?? ""
        return offered.contains(stored) ? stored : ""
    }

    /// Keeps the user's choice: one of ``offered``, or empty for the phone's language.
    ///
    /// It also tells the system, so the parts of the app the system draws (a share sheet, the
    /// keyboard's keys, the permission questions) follow from the next launch. The app's own text
    /// changes at once: the app shows itself again in the new language.
    public static func choose(_ code: String) {
        let defaults = UserDefaults.standard
        if offered.contains(code) {
            defaults.set(code, forKey: chosenKey)
            defaults.set([code], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: chosenKey)
            defaults.removeObject(forKey: "AppleLanguages")
        }
    }

    /// A language's name in that language, as a language picker shows it: "Deutsch", "Français".
    public static func name(of code: String) -> String {
        let locale = Locale(identifier: code)
        let said = locale.localizedString(forIdentifier: code) ?? code
        return said.prefix(1).uppercased(with: locale) + said.dropFirst()
    }

    /// The locale the strings come from, out of the five: `en`, `fr`, `es`, `de` or `zh-Hans`. Sent
    /// to the store, which names the lists it cuts in the same language.
    public static var language: String {
        let chosen = self.chosen
        return chosen.isEmpty ? (module.preferredLocalizations.first ?? "en") : chosen
    }

    /// The string for a key, in the locale this phone is set to, out of the five locales.
    public static func get(_ key: String) -> String {
        table.localizedString(forKey: key, value: key, table: nil)
    }

    /// The string for a key, with its placeholders filled in.
    ///
    /// The table uses positional placeholders (`%1$@`) and not a plain `%@`, because the order of
    /// the parts in a sentence differs between languages. `scripts/strings.json` writes them as
    /// `{0}` and `{1}`, the same form the desktop reads. The generator converts them to the
    /// positional form when it writes this table.
    ///
    /// **Each argument is converted to a string first.** `%@` expects an object. Passing an `Int`
    /// straight to `String(format:)` is read as a pointer, which can print a wrong value or crash.
    /// Converting every argument with `description` makes that mistake impossible.
    public static func get(_ key: String, _ arguments: any CustomStringConvertible...) -> String {
        String(format: get(key), arguments: arguments.map { $0.description as NSString })
    }

    /// The string for a key in one of the five locales, whatever this phone is set to. The welcome
    /// uses it to say hello in each of the app's languages in turn.
    ///
    /// The locale is a language tag such as "fr" or "zh-Hans". SwiftPM can write a locale's folder
    /// in lower case (`zh-hans.lproj`), so both spellings are tried. A locale that is not in the
    /// bundle gives the phone's own string.
    public static func get(_ key: String, in locale: String) -> String {
        guard let bundle = Chosen.shared.bundle(for: locale, in: module) else { return get(key) }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

/// The table of each language, opened once. A string is read many times on every screen, and
/// opening a bundle from its folder each time would be slow.
///
/// It is read from any thread, so it holds a lock.
private final class Chosen: @unchecked Sendable {
    static let shared = Chosen()

    private let lock = NSLock()
    private var opened: [String: Bundle] = [:]

    /// The table of `locale` inside `module`, or nil for an empty code or a language that is not
    /// in the bundle. SwiftPM can write a locale's folder in lower case (`zh-hans.lproj`), so both
    /// spellings are tried.
    func bundle(for locale: String, in module: Bundle) -> Bundle? {
        guard !locale.isEmpty else { return nil }

        return lock.withLock {
            if let already = opened[locale] { return already }

            let path = module.path(forResource: locale, ofType: "lproj")
                ?? module.path(forResource: locale.lowercased(), ofType: "lproj")
            guard let path, let found = Bundle(path: path) else { return nil }
            opened[locale] = found
            return found
        }
    }
}
