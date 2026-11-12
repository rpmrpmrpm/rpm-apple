import Testing
import Foundation
@testable import RPMKit

private let api = URL(string: "https://api.example.com")!

private func community(
    _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> RPMCommunityClient {
    RPMCommunityClient(transport: Transport(
        base: api, tokens: FixedTokens(token: "t"), reach: openLine(),
        session: stubbedSession(handler)))
}

private func community(_ status: Int, _ json: String = "") -> RPMCommunityClient {
    RPMCommunityClient(transport: Transport(
        base: api, tokens: FixedTokens(token: "t"), reach: openLine(),
        session: replying(status, json)))
}

private func sent(_ request: URLRequest) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: request.bodyData) as? [String: Any])
}

// ── the lines ──

@Test func theWallFixtureReadsBothKindsOfLine() throws {
    let wall = try fixture("artist-wall", as: [RPMWallEntry].self)
    #expect(wall.count == 4)

    let post = wall[0]
    #expect(post.isPost && !post.isReview)
    #expect(post.lineKey == nil)
    #expect(post.line == "Saw them in 1980.")
    #expect(post.written == Date(timeIntervalSince1970: 1_790_000_000.003))

    let review = wall[1]
    #expect(review.isReview && !review.isPost)
    #expect(review.lineKey == "Artists_WallWroteReview")
    #expect(review.stars == 4.5)
    #expect(review.line.contains("Remain in Light"))
    #expect(review.line != "Artists_WallWroteReview")

    let rating = wall[2]
    #expect(rating.lineKey == "Artists_WallRated")
    #expect(rating.authorShown == Loc.get("Community_DeletedUser"))
}

/// A kind this build does not know is neither a post nor a review, so the page does not draw it as
/// a post with no words.
@Test func aKindFromANewerServerIsNeitherPostNorReview() throws {
    let unknown = try fixture("artist-wall", as: [RPMWallEntry].self)[3]
    #expect(!unknown.isPost)
    #expect(!unknown.isReview)
    #expect(unknown.rating == 0)
    #expect(unknown.albumTitle == nil)
}

// ── finding the artist ──

@Test func anArtistIsLookedUpByNameWithoutCreatingOne() async throws {
    let asked = Box<URLRequest>()
    let client = community { request in
        asked.value = request
        return ok(request, #"{"artistId":"ar_7f3c","name":"Talking Heads","createdAt":1790000000000}"#)
    }

    let artist = try await client.lookupArtist(name: "Talking Heads")

    #expect(artist?.artistId == "ar_7f3c")
    #expect(asked.value?.httpMethod == "GET")
    #expect(asked.value?.url?.path == "/artists/lookup")
    #expect(asked.value?.url?.query == "name=Talking%20Heads")
}

/// Nobody has written about most artists. That is a wall with nothing on it, not a failure.
@Test func anArtistNobodyWroteAboutIsNil() async throws {
    #expect(try await community(404).lookupArtist(name: "Talking Heads") == nil)
}

/// A failure throws, so the page can say the wall is not available instead of saying it is empty.
@Test func aWallThatCannotBeReadThrows() async {
    await #expect(throws: RPMError.self) {
        _ = try await community(500).lookupArtist(name: "Talking Heads")
    }
}

@Test func aBlankNameIsNotAsked() async throws {
    let asked = Box<Int>()
    let client = community { request in
        asked.value = (asked.value ?? 0) + 1
        return ok(request, "{}")
    }

    #expect(try await client.lookupArtist(name: "  ") == nil)
    #expect(asked.value == nil)
}

// ── writing ──

@Test func aPostGoesToTheArtistsWall() async throws {
    let asked = Box<URLRequest>()
    let client = community { request in
        asked.value = request
        return ok(request, #"{"artistId":"ar 1","entryId":"e1","kind":"post","userId":"u","body":"Hi"}"#)
    }

    let entry = try await client.postToWall(artistId: "ar 1", body: "Hi")

    let request = try #require(asked.value)
    #expect(entry.isPost)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.absoluteString == "https://api.example.com/artists/ar%201/wall")
    #expect(try sent(request)["body"] as? String == "Hi")
}

@Test func resolvingAnArtistSendsTheName() async throws {
    let asked = Box<URLRequest>()
    let client = community { request in
        asked.value = request
        return ok(request, #"{"artistId":"ar_7f3c","name":"Talking Heads"}"#)
    }

    _ = try await client.resolveArtist(name: "Talking Heads")

    let request = try #require(asked.value)
    #expect(request.httpMethod == "POST")
    #expect(request.url?.path == "/artists/resolve")
    #expect(try sent(request)["name"] as? String == "Talking Heads")
}

// ── reporting ──

/// The server reads `targetType`, and a wall post report must name the artist. Without either it
/// answers 400 and the report is lost.
@Test func aWallPostReportNamesTheArtistAndTheLine() async throws {
    let asked = Box<URLRequest>()
    let client = community { request in
        asked.value = request
        return ok(request, #"{"reportId":"r1"}"#)
    }

    try await client.report(.wallPost(artistId: "ar_7f3c", entryId: "e1"), reason: "wallpost", note: "Spam")

    let body = try sent(try #require(asked.value))
    #expect(body["targetType"] as? String == "wallpost")
    #expect(body["artistId"] as? String == "ar_7f3c")
    #expect(body["targetId"] as? String == "e1")
    #expect(body["note"] as? String == "Spam")
    #expect(body["albumId"] == nil)
}

@Test func aCommentReportNamesTheAlbum() async throws {
    let asked = Box<URLRequest>()
    let client = community { request in
        asked.value = request
        return ok(request, #"{"reportId":"r1"}"#)
    }

    try await client.report(.comment(albumId: "al_1", commentId: "c9"), reason: nil, note: nil)

    let body = try sent(try #require(asked.value))
    #expect(body["targetType"] as? String == "comment")
    #expect(body["albumId"] as? String == "al_1")
    #expect(body["targetId"] as? String == "c9")
    #expect(body["artistId"] == nil)
    #expect(body["reason"] == nil)
}
