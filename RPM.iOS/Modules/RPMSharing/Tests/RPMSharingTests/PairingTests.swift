import Foundation
import Testing
@testable import RPMSharing

/// The expected values were printed by `PairingCode` in `RPM.Core` for the same inputs, so these
/// tests check that both ends compute the same bytes and the same six digits.
@Suite struct PairingCodeTests {
    let asker = bytes(from: 1, count: 91)
    let owner = bytes(from: 101, count: 91)
    let askerNonce = bytes(from: 201, count: 16)
    let ownerNonce = bytes(from: 17, count: 16)

    @Test func theCodeMatchesTheDesktopWhicheverKeyComesFirst() {
        #expect(PairingCode.code(asker, owner, askerNonce, ownerNonce) == "542697")
        #expect(PairingCode.code(owner, asker, ownerNonce, askerNonce) == "542697")
    }

    @Test func theCodeKeepsItsLeadingZero() {
        let nonce = Data(hex: "02030405060708090a0b0c0d0e0f1000")
        #expect(PairingCode.code(asker, owner, nonce, ownerNonce) == "069614")
    }

    @Test func theCommitmentsAndTheAskersNoncesMatchTheDesktop() {
        #expect(PairingCode.commitNonce(ownerNonce)
                == Data(hex: "705369f212cf0be6967361adac52ed7f53093c7d1b2b70d2e6a6a94b89187c93"))
        #expect(PairingCode.commitCode(askerKey: asker, ownerKey: owner,
                                       opening: bytes(from: 49, count: 16), code: "004213")
                == Data(hex: "1f9346caf8a9f6c5562c152040941b0ac3ea5da04d6a97d225c70393af01f63a"))
        let seed = bytes(from: 33, count: 16)
        #expect(PairingCode.askerNonce(seed: seed, round: 1) == Data(hex: "7c4eeae5903afc8bbc20c4a94f3b9f0a"))
        #expect(PairingCode.askerNonce(seed: seed, round: 2) == Data(hex: "8024d2c8146d09640b1bdfbd49519faa"))
    }

    @Test func codesMatchOnlyWhenTheyAreTheSameCode() {
        #expect(PairingCode.same("004213", "004213"))
        #expect(!PairingCode.same("004213", "004214"))
        #expect(!PairingCode.same("004213", "04213"))
        #expect(!PairingCode.same(nil, "004213"))
        #expect(!PairingCode.same(Data(), Data()))
    }
}

/// The asking side's rules, as `PairingAskerTests` checks them on the desktop. A fake computer plays
/// the asked side: it commits to its nonce, and reveals it when a commitment arrives.
@MainActor @Suite struct PairingAskerTests {
    let askerKey = bytes(from: 1, count: 91)
    let ownerKey = bytes(from: 101, count: 91)
    let ownerNonce = bytes(from: 17, count: 16)

    func showing(round: Int, commit: Data, shown: Bool = false) -> PairStatus {
        PairStatus(state: "ShowingCode", rev: round, triesLeft: 3, round: round,
                   commit: PeerWire.base64Url(commit), shown: shown)
    }

    @Test func noNonceGoesOutBeforeTheComputerHasCommitted() async {
        let computer = FakeComputer()
        let asker = PairingAsker(askerKey: askerKey, ownerKey: ownerKey, id: "p1", post: computer.post)
        #expect(await asker.join(showing(round: 1, commit: Data())) == nil)
        #expect(computer.posts.isEmpty)
    }

    @Test func theNonceForARoundIsTheSameEachTimeAndANewRoundGetsANewOne() async {
        let computer = FakeComputer()
        let asker = PairingAsker(askerKey: askerKey, ownerKey: ownerKey, id: "p1", post: computer.post)
        _ = await asker.join(showing(round: 1, commit: PairingCode.commitNonce(ownerNonce)))
        _ = await asker.join(showing(round: 1, commit: PairingCode.commitNonce(ownerNonce)))
        _ = await asker.join(showing(round: 2, commit: PairingCode.commitNonce(bytes(from: 60, count: 16))))

        #expect(computer.posts.map(\.route) == ["/rpm/pair/nonce", "/rpm/pair/nonce", "/rpm/pair/nonce"])
        #expect(computer.posts.map { $0.body["id"] as? String } == ["p1", "p1", "p1"])
        #expect(computer.posts.map { $0.body["round"] as? Int } == [1, 1, 2])
        let nonces = computer.posts.map { $0.body["nonce"] as? String ?? "" }
        #expect(nonces[0] == nonces[1])
        #expect(nonces[0] != nonces[2])
        #expect(PeerWire.fromBase64Url(nonces[0])?.count == 16)
    }

    @Test func aRoundAlreadyShowingItsDigitsIsNotSentANonce() async {
        let computer = FakeComputer()
        let asker = PairingAsker(askerKey: askerKey, ownerKey: ownerKey, id: "p1", post: computer.post)
        #expect(await asker.join(showing(round: 1, commit: PairingCode.commitNonce(ownerNonce), shown: true)) == nil)
        #expect(computer.posts.isEmpty)
    }

    @Test func theRightCodeIsOpenedAndTheOpeningShowsTheCodeBoundToBothKeys() async throws {
        let computer = FakeComputer()
        let asker = PairingAsker(askerKey: askerKey, ownerKey: ownerKey, id: "p1", post: computer.post)
        _ = await asker.join(showing(round: 1, commit: PairingCode.commitNonce(ownerNonce)))
        let code = try computer.digits(askerKey: askerKey, ownerKey: ownerKey, ownerNonce: ownerNonce)
        computer.reveal = ownerNonce

        _ = await asker.type(code)

        #expect(computer.posts.map(\.route) == ["/rpm/pair/nonce", "/rpm/pair/commit", "/rpm/pair/open"])
        let commitment = try #require(PeerWire.fromBase64Url(computer.posts[1].body["commit"] as? String))
        let opening = try #require(PeerWire.fromBase64Url(computer.posts[2].body["opening"] as? String))
        #expect(computer.posts[2].body["round"] as? Int == 1)
        #expect(PairingCode.commitCode(askerKey: askerKey, ownerKey: ownerKey, opening: opening, code: code)
                == commitment)
    }

    @Test func aWrongCodeIsNotOpened() async throws {
        let computer = FakeComputer()
        let asker = PairingAsker(askerKey: askerKey, ownerKey: ownerKey, id: "p1", post: computer.post)
        _ = await asker.join(showing(round: 1, commit: PairingCode.commitNonce(ownerNonce)))
        let code = try computer.digits(askerKey: askerKey, ownerKey: ownerKey, ownerNonce: ownerNonce)
        computer.reveal = ownerNonce

        _ = await asker.type(code == "000000" ? "000001" : "000000")

        #expect(computer.posts.last?.route == "/rpm/pair/open")
        #expect(computer.posts.last?.body["opening"] as? String == "")
    }

    @Test func aRevealedNonceThatIsNotTheCommittedOneIsNotBelieved() async throws {
        let computer = FakeComputer()
        let asker = PairingAsker(askerKey: askerKey, ownerKey: ownerKey, id: "p1", post: computer.post)
        _ = await asker.join(showing(round: 1, commit: PairingCode.commitNonce(ownerNonce)))
        // A machine in the middle reveals a nonce of its own, and the person typed the digits that
        // nonce gives.
        let other = bytes(from: 90, count: 16)
        let code = try computer.digits(askerKey: askerKey, ownerKey: ownerKey, ownerNonce: other)
        computer.reveal = other

        _ = await asker.type(code)

        #expect(computer.posts.last?.route == "/rpm/pair/open")
        #expect(computer.posts.last?.body["opening"] as? String == "")
    }

    @Test func aCommitmentChangedAfterThisSidesNonceWentOutIsNotBelieved() async throws {
        let computer = FakeComputer()
        let asker = PairingAsker(askerKey: askerKey, ownerKey: ownerKey, id: "p1", post: computer.post)
        _ = await asker.join(showing(round: 1, commit: PairingCode.commitNonce(ownerNonce)))
        // The same round again, now with a commitment to a nonce chosen after this side's went out.
        let other = bytes(from: 90, count: 16)
        _ = await asker.join(showing(round: 1, commit: PairingCode.commitNonce(other), shown: true))
        let code = try computer.digits(askerKey: askerKey, ownerKey: ownerKey, ownerNonce: other)
        computer.reveal = other

        _ = await asker.type(code)

        #expect(computer.posts.last?.route == "/rpm/pair/open")
        #expect(computer.posts.last?.body["opening"] as? String == "")
    }

    @Test func aCommitAnsweredForAnotherRoundIsNotOpened() async throws {
        let computer = FakeComputer()
        let asker = PairingAsker(askerKey: askerKey, ownerKey: ownerKey, id: "p1", post: computer.post)
        _ = await asker.join(showing(round: 1, commit: PairingCode.commitNonce(ownerNonce)))
        let code = try computer.digits(askerKey: askerKey, ownerKey: ownerKey, ownerNonce: ownerNonce)
        computer.reveal = ownerNonce
        computer.answerRound = 2

        let answer = await asker.type(code)

        #expect(computer.posts.map(\.route) == ["/rpm/pair/nonce", "/rpm/pair/commit"])
        #expect(answer?.round == 2)
    }

    @Test func nothingIsSentOnceThePairingIsStopped() async throws {
        let computer = FakeComputer()
        let asker = PairingAsker(askerKey: askerKey, ownerKey: ownerKey, id: "p1", post: computer.post)
        _ = await asker.join(showing(round: 1, commit: PairingCode.commitNonce(ownerNonce)))
        let code = try computer.digits(askerKey: askerKey, ownerKey: ownerKey, ownerNonce: ownerNonce)
        computer.reveal = ownerNonce
        // Stopped while the commitment is on its way: the opening must not follow it.
        computer.onCommit = { asker.stop() }

        #expect(await asker.type(code) == nil)
        #expect(computer.posts.map(\.route) == ["/rpm/pair/nonce", "/rpm/pair/commit"])
        #expect(await asker.join(showing(round: 2, commit: PairingCode.commitNonce(ownerNonce))) == nil)
        #expect(computer.posts.count == 2)
    }

    @Test func nothingIsTypedBeforeARoundHasBeenSeen() async {
        let computer = FakeComputer()
        let asker = PairingAsker(askerKey: askerKey, ownerKey: ownerKey, id: "p1", post: computer.post)
        #expect(await asker.type("123456") == nil)
        #expect(computer.posts.isEmpty)
    }
}

/// The asked computer as the tests need it. It records each post and answers a commitment with
/// the nonce in `reveal`, for the round in `answerRound` (the posted round when nil).
@MainActor final class FakeComputer {
    struct Post { let route: String; let body: [String: Any] }
    private(set) var posts: [Post] = []
    var reveal = Data()
    var answerRound: Int?
    /// Runs when a commitment arrives, before it is answered.
    var onCommit: @MainActor () -> Void = {}

    var post: @MainActor (String, Data) async -> PairStatus? {
        { [self] route, json in
            let body = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] ?? [:]
            posts.append(Post(route: route, body: body))
            let round = answerRound ?? (body["round"] as? Int ?? 0)
            switch route {
            case "/rpm/pair/nonce":
                return PairStatus(state: "ShowingCode", rev: posts.count, triesLeft: 3, round: round, shown: true)
            case "/rpm/pair/commit":
                onCommit()
                return PairStatus(state: "ShowingCode", rev: posts.count, triesLeft: 3, round: round,
                                  shown: true, reveal: PeerWire.base64Url(reveal))
            default:
                return PairStatus(state: "Accepted", rev: posts.count)
            }
        }
    }

    /// The digits the asked computer would show, from the asking side's nonce it was sent.
    func digits(askerKey: Data, ownerKey: Data, ownerNonce: Data) throws -> String {
        let sent = try #require(posts.first { $0.route == "/rpm/pair/nonce" })
        let askerNonce = try #require(PeerWire.fromBase64Url(sent.body["nonce"] as? String))
        return PairingCode.code(askerKey, ownerKey, askerNonce, ownerNonce)
    }
}

/// `count` bytes counting up from `start`, the inputs the desktop's values were printed for.
func bytes(from start: Int, count: Int) -> Data {
    Data((0..<count).map { UInt8((start + $0) & 0xFF) })
}

extension Data {
    init(hex: String) {
        var bytes: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16) ?? 0)
            index = next
        }
        self.init(bytes)
    }
}
