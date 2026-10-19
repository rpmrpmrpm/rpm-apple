import Foundation

/// Whether two names are the same name, even when they are written differently.
///
/// This follows the same rules as `RPM.Fingerprint/Catalog/NameMatch.cs` on the desktop. A tag may
/// say "Earth Wind and Fire" while a catalogue says "Earth, Wind & Fire", and both mean the same
/// band. Comparing the strings directly cannot show that. So case, spacing, punctuation and the
/// word "and" are removed first.
public enum NameMatch {
    /// Whether these are the same name. Returns false when either name is missing. Also returns
    /// false when both names are empty after cleaning, because two strings made only of
    /// punctuation do not match.
    public static func same(_ one: String?, _ other: String?) -> Bool {
        guard let one, !one.isEmpty, let other, !other.isEmpty else { return false }

        let squashed = squash(one)
        return !squashed.isEmpty && squashed == squash(other)
    }

    /// The name with everything that varies removed: case, spacing, punctuation, and the word
    /// "and". "and" is removed rather than kept, so that it matches the `&` it stands for.
    public static func squash(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return "" }

        var squashed = ""
        var word = ""

        for character in name + " " {
            if character.isLetter || character.isNumber {
                // Use String, not Character. Lowercasing one character can give more than one
                // character (for example "İ" becomes "i" followed by a combining dot), and
                // building a Character from that traps.
                word += String(character).lowercased()
                continue
            }

            if !word.isEmpty && word != "and" { squashed += word }
            word = ""
        }

        return squashed
    }
}
