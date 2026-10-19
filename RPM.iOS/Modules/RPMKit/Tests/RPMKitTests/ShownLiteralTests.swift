import Foundation
import Testing

/// No English literal reaches the screen from the Swift head. Text such as "1 track",
/// "Reviews · 4.5 of 5", "Add to favourites" or an error sentence must come from the
/// table, and a check of SwiftUI calls alone cannot see all of them.
///
/// Three places are read, each where a literal can only be on its way to the screen:
///
/// * any line that calls a SwiftUI text view or modifier, every literal on it, so a
///   ternary inside `.accessibilityLabel` is read as well as the plain call;
/// * an assignment to a property named for a message (`trouble`, `notice`, `message`,
///   `heading`, `caption`, `banner`);
/// * in the view layer (RPMUI and the app), what a `String` property or function
///   returns.
///
/// A literal with a letter in it is reported unless it is shaped like a key, a path or
/// a name in code, or is in ``ShownLiteral/asWritten``. `Loc.get("Key")` arguments,
/// `Text(verbatim:)`, log lines, tests and the Debug-only LaunchClock are not read.
/// `RPMError` carries no text of its own, so a sentence cannot reach a screen through
/// an error either.
@Test func noSwiftSourceShowsAnEnglishLiteral() throws {
    let found = try ShownLiteral.scan(ShownLiteral.sources())

    #expect(ShownLiteral.filesRead > 100, "only \(ShownLiteral.filesRead) files read; the scan is wrong")
    #expect(found.isEmpty, Comment(rawValue: "Add the words to scripts/strings.json and use Loc.get:\n"
            + found.joined(separator: "\n")))
}

/// The rule itself, on small cases, so a change to it is seen here first.
@Test(arguments: [
    (#"Text("x").accessibilityLabel(on ? Loc.get("A_B") : "Add to favourites")"#, false, ["Add to favourites"]),
    (#"    trouble = "That station seems offline.""#, false, ["That station seems offline."]),
    (#"        return n == 1 ? "1 track" : "\(n) tracks""#, true, ["1 track", #"\(n) tracks"#]),
    (#"    private var key: String { "end|\(count)" }"#, true, []),
    (#"Text(Loc.get("Rpm_Album_Tracks", 3))"#, false, []),
    (#"Text(verbatim: "A")"#, false, []),
    (#"Text("\u{f5db}")"#, false, []),
    (#"Text("\(Loc.get("About_Version", v))  ·  © \(year) rpm.")"#, false, []),
    (#"Text(Loc.get(marked ? "Track_UnsetFavorite" : "Track_SetFavorite"))"#, false, []),
    (#"log.error("could not play \(name)")"#, false, []),
])
func aLiteralIsReportedWhereItCanOnlyBeOnItsWayToTheScreen(line: String, returning: Bool, expected: [String]) {
    #expect(ShownLiteral.literals(in: line, returning: returning, messageSet: true) == expected)
}

enum ShownLiteral {
    /// Literals that read the same in every language, and why.
    static let asWritten: [String: String] = [
        "rpm": "the app's name",
        "E": "the explicit mark, which streaming services show as E in every language",
        "AD": "the mark beside a radio station that carries advertising",
    ]

    nonisolated(unsafe) static var filesRead = 0

    static func sources() throws -> [URL] {
        // …/RPM.iOS/Modules/RPMKit/Tests/RPMKitTests/ShownLiteralTests.swift
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in walk {
            let parts = url.pathComponents
            if parts.contains(".build") || parts.contains("Tests") || parts.contains("DerivedData") {
                continue
            }
            if url.pathExtension == "swift", url.lastPathComponent != "LaunchClock.swift",
               url.lastPathComponent != "Package.swift" {
                files.append(url)
            }
        }
        return files
    }

    static func scan(_ files: [URL]) throws -> [String] {
        var found: [String] = []
        filesRead = files.count

        for file in files {
            let parts = file.pathComponents
            let viewLayer = parts.contains("RPMUI") || parts.contains("rpm")
            var returning = false
            var depth = 0

            let text = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated() {
                let code = Self.code(of: line)

                if viewLayer, !returning, matches(returnsText, code) {
                    returning = true
                    depth = 0
                }

                for literal in literals(in: code, returning: returning, messageSet: true) {
                    found.append("\(file.lastPathComponent):\(index + 1)  \(literal)")
                }

                if returning {
                    depth += code.filter { $0 == "{" }.count - code.filter { $0 == "}" }.count
                    if depth <= 0 { returning = false }
                }
            }
        }
        return found
    }

    /// The literals on one line of code that would put words on screen.
    static func literals(in code: String, returning: Bool, messageSet: Bool) -> [String] {
        guard !code.isEmpty, !matches(logged, code) else { return [] }

        let bare = replace(keyed, in: code, with: "Loc.get(_")
        var read: [String] = []
        if matches(showsText, bare) || returning {
            read = all(literal, in: bare)
        } else if messageSet, let rhs = first(messageAssignment, in: bare) {
            read = all(literal, in: rhs)
        }
        return read.filter(worded)
    }

    /// A literal that would put words on screen: a letter outside its interpolations and
    /// escapes, not shaped like an identifier, a key or a path, and not a name that reads
    /// the same everywhere.
    static func worded(_ literal: String) -> Bool {
        if asWritten[literal] != nil { return false }

        var words = shown(literal)
        for name in asWritten.keys {
            words = replace(try! NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"),
                            in: words, with: "")
        }
        guard words.rangeOfCharacter(from: .letters) != nil else { return false }

        // One token with two capitals or more is a name in code, not a word: a string key
        // (`Track_SetFavorite`), an Info.plist key, a protocol's code (`NOT_ALLOWED`).
        if !words.contains(" "), words.filter(\.isUppercase).count >= 2 { return false }

        return !matches(idLike, words, whole: true)
    }

    /// What of a literal is written out: no `\u{…}` escapes and no `\(…)` interpolations,
    /// which may nest parentheses. The literal pattern stops at the first quote, so an
    /// interpolation that holds a string is cut short; an open one runs to the end.
    static func shown(_ literal: String) -> String {
        let plain = replace(try! NSRegularExpression(pattern: #"\\u\{[0-9A-Fa-f]+\}"#), in: literal, with: "")
        var out = ""
        var depth = 0
        var chars = Array(plain)[...]
        while let c = chars.first {
            if c == "\\", chars.dropFirst().first == "(" {
                depth += 1
                chars = chars.dropFirst(2)
                continue
            }
            if depth > 0 {
                if c == "(" { depth += 1 } else if c == ")" { depth -= 1 }
            } else {
                out.append(c)
            }
            chars = chars.dropFirst()
        }
        return out
    }

    private static func code(of line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("//") { return "" }
        return line
    }

    // ── patterns ──

    private static let literal = try! NSRegularExpression(pattern: #""((?:[^"\\]|\\.)*)""#)
    private static let keyed = try! NSRegularExpression(
        pattern: #"Loc\.get\(\s*"[A-Za-z0-9_]+"|verbatim:\s*"(?:[^"\\]|\\.)*""#)
    private static let idLike = try! NSRegularExpression(pattern: #"[a-z0-9_.\-/:|?&=%#]*"#)
    private static let logged = try! NSRegularExpression(
        pattern: #"\b(?:log|logger|Logger|os_log|print|debugPrint|assert|assertionFailure|precondition|preconditionFailure|fatalError|say|signpost)\b\s*[.(]"#)
    private static let messageAssignment = try! NSRegularExpression(
        pattern: #"\b\w*(?:[Tt]rouble|[Nn]otice|[Mm]essage|[Hh]eading|[Cc]aption|[Bb]anner)\s*=\s*(.*)$"#)
    private static let showsText = try! NSRegularExpression(
        pattern: #"\b(?:Text|Button|Label|Toggle|TextField|SecureField|Section|Menu|Picker|Link|placeholder|navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|help)\("#)
    private static let returnsText = try! NSRegularExpression(
        pattern: #"\b(?:var\s+\w+\s*:\s*String\??|func\s+\w+\s*\([^)]*\)\s*->\s*String\??)\s*\{"#)

    private static func matches(_ pattern: NSRegularExpression, _ text: String, whole: Bool = false) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = pattern.firstMatch(in: text, range: range) else { return false }
        return !whole || m.range == range
    }

    private static func all(_ pattern: NSRegularExpression, in text: String) -> [String] {
        pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    private static func first(_ pattern: NSRegularExpression, in text: String) -> String? {
        guard let m = pattern.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func replace(_ pattern: NSRegularExpression, in text: String, with: String) -> String {
        pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: with)
    }
}
