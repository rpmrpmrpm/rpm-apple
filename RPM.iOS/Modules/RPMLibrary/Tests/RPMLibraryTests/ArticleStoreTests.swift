import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

private let girl = ArticleStore.Subject.album(artist: "Pharrell Williams", title: "G I R L", tracks: 10)

private let written = EncyclopediaArticle(
    language: "nl", title: "G I R L", extract: "Het tweede soloalbum.",
    url: "https://nl.wikipedia.org/wiki/G_I_R_L")

private struct Down: Error {}

private func folder() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("articles-\(UUID().uuidString)", isDirectory: true)
}

@MainActor
private func store(_ directory: URL? = nil, languages: [String] = ["nl", "en"],
                   asked: Counter = Counter(), partial: Bool = false,
                   answer: @escaping @Sendable () throws -> EncyclopediaArticle? = { written })
    -> ArticleStore {
    ArticleStore(languages: languages, directory: directory) { _, _ in
        asked.bump()
        return ArticleAnswer(article: try answer(), partial: partial)
    }
}

/// Sets the modification date of every file in the folder to `days` ago, to simulate older files.
private func age(_ directory: URL, days: Double) throws {
    let then = Date().addingTimeInterval(-days * 24 * 3600)
    for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
        try FileManager.default.setAttributes([.modificationDate: then], ofItemAtPath: file.path)
    }
}

// ── asking ──

@MainActor
@Test func anArticleIsAskedForOnceAndThenKnown() async {
    let asked = Counter()
    let articles = store(asked: asked)

    #expect(articles.cached(girl) == nil)
    #expect(await articles.article(girl) == written)
    #expect(articles.cached(girl) == written)
    #expect(await articles.article(girl) == written)
    #expect(asked.value == 1)
}

/// Two callers asking about one record at the same time share one request.
@MainActor
@Test func twoPagesAskingAtOnceMakeOneRequest() async {
    let asked = Counter()
    let articles = ArticleStore(languages: ["en"], directory: nil) { _, _ in
        asked.bump()
        try await Task.sleep(for: .milliseconds(50))
        return ArticleAnswer(article: written, partial: false)
    }

    async let first = articles.article(girl)
    async let second = articles.article(girl)
    let both = await [first, second]

    #expect(both == [written, written])
    #expect(asked.value == 1)
}

/// "No article" is a valid answer, so it is kept and not asked again.
@MainActor
@Test func noArticleIsKeptAsAnAnswer() async {
    let asked = Counter()
    let articles = store(asked: asked, answer: { nil })

    #expect(await articles.article(girl) == nil)
    #expect(await articles.article(girl) == nil)
    #expect(asked.value == 1)
}

/// A partial answer from the API is shown but not stored. The next caller asks again and gets the rest.
/// If it were stored, "no article" would hold for five days.
@MainActor
@Test func aPartialAnswerIsShownAndNotKept() async {
    let asked = Counter()
    let articles = store(asked: asked, partial: true, answer: { nil })

    #expect(await articles.article(girl) == nil)
    #expect(articles.cached(girl) == nil)
    #expect(await articles.article(girl) == nil)
    #expect(asked.value == 2)
}

/// A failed request is not an answer. The next caller asks again.
@MainActor
@Test func aFailureIsNotKept() async {
    let asked = Counter()
    let articles = store(asked: asked, answer: { throw Down() })

    #expect(await articles.article(girl) == nil)
    #expect(await articles.article(girl) == nil)
    #expect(asked.value == 2)
}

/// If the caller stops waiting before the answer arrives, the request still finishes and its answer
/// is stored.
@MainActor
@Test func aPageThatStopsWaitingDoesNotStopTheRequest() async {
    let asked = Counter()
    let articles = ArticleStore(languages: ["en"], directory: nil) { _, _ in
        asked.bump()
        try? await Task.sleep(for: .milliseconds(50))
        return ArticleAnswer(article: written, partial: false)
    }

    let page = Task { await articles.article(girl) }
    page.cancel()
    _ = await page.value

    #expect(articles.cached(girl) == written)
    #expect(asked.value == 1)
}

@MainActor
@Test func theCompilationsShelfAndBlankNamesAreNotAskedAbout() async {
    let asked = Counter()
    let articles = store(asked: asked)

    #expect(await articles.article(.artist("Various Artists")) == nil)
    #expect(await articles.article(.artist("  ")) == nil)
    #expect(await articles.article(.album(artist: "", title: "G I R L", tracks: 10)) == nil)
    #expect(asked.value == 0)
}

/// The track count helps the server, but it is not part of the article's identity.
@MainActor
@Test func theTrackCountIsNotPartOfTheSubject() async {
    let asked = Counter()
    let articles = store(asked: asked)

    _ = await articles.article(girl)
    let recounted = ArticleStore.Subject.album(artist: "pharrell williams ", title: "G I R L", tracks: 11)

    #expect(recounted.id == girl.id)
    #expect(articles.cached(recounted) == written)
    #expect(asked.value == 1)
}

// ── the disk ──

/// An article saved on disk is available on the first frame of the next launch.
@MainActor
@Test func anAnswerIsReadBackInTheNextLaunch() async {
    let directory = folder()
    _ = await store(directory).article(girl)

    let asked = Counter()
    let next = store(directory, asked: asked)

    #expect(next.cached(girl) == written)
    #expect(await next.article(girl) == written)
    #expect(asked.value == 0)
}

/// Each language has its own article, so a different language is asked for again.
@MainActor
@Test func anotherLanguageIsAskedAgain() async {
    let directory = folder()
    _ = await store(directory, languages: ["nl", "en"]).article(girl)

    #expect(store(directory, languages: ["fr", "en"]).cached(girl) == nil)
}

/// An article is kept for 30 days. A "no article" answer is kept for 5 days, so an article written later
/// is still found.
@MainActor
@Test func noArticleIsAskedAgainAfterFiveDaysAndAnArticleAfterThirty() async throws {
    let none = folder()
    _ = await store(none, answer: { nil }).article(girl)
    try age(none, days: 6)

    let askedNone = Counter()
    _ = await store(none, asked: askedNone, answer: { nil }).article(girl)
    #expect(askedNone.value == 1)

    let found = folder()
    _ = await store(found).article(girl)
    try age(found, days: 6)
    #expect(store(found).cached(girl) == written)

    try age(found, days: 31)
    #expect(store(found).cached(girl) == nil)
}

/// A subject that was looked up before it was fetched is known once the fetch finishes. The earlier miss
/// does not hide the answer.
@MainActor
@Test func aSubjectLookedForBeforeItWasFetchedIsKnownOnceFetched() async {
    let articles = store(folder())

    #expect(articles.cached(girl) == nil)
    _ = await articles.article(girl)
    #expect(articles.cached(girl) == written)
}

// ── a genre ──

/// A genre is asked about under its name, once, and then known, as a record is.
@MainActor
@Test func aGenreIsAskedForOnceAndThenKnown() async {
    let asked = Counter()
    let articles = store(asked: asked)
    let rock = ArticleStore.Subject.genre("Rock")

    #expect(await articles.article(rock) == written)
    #expect(articles.cached(rock) == written)
    #expect(asked.value == 1)
}

/// A blank genre is not asked about at all.
@MainActor
@Test func aBlankGenreIsNotAskedAbout() async {
    let asked = Counter()
    #expect(await store(asked: asked).article(.genre("  ")) == nil)
    #expect(asked.value == 0)
}

