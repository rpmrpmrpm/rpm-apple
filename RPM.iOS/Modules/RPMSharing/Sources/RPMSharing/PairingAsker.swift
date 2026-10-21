import Foundation
import CryptoKit
import Security

/// The six digits the computer shows and the person types on this device, and the hashes around
/// them. It matches the desktop's `PairingCode` byte for byte.
///
/// The digits come from both keys and both nonces. The computer reveals its nonce only after this
/// device has committed to what was typed, so this device cannot work out the digits before
/// somebody has read them off the computer's screen.
enum PairingCode {
    /// How many random bytes each side contributes.
    static let nonceBytes = 16

    /// A fresh random value. One per use, never reused.
    static func nonce() -> Data {
        var data = Data(count: nonceBytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, nonceBytes, $0.baseAddress!) }
        return data
    }

    /// Six digits, leading zeros kept. The keys are sorted before hashing and each nonce stays with
    /// its key, so both ends hash the same bytes whichever of them asked.
    static func code(_ keyA: Data, _ keyB: Data, _ nonceA: Data, _ nonceB: Data) -> String {
        let (first, second) = keyB.lexicographicallyPrecedes(keyA)
            ? ((keyB, nonceB), (keyA, nonceA))
            : ((keyA, nonceA), (keyB, nonceB))
        var hash = SHA256()
        hash.update(data: first.0)
        hash.update(data: first.1)
        hash.update(data: second.0)
        hash.update(data: second.1)
        let digest = Array(hash.finalize())
        // Twenty bits from the front of the hash, folded into the six-digit range.
        let value = ((Int(digest[0]) << 16) | (Int(digest[1]) << 8) | Int(digest[2])) & 0xFFFFF
        return String(format: "%06d", value % 1_000_000)
    }

    /// The computer's commitment to its nonce for one round, as it sends it before anybody has
    /// typed anything.
    static func commitNonce(_ nonce: Data) -> Data {
        hash("rpm-pair-nonce", nonce)
    }

    /// This device's commitment to the typed code, bound to both keys. It is sent in place of the
    /// code. `opening` is a fresh random value, sent afterwards to open the commitment.
    static func commitCode(askerKey: Data, ownerKey: Data, opening: Data, code: String) -> Data {
        hash("rpm-pair-code", askerKey, ownerKey, opening, Data(code.utf8))
    }

    /// This device's nonce for one round, derived from a seed that is never sent. Two sends for the
    /// same round carry the same bytes, and the computer keeps the first one it receives.
    static func askerNonce(seed: Data, round: Int) -> Data {
        var number = UInt32(truncatingIfNeeded: round).bigEndian
        let bytes = withUnsafeBytes(of: &number) { Data($0) }
        return Data(hash("rpm-pair-asker-nonce", seed, bytes).prefix(nonceBytes))
    }

    /// Whether two hashes are the same, compared in constant time. False when either is missing.
    static func same(_ a: Data?, _ b: Data?) -> Bool {
        guard let a, let b, !a.isEmpty, a.count == b.count else { return false }
        var difference: UInt8 = 0
        for (x, y) in zip(a, b) { difference |= x ^ y }
        return difference == 0
    }

    /// Whether two codes are the same. The time taken does not depend on how many digits match.
    static func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        let x = Array(a.utf16), y = Array(b.utf16)
        guard x.count == y.count else { return false }
        var difference: UInt16 = 0
        for (p, q) in zip(x, y) { difference |= p ^ q }
        return difference == 0
    }

    /// SHA-256 over a label and each part, with each part's length in front, so no two different
    /// lists of parts hash to the same bytes.
    private static func hash(_ label: String, _ parts: Data...) -> Data {
        var hash = SHA256()
        hash.update(data: Data(label.utf8))
        for part in parts {
            var length = UInt32(part.count).bigEndian
            withUnsafeBytes(of: &length) { hash.update(bufferPointer: $0) }
            hash.update(data: part)
        }
        return Data(hash.finalize())
    }
}

/// This device's half of one pairing, the desktop's `PeerClient.PairingAsker`. It sends this
/// device's nonce for each round, and turns the typed code into a commitment, a check and an
/// opening. The code itself never crosses the network.
///
/// Two rules carry this side's protection. Only this type sends a nonce, a commitment or an
/// opening, so nothing else can break them.
/// - This device's nonce for a round goes out only after the computer's commitment for that round
///   has arrived. A machine in the middle then has to fix its nonce before it learns this one, so it
///   cannot choose a nonce that makes the digits here match the ones on the real computer's screen.
/// - The commitment is pinned at the first status of the round. A later status for the same round
///   can carry a different commitment. Checking against that one would let a machine in the middle
///   commit again after it has seen this device's nonce.
///
/// Statuses arrive from the status loop and from the answers to this type's own posts, in any
/// order. Each call reads the pinned round when it starts, and a round is pinned only when it is
/// newer than the pinned one, so an older status cannot take the round back.
@MainActor
final class PairingAsker {
    /// Posts one step to the computer: the route and the JSON body. Nil when the call failed.
    typealias Post = @MainActor (_ route: String, _ json: Data) async -> PairStatus?

    private static let nonceRoute = "/rpm/pair/nonce"
    private static let commitRoute = "/rpm/pair/commit"
    private static let openRoute = "/rpm/pair/open"

    private let askerKey: Data
    private let ownerKey: Data
    private let id: String
    private let post: Post
    /// Never sent. Each round's nonce is derived from it.
    private let seed = PairingCode.nonce()
    /// The newest round seen, with the commitment it was first seen with.
    private var round: Round?
    /// True once the pairing was cancelled or replaced. Nothing is sent after that.
    private var stopped = false

    private struct Round {
        let number: Int
        let promised: Data
        let nonce: Data
    }

    /// - Parameters:
    ///   - askerKey: this device's public key.
    ///   - ownerKey: the computer's public key as pinned from its beacon. The commitment to the
    ///     typed code is bound to it, so the commitment cannot be forwarded to another computer.
    ///   - id: the pairing id from the computer's offer.
    init(askerKey: Data, ownerKey: Data, id: String, post: @escaping Post) {
        self.askerKey = askerKey
        self.ownerKey = ownerKey
        self.id = id
        self.post = post
    }

    /// Takes a status seen from the computer. When it shows a round whose digits are not on that
    /// screen yet, sends this device's nonce for it.
    /// - Returns: the answer when a nonce was sent. Nil when nothing needed sending, or when the
    ///   call failed. A failed send is sent again with the next status for the round.
    func join(_ status: PairStatus) async -> PairStatus? {
        // Pinned even when the digits are already on screen, so `type` knows the round whichever
        // status arrives first.
        guard status.state == "ShowingCode", let round = pin(status), round.number == status.round,
              !status.shown
        else { return nil }
        return await send(Self.nonceRoute,
                          PairNonce(id: id, round: round.number, nonce: PeerWire.base64Url(round.nonce)))
    }

    private func pin(_ status: PairStatus) -> Round? {
        if status.round > (round?.number ?? 0),
           let promised = PeerWire.fromBase64Url(status.commit), !promised.isEmpty {
            round = Round(number: status.round, promised: promised,
                          nonce: PairingCode.askerNonce(seed: seed, round: status.round))
        }
        return round
    }

    /// The code typed here, in three steps: commit to it, check the nonce the computer reveals
    /// against the pinned commitment and work out the digits here, then open the commitment if the
    /// digits agree. Otherwise the opening is empty, which the computer counts as a wrong code. A
    /// commitment that could not be checked is never opened: the opening is what would let a
    /// machine in the middle read the code.
    /// - Returns: the last status received. Nil when no round has been seen or when a call failed.
    func type(_ code: String) async -> PairStatus? {
        guard let round else { return nil }
        let opening = PairingCode.nonce()
        let commitment = PairingCode.commitCode(askerKey: askerKey, ownerKey: ownerKey, opening: opening, code: code)

        // The pairing ended or moved to another round in the meantime, or the digits were not on
        // that screen yet. The status says which, and nothing is opened.
        guard let committed = await send(Self.commitRoute,
                                         PairCommit(id: id, round: round.number,
                                                    commit: PeerWire.base64Url(commitment)))
        else { return nil }
        guard committed.round == round.number,
              let nonce = PeerWire.fromBase64Url(committed.reveal), !nonce.isEmpty
        else { return committed }

        let agrees = PairingCode.same(PairingCode.commitNonce(nonce), round.promised)
            && PairingCode.same(PairingCode.code(askerKey, ownerKey, round.nonce, nonce), code)
        return await send(Self.openRoute,
                          PairOpen(id: id, round: round.number,
                                   opening: agrees ? PeerWire.base64Url(opening) : ""))
    }

    /// Ends this pairing on this device. A step that is already on its way still arrives, but no
    /// step follows it: an opening is never sent after the person cancelled.
    func stop() {
        stopped = true
    }

    private func send(_ route: String, _ body: some Encodable) async -> PairStatus? {
        guard !stopped, let json = try? JSONEncoder().encode(body) else { return nil }
        return await post(route, json)
    }
}
