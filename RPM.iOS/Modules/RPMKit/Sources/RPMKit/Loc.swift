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
public enum Loc {
    /// The bundle that holds the string table.
    ///
    /// `Bundle.module` is generated for each module. Inside a test it points at the test's bundle,
    /// which has no locales. Every lookup would then return the English fallback without any error.
    /// This property always points at the bundle that has the table.
    static var table: Bundle { .module }

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
}
