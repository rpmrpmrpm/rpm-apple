import Foundation
import RPMKit

/// A computer this device has paired with, kept in the user defaults.
public struct PairedComputer: Codable, Sendable, Equatable {
    public let deviceId: String
    /// SubjectPublicKeyInfo DER, base64url.
    public let publicKey: String
    public let name: String
}

/// A computer as the computers screen shows it: whether it is paired, and whether it is on the
/// network.
public struct ComputerRow: Identifiable, Equatable, Sendable {
    public let key: String
    public let name: String
    public let paired: Bool
    public let here: FoundComputer?
    public var id: String { key }
}

/// How a pairing ended.
public enum PairingEnding: Sendable, Equatable {
    case accepted, declined, expired, tooManyTries, full, lost, failed
}

/// Where a pairing is. Once a pairing has ended, later endings are ignored.
public enum Pairing: Sendable, Equatable {
    case asking(name: String)
    /// The computer shows a code. `wrong` is true when the last code entered was refused.
    case showingCode(name: String, triesLeft: Int, wrong: Bool)
    case ended(name: String, how: PairingEnding)

    public var name: String {
        switch self {
        case .asking(let name), .showingCode(let name, _, _), .ended(let name, _): return name
        }
    }

    var isEnded: Bool { if case .ended = self { return true } else { return false } }
}

/// One computer's catalogue as held: its version and its tracks by `rpmId`.
public struct HeldCatalog: Sendable, Equatable {
    public let computer: String
    public let version: String
    public let tracks: [String: PeerTrack]
}

/// The computers this device pairs with and reads from. It is the client side of the protocol in
/// `RPM.Core/Sharing`. The Android TV app has the same logic in its `Computers`, `HomeCatalogs`
/// and `Discovery` classes.
///
/// - Pairing: this device offers its key, the computer shows a six-digit code, and the person
///   types it here. The code never crosses the network: ``PairingAsker`` commits to it and checks
///   the computer's revealed nonce instead.
/// - Sessions: a challenge signed with this device's key gives a token that lasts 30 minutes. The
///   token is reused until 2 minutes before it expires. Only one token request runs at a time for
///   each computer.
/// - Catalogues: read when a paired computer is found, and then every 5 minutes. The version held
///   is sent, so an unchanged library answers 204.
///
/// Runs on the main actor. Replies can arrive in any order. A pairing reply is dropped when its
/// pairing was replaced (`attempt`) or when a newer status was already applied (`lastRev`). A token
/// request in progress is shared (`asking`). A failure is recorded with the address where it
/// happened.
@MainActor
@Observable
public final class HomeNetwork {
    private let store: UserDefaults
    private let keys: any SecretStore
    private let deviceName: String
    /// The account signed in on this device, read for each session proof. See `init`.
    @ObservationIgnored private let account: @Sendable () async -> String
    private let client = PeerClient()
    @ObservationIgnored private let discovery = Discovery()

    public private(set) var paired: [PairedComputer]
    public private(set) var found: [String: FoundComputer] = [:]
    public private(set) var pairing: Pairing?

    /// Every catalogue read, by computer key, whether or not its computer is on the network now.
    private var held: [String: HeldCatalog] = [:]

    /// The paired computers on the network now, by key, with their current address.
    public var reachable: [String: FoundComputer] {
        let keys = Set(paired.map { $0.deviceId.uppercased() })
        return found.filter { keys.contains($0.key) }
    }

    /// The catalogues of the paired computers that are on the network now.
    public var here: [String: HeldCatalog] {
        let near = reachable
        return held.filter { near[$0.key] != nil }
    }

    /// Called when ``here`` may have changed: after a catalogue read, after a computer is found or
    /// lost, or after a pairing. Set once by the owner.
    @ObservationIgnored public var onCatalogsChanged: @MainActor () -> Void = {}

    /// Every computer here or paired, paired first, then by name.
    public var rows: [ComputerRow] {
        let byKey = Dictionary(paired.map { ($0.deviceId.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
        let keys = Set(byKey.keys).union(found.keys)
        return keys.map { key in
            ComputerRow(key: key, name: found[key]?.name ?? byKey[key]?.name ?? "",
                        paired: byKey[key] != nil, here: found[key])
        }.sorted { a, b in
            if a.paired != b.paired { return a.paired }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// - Parameters:
    ///   - store: where the paired computers are kept.
    ///   - keys: where this device's key is kept.
    ///   - deviceName: what the computer shows this device as while pairing.
    ///   - account: the account signed in on this device (the user id), or empty. It goes inside
    ///     each session signature, so a computer learns which account this device is in only after
    ///     the key is proved. Required: forgetting it would make every computer treat this device as
    ///     a guest's.
    public init(store: UserDefaults, keys: any SecretStore, deviceName: String,
                account: @escaping @Sendable () async -> String) {
        self.store = store
        self.keys = keys
        self.deviceName = deviceName
        self.account = account
        paired = Self.readPaired(store)
    }

    public func start() {
        discovery.onChange = { [weak self] in self?.foundChanged() }
        discovery.start()
    }

    public func isPaired(_ key: String) -> Bool {
        paired.contains { $0.deviceId.caseInsensitiveCompare(key) == .orderedSame }
    }

    private func foundChanged() {
        found = discovery.found
        restartPolling()
        onCatalogsChanged()
    }

    // ── identity ──

    private var identity: PeerIdentity?

    private func me() async -> PeerIdentity {
        if let identity { return identity }
        let loaded = await PeerIdentity.load(from: keys)
        // Two callers can load the key at the same time. Both read or make the stored key, so their
        // answers match once the first write lands. The first one kept wins.
        if let identity { return identity }
        identity = loaded
        return loaded
    }

    // ── pairing ──

    private var pairingTask: Task<Void, Never>?
    private var pairingId = ""
    private var pairingWith: FoundComputer?
    /// This device's half of the pairing under way. Set once the computer's offer has arrived.
    private var asker: PairingAsker?

    /// Counts pairings. A reply for an older pairing is ignored.
    private var attempt = 0
    private var lastTries = 0
    /// The newest status revision applied to this pairing. The status loop and the answer to a code
    /// both bring a status, in any order. An older status is dropped, because it could raise the
    /// tries left again and hide the next wrong code.
    private var lastRev = -1

    /// Starts pairing with `computer`, replacing any pairing under way. The request names no account:
    /// a computer learns which account this device is in from the session proof, after pairing.
    public func pair(_ computer: FoundComputer) {
        pairingTask?.cancel()
        asker?.stop()
        asker = nil
        attempt += 1
        let mine = attempt
        pairingWith = computer
        pairingId = ""
        lastRev = -1
        pairing = .asking(name: computer.name)

        pairingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let me = await self.me()
                let request = PairRequest(version: PeerWire.version, publicKey: PeerWire.base64Url(me.publicKey),
                                          name: self.deviceName, face: "",
                                          nonce: PeerWire.base64Url(PairingCode.nonce()),
                                          pairing: PeerWire.pairing)
                guard let offer = try await self.client.read(PairOffer.self, computer.base + "/rpm/pair",
                                                             body: request, token: nil)
                else { return self.end(mine, .failed) }

                // The computer that answered must be the one whose beacon was pinned.
                guard PeerWire.fromBase64Url(offer.publicKey) == computer.publicKey else {
                    return self.end(mine, .failed)
                }
                guard !offer.id.isEmpty else { return self.onStatus(mine, offer.status) }

                self.pairingId = offer.id
                // A code shown with no commitment comes from a computer that expects the code in the
                // clear. This device does not pair with it, and withdraws so the code comes off
                // that screen.
                if offer.status.state == "ShowingCode", offer.status.commit.isEmpty {
                    self.end(mine, .failed)
                    _ = try? await self.client.call(computer.base + "/rpm/pair/withdraw",
                                                    body: PairId(id: offer.id), token: nil)
                    return
                }

                let asker = PairingAsker(askerKey: me.publicKey, ownerKey: computer.publicKey,
                                         id: offer.id, post: self.post(to: computer))
                self.asker = asker
                self.lastTries = offer.status.triesLeft
                var status = offer.status
                self.onStatus(mine, status)
                await self.join(mine, asker, status)

                // Asked again at once after each answer. The computer ends a pairing that nobody
                // follows for 10 s. A failed request is retried each second, and the pairing is
                // given up as lost after 15 s.
                var failingSince: Date?
                while self.attempt == mine, !(self.pairing?.isEnded ?? true) {
                    do {
                        let url = computer.base + "/rpm/pair/status?id=\(offer.id)&rev=\(status.rev)"
                        if let next = try await self.client.read(PairStatus.self, url, token: nil) { status = next }
                        failingSince = nil
                    } catch is CancellationError {
                        return
                    } catch {
                        if Task.isCancelled { return }
                        let since = failingSince ?? Date()
                        failingSince = since
                        if Date().timeIntervalSince(since) > 15 { return self.end(mine, .lost) }
                        try? await Task.sleep(for: .seconds(1))
                        continue
                    }
                    self.onStatus(mine, status)
                    await self.join(mine, asker, status)
                }
            } catch {
                if Task.isCancelled { return }
                self.end(mine, .failed)
            }
        }
    }

    /// Sends the code the person typed, through ``PairingAsker/type(_:)``: the code itself never
    /// crosses the network. The answer is applied the same way as a status from the status loop.
    public func submit(_ code: String) {
        guard let asker else { return }
        let mine = attempt
        Task { [weak self] in
            guard let self, let status = await asker.type(code) else { return }
            self.onStatus(mine, status)
            await self.join(mine, asker, status)
        }
    }

    /// Sends this device's nonce when `status` shows a round still waiting for it (a new pairing,
    /// or a new round after a wrong code), and applies the answer.
    private func join(_ mine: Int, _ asker: PairingAsker, _ status: PairStatus) async {
        if let joined = await asker.join(status) { onStatus(mine, joined) }
    }

    /// How ``PairingAsker`` posts to `computer`.
    private func post(to computer: FoundComputer) -> PairingAsker.Post {
        { [client] route, json in
            guard let data = try? await client.send(computer.base + route, json: json, token: nil) else { return nil }
            return try? JSONDecoder().decode(PairStatus.self, from: data)
        }
    }

    /// Withdraws a pairing under way, or forgets one that ended.
    public func cancelPairing() {
        let computer = pairingWith
        let id = pairingId
        attempt += 1
        pairingTask?.cancel()
        asker?.stop()
        asker = nil
        pairing = nil
        if let computer, !id.isEmpty {
            Task { [client] in
                _ = try? await client.call(computer.base + "/rpm/pair/withdraw", body: PairId(id: id), token: nil)
            }
        }
    }

    private func onStatus(_ mine: Int, _ status: PairStatus) {
        guard mine == attempt, !(pairing?.isEnded ?? false), status.rev >= lastRev else { return }
        lastRev = status.rev
        let name = pairingWith?.name ?? ""
        switch status.state {
        case "ShowingCode":
            let wrong = status.triesLeft < lastTries
            lastTries = status.triesLeft
            pairing = .showingCode(name: name, triesLeft: status.triesLeft, wrong: wrong)
        case "Accepted":
            if let computer = pairingWith { record(computer) }
            end(mine, .accepted)
        case "Declined": end(mine, .declined)
        case "Expired": end(mine, .expired)
        case "TooManyTries": end(mine, .tooManyTries)
        case "Full": end(mine, .full)
        default: end(mine, .lost)
        }
    }

    private func end(_ mine: Int, _ how: PairingEnding) {
        guard mine == attempt, !(pairing?.isEnded ?? false) else { return }
        pairing = .ended(name: pairingWith?.name ?? "", how: how)
    }

    /// Saves `computer` as paired. A computer that is already paired is replaced, not added
    /// twice.
    private func record(_ computer: FoundComputer) {
        paired = paired.filter { $0.deviceId.caseInsensitiveCompare(computer.deviceId) != .orderedSame }
            + [PairedComputer(deviceId: computer.deviceId, publicKey: PeerWire.base64Url(computer.publicKey),
                              name: computer.name)]
        if let data = try? JSONEncoder().encode(paired) { store.set(data, forKey: Self.pairedKey) }
        restartPolling()
        onCatalogsChanged()
    }

    private static let pairedKey = "rpm.computers"

    private static func readPaired(_ store: UserDefaults) -> [PairedComputer] {
        guard let data = store.data(forKey: pairedKey),
              let list = try? JSONDecoder().decode([PairedComputer].self, from: data)
        else { return [] }
        return list
    }

    // ── sessions ──

    private struct Token {
        let value: String
        let expires: Date
    }

    private var tokens: [String: Token] = [:]

    /// The token request in progress for each computer, so two callers wait on one request.
    private var asking: [String: Task<String, any Error>] = [:]

    /// A token for `computer`. It is reused until 2 minutes before it expires. Throws
    /// ``PeerRefused`` with status 403 when the computer no longer trusts this device.
    public func token(for computer: FoundComputer) async throws -> String {
        if let held = tokens[computer.key], held.expires.timeIntervalSinceNow > 120 { return held.value }
        if let running = asking[computer.key] { return try await running.value }

        let task = Task { [client, account] () async throws -> String in
            let me = await self.me()
            let signedIn = await account()
            guard let challenge = try await client.read(SessionChallenge.self, computer.base + "/rpm/session",
                                                        token: nil)
            else { throw PeerFailed(what: "no challenge") }
            let signature = try me.sign(PeerWire.sessionText(serverDeviceId: computer.deviceId,
                                                             challenge: challenge.challenge,
                                                             account: signedIn))
            let redeem = SessionRedeem(publicKey: PeerWire.base64Url(me.publicKey),
                                       challenge: challenge.challenge,
                                       signature: PeerWire.base64Url(signature),
                                       account: signedIn)
            guard let grant = try await client.read(SessionGrant.self, computer.base + "/rpm/session",
                                                    body: redeem, token: nil)
            else { throw PeerFailed(what: "no grant") }
            self.tokens[computer.key] = Token(value: grant.token,
                                              expires: Date().addingTimeInterval(TimeInterval(grant.expiresIn)))
            return grant.token
        }
        asking[computer.key] = task
        defer { asking[computer.key] = nil }
        return try await task.value
    }

    /// Drops a computer's token after a 401, so the next call asks for a new one.
    public func forgetToken(_ key: String) {
        tokens[key] = nil
    }

    // ── catalogues ──

    /// One computer's catalogue, or nil when it still has the version `have` (the computer answers
    /// 204). A 401 drops the token, and the request is tried once more with a new token.
    func catalog(_ computer: FoundComputer, have: String?) async throws -> PeerCatalog? {
        var url = computer.base + "/rpm/catalog"
        if let have, let escaped = have.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) {
            url += "?have=" + escaped
        }
        for round in 0..<2 {
            let token = try await token(for: computer)
            do {
                guard let data = try await client.call(url, token: token) else { return nil }
                return try JSONDecoder().decode(PeerCatalog.self, from: data)
            } catch let refused as PeerRefused where refused.status == 401 && round == 0 {
                forgetToken(computer.key)
            }
        }
        throw PeerRefused(status: 401)
    }

    /// The paired computers on the network that the poll was last started for. A change to this
    /// list restarts the poll.
    private var polled: [String: String] = [:]
    private var pollTask: Task<Void, Never>?

    private func restartPolling() {
        let near = reachable
        let seen = near.mapValues(\.base)
        guard seen != polled else { return }
        polled = seen
        pollTask?.cancel()
        let computers = Array(near.values)
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                for computer in computers {
                    guard let self, !Task.isCancelled else { return }
                    await self.read(computer)
                }
                try? await Task.sleep(for: Self.pollEvery)
            }
        }
    }

    /// The same interval as the desktop's `CatalogPoll`.
    private static let pollEvery = Duration.seconds(5 * 60)

    private func read(_ computer: FoundComputer) async {
        do {
            guard let catalog = try await catalog(computer, have: held[computer.key]?.version) else { return }
            let tracks = Dictionary(catalog.tracks.map { ($0.rpmId, $0) }, uniquingKeysWith: { first, _ in first })
            held[computer.key] = HeldCatalog(computer: computer.key, version: catalog.version, tracks: tracks)
            onCatalogsChanged()
        } catch {
            // The catalogue held stays. The next poll tries again.
        }
    }

    // ── where a track plays from ──

    private struct Failure {
        let at: Date
        let base: String
    }

    /// When each computer last failed, and at which address.
    private var failures: [String: Failure] = [:]

    /// How long a computer that failed is not used, unless it is found at another address.
    private static let awayFor: TimeInterval = 120

    /// Marks a computer as away after a failure at `base`, the address that failed. It is tried
    /// again after two minutes, or as soon as it is found at another address or port (for example,
    /// after its server restarts).
    ///
    /// - Parameter base: **the address where the failure happened, not the address the computer is
    ///   found at now.** A computer can move while a request is in progress. Its new address has
    ///   not failed, so marking that one away would leave the computer unused for two minutes.
    public func markAway(_ key: String, at base: String) {
        failures[key] = Failure(at: Date(), base: base)
    }

    /// The computer to read from now: paired, on the network, and not failed recently at the
    /// address it is found at.
    public func usable(_ key: String) -> FoundComputer? {
        guard isPaired(key), let computer = found[key] else { return nil }
        guard let failed = failures[key] else { return computer }
        if failed.base != computer.base || Date().timeIntervalSince(failed.at) > Self.awayFor {
            failures[key] = nil
            return computer
        }
        return nil
    }

    /// The computer that holds `rpmId` in a format that plays on this device, if one is usable now.
    public func computer(holding rpmId: String) -> FoundComputer? {
        for catalog in here.values {
            guard let track = catalog.tracks[rpmId], PeerFormats.playsHere(track),
                  let computer = usable(catalog.computer)
            else { continue }
            return computer
        }
        return nil
    }

    /// The address to stream `rpmId` from `computer`. Its query carries a ticket for this one track,
    /// not the session token: the player does not pin the computer's key, so this URL is what
    /// someone on the network could read (``PeerWire/mediaTicket(_:route:id:)``).
    public func address(of rpmId: String, on computer: FoundComputer) async throws -> URL {
        let token = try await token(for: computer)
        let id = rpmId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/"])) ?? rpmId
        func query(_ value: String) -> String {
            value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
        }
        let s = query(PeerWire.mediaHandle(token))
        let t = query(PeerWire.mediaTicket(token, route: PeerWire.trackRoute, id: rpmId))
        guard let url = URL(string: computer.base + PeerWire.trackRoute + id + "?s=" + s + "&t=" + t) else {
            throw PeerFailed(what: "bad address")
        }
        return url
    }

    /// Forgets the session tokens and the failures, for signing out. The pairings stay: they
    /// belong to this device, not to the account.
    public func forgetSessions() {
        tokens = [:]
        failures = [:]
    }
}

extension CharacterSet {
    /// The characters that may stand unescaped in a query value: the query characters, less the
    /// ones that split a query (`&`, `=`, `+`, `?`).
    static let urlQueryValueAllowed = CharacterSet.urlQueryAllowed.subtracting(["&", "=", "+", "?"])
}

/// Which of a computer's files this device decodes itself.
public enum PeerFormats {
    /// File types Core Audio's stream parser reads.
    static let containers: Set<String> = ["flac", "mp3", "m4a", "m4b", "mp4", "aac", "wav", "aif", "aiff"]

    /// Whether this device can decode the computer's file. Its container must be in `containers`,
    /// and its codec must not be AC-3 or E-AC-3. TagLib names these in the codec text, for example
    /// "MPEG-4 Audio (ec-3)". A track that does not play here is played from the cloud's AAC copy.
    public static func playsHere(_ track: PeerTrack) -> Bool {
        guard containers.contains(track.container) else { return false }
        let codec = (track.codec ?? "").lowercased()
        return !["ac-3", "ec-3"].contains { codec.contains($0) }
    }
}
