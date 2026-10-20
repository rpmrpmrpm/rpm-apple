import Foundation
import Network
import RPMKit

/// A computer on the network that shares its library: what its beacon says, checked.
public struct FoundComputer: Sendable, Equatable {
    /// As the beacon spells it. The session signature covers this exact text.
    public let deviceId: String
    public let name: String
    /// An IPv4 address.
    public let address: String
    public let port: Int
    /// SubjectPublicKeyInfo DER.
    public let publicKey: Data

    public init(deviceId: String, name: String, address: String, port: Int, publicKey: Data) {
        self.deviceId = deviceId; self.name = name; self.address = address; self.port = port
        self.publicKey = publicKey
    }

    /// The id in upper case. Computers are stored under this key.
    public var key: String { deviceId.uppercased() }

    public var base: String { "https://\(address):\(port)" }
}

/// What a beacon's TXT record says, checked the same way as the desktop's `PeerBeacon`: `v` must
/// be 4, `k` is the key (base64url SubjectPublicKeyInfo), and `id` must be the id that key implies.
/// Nil for a beacon that fails any of those.
public struct Beacon: Equatable, Sendable {
    public let deviceId: String
    public let name: String
    public let publicKey: Data

    public init?(txt: [String: String]) {
        var text: [String: String] = [:]
        for (key, value) in txt { text[key.lowercased()] = value }

        guard text["v"]?.trimmingCharacters(in: .whitespaces) == String(PeerWire.version),
              let key = PeerWire.fromBase64Url(text["k"])
        else { return nil }

        let id = text["id"]?.trimmingCharacters(in: .whitespaces) ?? ""
        guard id.caseInsensitiveCompare(PeerWire.id(for: key)) == .orderedSame else { return nil }

        func said(_ field: String) -> String? {
            guard let value = text[field]?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
            return value
        }

        deviceId = id
        // The beacon names no person and no account, only the machine.
        name = said("n") ?? id
        publicKey = key
    }
}

/// Computers that share on the network, found through `_rpm._tcp` beacons. A computer's port
/// changes each time its server restarts, so a changed beacon is resolved again. Reads always use
/// the latest address. Each address is pinned to its key in ``PeerPins``.
///
/// Runs on the main actor. The browser delivers its callbacks on the main queue, and every change
/// to ``found`` happens there.
@MainActor
public final class Discovery {
    /// By upper-case device id.
    public private(set) var found: [String: FoundComputer] = [:]

    /// Told after every change to ``found``. Set once by the owner.
    var onChange: @MainActor () -> Void = {}

    private var browser: NWBrowser?

    /// Maps each service name to its device key, so a lost service can be removed.
    private var names: [String: String] = [:]

    /// The resolve running for each service name. A newer resolve replaces it.
    private var resolving: [String: NWConnection] = [:]

    public init() {}

    public func start() {
        guard browser == nil else { return }

        let parameters = NWParameters()
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: PeerWire.serviceType, domain: nil),
                                using: parameters)
        browser.browseResultsChangedHandler = { [weak self] _, changes in
            MainActor.assumeIsolated { self?.apply(changes) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        for connection in resolving.values { connection.cancel() }
        resolving = [:]
    }

    private func apply(_ changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                resolve(result)
            case .changed(old: _, new: let result, flags: _):
                resolve(result)
            case .removed(let result):
                guard let name = Self.serviceName(result.endpoint) else { continue }
                resolving.removeValue(forKey: name)?.cancel()
                if let key = names.removeValue(forKey: name) {
                    found[key] = nil
                    onChange()
                }
            case .identical:
                break
            @unknown default:
                break
            }
        }
    }

    private static func serviceName(_ endpoint: NWEndpoint) -> String? {
        if case .service(let name, _, _, _) = endpoint { return name }
        return nil
    }

    /// Reads the beacon and finds the address and port it answers on. The address is learned by
    /// opening a TCP connection to the service over IPv4, reading the remote address, and closing
    /// the connection.
    private func resolve(_ result: NWBrowser.Result) {
        guard let name = Self.serviceName(result.endpoint),
              case .bonjour(let record) = result.metadata,
              let beacon = Beacon(txt: record.dictionary)
        else { return }

        let tcp = NWProtocolTCP.Options()
        let parameters = NWParameters(tls: nil, tcp: tcp)
        if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: result.endpoint, using: parameters)
        resolving.removeValue(forKey: name)?.cancel()
        resolving[name] = connection

        connection.stateUpdateHandler = { [weak self, weak connection] state in
            MainActor.assumeIsolated {
                guard let self, let connection, self.resolving[name] === connection else { return }
                switch state {
                case .ready:
                    if case .hostPort(let host, let port) = connection.currentPath?.remoteEndpoint,
                       case .ipv4(let address) = host {
                        self.place(name: name, beacon: beacon,
                                   address: address.rawValue.map(String.init).joined(separator: "."),
                                   port: Int(port.rawValue))
                    }
                    self.resolving[name] = nil
                    connection.cancel()
                case .failed, .cancelled:
                    self.resolving[name] = nil
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
    }

    private func place(name: String, beacon: Beacon, address: String, port: Int) {
        let computer = FoundComputer(deviceId: beacon.deviceId, name: beacon.name, address: address,
                                     port: port, publicKey: beacon.publicKey)
        PeerPins.shared.pin(address, spki: beacon.publicKey)
        names[name] = computer.key
        guard found[computer.key] != computer else { return }
        found[computer.key] = computer
        onChange()
    }
}
