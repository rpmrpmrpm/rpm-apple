import Foundation
import Testing
@testable import RPMKit

// The App Store subscription, as the phone hands it to the accounts service. A transaction is
// finished only once the service has answered, so a purchase made with no network is sent again.

private let accounts = URL(string: "https://accounts.example.com/")!

private let standing = #"""
{"grSupporter":true,"grSupporterUntil":1800000000,"grSupporterStore":"apple","grUnlimitedStorage":true,"grTester":false}
"""#

/// Answers every post the same way and counts them.
private final class Poster: SupporterPosting, @unchecked Sendable {
    let answer: SupporterPost
    private let lock = NSLock()
    private var sent: [String] = []
    var posts: [String] { lock.withLock { sent } }

    init(_ answer: SupporterPost) { self.answer = answer }

    func postApple(signedTransaction: String) async -> SupporterPost {
        lock.withLock { sent.append(signedTransaction) }
        return answer
    }
}

/// Counts the times a transaction was finished.
private final class Finishes: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func note() { lock.withLock { count += 1 } }
}

private func held(_ finishes: Finishes) -> HeldTransaction {
    HeldTransaction(signed: "jws", finish: { finishes.note() })
}

private let confirmed = SupporterPost.confirmed(SupporterAnswer(
    grSupporter: true, grSupporterUntil: 1_800_000_000, grSupporterStore: "apple",
    grUnlimitedStorage: true, grTester: false))

@Test func aTransactionIsFinishedOnlyAfterTheServerConfirmedIt() async {
    let finishes = Finishes()
    let poster = Poster(confirmed)

    let said = await SupporterStore(client: poster).send(held(finishes))

    #expect(said == confirmed)
    #expect(poster.posts == ["jws"])
    #expect(finishes.value == 1)
}

@Test func aPostThatDidNotArriveLeavesTheTransactionUnfinished() async {
    let finishes = Finishes()

    let said = await SupporterStore(client: Poster(.unavailable)).send(held(finishes))

    #expect(said == .unavailable)
    #expect(finishes.value == 0, "a transaction finished before the server had it would never be sent again")
}

@Test func anotherAccountsSubscriptionIsReportedAndFinished() async {
    let finishes = Finishes()

    let said = await SupporterStore(client: Poster(.otherAccount)).send(held(finishes))

    #expect(said == .otherAccount)
    #expect(finishes.value == 1)
}

@Test func aRefusedTransactionIsFinished() async {
    let finishes = Finishes()

    let said = await SupporterStore(client: Poster(.refused)).send(held(finishes))

    #expect(said == .refused)
    #expect(finishes.value == 1)
}

@Test func theClientSendsTheSignedTransactionToTheAccountsService() async throws {
    let seen = Box<URLRequest>()
    let session = stubbedSession { request in
        seen.value = request
        return ok(request, standing)
    }
    let client = SupporterClient(transport: Transport(base: accounts, tokens: FixedTokens(token: "tok"), reach: openLine(), session: session))

    let said = await client.postApple(signedTransaction: "eyJ.payload.sig")

    #expect(said == confirmed)
    let request = try #require(seen.value)
    #expect(request.url?.path == "/supporter/apple")
    #expect(request.httpMethod == "POST")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
    let body = try JSONSerialization.jsonObject(with: request.bodyData) as? [String: String]
    #expect(body == ["signedTransaction": "eyJ.payload.sig"])
}

/// One answer of the accounts service and what the phone makes of it.
struct ServiceSaid: Sendable, CustomTestStringConvertible {
    let status: Int
    let body: String
    let expected: SupporterPost
    var testDescription: String { "\(status) \(body)" }
}

private let answers: [ServiceSaid] = [
    ServiceSaid(status: 409, body: #"{"error":"otherAccount"}"#, expected: .otherAccount),
    ServiceSaid(status: 400, body: #"{"error":"notOurs"}"#, expected: .refused),
    ServiceSaid(status: 401, body: "", expected: .unavailable),
    ServiceSaid(status: 409, body: #"{"error":"noAccount"}"#, expected: .unavailable),
    ServiceSaid(status: 503, body: #"{"error":"unavailable"}"#, expected: .unavailable),
    ServiceSaid(status: 200, body: "not json", expected: .unavailable),
]

@Test(arguments: answers)
func theClientReadsEachAnswer(_ said: ServiceSaid) async {
    let session = replying(said.status, said.body)
    let client = SupporterClient(transport: Transport(base: accounts, tokens: FixedTokens(token: "tok"), reach: openLine(), session: session))

    let read = await client.postApple(signedTransaction: "jws")
    #expect(read == said.expected)
}

@Test func noNetworkIsUnavailable() async {
    let id = UUID().uuidString
    StubProtocol.registerFailure(id, .notConnectedToInternet)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubProtocol.self]
    config.httpAdditionalHeaders = [StubProtocol.idHeader: id]
    let client = SupporterClient(transport: Transport(base: accounts, tokens: FixedTokens(token: "tok"), reach: openLine(), session: URLSession(configuration: config)))

    #expect(await client.postApple(signedTransaction: "jws") == .unavailable)
}

@Test func theQuotaNamesThePayingStore() throws {
    let quota = try RPMJSON.decoder.decode(CloudQuota.self, from: Data(#"""
    {"usedBytes":1,"quotaBytes":2,"fileCount":3,"unlimited":true,"supporter":true,"tester":false,"store":"apple"}
    """#.utf8))
    #expect(quota.store == "apple")
}

@Test func aQuotaWithoutTheStoreFieldNamesNone() throws {
    let quota = try fixture("cloud-quota", as: CloudQuota.self)
    #expect(quota.store == nil)
}

// ── what the plan card offers ──

private func quota(supporter: Bool, tester: Bool, store: String?) -> CloudQuota {
    CloudQuota(usedBytes: 0, quotaBytes: 0, fileCount: 0, unlimited: supporter && !tester,
               supporter: supporter, tester: tester, store: store)
}

@Test func aFreeAccountIsOfferedTheSubscription() {
    #expect(quota(supporter: false, tester: false, store: nil).supporterOffer == .become)
}

@Test func aTesterIsOfferedTheSubscription() {
    #expect(quota(supporter: true, tester: true, store: nil).supporterOffer == .become)
}

@Test func anAppStoreSupporterIsOfferedTheAppStoresPage() {
    #expect(quota(supporter: true, tester: false, store: "apple").supporterOffer == .manageInAppStore)
}

@Test func aSupporterWhoPaysElsewhereIsOfferedNothing() {
    #expect(quota(supporter: true, tester: false, store: "google").supporterOffer == .nothing)
    #expect(quota(supporter: true, tester: false, store: nil).supporterOffer == .nothing)
}

// ── what the plan card says after a sync ──

@Test func aSyncThatFoundAnotherAccountsSubscriptionSaysSo() {
    #expect(SupporterStore.noteKey(for: [confirmed, .otherAccount]) == "Supporter_OtherAccount")
}

@Test func aSyncWithNothingToSaySaysNothing() {
    #expect(SupporterStore.noteKey(for: []) == nil)
    #expect(SupporterStore.noteKey(for: [confirmed, .unavailable]) == nil)
}
