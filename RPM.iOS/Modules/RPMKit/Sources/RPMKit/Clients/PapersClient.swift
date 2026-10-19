import Foundation

/// The Wikipedia text about a record or an artist, found the same way as in the desktop app.
///
/// Two halves, as in the desktop app (`TrackInfoService` and `EncyclopediaLookup`). Keep them
/// the same:
///
/// 1. **The catalogue half goes to the RPM API**, `metadata/papers`, with the same query the
///    desktop sends. The server identifies the act and the record, keeps the answer for all users,
///    and returns the Wikidata entity and the outside links.
/// 2. **The encyclopedia half is asked from the device**, because which Wikipedia to read depends
///    on the reader's language, and an answer that the server caches for all users could only be
///    in one language. Wikidata comes first, because the catalogue points to it and a person
///    matched the entity. A direct Wikipedia link is used only when there is no entity. Nothing
///    searches Wikipedia by name: a paragraph about the wrong band is worse than none.
///
/// **Nil and a throw are different answers.** Nil means the question was answered and there is no
/// article: the record is not in the catalogues, or has no Wikipedia page. A throw means somebody
/// did not answer (no network, a refused request, a server error). The cache in front of this keeps
/// the first kind of answer and never the second.
public struct PapersClient: Sendable {
    private static let wikidata = "https://www.wikidata.org/w/api.php"

    private let transport: Transport
    private let wire: Gated
    private let userAgent: String

    /// - Parameter reach: the same gate that every other request passes. It has no default, for
    ///   the reason that `Transport` gives.
    /// - Parameter userAgent: Wikipedia asks for one that names the app and a way to reach it.
    public init(transport: Transport, reach: NetworkReach, session: URLSession = Wire.session(),
                userAgent: String = "rpm/1.0 ( https://rpmrpmrpm.com )") {
        self.transport = transport
        self.wire = Gated(reach: reach, session: session)
        self.userAgent = userAgent
    }

    /// The article about one record.
    ///
    /// - Parameter artist: the album artist, as the files spell it.
    /// - Parameter album: the album title, as the files spell it. The server reduces it to the
    ///   release group's title, so an edition suffix does not lose the record.
    /// - Parameter tracks: how many songs the record has. The server uses it to tell an album from
    ///   the single of the same name.
    /// - Parameter languages: which Wikipedias to read, best first. See
    ///   ``Encyclopedia/languages(preferred:)``.
    public func albumArticle(artist: String, album: String, tracks: Int,
                             languages: [String]) async throws -> ArticleAnswer {
        guard !Self.blank(artist), !Self.blank(album) else { return .none }

        let (papers, partial) = try await papers(artist: artist, album: album, tracks: tracks)

        // The desktop app drops a record with no title before it looks for the article
        // (`EncyclopediaLookup.Profile`). This code does the same.
        guard let record = papers.album, !Self.blank(record.title) else {
            return ArticleAnswer(article: nil, partial: partial)
        }

        return ArticleAnswer(article: try await article(entity: nil, links: record.links ?? [], languages: languages),
                             partial: partial)
    }

    /// The article about one act, asked with the name alone, as the desktop app's artist page asks.
    public func artistArticle(artist: String, languages: [String]) async throws -> ArticleAnswer {
        guard !Self.blank(artist) else { return .none }

        let (papers, partial) = try await papers(artist: artist, album: nil, tracks: 0)
        guard let act = papers.artist else { return ArticleAnswer(article: nil, partial: partial) }

        // The desktop app reads the entity from the act whether or not it has a name, and reads the
        // links only when it has a name (`EncyclopediaLookup.ArticlesForAsync`). This code does the
        // same.
        let links = Self.blank(act.name) ? [] : act.links ?? []
        return ArticleAnswer(article: try await article(entity: act.wikidataId, links: links, languages: languages),
                             partial: partial)
    }

    /// What is said about a genre: the opening of the English Wikipedia article ``GenreArticles``
    /// names for it, as the desktop app's genre page reads it (`EncyclopediaLookup.GenreArticleAsync`,
    /// English only). It returns nothing for a genre that the table does not name.
    public func genreArticle(_ genre: String) async throws -> ArticleAnswer {
        guard let title = GenreArticles.title(genre) else { return .none }
        return ArticleAnswer(article: try await extract(language: "en", title: title), partial: false)
    }

    // ── the catalogue half ──

    private func papers(artist: String, album: String?, tracks: Int) async throws -> (CatalogPapers, Bool) {
        var path = "metadata/papers?artist=" + escaped(artist)
        if let album, !Self.blank(album) { path += "&album=" + escaped(album) }
        if tracks > 0 { path += "&tracks=\(tracks)" }

        let (papers, partial) = try await transport.getMarked(path, as: CatalogPapers.self)
        return (papers, partial)
    }

    // ── the encyclopedia half ──

    /// Looks up the entity that the API named once, or the first Wikidata link if there is no
    /// entity. If it has no page in any of `languages`, the first Wikipedia link is read instead.
    private func article(entity: String?, links: [CatalogLink],
                         languages: [String]) async throws -> EncyclopediaArticle? {
        let named = entity.flatMap { Self.blank($0) ? nil : $0 }
            ?? Encyclopedia.firstLink(links, onHost: "wikidata.org").flatMap(Encyclopedia.wikidataEntity)

        if let named, let url = URL(string: Self.wikidata
            + "?action=wbgetentities&format=json&props=sitelinks&ids=" + escaped(named)) {
            let body = try await ask(url)
            if let found = Encyclopedia.sitelink(body, languages: languages) {
                return try await extract(language: found.language, title: found.title)
            }
        }

        if let link = Encyclopedia.firstLink(links, onHost: "wikipedia.org"),
           let found = Encyclopedia.wikipediaArticle(link) {
            return try await extract(language: found.language, title: found.title)
        }

        return nil
    }

    /// One article's lead section. `formatversion=1` keys the pages by id, which is the shape
    /// ``Encyclopedia/extract(_:language:)`` reads. `redirects=1` makes a title that has been
    /// renamed lead to the article under its new name.
    private func extract(language: String, title: String) async throws -> EncyclopediaArticle? {
        guard let url = URL(string: "https://\(language).wikipedia.org/w/api.php"
            + "?action=query&format=json&formatversion=1"
            + "&prop=extracts%7Cinfo%7Cpageprops&inprop=url&ppprop=disambiguation"
            + "&exintro=1&explaintext=1&redirects=1"
            + "&titles=" + escaped(title))
        else { return nil }

        return Encyclopedia.extract(try await ask(url), language: language)
    }

    private func ask(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, http) = try await wire.fetch(request, method: "GET")
        guard (200..<300).contains(http.statusCode) else {
            throw RPMError.status(http.statusCode)
        }
        return data
    }

    private static func blank(_ text: String?) -> Bool {
        (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func escaped(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}

/// An article, and whether the papers it was found through were only part of an answer.
///
/// A partial answer is shown but not kept. The API finishes the answer in the background, so the
/// next time the page is opened the article may be there, or may be a different one. If it were
/// kept, "no article" from a partial answer would stay for five days.
public struct ArticleAnswer: Sendable, Equatable {
    public let article: EncyclopediaArticle?
    public let partial: Bool

    public init(article: EncyclopediaArticle?, partial: Bool) {
        self.article = article
        self.partial = partial
    }

    /// No question was asked, because there was nothing to ask about.
    public static let none = ArticleAnswer(article: nil, partial: false)
}
