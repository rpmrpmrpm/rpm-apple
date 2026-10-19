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

private let said = #"""
{"userId":"them","displayName":"Ada","hasAvatar":true,"avatarUpdatedAt":1787870345843,
 "createdAt":1787870345843,"supporter":true}
"""#

// ── whose collection it is ──

/// `profile` is the caller's OWN; everybody else's is `profiles/{id}`. Asking for
/// `profile/{id}` is a 404 that looks like a person with no name, and every shared
/// library would then be called "Shared library".
@Test func somebodyElsesProfileIsAskedForUnderProfilesPlural() async throws {
    let asked = Box<String>()
    let client = community { request in
        asked.value = request.url!.path
        return ok(request, said)
    }

    let profile = try await client.publicProfile(userId: "them")

    #expect(asked.value == "/profiles/them")
    #expect(profile?.displayName == "Ada")
    #expect(profile?.supporter == true)
}

@Test func anIdWithNothingBehindItIsNotAsked() async throws {
    let asked = Box<Int>()
    let client = community { request in
        asked.value = (asked.value ?? 0) + 1
        return ok(request, said)
    }

    #expect(try await client.publicProfile(userId: "") == nil)
    #expect(asked.value == nil)
}

/// An account that never named itself is an answer, and the row draws whatever it
/// was told to call a nameless collection.
@Test func anAccountWithNoProfileIsNilRatherThanAThrow() async throws {
    #expect(try await community(404).publicProfile(userId: "them") == nil)
}

/// The other half of that, and the reason it throws rather than answering nil: a
/// caller that cannot tell an outage from a nameless account files the outage as a
/// person and never asks again.
@Test func aServiceHavingABadMinuteThrows() async {
    await #expect(throws: RPMError.self) {
        _ = try await community(500).publicProfile(userId: "them")
    }
}

// ── where their picture is ──

@Test func theAvatarAddressCarriesTheProfilesStamp() throws {
    let profile = try RPMJSON.decoder.decode(RPMProfile.self, from: Data(said.utf8))

    #expect(community(200).avatar(for: profile)?.absoluteString
            == "https://api.example.com/profiles/them/avatar?v=1787870345843")
}

@Test func somebodyWithNoPictureHasNoAddress() throws {
    let none = #"{"userId":"them","displayName":"Ada","hasAvatar":false,"avatarUpdatedAt":0}"#
    let profile = try RPMJSON.decoder.decode(RPMProfile.self, from: Data(none.utf8))

    #expect(community(200).avatar(for: profile) == nil)
}

/// A picture that has never been replaced has no stamp to hang, and a `?v=0` would
/// be a second address for the same bytes.
@Test func aPictureThatHasNeverChangedIsAskedForPlainly() throws {
    let fresh = #"{"userId":"them","displayName":"Ada","hasAvatar":true,"avatarUpdatedAt":0}"#
    let profile = try RPMJSON.decoder.decode(RPMProfile.self, from: Data(fresh.utf8))

    #expect(community(200).avatar(for: profile)?.absoluteString
            == "https://api.example.com/profiles/them/avatar")
}

// ── a deleted author ──

/// A deleted account's review keeps its words and loses its name; the phone draws "Deleted user".
@Test func aDeletedAuthorsReviewIsDrawnAsDeletedUser() throws {
    let json = #"{"albumId":"a1","userId":"u1","authorName":"","hasAvatar":false,"rating":8,"body":"Loud.","authorDeleted":true}"#
    let review = try RPMJSON.decoder.decode(RPMReview.self, from: Data(json.utf8))

    #expect(review.authorDeleted)
    #expect(review.authorShown == Loc.get("Community_DeletedUser"))
    #expect(review.authorShown != "Community_DeletedUser")
    #expect(review.body == "Loud.")
}

@Test func aReviewFromAnOlderServerIsNotADeletedAuthor() throws {
    let json = #"{"albumId":"a1","userId":"u1","authorName":"Anna","hasAvatar":true,"rating":6,"body":"Fine."}"#
    let review = try RPMJSON.decoder.decode(RPMReview.self, from: Data(json.utf8))

    #expect(!review.authorDeleted)
    #expect(review.authorShown == "Anna")
}
