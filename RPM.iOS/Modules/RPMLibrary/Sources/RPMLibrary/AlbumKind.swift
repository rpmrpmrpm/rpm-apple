import Foundation

/// What a record's title says it is: a live recording, one song released on its own,
/// music written for a film or show, or a compilation of earlier material. Each is a
/// shelf on an artist's page.
///
/// Ported from `RPM.Core/Library/AlbumKind.cs`, patterns included. Read from the title
/// because nothing else says: no tag carries these facts.
///
/// Ask with the title as tagged, never a tidied one. The markers are in the text that a
/// title tidier removes, so a tidied title has already lost the answer.
public enum AlbumKind {
    /// Whether this title names a record played in front of an audience rather than built
    /// in a studio: "Live at the Apollo", "MTV Unplugged", "The Abbey Road Sessions".
    ///
    /// The whole word, never a piece of one: "Alive", "Olive" and "Delivered" contain the
    /// letters and none of them matches. Sessions, unplugged and storytellers are on the
    /// same shelf, because those records are live recordings and the title often says
    /// nothing else.
    ///
    /// Known mistake: a studio record whose name starts with the word. Hole's "Live
    /// Through This" lands on the live shelf. Requiring "at" or a year after the word
    /// would also reject "Live '75" and many other real spellings.
    public static func isLive(_ title: String?) -> Bool { matches(title, live) }

    /// Whether this title names one song released on its own: "Runaway - Single".
    ///
    /// The dash is half the rule. "Single" on its own is an ordinary word in a title
    /// ("Single Ladies"), so what is matched is the ending that stores and exports add:
    /// the record's name, a dash, the word.
    public static func isSingle(_ title: String?) -> Bool { matches(title, single) }

    /// Whether this title names a collection of earlier material rather than a new
    /// record: "The Essential Aretha Franklin", "Greatest Hits", "The Collection".
    ///
    /// A short list of phrases, not a smart rule: nothing in the tags tells a compilation
    /// from an album, but the record industry uses a small set of words for it. Whole
    /// words, and the two-word ones kept whole, so "Recollection" and "Collective" are
    /// not matched.
    ///
    /// Known miss: a compilation that does not say so ("Legend", "Hot Rocks"). Those
    /// stay with the ordinary records.
    public static func isCompilation(_ title: String?) -> Bool { matches(title, compilation) }

    /// Whether this title names music written for a film or TV show: "Purple Rain
    /// (Original Soundtrack)", "Music from the HBO Series".
    ///
    /// The word "soundtrack" can be matched alone. "Score" cannot (the Fugees' "The
    /// Score"), so it counts only after a word that says what it is a score for.
    ///
    /// Known mistakes: "OST" also matches a German record whose title holds the word for
    /// east, and "music from" matches The Band's "Music from Big Pink". Both phrases are
    /// right far more often than they are wrong.
    public static func isSoundtrack(_ title: String?) -> Bool { matches(title, soundtrack) }

    // ── the patterns ──

    private static func matches(_ title: String?, _ pattern: NSRegularExpression) -> Bool {
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        return pattern.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)) != nil
    }

    private static let live = try! NSRegularExpression(
        pattern: #"\b(?:live|sessions|unplugged|storytellers)\b"#, options: [.caseInsensitive])

    private static let single = try! NSRegularExpression(
        pattern: #"[-–—]\s*singles?\b"#, options: [.caseInsensitive])

    private static let soundtrack = try! NSRegularExpression(
        pattern: #"\b(?:soundtracks?|(?:original|film|motion\s+picture)\s+scores?"#
               + #"|motion\s+picture|music\s+from|cast\s+recording|ost)\b"#,
        options: [.caseInsensitive])

    private static let compilation = try! NSRegularExpression(
        pattern: #"\b(?:greatest\s+hits|best\s+of|essentials?|collections?|anthology|anthologies"#
               + #"|compilations?|retrospective|definitive|hits)\b"#,
        options: [.caseInsensitive])
}

/// What kind of release a record is: the shelf it stands on on an artist's page. The
/// desktop's `ReleaseType`; the raw values are its stored names (`ReleaseTypes.ToStored`),
/// which the cloud's listing carries as `releaseType`.
public enum ReleaseType: String, Sendable, CaseIterable {
    case album = "Album", ep = "Ep", single = "Single", live = "Live", mixtape = "Mixtape"
    case compilation = "Compilation", soundtrack = "Soundtrack"

    /// The type a stored name means, or nil for a name that is none of them. Any case.
    public static func fromStored(_ stored: String?) -> ReleaseType? {
        guard let stored = stored?.trimmingCharacters(in: .whitespaces), !stored.isEmpty else { return nil }
        return allCases.first { $0.rawValue.caseInsensitiveCompare(stored) == .orderedSame }
    }

    /// What the record's name suggests, in the desktop's order (`ReleaseTypes.FromTitle`):
    /// single, live, soundtrack, compilation. Nil where it suggests nothing.
    public static func fromTitle(_ title: String?) -> ReleaseType? {
        if AlbumKind.isSingle(title) { return .single }
        if AlbumKind.isLive(title) { return .live }
        if AlbumKind.isSoundtrack(title) { return .soundtrack }
        if AlbumKind.isCompilation(title) { return .compilation }
        return nil
    }

    /// The shelf a record goes on: the type its tracks carry, else what its name suggests,
    /// else an album. A set type always wins, which is the point of setting it: "Live
    /// Through This" set to Album leaves the live shelf. The desktop's
    /// `ReleaseTypes.ShelfOf`. Where the tracks disagree, most of them decide.
    public static func shelf(of album: CloudAlbum) -> ReleaseType {
        var counts: [ReleaseType: Int] = [:]
        for track in album.tracks {
            if let type = fromStored(track.tags?.releaseType) { counts[type, default: 0] += 1 }
        }
        let order = Array(allCases)
        let set = counts.max { a, b in
            if a.value != b.value { return a.value < b.value }
            return (order.firstIndex(of: a.key) ?? 0) > (order.firstIndex(of: b.key) ?? 0)
        }?.key
        return set ?? fromTitle(album.album) ?? .album
    }
}
