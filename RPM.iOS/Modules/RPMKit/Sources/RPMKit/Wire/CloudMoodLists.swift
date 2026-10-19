import Foundation

/// One generated list as the computer cut it: what it is, and the records in it,
/// in order.
///
/// The phone renders these and does not compute them. The arithmetic behind them
/// is percentiles over a whole collection, and the phone does not have one: it
/// knows the tracks in the cloud and nothing about the records that never left
/// the computer's disk, so a cut made here would cover only part of a
/// library and would not give the same lists.
public struct CloudMoodList: Codable, Hashable, Sendable, Identifiable {
    /// The mood, as the desktop's own `SmartPlaylistKind` spells it ("Calm",
    /// "Danceable", "Sleep"). Matched by name and not by a number, so a mood
    /// added on the computer reaches an older phone as a list it can still show.
    public let kind: String

    /// The genre it is narrowed to, or nil for the whole list.
    public let genre: String?

    /// The first year of the decade it is narrowed to, or 0 for all of them.
    public let decade: Int

    /// What the computer calls this list ("Slow Burn", "Chill", "1970s"), or nil
    /// where the build that sent it had no name to give.
    ///
    /// **Carried here and not worked out here.** The words live in one table on the
    /// desktop, and the poetic ones are in English in every locale by design. If they
    /// were written a second time in Swift, the two would drift apart, and nobody
    /// would see it until the same list read as two different things on the two
    /// screens.
    ///
    /// Nil is an ordinary answer, not a fault: an older cut carries no names, and a
    /// reader falls back to the mood or the genre it already knows, as the desktop's
    /// own table does.
    public let title: String?

    /// Where the list sits in the tree the computer cut it in, outermost first:
    /// "Moods", or "Moods" then the mood, or "Decades". Empty where the computer's
    /// build does not send it, and then the reader places it itself.
    ///
    /// **Carried here and not worked out here.** The arrangement is part of what is
    /// shared: a reader that derived a place from the kind and the genre would
    /// arrive at a different one from the owner's, and each reader would differ from
    /// the others.
    public let folder: [String]

    /// RPM ids, best first. This is a RUN of `shows`-long lists and not one list.
    /// Played in this order, stepping over the ones this phone cannot resolve.
    public let trackIds: [String]

    /// How many of `trackIds` make ONE list. The rest are the readings after it.
    ///
    /// **This is what lets this phone offer a refresh.** It cannot cut a list, because
    /// the arithmetic is percentiles over a collection it does not have. So the
    /// computer sends a run of several lists' worth and the phone shows a slice this
    /// long, moving the slice on when somebody asks for a new list. One song per record
    /// holds across the whole run, so every slice is a different list.
    ///
    /// Zero, or anything at least as long as the run, means the run IS the list and
    /// there is nothing to step to: a cut from an older computer build, or
    /// a kind with no deeper pool behind it. See ``GeneratedLists/window(_:shows:reading:)``.
    public let shows: Int

    /// The id the computer gave this list, or nil from a build that sent none.
    ///
    /// A generated list is not stored anywhere as a row, so its id is made from what
    /// the list IS. It therefore survives a new cut, and it is the address its PICTURE
    /// lives at.
    public let listId: String?

    /// What this list is, whatever the computer calls it: the same three fields the
    /// cut is keyed on. It is the fallback identity when no id was sent.
    public var id: String { listId ?? "\(kind)|\(genre ?? "")|\(decade)" }

    /// Spelled out, because one of these is not named after its own field: the store
    /// calls it `id` and this type keeps `id` for what a list IS, so that a row read
    /// from a computer that sent no id is still identified by the three fields the cut
    /// is keyed on.
    private enum CodingKeys: String, CodingKey {
        case kind, genre, decade, title, folder, trackIds, shows
        case listId = "id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind     = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        genre    = try c.decodeIfPresent(String.self, forKey: .genre)
        decade   = try c.decodeIfPresent(Int.self, forKey: .decade) ?? 0
        title    = try c.decodeIfPresent(String.self, forKey: .title)
        folder   = try c.decodeIfPresent([String].self, forKey: .folder) ?? []
        listId   = try c.decodeIfPresent(String.self, forKey: .listId)
        trackIds = try c.decodeIfPresent([String].self, forKey: .trackIds) ?? []
        shows    = try c.decodeIfPresent(Int.self, forKey: .shows) ?? 0
    }

    public init(kind: String, genre: String? = nil, decade: Int = 0,
                title: String? = nil, folder: [String] = [], listId: String? = nil,
                trackIds: [String], shows: Int = 0) {
        self.kind = kind; self.genre = genre; self.decade = decade
        self.title = title; self.folder = folder; self.listId = listId
        self.trackIds = trackIds; self.shows = shows
    }
}

/// A whole cut, as one computer last sent it.
///
/// Whole because a cut is one answer: every list in it came from a single
/// reading of the collection, so that no two of them disagree about which
/// records are calm. It arrives in one object for the same reason.
public struct CloudMoodLists: Codable, Hashable, Sendable {
    /// Which version of the arithmetic made this. Nothing here branches on it;
    /// it is carried so a cut can be told apart from a later one made
    /// differently.
    public let recipe: Int

    /// When the store stamped it, in unix milliseconds off the SERVER's clock.
    /// What lets the phone say how old the lists it is showing are: a computer
    /// that has not run in a month is a real state, and a month-old list shown
    /// silently is not the same thing as a current one.
    public let computedAt: Int64

    public let lists: [CloudMoodList]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recipe     = try c.decodeIfPresent(Int.self, forKey: .recipe) ?? 0
        computedAt = try c.decodeIfPresent(Int64.self, forKey: .computedAt) ?? 0
        lists      = try c.decodeIfPresent([CloudMoodList].self, forKey: .lists) ?? []
    }

    public init(recipe: Int, computedAt: Int64, lists: [CloudMoodList]) {
        self.recipe = recipe; self.computedAt = computedAt; self.lists = lists
    }

    /// How long ago the computer cut these, or nil where the store gave no stamp.
    public var age: TimeInterval? {
        guard computedAt > 0 else { return nil }
        return Date().timeIntervalSince1970 - Double(computedAt) / 1000
    }
}
