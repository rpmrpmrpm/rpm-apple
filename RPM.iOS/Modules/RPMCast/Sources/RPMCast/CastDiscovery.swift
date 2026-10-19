import Foundation
import Network
import os

/// Finds Cast speakers from a phone.
///
/// **Not by opening a multicast socket.** iOS does not allow that without the
/// `com.apple.developer.networking.multicast` entitlement. Apple grants that entitlement on written
/// application, case by case. Code that tries to open a multicast socket finds nothing, and gives no
/// error to say why.
///
/// The supported route asks the system's own mDNS responder. It needs no entitlement. It needs only
/// the Local Network permission, and the service type listed under `NSBonjourServices` in `Info.plist`.
/// **A service type that is not listed there is not refused. It simply never returns anything.**
///
/// This uses `NWBrowser`, not the deprecated `NSNetServiceBrowser`. `bonjourWithTXTRecord` also returns
/// the TXT record with each browse result, so a speaker's name and model arrive without a second round trip.
public actor CastDiscovery {
    private static let log = Logger(subsystem: "com.rpm.player", category: "cast")

    /// What Cast advertises itself as. `Info.plist` must declare this type.
    public static let serviceType = "_googlecast._tcp"

    /// How long a resolve is given before it is abandoned. There is one timer for the whole sweep, not
    /// one per speaker. A speaker that has left the network is still browsed, but it never resolves.
    /// Its wait must not add to everyone else's wait.
    public static let resolve: Duration = .seconds(4)

    private var browser: NWBrowser?
    private var found: [String: CastDevice] = [:]

    public init() {}

    /// Browses for `howLong`, then returns the speakers that answered, sorted by name.
    ///
    /// **Never throws.** No network, no permission, and no speakers all give the same result: an empty
    /// list. The picker then shows that no speakers were found.
    public func speakers(for howLong: Duration = .seconds(3)) async -> [CastDevice] {
        found = [:]
        start()

        try? await Task.sleep(for: howLong)

        stop()
        return found.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func start() {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
            using: parameters)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            // Passed from the browser's queue to the actor. The results are values, so they can be
            // handled wherever they arrive.
            let seen = results.compactMap(Reading.of)
            Task { [weak self] in await self?.note(seen) }
        }

        browser.stateUpdateHandler = { state in
            // The failure worth logging. A browser that cannot start usually means the Local Network
            // permission is missing. From the outside, that looks exactly like a house with no speakers.
            if case .failed(let why) = state {
                Self.log.error("browsing stopped: \(why.localizedDescription, privacy: .public)")
            }
        }

        browser.start(queue: .global(qos: .userInitiated))
        self.browser = browser
    }

    private func stop() {
        browser?.cancel()
        browser = nil
    }

    /// Resolves each reading to an address, and keeps it.
    ///
    /// A browse result has the TXT record but no address, so the endpoint is resolved here. A group and its
    /// host speaker share an address and differ in port and id. That is why the key is the id.
    private func note(_ readings: [Reading]) async {
        await withTaskGroup(of: CastDevice?.self) { group in
            for reading in readings {
                group.addTask { await Address.of(reading) }
            }
            for await device in group {
                guard let device else { continue }
                found[device.id] = device
            }
        }
    }

    /// What a browse result says before anything has been resolved.
    struct Reading: Sendable {
        let endpoint: NWEndpoint
        let txt: [String: String]

        static func of(_ result: NWBrowser.Result) -> Reading? {
            guard case .bonjour(let record) = result.metadata else { return nil }

            var txt: [String: String] = [:]
            for key in [CastDevice.Keys.name, CastDevice.Keys.model, CastDevice.Keys.id] {
                if case .string(let value) = record.getEntry(for: key) { txt[key] = value }
            }
            return Reading(endpoint: result.endpoint, txt: txt)
        }
    }
}
