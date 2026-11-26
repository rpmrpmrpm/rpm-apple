import Foundation

/// rpm's own record of the radio: the logo the API has chosen for each station, the card picture the
/// admin chose for some, and what the admin has decided about stations. This is the phone's version of the desktop's `RadioLogoApi` and `RadioState`.
///
/// **Requests go through ``Transport``, like every other API call.** Each request therefore carries the
/// app key (both endpoints are public reads, and they refuse a caller without it), waits for a network,
/// and is retried on a transient failure by ``Gated``.
///
/// **Why the logo comes from here first.** Radio Browser has no usable picture for about 38% of the stations it
/// lists, and a dead one for another 19%. The `tools/StationLogos` script visited each station's own website
/// and chose a 512px mark for 42,750 of the 59,654 stations. So the API's answer is usually better than what the directory has.
public struct RadioRepositoryClient: Sendable {
    private let transport: Transport

    public init(transport: Transport) {
        self.transport = transport
    }

    /// What the admin has decided. See `RadioStateController` in the API.
    public struct State: Decodable, Sendable, Equatable {
        /// Changes whenever a logo is set by hand. Empty if that has never happened.
        public let logos: String

        /// Stations not to show, by uuid.
        public let hidden: [String]

        /// Stations shown with a different title, tags or description, or marked for ads, by uuid
        /// (the admin's station edit page). Empty from an API that sends no edits.
        public let edits: [String: Edit]

        /// The stations with a card picture: a 16:9 picture the admin chose for the station's card, served
        /// at `radio/card/{uuid}` (see ``card(station:stamp:)``). Listed under every row of a station, as
        /// edits are. Empty from an API that sends none.
        public let cards: [String]

        /// Changes whenever a card picture changes. It goes in the picture's address, as ``logos`` does
        /// for a logo. Empty if no card picture was ever set.
        public let cardStamp: String

        /// One station's edit as the API sends it; a nil value is the directory's own.
        public struct Edit: Decodable, Sendable, Equatable {
            public let name: String?
            public let tags: [String]?
            public let description: String?
            /// True for a station that carries advertising, false for one that does not. Nil leaves
            /// it to the app's own rule (`RadioAds`). Not sent when the admin did not set it.
            public let ads: Bool?

            public init(name: String?, tags: [String]?, description: String?, ads: Bool? = nil) {
                self.name = name; self.tags = tags; self.description = description; self.ads = ads
            }
        }

        public init(logos: String, hidden: [String], edits: [String: Edit] = [:],
                    cards: [String] = [], cardStamp: String = "") {
            self.logos = logos
            self.hidden = hidden
            self.edits = edits
            self.cards = cards
            self.cardStamp = cardStamp
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            logos = try c.decodeIfPresent(String.self, forKey: .logos) ?? ""
            hidden = try c.decodeIfPresent([String].self, forKey: .hidden) ?? []
            // A malformed edits object is no edits, not a failed answer: the hidden list must still land.
            edits = (try? c.decodeIfPresent([String: Edit].self, forKey: .edits)) ?? [:]
            // The same for the card pictures: without them the cards are drawn as before.
            cards = (try? c.decodeIfPresent([String].self, forKey: .cards)) ?? []
            cardStamp = (try? c.decodeIfPresent(String.self, forKey: .cardStamp)) ?? ""
        }

        private enum CodingKeys: String, CodingKey { case logos, hidden, edits, cards, cardStamp }
    }

    /// Whether a stored answer may be used instead of asking the server.
    public enum Reading: Sendable {
        /// The first read after launch. The URL cache keeps an answer for an hour. Without this, a
        /// restart would show the state from before a change made in the admin.
        case pastTheStore

        /// Any later read. An answer less than an hour old is used.
        case stored
    }

    public func state(_ reading: Reading) async throws -> State {
        let (status, data) = try await transport.raw(
            "GET", "radio/state",
            cache: reading == .pastTheStore ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy)

        guard (200..<300).contains(status) else { throw RPMError.status(status) }

        do { return try RPMJSON.decoder.decode(State.self, from: data) }
        catch { throw RPMError.decoding(error) }
    }

    /// A station's logo as the API holds it.
    public enum Logo: Sendable, Equatable {
        /// The picture's bytes: WebP for a raster image, SVG for a drawing, as the stored object says.
        case found(Data)

        /// The crawl found no logo for this station. This is an answer, and the server lets it be
        /// cached for a day.
        case none
    }

    /// - Parameter stamp: The ``State/logos`` stamp currently held, or empty before the first answer.
    ///   It goes in the address, not in a header. The URL cache keeps a logo for thirty days, and a new
    ///   address is the one change it cannot miss. See `RadioLogoApi.For`.
    /// - Throws: When the server gave no answer about this station (offline, or a 5xx after the retries).
    ///   This is not the same as ``Logo/none``, and a caller must not store it as if it were.
    public func logo(station uuid: String, stamp: String) async throws -> Logo {
        // The uuid is about to become part of a path, so it is checked, as the desktop does. A value
        // that is not a uuid has no logo here.
        guard let id = UUID(uuidString: uuid) else { return .none }

        var path = "radio/logo/\(id.uuidString.lowercased())"
        if !stamp.isEmpty {
            path += "?v=" + (stamp.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        }

        let (status, data) = try await transport.raw("GET", path, cache: .useProtocolCachePolicy)

        switch status {
        case 200..<300 where !data.isEmpty: return .found(data)
        case 404: return .none
        default: throw RPMError.status(status)
        }
    }

    /// A station's card picture as the API holds it: the bytes as the admin uploaded them, or nil where
    /// the station has none (404). Ask only for a station that ``State/cards`` lists.
    ///
    /// - Parameter stamp: The ``State/cardStamp`` currently held. It goes in the address, as a logo's
    ///   stamp does, so a changed picture is a new address that the url cache has not kept.
    /// - Throws: When the server gave no answer about this station (offline, or a 5xx after the retries).
    public func card(station uuid: String, stamp: String) async throws -> Data? {
        // The uuid is about to become part of a path, so it is checked, as for a logo.
        guard let id = UUID(uuidString: uuid) else { return nil }

        var path = "radio/card/\(id.uuidString.lowercased())"
        if !stamp.isEmpty {
            path += "?v=" + (stamp.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        }

        let (status, data) = try await transport.raw("GET", path, cache: .useProtocolCachePolicy)

        switch status {
        case 200..<300 where !data.isEmpty: return data
        case 404: return nil
        default: throw RPMError.status(status)
        }
    }
}
