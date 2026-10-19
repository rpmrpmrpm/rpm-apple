import Testing
import Foundation
@testable import RPMKit

/// The phone's reads of RPM's own radio record: `radio/logo/{uuid}` and `radio/state`. What has to
/// hold: every call carries the app key, a station with no logo is an answer and a failure is not,
/// the stamp is in the address, and the first state read of a launch goes past the url cache.
struct RadioRepositoryClientTests {
    private let uuid = "96062A7E-0601-11E8-AE97-52543BE04C81"

    private func repository(_ session: URLSession) -> RadioRepositoryClient {
        RadioRepositoryClient(transport: Transport(
            base: URL(string: "https://api.example.com")!,
            tokens: FixedTokens(token: nil),
            reach: openLine(),
            session: session))
    }

    private func answering(_ status: Int, _ body: Data,
                           seen: Box<URLRequest>? = nil) -> URLSession {
        stubbedSession { request in
            seen?.value = request
            return (HTTPURLResponse(url: request.url!, statusCode: status,
                                    httpVersion: nil, headerFields: nil)!, body)
        }
    }

    @Test func aLogoIsAskedForByTheStationWithTheAppKey() async throws {
        let seen = Box<URLRequest>()
        let answer = try await repository(answering(200, Data([1, 2, 3]), seen: seen))
            .logo(station: uuid, stamp: "")

        #expect(answer == .found(Data([1, 2, 3])))
        #expect(seen.value?.url?.path == "/radio/logo/96062a7e-0601-11e8-ae97-52543be04c81")
        #expect(seen.value?.url?.query == nil)
        #expect(seen.value?.value(forHTTPHeaderField: AppKey.header) == AppKey.value)
    }

    /// A logo changed in the admin is a new address, which is the one change a thirty-day cache
    /// cannot miss.
    @Test func theStampIsInTheAddress() async throws {
        let seen = Box<URLRequest>()
        _ = try await repository(answering(200, Data([1]), seen: seen))
            .logo(station: uuid, stamp: "20260928211500")

        #expect(seen.value?.url?.query == "v=20260928211500")
    }

    @Test func aStationWithNoLogoIsAnAnswer() async throws {
        #expect(try await repository(answering(404, Data())).logo(station: uuid, stamp: "") == .none)
    }

    /// A server that did not answer about this station must not read as "no logo", or the phone
    /// would remember a failure as a fact.
    @Test func aFailureIsNotAStationWithNoLogo() async {
        await #expect(throws: RPMError.self) {
            _ = try await repository(answering(502, Data())).logo(station: uuid, stamp: "")
        }
    }

    @Test func somethingThatIsNotAUuidIsNeverSent() async throws {
        let seen = Box<URLRequest>()
        let answer = try await repository(answering(200, Data([1]), seen: seen))
            .logo(station: "../admin/stations.json", stamp: "")

        #expect(answer == .none)
        #expect(seen.value == nil)
    }

    @Test func theStateIsReadWithTheAppKey() async throws {
        let seen = Box<URLRequest>()
        let state = try await repository(answering(
            200, Data(#"{"logos":"20260928211500","hidden":["a","b"]}"#.utf8), seen: seen))
            .state(.stored)

        #expect(state == .init(logos: "20260928211500", hidden: ["a", "b"]))
        #expect(seen.value?.url?.path == "/radio/state")
        #expect(seen.value?.value(forHTTPHeaderField: AppKey.header) == AppKey.value)
        #expect(seen.value?.cachePolicy == .useProtocolCachePolicy)
    }

    /// Without this a restart would show the state from before a change made in the admin, for up
    /// to the hour the answer is kept.
    @Test func theFirstReadOfALaunchGoesPastTheStore() async throws {
        let seen = Box<URLRequest>()
        _ = try await repository(answering(200, Data(#"{"logos":"","hidden":[]}"#.utf8), seen: seen))
            .state(.pastTheStore)

        #expect(seen.value?.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func anEmptyStateReadsAsNothingDecided() async throws {
        let state = try await repository(answering(200, Data("{}".utf8))).state(.stored)

        #expect(state == .init(logos: "", hidden: []))
    }
}
