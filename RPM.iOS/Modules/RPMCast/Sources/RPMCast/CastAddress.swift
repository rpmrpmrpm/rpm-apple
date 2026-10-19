import Foundation
import Network
import os

extension CastDiscovery {
    /// Turns a browse result into an address.
    ///
    /// A Bonjour browse returns a *service*, not a host. It has the name, the type and the
    /// TXT record, but nothing to connect to. To resolve it, this opens a connection to the
    /// service endpoint and reads the address that the connection was built with. Network
    /// framework does the resolving, so no separate resolver is needed.
    enum Address {
        /// How long one speaker has to answer. On a local network, Bonjour resolves in
        /// milliseconds when it works. After this time the device has most likely left the
        /// network, but it is still advertised.
        static let patience: Duration = .seconds(4)

        static func of(_ reading: Reading) async -> CastDevice? {
            guard let (host, port) = await resolve(reading.endpoint) else { return nil }
            return CastDevice.from(txt: reading.txt, host: host, port: port)
        }

        private static func resolve(_ endpoint: NWEndpoint) async -> (String, Int)? {
            let connection = NWConnection(to: endpoint, using: .tcp)

            // **Resumed once, whatever happens.** A continuation that is resumed twice crashes.
            // There are three ways out: ready, failed, and the timeout.
            let answered = OSAllocatedUnfairLock(initialState: false)

            return await withTaskGroup(of: (String, Int)?.self) { group in
                group.addTask {
                    await withCheckedContinuation { continuation in
                        @Sendable func answer(_ found: (String, Int)?) {
                            let first = answered.withLock { done -> Bool in
                                guard !done else { return false }
                                done = true
                                return true
                            }
                            guard first else { return }
                            continuation.resume(returning: found)
                        }

                        connection.stateUpdateHandler = { state in
                            switch state {
                            case .ready: answer(named(connection.currentPath?.remoteEndpoint))
                            case .failed, .cancelled: answer(nil)
                            default: break
                            }
                        }

                        connection.start(queue: .global(qos: .userInitiated))
                    }
                }

                group.addTask {
                    try? await Task.sleep(for: patience)
                    return nil
                }

                let first = await group.next() ?? nil
                group.cancelAll()
                connection.cancel()
                return first
            }
        }

        /// The address that a ready connection was built on.
        private static func named(_ endpoint: NWEndpoint?) -> (String, Int)? {
            guard case .hostPort(let host, let port) = endpoint else { return nil }

            switch host {
            case .ipv4(let address): return (text(of: address), Int(port.rawValue))
            case .ipv6(let address): return (text(of: address), Int(port.rawValue))
            case .name(let name, _): return (name, Int(port.rawValue))
            @unknown default: return nil
            }
        }

        /// The address without the interface suffix that `debugDescription` adds. For example,
        /// `fe80::1%en0` cannot go in a URL. An IPv4 address can carry the same suffix.
        private static func text(of address: some IPAddress) -> String {
            "\(address)".split(separator: "%").first.map(String.init) ?? "\(address)"
        }
    }
}
