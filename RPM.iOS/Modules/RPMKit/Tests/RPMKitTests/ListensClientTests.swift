import Testing
import Foundation
@testable import RPMKit

private func client(
    _ handler: @escaping @Sendable (URLRequest) -> (HTTPURLResponse, Data)
) -> RPMCloudClient {
    RPMCloudClient(transport: Transport(
        base: URL(string: "https://api.example.com")!,
        tokens: FixedTokens(token: "t"),
        reach: openLine(),
        session: stubbedSession(handler)))
}

private func status(_ request: URLRequest, _ code: Int, _ json: String) -> (HTTPURLResponse, Data) {
    (HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
}

// ── the listening log ──

@Test func listensArePutUnderTheDeviceWithEveryField() async throws {
    let seen = Box<(String, String, Data)>()
    let cloud = client { request in
        seen.value = (request.httpMethod ?? "", request.url?.path ?? "", request.bodyData)
        return ok(request, #"{"receivedAt":1790000000123}"#)
    }

    let stamp = try await cloud.sendListens(deviceId: "phone-1", listens: [
        CloudListen(listenId: "l1", rpmId: "t1", at: 1_790_000_000, heardSeconds: 120.5, lengthSeconds: 241,
                    counted: true, localHour: 23, localDayOfWeek: 5),
    ])

    #expect(stamp == 1_790_000_000_123)
    let (method, path, body) = try #require(seen.value)
    #expect(method == "PUT")
    #expect(path == "/cloud/listens")
    let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["deviceId"] as? String == "phone-1")
    let listen = try #require((json["listens"] as? [[String: Any]])?.first)
    #expect(listen["listenId"] as? String == "l1")
    #expect(listen["rpmId"] as? String == "t1")
    #expect(listen["at"] as? Int64 == 1_790_000_000)
    #expect(listen["heardSeconds"] as? Double == 120.5)
    #expect(listen["lengthSeconds"] as? Double == 241)
    #expect(listen["counted"] as? Bool == true)
    #expect(listen["localHour"] as? Int == 23)
    #expect(listen["localDayOfWeek"] as? Int == 5)
}

// ── the generated lists ──

@Test func theListsAreAskedForInTheAppsLanguageAndZone() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"recipe":1,"computedAt":1,"lists":[]}"#)
    }

    _ = try await cloud.moodLists(.own, language: "zh-Hans", zone: "America/Argentina/Buenos_Aires")

    let query = URLComponents(url: try #require(seen.value), resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(query.first { $0.name == "lang" }?.value == "zh-Hans")
    #expect(query.first { $0.name == "tz" }?.value == "America/Argentina/Buenos_Aires")
}

@Test func aBorrowedShelfsListsAreAskedForUnderItsOwnerWithTheZone() async throws {
    let seen = Box<URL>()
    let cloud = client { request in
        seen.value = request.url
        return ok(request, #"{"recipe":1,"computedAt":1,"lists":[]}"#)
    }

    _ = try await cloud.moodLists(.of("owner-1"), language: "en", zone: "Europe/Paris")

    let query = URLComponents(url: try #require(seen.value), resolvingAgainstBaseURL: false)?.queryItems ?? []
    #expect(query.first { $0.name == "owner" }?.value == "owner-1")
    #expect(query.first { $0.name == "tz" }?.value == "Europe/Paris")
}

@Test func aPressIsAnsweredWithANewReading() async throws {
    let seen = Box<Data>()
    let cloud = client { request in
        seen.value = request.bodyData
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/cloud/moodlists/next")
        return ok(request, #"{"id":"L","trackIds":["a","b"],"shows":50}"#)
    }

    let reading = try await cloud.nextReading(of: "L", reading: 5, language: "fr", zone: "Europe/Paris")

    #expect(reading == CloudListReading(id: "L", trackIds: ["a", "b"], shows: 50))
    let sent = try #require(seen.value)
    let json = try #require(JSONSerialization.jsonObject(with: sent) as? [String: Any])
    #expect(json["id"] as? String == "L")
    #expect(json["reading"] as? Int == 5)
    #expect(json["lang"] as? String == "fr")
    #expect(json["tz"] as? String == "Europe/Paris")
}

/// The store is still building the library, or no longer offers the list. Neither is a failure: the
/// app shows the next of the readings it was sent.
@Test func aPressTheStoreCannotAnswerYetIsNil() async throws {
    #expect(try await client { status($0, 409, #"{"message":"building"}"#) }
        .nextReading(of: "L", reading: 1, language: "en", zone: "UTC") == nil)
    #expect(try await client { status($0, 404, "") }
        .nextReading(of: "L", reading: 1, language: "en", zone: "UTC") == nil)
}
