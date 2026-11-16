import Foundation

/// The badges a person can show under their name on their profile page, and what unlocks each. It is the Android
/// app's `ProfileBadges`: the same ids, the same order and the same rules; change both.
///
/// Every badge is worked out from the person's own collection on their own phone (``unlocked(albums:tracks:genreAlbums:)``),
/// sent to the server (`PUT profile/badges`), and kept there, so a badge once unlocked stays. The server only checks
/// the ids' shape.
public enum RPMProfileBadges {
    /// One badge: its id on the wire, and the string keys of its name and of what unlocks it.
    public struct Badge: Hashable, Sendable, Identifiable {
        public let id: String
        public let nameKey: String
        public let needKey: String

        public var name: String { Loc.get(nameKey) }
        public var need: String { Loc.get(needKey) }
    }

    private static func badge(_ id: String, _ key: String) -> Badge {
        Badge(id: id, nameKey: "Rpm_Badge_" + key, needKey: "Rpm_Badge_" + key + "_Need")
    }

    /// Every badge, in the order the edit page lists them.
    public static let all: [Badge] = [
        badge("first-spin", "FirstSpin"),
        badge("crate-digger", "CrateDigger"),
        badge("record-collector", "RecordCollector"),
        badge("music-connoisseur", "Connoisseur"),
        badge("living-archive", "LivingArchive"),
        badge("museum-curator", "MuseumCurator"),
        badge("ten-thousand", "TenThousand"),
        badge("rock", "Rock"),
        badge("jazz", "Jazz"),
        badge("classical", "Classical"),
        badge("hiphop", "HipHop"),
        badge("electronic", "Electronic"),
        badge("metal", "Metal"),
        badge("pop", "Pop"),
        badge("soul", "Soul"),
        badge("folk", "Folk"),
        badge("blues", "Blues"),
        badge("reggae", "Reggae"),
        badge("latin", "Latin"),
        badge("genre-hopper", "GenreHopper"),
        badge("omnivore", "Omnivore"),
    ]

    public static func byId(_ id: String) -> Badge? { all.first { $0.id == id } }

    /// The badge colours, as 0xRRGGBB; the first is the default. The Android app's `ProfileBadges.colours`; change both.
    public static let colours: [UInt32] = [0x7A1FD1, 0x2563EB, 0x0E9F95, 0x2E9E4F, 0xD12A4E, 0xE0701B, 0xD63FA6, 0xB8901F]

    /// A colour's wire value: `#RRGGBB`.
    public static func wire(_ colour: UInt32) -> String { "#" + String(format: "%06X", colour & 0xFFFFFF) }

    /// A badge colour from its wire value; the first of ``colours`` when it cannot be read.
    public static func colour(_ wire: String) -> UInt32 {
        guard wire.count == 7, wire.hasPrefix("#"), let value = UInt32(wire.dropFirst(), radix: 16) else { return colours[0] }
        return value
    }

    /// Albums needed for each size badge.
    private static let sizes: [(String, Int)] = [("first-spin", 1), ("crate-digger", 50), ("record-collector", 250),
                                                  ("music-connoisseur", 1_000), ("living-archive", 2_500),
                                                  ("museum-curator", 5_000)]

    /// The genre badges, each with the shelves it counts (lower case; see `Genres`).
    private static let genres: [(String, Set<String>)] = [
        ("rock", ["rock", "indie", "punk", "noise"]),
        ("jazz", ["jazz"]),
        ("classical", ["classical", "neo-classical", "opera"]),
        ("hiphop", ["hip-hop / rap", "rap", "trap", "old school hip hop"]),
        ("electronic", ["electronic / dance", "house", "techno", "club"]),
        ("metal", ["metal"]),
        ("pop", ["pop", "disco"]),
        ("soul", ["r&b", "soul", "funk"]),
        ("folk", ["folk", "country"]),
        ("blues", ["blues"]),
        ("reggae", ["reggae"]),
        ("latin", ["latin"]),
    ]

    /// A genre badge needs this share of all albums ...
    private static let genreShare = 0.2

    /// ... and at least this many albums of the genre.
    private static let genreLeast = 25

    /// A genre counts towards the range badges with this many albums.
    private static let rangeAlbums = 5

    /// The shelf for music the app cannot file; it is not a genre.
    private static let unclassified = "other / unknown"

    /// The badges this collection has unlocked, in ``all``'s order.
    ///
    /// - Parameter genreAlbums: how many albums each genre shelf holds, by the shelf's name.
    public static func unlocked(albums: Int, tracks: Int, genreAlbums: [String: Int]) -> [String] {
        var held = Set<String>()
        for (id, least) in sizes where albums >= least { held.insert(id) }
        if tracks >= 10_000 { held.insert("ten-thousand") }
        var byShelf: [String: Int] = [:]
        for (shelf, count) in genreAlbums {
            byShelf[shelf.trimmingCharacters(in: .whitespaces).lowercased(), default: 0] += count
        }
        for (id, shelves) in genres {
            let count = byShelf.filter { shelves.contains($0.key) }.values.reduce(0, +)
            if count >= genreLeast, albums > 0, Double(count) >= Double(albums) * genreShare { held.insert(id) }
        }
        let wide = byShelf.filter { $0.key != unclassified && $0.value >= rangeAlbums }.count
        if wide >= 10 { held.insert("genre-hopper") }
        if wide >= 20 { held.insert("omnivore") }
        return all.map(\.id).filter(held.contains)
    }
}
