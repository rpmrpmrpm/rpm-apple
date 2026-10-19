import Testing
import Foundation
@testable import RPMKit

private let api = URL(string: "https://api.example.com")!

/// A client whose API, Wikidata and Wikipedia all answer from `handler`, told apart by host.
private func papers(
    _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> PapersClient {
    let session = stubbedSession(handler)
    return PapersClient(
        transport: Transport(base: api, tokens: FixedTokens(token: nil), reach: openLine(),
                             session: session),
        reach: openLine(), session: session)
}

private func query(_ request: URLRequest) -> [String: String] {
    let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: true)?.queryItems ?? []
    return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
}

private let record = #"""
{"artist":{"name":"Pharrell Williams","wikidataId":"Q14313"},
 "album":{"title":"G I R L","links":[
   {"url":"https://www.discogs.com/master/123","relation":"discogs"},
   {"url":"https://www.wikidata.org/wiki/Q15733411","relation":"wikidata"},
   {"url":"https://en.wikipedia.org/wiki/Girl_(Pharrell_Williams_album)","relation":"wikipedia"}]}}
"""#

private let sitelinks = #"""
{"entities":{"Q15733411":{"sitelinks":{
  "enwiki":{"site":"enwiki","title":"Girl (Pharrell Williams album)"},
  "nlwikiquote":{"site":"nlwikiquote","title":"Not Wikipedia"},
  "nlwiki":{"site":"nlwiki","title":"G I R L"}}}}}
"""#

private let dutch = #"""
{"batchcomplete":"","query":{"pages":{"4567":{"pageid":4567,"ns":0,"title":"G I R L",
 "extract":"Het tweede soloalbum.\n\n\nHet kwam uit in 2014.  \n",
 "fullurl":"https://nl.wikipedia.org/wiki/G_I_R_L"}}}}
"""#

// ── the record ──

/// The route the desktop takes: the API's papers with the same query, the entity off the
/// record's links, and the reader's own Wikipedia first.
@Test func aRecordsArticleIsReadThroughItsWikidataEntityInTheReadersLanguage() async throws {
    let asked = Box<[String]>()
    let client = papers { request in
        asked.value = (asked.value ?? []) + [request.url!.host! + request.url!.path]
        switch request.url!.host! {
        case "api.example.com":
            let q = query(request)
            #expect(request.url!.path == "/metadata/papers")
            #expect(q["artist"] == "Pharrell Williams")
            #expect(q["album"] == "G I R L")
            #expect(q["tracks"] == "10")
            return ok(request, record)
        case "www.wikidata.org":
            #expect(query(request)["ids"] == "Q15733411")
            return ok(request, sitelinks)
        case "nl.wikipedia.org":
            #expect(query(request)["titles"] == "G I R L")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("rpm/") == true)
            return ok(request, dutch)
        default:
            Issue.record("asked \(request.url!)")
            return ok(request, "{}")
        }
    }

    let article = try await client.albumArticle(
        artist: "Pharrell Williams", album: "G I R L", tracks: 10, languages: ["nl", "en"]).article

    #expect(article?.language == "nl")
    #expect(article?.title == "G I R L")
    #expect(article?.extract == "Het tweede soloalbum.\n\nHet kwam uit in 2014.")
    #expect(article?.paragraphs.count == 2)
    #expect(article?.url == "https://nl.wikipedia.org/wiki/G_I_R_L")
    #expect(asked.value == ["api.example.com/metadata/papers", "www.wikidata.org/w/api.php",
                            "nl.wikipedia.org/w/api.php"])
}

/// An entity with no page in the reader's language is read in English.
@Test func anEntityWithNoPageInTheReadersLanguageIsReadInEnglish() async throws {
    let wiki = Box<String>()
    let client = papers { request in
        switch request.url!.host! {
        case "api.example.com": return ok(request, record)
        case "www.wikidata.org": return ok(request, sitelinks)
        default:
            wiki.value = request.url!.host!
            return ok(request, dutch)
        }
    }

    _ = try await client.albumArticle(
        artist: "Pharrell Williams", album: "G I R L", tracks: 10, languages: ["fr", "en"])

    #expect(wiki.value == "en.wikipedia.org")
}

/// Without an entity, the record's own Wikipedia link is read.
@Test func aRecordWithNoEntityIsReadFromItsWikipediaLink() async throws {
    let title = Box<String>()
    let client = papers { request in
        switch request.url!.host! {
        case "api.example.com":
            return ok(request, #"""
            {"album":{"title":"Girl","links":[
              {"url":"https://en.wikipedia.org/wiki/Girl_%28Pharrell_Williams_album%29"}]}}
            """#)
        case "en.wikipedia.org":
            title.value = query(request)["titles"]
            return ok(request, dutch)
        default:
            Issue.record("asked \(request.url!)")
            return ok(request, "{}")
        }
    }

    let article = try await client.albumArticle(
        artist: "Pharrell Williams", album: "Girl", tracks: 10, languages: ["en"]).article

    #expect(title.value == "Girl (Pharrell Williams album)")
    #expect(article != nil)
}

/// A record the catalogues do not know is an answer, and nothing else is asked.
@Test func aRecordTheCataloguesDoNotKnowHasNoArticle() async throws {
    let count = Tally()
    let client = papers { request in
        count.mark()
        return ok(request, #"{"artist":{"name":"Somebody"}}"#)
    }

    let article = try await client.albumArticle(
        artist: "Somebody", album: "Demo", tracks: 4, languages: ["en"]).article

    #expect(article == nil)
    #expect(count.count == 1)
}

/// The API not answering is a failure, not "no article", so the cache does not keep it.
@Test func theApiNotAnsweringThrows() async {
    let client = papers { request in
        (HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
         Data())
    }

    await #expect(throws: RPMError.self) {
        _ = try await client.albumArticle(
            artist: "Pharrell Williams", album: "G I R L", tracks: 10, languages: ["en"])
    }
}

/// Wikipedia not answering is a failure too.
@Test func wikipediaNotAnsweringThrows() async {
    let client = papers { request in
        switch request.url!.host! {
        case "api.example.com": return ok(request, record)
        case "www.wikidata.org": return ok(request, sitelinks)
        default:
            return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil,
                                    headerFields: nil)!, Data())
        }
    }

    await #expect(throws: RPMError.self) {
        _ = try await client.albumArticle(
            artist: "Pharrell Williams", album: "G I R L", tracks: 10, languages: ["nl", "en"])
    }
}

// ── the act ──

/// The artist page asks under the name alone, and reads the entity the API named.
@Test func anActsArticleIsAskedUnderTheirNameAloneAndReadThroughTheirEntity() async throws {
    let client = papers { request in
        switch request.url!.host! {
        case "api.example.com":
            let q = query(request)
            #expect(q["artist"] == "Pharrell Williams")
            #expect(q["album"] == nil)
            #expect(q["tracks"] == nil)
            return ok(request, record)
        case "www.wikidata.org":
            #expect(query(request)["ids"] == "Q14313")
            return ok(request, #"{"entities":{"Q14313":{"sitelinks":{"enwiki":{"title":"Pharrell Williams"}}}}}"#)
        default:
            return ok(request, #"""
            {"query":{"pages":{"1":{"title":"Pharrell Williams","extract":"An American musician.",
             "fullurl":"https://en.wikipedia.org/wiki/Pharrell_Williams"}}}}
            """#)
        }
    }

    let article = try await client.artistArticle(artist: "Pharrell Williams", languages: ["en"]).article

    #expect(article?.extract == "An American musician.")
}

// ── what Wikipedia says ──

@Test func aDisambiguationPageIsNoArticle() {
    let json = #"""
    {"query":{"pages":{"1":{"title":"Girl","extract":"Girl may refer to:",
     "pageprops":{"disambiguation":""}}}}}
    """#
    #expect(Encyclopedia.extract(Data(json.utf8), language: "en") == nil)
}

@Test func aMissingPageIsNoArticle() {
    let json = #"{"query":{"pages":{"-1":{"title":"Nobody","missing":""}}}}"#
    #expect(Encyclopedia.extract(Data(json.utf8), language: "en") == nil)
}

@Test func aPageWithoutAnAddressIsGivenOneFromItsTitle() {
    let json = #"{"query":{"pages":{"1":{"title":"Fine Line","extract":"An album."}}}}"#
    #expect(Encyclopedia.extract(Data(json.utf8), language: "en")?.url
            == "https://en.wikipedia.org/wiki/Fine_Line")
}

// ── links and languages ──

@Test func entitiesAndArticlesAreReadOffTheirLinks() {
    #expect(Encyclopedia.wikidataEntity("https://www.wikidata.org/wiki/Q15733411") == "Q15733411")
    #expect(Encyclopedia.wikidataEntity("https://www.wikidata.org/wiki/Property:P31") == nil)
    #expect(Encyclopedia.wikidataEntity("https://en.wikipedia.org/wiki/Q1") == nil)

    let found = Encyclopedia.wikipediaArticle("https://nl.wikipedia.org/wiki/Fine_Line_(album)")
    #expect(found?.language == "nl")
    #expect(found?.title == "Fine Line (album)")
    #expect(Encyclopedia.wikipediaArticle("https://nl.wikipedia.org/w/index.php?title=X") == nil)
}

@Test func theReaderIsGivenTheirOwnWikipediaThenEnglish() {
    #expect(Encyclopedia.languages(preferred: ["nl-NL", "en-GB"]) == ["nl", "en"])
    #expect(Encyclopedia.languages(preferred: ["zh-Hans-CN"]) == ["zh", "en"])
    #expect(Encyclopedia.languages(preferred: ["en-GB", "nl"]) == ["en"])
    #expect(Encyclopedia.languages(preferred: []) == ["en"])
}

// ── a partial answer ──

/// The API marks an answer that is only part of one, and finishes it in the background. The mark
/// comes through with the article, so the store shows it and keeps it nowhere.
@Test func aPartialAnswerIsMarked() async throws {
    let client = papers { request in
        switch request.url!.host! {
        case "api.example.com":
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json",
                                                          Transport.partialHeader: "1"])!
            return (response, Data(#"{"artist":{"name":"Pharrell Williams"}}"#.utf8))
        default:
            return ok(request, "{}")
        }
    }

    let answer = try await client.albumArticle(
        artist: "Pharrell Williams", album: "G I R L", tracks: 10, languages: ["en"])

    #expect(answer.partial)
    #expect(answer.article == nil)
}

/// And a whole one is not.
@Test func aWholeAnswerIsNotMarked() async throws {
    let client = papers { request in ok(request, #"{"artist":{"name":"Pharrell Williams"}}"#) }

    let answer = try await client.albumArticle(
        artist: "Pharrell Williams", album: "G I R L", tracks: 10, languages: ["en"])

    #expect(!answer.partial)
}
