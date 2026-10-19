import Testing
import Foundation
@testable import RPMKit

private func client(_ status: Int, _ json: String) -> RPMCloudClient {
    RPMCloudClient(transport: Transport(
        base: URL(string: "https://api.example.com")!,
        tokens: FixedTokens(token: "t"),
        reach: openLine(),
        session: replying(status, json)))
}

// ── the generated lists ──
//
// The phone renders these and does not compute them: the arithmetic is
// percentiles over a whole collection, and this head has only the part of one
// that is in the cloud. What has to hold here is that a cut arrives whole and in
// order, that a computer which has never pushed reads as nothing rather than as
// a failure, and that a field an older store does not send does not throw the
// cut away.

@Test func aListSaysHowMuchOfItIsOneList() async throws {
    // What lets this phone offer a refresh: the run is four lists' worth and `shows`
    // is where one list stops. A cut from an older desktop app says nothing,
    // and the run is then the list.
    let cloud = client(200, #"""
    {"recipe":3,"computedAt":1756000000000,
     "lists":[{"kind":"Calm","trackIds":["a","b","c","d"],"shows":2},
              {"kind":"Sleep","trackIds":["e","f"]}]}
    """#)

    let cut = try await cloud.moodLists()

    #expect(cut?.lists.first?.shows == 2)
    #expect(cut?.lists.last?.shows == 0)
}

@Test func aCutArrivesWholeAndInOrder() async throws {
    let cloud = client(200, #"""
    {"recipe":1,"computedAt":1756000000000,
     "lists":[{"kind":"Calm","genre":"Rock","decade":0,"trackIds":["a","b","c"]},
              {"kind":"Danceable","genre":null,"decade":1970,"trackIds":["d"]}]}
    """#)

    let cut = try await cloud.moodLists()

    #expect(cut?.recipe == 1)
    #expect(cut?.lists.count == 2)
    #expect(cut?.lists.first?.kind == "Calm")
    #expect(cut?.lists.first?.genre == "Rock")
    // The order, not merely the membership: it decides which of a deeper pool
    // this phone shows, so a list that arrived shuffled would be a different one.
    #expect(cut?.lists.first?.trackIds == ["a", "b", "c"])
    #expect(cut?.lists.last?.decade == 1970)
    #expect(cut?.lists.last?.genre == nil)
}

@Test func aComputerThatHasNeverPushedReadsAsNothing() async throws {
    // An ordinary answer, not a failure: the phone shows the music it can play
    // and no generated lists.
    let cloud = client(404, "{}")

    #expect(try await cloud.moodLists() == nil)
}

@Test func aCutSaysHowOldItIs() async throws {
    // A computer that has not run in a month is a real state, and a month-old
    // list shown silently is not the same thing as a current one.
    let stamped = Int64(Date().timeIntervalSince1970 * 1000) - 60_000
    let cloud = client(200, #"{"recipe":1,"computedAt":\#(stamped),"lists":[]}"#)

    let age = try await cloud.moodLists()?.age

    #expect(age != nil)
    #expect(age! > 30 && age! < 300)
}

@Test func aCutWithNoStampAdmitsItCannotSayHowOldItIs() async throws {
    let cloud = client(200, #"{"recipe":1,"lists":[]}"#)

    #expect(try await cloud.moodLists()?.age == nil)
}

@Test func aFieldAnOlderStoreDoesNotSendDoesNotThrowTheCutAway() async throws {
    // Every field is decoded if-present. A list missing its decade is a list on
    // every decade, which is what an absent field means.
    let cloud = client(200, #"{"lists":[{"kind":"Sleep","trackIds":["a"]}]}"#)

    let cut = try await cloud.moodLists()

    #expect(cut?.lists.count == 1)
    #expect(cut?.lists.first?.decade == 0)
    #expect(cut?.lists.first?.genre == nil)
    #expect(cut?.recipe == 0)
}

@Test func aListNamesItselfByWhatItIsRatherThanByAnIndex() {
    // Two lists differing only in decade are two lists, and the identity has to
    // say so or a view would collapse them into one row.
    let seventies = CloudMoodList(kind: "Calm", genre: "Rock", decade: 1970, trackIds: [])
    let eighties = CloudMoodList(kind: "Calm", genre: "Rock", decade: 1980, trackIds: [])

    #expect(seventies.id != eighties.id)
}

/// The name travels with the list, because the words are the computer's: a table of
/// a hundred and thirty-six titles that would drift if it were written twice.
@Test func aListCarriesTheNameTheComputerGaveIt() async throws {
    let cloud = client(200, #"""
    {"recipe":1,"computedAt":1756000000000,
     "lists":[{"kind":"Calm","genre":"Rock","decade":0,"title":"Slow Burn","trackIds":["a"]}]}
    """#)

    #expect(try await cloud.moodLists()?.lists.first?.title == "Slow Burn")
}

/// A cut pushed without names has none. An ordinary answer, and not one
/// that throws the cut away.
@Test func aCutWithNoNamesOnItStillArrives() async throws {
    let cloud = client(200, #"""
    {"recipe":1,"computedAt":1756000000000,
     "lists":[{"kind":"Calm","genre":"Rock","decade":0,"trackIds":["a"]}]}
    """#)

    let cut = try await cloud.moodLists()
    #expect(cut?.lists.count == 1)
    #expect(cut?.lists.first?.title == nil)
}
