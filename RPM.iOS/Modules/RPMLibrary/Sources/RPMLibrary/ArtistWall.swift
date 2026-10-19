import Foundation
import RPMKit

/// One album's credits as the phone holds them: the record's own artist, one of its
/// tracks' artists, and how many of its tracks carry that pairing.
///
/// `album` is the album's grouping key rather than a folder, which is the desktop's own
/// identity for the same thing. See ``AlbumGrouping/key(for:)``.
public struct ArtistCreditRow: Sendable, Equatable {
    public let album: String
    public let albumArtist: String?
    public let artist: String?
    public let tracks: Int

    public init(album: String, albumArtist: String?, artist: String?, tracks: Int) {
        self.album = album
        self.albumArtist = albumArtist
        self.artist = artist
        self.tracks = tracks
    }
}

/// One person or band on the artists wall: their name, the records the collection files
/// under them, and the records they only turn up on.
public struct ArtistWallItem: Sendable, Equatable, Identifiable {
    /// The spelling to show: the one the most rows carry, where the collection spells
    /// them more than one way.
    public let name: String

    /// Albums filed under this artist alone.
    public let albums: [String]

    /// Albums filed under a credit naming this artist and somebody else: a record the two
    /// of them made, not a record of theirs with a guest on it. Apart from ``albums``
    /// because it is a different fact and the page says so.
    public let together: [String]

    /// Albums where they are credited on a track but the record is somebody else's. This
    /// is what puts one album in two artists' listings.
    public let appearances: [String]

    /// How many tracks name them, anywhere.
    public let tracks: Int

    public var id: String { name }

    /// The records that are theirs, alone or shared. An artist whose only records are
    /// collaborations has none of the first kind and is not a stranger to the collection.
    public var own: [String] { albums + together }

    /// Every album they are on at all, their own records first.
    public var everything: [String] { own + appearances }

    /// Which letter of the index rail they sit under.
    public var initial: Character { ArtistWall.initial(name) }

    public init(name: String, albums: [String], together: [String],
                appearances: [String], tracks: Int) {
        self.name = name
        self.albums = albums
        self.together = together
        self.appearances = appearances
        self.tracks = tracks
    }
}

/// The collection read by who made it: one entry per act, not per credit.
///
/// Ported from `RPM.Core/Library/ArtistWall.cs`, rule for rule, so the phone and the
/// desktop hold the same wall.
///
/// The whole difficulty is in one line of the tags. A track's artist field is a credit,
/// not a name: "Ellie Goulding" and "Calvin Harris feat. Ellie Goulding" are two strings
/// naming one person twice, and a wall built on the strings shows her twice. So every
/// credit is split into the acts it names, and the album lands in the listing of each of
/// them: one record, two boxes, which is what a guest appearance is.
///
/// Except where the credit is itself a band. The same separators that mean "and also" are
/// in "Earth, Wind & Fire" and "AC/DC". What tells the two apart is the collection
/// itself: a credit the library files a record under is a name, because somebody's tagger
/// wrote it into an album-artist field. "Queen & David Bowie" is nobody's album artist and
/// splits; "Simon & Garfunkel" is, and stands.
///
/// An act with nothing of their own is not on the wall. A guest verse is a credit, not a
/// discography. So a box is for an act the collection files a record under, and everybody
/// else is still named, still split, still matched, and still listed on the pages of the
/// artists they appear beside.
///
/// And the compilations are an act: records filed under "Various Artists" get one box
/// under one spelling, however many the collection holds.
public enum ArtistWall {
    /// The one name every spelling of the compilation marker is shown under.
    public static let compilations = ArtistCredit.variousArtists

    /// The credit rows a wall of records makes, one per (album, track artist) pairing.
    ///
    /// The desktop reads these out of its mirror with a group-by; the phone has the
    /// albums in hand and counts them here. An album with no track artists at all still
    /// yields one row, so a record nobody's tags credit is still filed under whoever it
    /// is filed under.
    ///
    /// The album artist is ``CloudAlbum/artist``, which is already the desktop's own
    /// answer with its own fallbacks: the album-artist tag, then the first track artist,
    /// then the folder above the album. So every album here has somebody to be filed
    /// under, where the desktop's mirror rows can carry a null. A record whose tags say
    /// nothing lands on the page of whoever the wall already draws it under, rather than
    /// on nobody's page.
    public static func rows(_ albums: [CloudAlbum]) -> [ArtistCreditRow] {
        var rows: [ArtistCreditRow] = []
        rows.reserveCapacity(albums.count)

        for album in albums {
            var counts: [String: Int] = [:]
            var order: [String] = []

            for track in album.tracks {
                let credit = (track.artist ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !credit.isEmpty else { continue }
                if counts[credit] == nil { order.append(credit) }
                counts[credit, default: 0] += 1
            }

            guard !order.isEmpty else {
                rows.append(ArtistCreditRow(album: album.key, albumArtist: album.artist,
                                            artist: nil, tracks: album.tracks.count))
                continue
            }

            for credit in order {
                rows.append(ArtistCreditRow(album: album.key, albumArtist: album.artist,
                                            artist: credit, tracks: counts[credit] ?? 0))
            }
        }

        return rows
    }

    /// The wall, in name order.
    public static func build(_ credits: [ArtistCreditRow]) -> [ArtistWallItem] {
        // What the collection files records under: squashed name to the spelling as filed.
        // A credit in here is a name however many separators it has in it, unless the
        // pass below finds it to be two acts working together. The spelling is kept
        // beside the squashed name because deciding that means splitting the credit up,
        // and a squashed name cannot be split back into people. It is also the spelling
        // that a run of split parts is shown under when it is rejoined (see `rejoined`).
        var bands: [String: String] = [:]
        var filed: [String] = []

        for row in credits {
            guard let credit = row.albumArtist, !credit.isEmpty,
                  !ArtistCredit.isVariousArtists(credit),
                  bands[NameMatch.squash(credit)] == nil
            else { continue }

            let spelled = credit.trimmingCharacters(in: .whitespacesAndNewlines)
            bands[NameMatch.squash(credit)] = spelled
            filed.append(spelled)
        }

        let joint = collaborations(credits, bands: bands, filed: filed)

        var acts: [String: Act] = [:]

        for (index, row) in credits.enumerated() {
            // The record's own name first, so whoever it is filed under leads their own
            // album even when no track of it credits them by name.
            //
            // More than one name out of one album-artist credit means the record was
            // made by the pair of them rather than by either alone, and each of them is
            // told so: the page shelves those apart.
            let leads = names(row.albumArtist, bands: bands, joint: joint)
            for name in leads {
                Act.at(&acts, name)
                    .lead(row.album, row: index, tracks: row.tracks, shared: leads.count > 1)
            }

            for name in names(row.artist, bands: bands, joint: joint) {
                Act.at(&acts, name).guest(row.album, row: index, tracks: row.tracks)
            }
        }

        // In the rail's order, which is not quite name order: the hash bucket is the last
        // letter of the rail and has to be the last stretch of the wall, or reaching for
        // it would scroll upwards. Through ``ArtistSort/byName(_:)`` rather than a
        // comparator written here, so a wall built by this and a wall the page has since
        // put back into name order cannot come out in two different orders.
        let wall = acts.values
            .map { $0.settle() }
            // A record of their own is what a box is for. Filtered here rather than while
            // the credits are read, because a guest credit is still how the collection
            // comes to know a name: the collaboration rule above reads every act it has
            // heard of, and an act dropped before that would take a joint record's other
            // half down with it.
            .filter { !$0.albums.isEmpty || !$0.together.isEmpty }

        return ArtistSort.byName(wall)
    }

    /// Whether one credit as typed names this act: what an artist's page picks their own
    /// songs out of somebody else's record with.
    ///
    /// The credit whole first, so a band whose name has a separator in it matches itself
    /// before it is ever cut up; then each act the credit names.
    ///
    /// The wide reading, because a record two acts made is credited "A with B" as often
    /// as "A & B". Safe here in a way it is not when building the wall: this asks whether
    /// one credit names one artist the caller already has in hand, so a name cut in the
    /// wrong place matches nobody and costs nothing.
    public static func names(_ credit: String?, artist: String?) -> Bool {
        guard let credit, !credit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let artist, !artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return false }

        return NameMatch.same(credit, artist)
            || ArtistCredit.splitWide(credit).contains { NameMatch.same($0, artist) }
    }

    /// The letter this name sits under on the index rail: its first letter, or "#" for a
    /// name that starts with a digit, a symbol, or a script the rail has no letter for.
    ///
    /// Diacritics fold, so "Sigur Rós" and "Ólafur Arnalds" sit under S and O rather than
    /// in the hash bucket with the numbers.
    public static func initial(_ name: String?) -> Character {
        for character in (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines) {
            guard character.isLetter || character.isNumber else { continue }

            let folded = fold(character)
            return ("A"..."Z").contains(folded) ? folded : "#"
        }

        return "#"
    }

    /// Whether this artist answers to what has been typed in the wall's search field.
    ///
    /// A substring, but of a folded reading of both: case, accents, spacing and
    /// punctuation are dropped from the name and from the query alike. "sigur ros" finds
    /// Sigur Rós, "acdc" finds AC/DC, "guns n roses" finds Guns N' Roses.
    ///
    /// A query that folds away to nothing matches everybody rather than nobody: a field
    /// with one character in it must not empty the wall while the second is on its way.
    public static func matches(_ name: String?, _ query: String?) -> Bool {
        let wanted = searchKey(query)
        return wanted.isEmpty || searchKey(name).contains(wanted)
    }

    /// A name as the search compares it: lower case, accents off, everything that is not
    /// a letter or a digit gone. Public so a caller filtering a long list can fold the
    /// query once instead of once per name.
    public static func searchKey(_ text: String?) -> String {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        // By SCALAR, not by Character. Decomposing "ó" gives "o" plus a combining
        // acute, and a String iterated by Character puts those straight back together
        // into one "ó". Read that way the decomposition does nothing at all, and
        // "sigur ros" does not find Sigur Rós.
        var folded = ""
        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
            let part = Character(scalar)
            guard part.isLetter || part.isNumber else { continue }
            folded += String(part).lowercased()
        }

        return folded
    }

    /// The alphabet the rail is drawn from: A to Z, then the bucket for everything that
    /// does not start with one. Shared so the rail and the wall cannot disagree.
    public static let alphabet: [Character] =
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).map { Character(UnicodeScalar($0)) } + ["#"]

    // ── reading a credit ──

    /// The acts one credit names. A credit the collection files a record under is one act
    /// whatever is written in it; anything else is split. A blank credit names nobody.
    ///
    /// The compilation marker names one act, and always the same one: every spelling of
    /// it is the same shelf. It is never split and never a band. It is not a name at all,
    /// it is what a record says when it has no single artist.
    private static func names(
        _ credit: String?, bands: [String: String], joint: [String: [String]]
    ) -> [String] {
        guard let credit, !credit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        if ArtistCredit.isVariousArtists(credit) { return [compilations] }

        let whole = credit.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = NameMatch.squash(whole)

        // A record two acts made together comes first: it is filed under a credit naming
        // both of them, so the rule below would call it one band and give it a box of its
        // own, which is the record missing from both their pages.
        if let together = joint[key] { return together }
        if bands[key] != nil { return [whole] }
        return rejoined(ArtistCredit.splitGuests(whole), bands: bands)
    }

    /// A split credit with any run of its parts that spells a name the collection files
    /// records under put back together (the desktop's `ArtistWall.Rejoined`). The split knows
    /// where a separator is, not which ones are inside a name: "A$AP Rocky; Tyler, The
    /// Creator; Jozzy" cuts into four, and two of the four are one act. Only a run that
    /// squashes to a filed credit is rejoined, so this never invents an act.
    ///
    /// This is also what keeps `collaborations` right: it reads the names a collection knows
    /// from split track credits. Without rejoining, "Tyler" and "The Creator" would both be in
    /// that set, so "Tyler, The Creator" would pass as two people and get two boxes.
    /// Never across a "feat"; the longest run wins, under the collection's spelling.
    private static func rejoined(_ groups: [[String]], bands: [String: String]) -> [String] {
        var kept: [String] = []
        for parts in groups {
            var i = 0
            while i < parts.count {
                // Squashes concatenate the way the names do, so a run never has to be
                // spelled back out to be recognised.
                var run = NameMatch.squash(parts[i])
                var joined = run
                var last = i
                var j = i + 1
                while j < parts.count {
                    joined += NameMatch.squash(parts[j])
                    if bands[joined] != nil {
                        run = joined
                        last = j
                    }
                    j += 1
                }

                if last == i {
                    kept.append(parts[i])
                } else if !kept.contains(where: { NameMatch.squash($0) == run }), let spelled = bands[run] {
                    // A rejoin can bring back a name the credit already named elsewhere.
                    kept.append(spelled)
                }
                i = last + 1
            }
        }
        return kept
    }

    /// Which of the credits the collection files records under name two acts working
    /// together rather than one act with a separator in its name, and who each names.
    ///
    /// "Simon & Garfunkel" and "Kanye West & Ty Dolla $ign" are the same shape, and the
    /// album-artist rule cannot tell them apart. What tells them apart is the collection,
    /// again: a collaboration is a credit whose every part is somebody the collection
    /// already knows on their own.
    ///
    /// Every part, not most. "Nick Cave & The Bad Seeds" is the case that decides it: a
    /// collection holding his solo records knows "Nick Cave" on his own, and a rule that
    /// split on one known part would break the band up.
    private static func collaborations(
        _ credits: [ArtistCreditRow], bands: [String: String], filed: [String]
    ) -> [String: [String]] {
        // Everybody the wall would hold under the album-artist rule alone. A guest on one
        // track is in here, and that is the point: most of an artist's collaborators
        // appear nowhere in a collection except as a featured credit on somebody's song.
        var known: Set<String> = []
        let none: [String: [String]] = [:]

        for row in credits {
            for name in names(row.albumArtist, bands: bands, joint: none) {
                known.insert(NameMatch.squash(name))
            }
            for name in names(row.artist, bands: bands, joint: none) {
                known.insert(NameMatch.squash(name))
            }
        }

        var joint: [String: [String]] = [:]
        for credit in filed {
            let parts = ArtistCredit.splitWide(credit)
            if parts.count > 1 && parts.allSatisfy({ known.contains(NameMatch.squash($0)) }) {
                joint[NameMatch.squash(credit)] = parts
            }
        }

        return joint
    }

    /// A letter with its accent taken off, where taking it off leaves a letter of the
    /// rail's own alphabet. Decomposition rather than a table.
    private static func fold(_ character: Character) -> Character {
        let upper = String(character).uppercased()

        // By scalar, for the reason searchKey reads by scalar: the base letter only
        // comes out of a decomposition if the combining mark is left where it is.
        for scalar in upper.decomposedStringWithCanonicalMapping.unicodeScalars {
            let part = Character(scalar)
            if ("A"..."Z").contains(part) { return part }
        }

        return upper.first ?? character
    }
}

// ── one act, while the rows are still being read ──

/// Every spelling seen with its weight, so the wall can show the one the most rows carry,
/// and the albums split by whether the record is theirs.
private final class Act {
    private var spellings: [String: Int] = [:]
    private var albums: [String] = []
    private var together: [String] = []
    private var appearances: [String] = []
    private var leads: Set<String> = []
    private var guests: Set<String> = []
    private var counted: Set<Int> = []
    private var tracks = 0

    static func at(_ acts: inout [String: Act], _ name: String) -> Act {
        let key = NameMatch.squash(name)
        let act = acts[key] ?? Act()
        if acts[key] == nil { acts[key] = act }
        act.spellings[name, default: 0] += 1
        return act
    }

    /// This record is theirs.
    ///
    /// - Parameter shared: somebody else is on the credit it is filed under, so the two
    ///   of them made it. Stated by the caller rather than worked out here, because what
    ///   says so is the credit as a whole and this only ever sees one name out of it.
    func lead(_ album: String, row: Int, tracks: Int, shared: Bool) {
        count(row, tracks)
        guard leads.insert(folded(album)).inserted else { return }

        // Filed under them after all: the album arrived as an appearance because a guest
        // credit of theirs was read first, and it is their own record.
        if guests.remove(folded(album)) != nil {
            appearances.removeAll { folded($0) == folded(album) }
        }

        if shared { together.append(album) } else { albums.append(album) }
    }

    /// They are on this record, which may or may not be theirs.
    func guest(_ album: String, row: Int, tracks: Int) {
        count(row, tracks)
        guard !leads.contains(folded(album)), guests.insert(folded(album)).inserted else { return }
        appearances.append(album)
    }

    /// One row's tracks, once. A row names an act twice whenever the record is filed
    /// under the same name its tracks are credited to, which is most records there are.
    private func count(_ row: Int, _ tracks: Int) {
        guard counted.insert(row).inserted else { return }
        self.tracks += tracks
    }

    func settle() -> ArtistWallItem {
        // The spelling on the most rows wins, and the alphabetically first of a tie, so
        // two builds over one collection never disagree about how somebody is written.
        let name = spellings
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .first?.key ?? ""

        return ArtistWallItem(name: name,
                              albums: albums.sorted(by: before),
                              together: together.sorted(by: before),
                              appearances: appearances.sorted(by: before),
                              tracks: tracks)
    }

    /// Album keys are compared without case, the way the desktop compares its folders.
    private func folded(_ album: String) -> String { album.lowercased() }

    private func before(_ one: String, _ other: String) -> Bool {
        let order = one.compare(other, options: .caseInsensitive)
        return order != .orderedSame ? order == .orderedAscending : one < other
    }
}
