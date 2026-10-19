import Foundation

/// A Wikipedia lead section in plain text, with the page it was read from.
///
/// Port of `EncyclopediaArticle` in `RPM.Core/Metadata/Providers/Encyclopedia.cs`.
public struct EncyclopediaArticle: Codable, Sendable, Equatable, Identifiable {
    /// The wiki it came from: "en", "nl".
    public let language: String
    public let title: String

    /// Plain text, paragraphs separated by a blank line.
    public let extract: String

    /// The article on Wikipedia, for the credit under the text.
    public let url: String

    public var id: String { url }

    public init(language: String, title: String, extract: String, url: String) {
        self.language = language
        self.title = title
        self.extract = extract
        self.url = url
    }

    /// The paragraphs, in order.
    public var paragraphs: [String] {
        extract.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }
}

/// Reading Wikidata and Wikipedia: from an entity id or a link to a paragraph of text.
///
/// Port of `WikipediaJson` and the two link readers in `ReferenceLinks`, in
/// `RPM.Core/Metadata/Providers`. The rules are the desktop's and are kept the same, so the two
/// apps show the same article for the same record.
public enum Encyclopedia {
    /// Which Wikipedias to read, best first: the reader's own language, then English. English is
    /// where the article usually is, and it is a fallback rather than a preference.
    ///
    /// - Parameter preferred: the phone's languages, best first (`Locale.preferredLanguages`).
    ///   Only the first is used, as the desktop uses only its UI culture.
    public static func languages(preferred: [String]) -> [String] {
        let own = preferred.first.map(baseLanguage) ?? ""
        return own.isEmpty || own == "en" ? ["en"] : [own, "en"]
    }

    /// "zh-Hans" to "zh", "nl_NL" to "nl". Lower-cased, because Wikidata's site keys are.
    public static func baseLanguage(_ language: String) -> String {
        let code = language.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return "" }
        let head = code.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? code
        return head.lowercased()
    }

    // ── links ──

    /// The Wikidata entity a link points at ("Q170572"), or nil for any other link.
    public static func wikidataEntity(_ url: String) -> String? {
        guard let parsed = URL(string: url), let host = parsed.host?.lowercased(),
              host.hasSuffix("wikidata.org")
        else { return nil }

        let last = parsed.path.split(separator: "/").last.map(String.init) ?? ""
        guard last.count > 1, let first = last.first, first == "Q" || first == "q",
              last.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }

        return "Q" + last.dropFirst()
    }

    /// The language and title of a Wikipedia article link, or nil for any other link.
    public static func wikipediaArticle(_ url: String) -> (language: String, title: String)? {
        guard let parsed = URL(string: url), let host = parsed.host?.lowercased(),
              host.hasSuffix("wikipedia.org")
        else { return nil }

        let parts = host.split(separator: ".")
        let language = parts.count >= 3 ? String(parts[0]) : "en"

        // `path` is already percent-decoded.
        let wiki = "/wiki/"
        let path = parsed.path
        guard path.hasPrefix(wiki), path.count > wiki.count else { return nil }

        let title = String(path.dropFirst(wiki.count)).replacingOccurrences(of: "_", with: " ")
        return title.trimmingCharacters(in: .whitespaces).isEmpty ? nil : (language, title)
    }

    /// The first link on a Wikidata host and the first on a Wikipedia host, which is what the
    /// desktop's `ReferenceLinks.Merge` keeps: one link per site, the first one listed.
    static func firstLink(_ links: [CatalogLink], onHost suffix: String) -> String? {
        links.first { link in
            guard let host = URL(string: link.url)?.host?.lowercased() else { return false }
            return host.hasSuffix(suffix)
        }?.url
    }

    // ── Wikidata ──

    /// Which Wikipedia has an article for the entity, in the order of `languages`, and what it is
    /// called there.
    ///
    /// Wikidata keys its sitelinks "enwiki", "nlwiki": the language code with "wiki" on the end.
    /// Sister projects ("enwikiquote", "commonswiki") are in the same dictionary and are not
    /// Wikipedia, so only an exact "{language}wiki" counts.
    public static func sitelink(_ json: Data, languages: [String]) -> (language: String, title: String)? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let entities = root["entities"] as? [String: Any]
        else { return nil }

        for case let entity as [String: Any] in entities.values {
            guard let sitelinks = entity["sitelinks"] as? [String: Any] else { continue }

            for language in languages {
                let code = baseLanguage(language)
                guard !code.isEmpty else { continue }

                if let link = sitelinks[code + "wiki"] as? [String: Any],
                   let title = link["title"] as? String, !title.isEmpty {
                    return (code, title)
                }
            }
        }

        return nil
    }

    // ── Wikipedia ──

    /// The lead section of an article, as the MediaWiki action API returns it with
    /// `prop=extracts&exintro&explaintext`.
    ///
    /// Nil for a page that does not exist (the API marks it "missing" rather than failing) and for
    /// a disambiguation page, which is a list of other articles and reads as nonsense under an
    /// album's name.
    public static func extract(_ json: Data, language: String) -> EncyclopediaArticle? {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let query = root["query"] as? [String: Any],
              let pages = query["pages"] as? [String: Any]
        else { return nil }

        for case let page as [String: Any] in pages.values {
            if page["missing"] != nil { continue }

            guard let text = page["extract"] as? String,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }

            if let props = page["pageprops"] as? [String: Any], props["disambiguation"] != nil {
                continue
            }

            let title = page["title"] as? String ?? ""
            let url = (page["fullurl"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? "https://\(language).wikipedia.org/wiki/"
                   + (title.replacingOccurrences(of: " ", with: "_")
                        .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "")

            return EncyclopediaArticle(language: language, title: title, extract: tidy(text), url: url)
        }

        return nil
    }

    /// The API separates paragraphs with one newline and leaves blank lines where its section
    /// headings were. Paragraphs are joined with a blank line and the stray whitespace goes.
    static func tidy(_ extract: String) -> String {
        extract
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
