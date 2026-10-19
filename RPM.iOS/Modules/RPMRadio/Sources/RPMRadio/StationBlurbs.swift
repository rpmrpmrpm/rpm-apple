import Foundation
import RPMKit

/// One short line saying what a station is, for the radio banner. The line comes from the station's
/// front page: the `og:description` meta tag, or else the `description` meta tag. It is cut to
/// ``longest`` characters, at a sentence end or at a word. The desktop app also asks Wikipedia when
/// the page has no description. This actor does not, so such a station has no line.
///
/// Each station is asked for once, and the answer is kept until the app ends. Two requests made while
/// the first is pending share its answer. **A page that could not be read is not an answer.** No
/// network, a 5xx, a 408 or a 429 says nothing about the station. So the next request asks again,
/// rather than storing "no line".
public actor StationBlurbs {
    /// Fetches a page: the network through `Gated`, or a stand-in in a test.
    typealias Fetch = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    private let fetch: Fetch
    private var known: [String: Task<Asked, Never>] = [:]

    /// What asking came to.
    enum Asked: Sendable {
        /// The page answered: its line, or none where it says nothing.
        case line(String?)
        /// The page could not be read.
        case unreachable
    }

    /// About two lines of the banner's box.
    public static let longest = 80
    private static let shortest = 12

    /// How much of a page is read. A front page's head is in the first few kilobytes.
    private static let headRead = 64 * 1024

    public init(reach: NetworkReach) {
        let wire = Gated(reach: reach)
        self.init(fetch: { try await wire.fetch($0, method: "GET") })
    }

    init(fetch: @escaping Fetch) {
        self.fetch = fetch
    }

    /// The answers so far, for ``answered(_:)``. `NSCache` is thread-safe, which is what the
    /// `unsafe` relies on.
    private nonisolated(unsafe) let answers = NSCache<NSString, Answer>()

    private final class Answer {
        let line: String?
        init(_ line: String?) { self.line = line }
    }

    /// What ``of(_:)`` answered for this station, or nil where it has not answered yet. This is read
    /// at once, from any thread, so a card can be drawn with its line, or without one, on its first
    /// frame. A station with no line answers `.some(nil)`.
    public nonisolated func answered(_ station: RadioStation) -> String?? {
        if let line = station.edit?.description { return .some(line) }
        guard let page = station.homepage, page.hasPrefix("http"), URL(string: page) != nil else { return .some(nil) }
        return answers.object(forKey: station.uuid.lowercased() as NSString).map(\.line)
    }

    public func of(_ station: RadioStation) async -> String? {
        // The admin's line, as written: the admin holds it to the same 80 characters. Not kept with
        // the pages' lines, so a changed edit shows the next time the card asks.
        if let line = station.edit?.description { return line }
        guard let page = station.homepage, page.hasPrefix("http"), let url = URL(string: page) else { return nil }
        let key = station.uuid.lowercased()

        let task = known[key] ?? Task { [fetch] () -> Asked in
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("RPM/1.0", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await fetch(request) else { return .unreachable }
            switch response.statusCode {
            case 200..<300:
                return .line(Self.fromPage(String(decoding: data.prefix(Self.headRead), as: UTF8.self)))
            case 408, 429, 500...:
                return .unreachable
            default:
                // The page refuses or is gone: an answer about it.
                return .line(nil)
            }
        }
        known[key] = task

        switch await task.value {
        case .line(let line):
            answers.setObject(Answer(line), forKey: key as NSString)
            return line
        case .unreachable:
            // Asked again next time. Only this request's task is removed, because a newer request may be
            // pending.
            if known[key] == task { known[key] = nil }
            return nil
        }
    }

    /// The page's own description: Open Graph first, then the plain one.
    public static func fromPage(_ html: String) -> String? {
        var social: String?
        var plain: String?
        let meta = try! NSRegularExpression(pattern: "<meta\\b[^>]*>", options: .caseInsensitive)
        let attribute = try! NSRegularExpression(pattern: "([a-zA-Z:-]+)\\s*=\\s*(\"([^\"]*)\"|'([^']*)')")
        let whole = NSRange(html.startIndex..., in: html)
        for tag in meta.matches(in: html, range: whole) {
            guard let tagRange = Range(tag.range, in: html) else { continue }
            let text = String(html[tagRange])
            var attributes: [String: String] = [:]
            for m in attribute.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let name = Range(m.range(at: 1), in: text) else { continue }
                let value = Range(m.range(at: 3), in: text) ?? Range(m.range(at: 4), in: text)
                attributes[text[name].lowercased()] = value.map { String(text[$0]) } ?? ""
            }
            guard let what = attributes["property"] ?? attributes["name"],
                  let content = attributes["content"] else { continue }
            if social == nil, what.caseInsensitiveCompare("og:description") == .orderedSame {
                social = content
            } else if plain == nil, what.caseInsensitiveCompare("description") == .orderedSame {
                plain = content
            }
        }
        return shorten(social) ?? shorten(plain)
    }

    /// One line of at most ``longest`` characters. The text is kept whole if it fits. Otherwise it is
    /// cut at the last sentence end, or else at a word, with an ellipsis.
    public static func shorten(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let line = unescape(text)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let chars = Array(line)
        guard chars.count >= shortest else { return nil }
        if chars.count <= longest { return line }

        for end in stride(from: longest, through: shortest, by: -1) where end <= chars.count {
            if ".!?".contains(chars[end - 1]), end == chars.count || chars[end] == " " {
                return String(chars[0..<end]).trimmingCharacters(in: .whitespaces)
            }
        }
        let cut = chars[0..<(longest - 1)]
        if let space = cut.lastIndex(of: " "), space >= shortest {
            return String(chars[0..<space]).trimmingCharacters(in: .whitespaces) + "\u{2026}"
        }
        return String(cut).trimmingCharacters(in: .whitespaces) + "\u{2026}"
    }

    /// Replaces the HTML entities that a description is written with.
    private static func unescape(_ text: String) -> String {
        var out = text
        for (entity, char) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"),
                               ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: entity, with: char)
        }
        let numeric = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        var result = ""
        var last = out.startIndex
        for m in numeric.matches(in: out, range: NSRange(out.startIndex..., in: out)) {
            guard let range = Range(m.range, in: out), let hex = Range(m.range(at: 1), in: out),
                  let digits = Range(m.range(at: 2), in: out) else { continue }
            result += out[last..<range.lowerBound]
            let value = UInt32(out[digits], radix: out[hex].isEmpty ? 10 : 16)
            result += value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(out[range])
            last = range.upperBound
        }
        result += out[last...]
        return result
    }
}
