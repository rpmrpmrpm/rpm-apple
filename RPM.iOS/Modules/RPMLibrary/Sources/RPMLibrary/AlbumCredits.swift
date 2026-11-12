import Foundation

/// The copyright line and the record label of a record, as its files' tags give them, and the
/// lines the album page draws under its songs.
///
/// The tags are read from one song's sidecar, because the track row does not carry them. Both are
/// album-level tags, and the desktop writes the same value on every song of a record.
public struct AlbumCredits: Sendable, Equatable {
    public let copyright: String?
    public let label: String?

    public init(copyright: String?, label: String?) {
        self.copyright = Self.cleaned(copyright)
        self.label = Self.cleaned(label)
    }

    /// The lines under the songs, copyright first. Empty when the tags have neither.
    ///
    /// **The label is left out where the copyright line already names it**, because
    /// "\u{2117} 1998 Warp Records Limited" over "Warp Records" says the same thing twice.
    ///
    /// The copyright line is drawn as the tag has it. A tag that does not start with a copyright
    /// or sound recording mark gets "\u{00A9}", so the line reads as a copyright and not as a
    /// second label.
    public var lines: [String] {
        var lines: [String] = []

        if let copyright {
            lines.append(Self.marked(copyright))
        }

        if let label, !(copyright.map { Self.names($0, label) } ?? false) {
            lines.append(label)
        }

        return lines
    }

    /// Whether the record has anything to show.
    public var isEmpty: Bool { lines.isEmpty }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The marks a copyright tag can start with: the copyright and sound recording signs, and the
    /// ASCII forms some taggers write instead.
    private static let marks = ["\u{00A9}", "\u{2117}", "(c)", "(p)", "copyright"]

    private static func marked(_ copyright: String) -> String {
        let lower = copyright.lowercased()
        return marks.contains(where: lower.hasPrefix) ? copyright : "\u{00A9} " + copyright
    }

    /// Whether `copyright` contains `label`, ignoring case and accents.
    private static func names(_ copyright: String, _ label: String) -> Bool {
        copyright.range(of: label, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
