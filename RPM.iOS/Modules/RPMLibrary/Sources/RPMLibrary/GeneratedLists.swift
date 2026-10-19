import Foundation
import RPMKit

/// The computer's generated lists, turned into rows that the playlists tab already knows
/// how to draw.
///
/// **They arrive as lists of ids, and that is exactly what a playlist is here.** The phone
/// cannot cut a list again. The cutting uses percentiles over a whole collection, and this
/// platform knows the tracks in the cloud rather than the collection. So what arrives is a
/// fixed order of records with a name on it.
///
/// Folding them into the playlist tree means that browsing, opening, the cover and playback
/// all work already, and none of them needed any change. The desktop does the same thing
/// for a shelf that it has borrowed. See `BorrowedMoodLists`.
///
/// **This type can take its own window.** A list arrives as a RUN of several lists' worth,
/// and `shows` says how long one list is. The refresh button here steps a slice along the
/// run, so nobody has to cut anything. Nothing is computed, and nothing can drift: every
/// slice was chosen by the computer, in the computer's own order. See
/// ``window(_:shows:reading:)``.
///
/// **The tree they go into is the computer's own.** Every list carries the folders it sits
/// in, such as "Moods", then "Moods" and the mood, or "Decades". A listener who arranges
/// music on a computer and then picks up a phone sees the arrangement they made. The phone
/// works the tree out only as a fallback, for a cut from a computer whose build is too old
/// to send the folders. That fallback uses the kind and the genre. See `placed`.
///
/// **A mood that has cuts under it is a FOLDER here, and its own list is the first row
/// inside.** This is the one place where this surface departs from the tree it is given.
/// The departure is about rows, not about arrangement. On the computer, the mood is one row
/// that is both a playlist and a folder. A phone row leads to exactly one place. So a mood
/// such as Adrenaline is a place, and the first thing in it is the whole Adrenaline list,
/// above the cuts of it.
///
/// **Every list is `.generated`, and that is what keeps them read-only.** Their ids name
/// nothing in the cloud. A write would not change a list. It would make a playlist out of
/// a cut that the computer replaces completely on its next run.
public enum GeneratedLists {
    /// The prefix that every generated id has. A cloud playlist id is a UUID that the store
    /// holds. This prefix is a string that no store has ever issued, so a generated row can
    /// never be mistaken for a playlist that somebody made. The desktop has the same reason
    /// for numbering its borrowed generated rows downwards from zero.
    private static let mark = "\u{1}mood/"

    /// The id that the STORE knows a list by. This is not always the id this app files it
    /// under.
    ///
    /// A generated list has a mark that no cloud id carries, so it can never be mistaken
    /// for a playlist that somebody made. The store has never seen that mark. It holds a
    /// picture under the id the computer sent. So the mark is removed on the way out, and
    /// the two sets of ids stay separate on the way in.
    ///
    /// A list from a cut that carried no id keeps its made-up id. No store will answer for
    /// that id, which is the right result, and it is the same result as for a list with no
    /// picture.
    public static func storeId(of set: PlaylistSet) -> String {
        guard set.origin == .generated, set.id.hasPrefix(mark) else { return set.id }
        return String(set.id.dropFirst(mark.count))
    }

    /// The slice of a run that is one list.
    ///
    /// **Slices do not overlap, except at the end.** A run of 150 with lists of 50 gives
    /// three lists. The reading number picks one, and the choice wraps around. Where the run
    /// does not divide evenly, the LAST slice reaches back, so that it is still a full list
    /// and not a row of six songs. A run of 130 gives 0..<50, 50..<100 and 80..<130. Nothing
    /// is invented and nothing is dropped. The only cost is that the last list shares some
    /// songs with the one before it.
    ///
    /// A run no deeper than one list is the list itself, whatever the reading says. This
    /// happens for a cut from an older computer, where `shows` is 0, and for a small pool.
    ///
    /// - Parameter reading: how many times somebody has pressed refresh on this list. Any
    ///   number, including a negative one, lands somewhere in the run.
    public static func window(_ ids: [String], shows: Int, reading: Int) -> [String] {
        guard shows > 0, ids.count > shows else { return ids }

        let slices = (ids.count + shows - 1) / shows
        let which = ((reading % slices) + slices) % slices
        let start = min(which * shows, ids.count - shows)

        return Array(ids[start ..< start + shows])
    }

    /// One cut as playlist sets, resolved against a shelf's listing.
    ///
    /// This is a pure function of its two inputs, like ``PlaylistSet/resolve(_:against:shelf:)``,
    /// and for the same reason. A screen can ask what a cut looks like against a library
    /// without fetching either of them again.
    ///
    /// - Parameters:
    ///   - cut: what the computer last sent. An empty cut is a normal answer and gives no
    ///     rows. A collection whose computer has not run since this version shipped has
    ///     nothing to show, and an empty folder is a heading with nothing under it.
    ///   - tracks: the shelf's listing. A list that names records this phone cannot see is
    ///     kept and counted, not dropped. A stored playlist is handled the same way. On a
    ///     borrowed shelf only what the owner put in the cloud resolves. A list cut down to
    ///     that would be cut down to one connection.
    ///   - shelf: whose lists these are, and whose listing they are resolved against. **One
    ///     answer for both.** A borrowed cut names that owner's tracks. Looking them up in
    ///     the reader's own library would report every one as missing.
    ///   - readings: how many times refresh has been pressed on each list, by
    ///     ``CloudMoodList/id``. A list nobody has pressed is at zero, which is the first
    ///     slice of the run. That is the best slice, and it is what the computer shows.
    public static func sets(
        _ cut: CloudMoodLists, against tracks: [CloudTrack], shelf: CloudShelf,
        readings: [String: Int] = [:]
    ) -> [PlaylistSet] {
        guard !cut.lists.isEmpty else { return [] }

        var byId: [String: CloudTrack] = [:]
        byId.reserveCapacity(tracks.count)
        for track in tracks { byId[track.rpmId] = track }

        // Owner-only lists from somebody else's shelf are left out. They are cut from that
        // person's listening, and the computer sends them only to its owner's phone. See
        // ``ownerOnly``.
        let drawn = cut.lists.filter {
            !$0.trackIds.isEmpty && (shelf.isOwn || !ownerOnly.contains($0.kind))
        }

        // An empty list is not a row. The computer does not send one. A list that arrives
        // from a build that did would promise music and open on nothing.
        let sets = drawn.map { list -> PlaylistSet in
            // The slice this phone is showing, not the whole run the computer sent.
            let showing = window(list.trackIds, shows: list.shows,
                                 reading: readings[list.id] ?? 0)
            let found = showing.compactMap { byId[$0] }

            return PlaylistSet(
                id: mark + list.id,
                name: name(list),
                tracks: found,
                missing: showing.count - found.count,
                folder: placed(list, in: drawn),
                // Nothing is ever written against it, so there is no copy to name.
                stamp: 0,
                shelf: shelf,
                origin: .generated,
                // The colours of the frame on the cover come from this. It is carried here,
                // not derived. See `GeneratedListLook`.
                cut: GeneratedCut(kind: list.kind, genre: list.genre, decade: list.decade))
        }

        return sunk(sets)
    }

    /// The one departure from the arrangement the computer sent. A list whose name is also
    /// a folder in the same place moves INTO that folder, and sorts to the top of it. See
    /// ``PlaylistBrowse``.
    ///
    /// A mood is both a playlist and the place where its cuts hang. On the computer it is
    /// one row with a triangle beside it. This surface has no row that is both. Here a
    /// chevron means "step in". A row that also opened a list of songs would be saying two
    /// things. Nothing is invented and nothing is dropped. One row moves one level down,
    /// into the place already named after it.
    private static func sunk(_ sets: [PlaylistSet]) -> [PlaylistSet] {
        // Every place that any of these lists sits in, by the place that holds it. "Moods"
        // holds a folder called "Chill" as soon as one cut says it sits in Moods/Chill.
        var places: Set<[String]> = []
        for set in sets where set.folder.count > 0 { places.insert(set.folder) }

        return sets.map { set in
            let below = set.folder + [set.name]
            guard places.contains(where: { same($0, below) }) else { return set }

            return PlaylistSet(
                id: set.id, name: set.name, tracks: set.tracks, missing: set.missing,
                folder: below, stamp: set.stamp, shelf: set.shelf, origin: set.origin,
                cut: set.cut)
        }
    }

    private static func same(_ a: [String], _ b: [String]) -> Bool {
        a.count == b.count && !zip(a, b).contains {
            $0.lowercased(with: .current) != $1.lowercased(with: .current)
        }
    }

    // ── what one is called ──

    /// The name on the row.
    ///
    /// **The computer's name wherever it sent one**, because the words are its own. This
    /// is a table of a hundred and thirty-six titles, in English in every locale by design.
    /// A second copy here would drift, until the same list read as two different things on
    /// the two screens.
    ///
    /// **Except a whole mood, which reads in the phone's language.** "Chill" is one word that
    /// this app has in five locales. The name that travels is in whatever language the
    /// computer that sent it was set to. A French desktop and an English phone would put
    /// "Détente" at the top of an English shelf, and the folder it opens would disagree with
    /// it. The genre titles under a mood are not translated anywhere, so the computer alone
    /// gives them.
    ///
    /// The remaining fallbacks are for a cut sent by an older build. They are the desktop's
    /// own names, not inventions. A decade is named by its number. A cut with no title is
    /// named by the genre it cuts. The place the list sits in has already said which mood it is.
    public static func name(_ list: CloudMoodList) -> String {
        if list.decade > 0 { return decadeName(list.decade) }

        let title = list.title?.trimmingCharacters(in: .whitespacesAndNewlines)

        if list.genre == nil {
            // A mood this build does not know. The computer is ahead of it. Such a mood is
            // called what the computer called it, and failing that by its own spelling,
            // because a list with an unfamiliar name still plays.
            return moodName(list.kind) ?? title.flatMap { $0.isEmpty ? nil : $0 } ?? list.kind
        }

        if let title, !title.isEmpty { return title }
        return list.genre.flatMap { $0.isEmpty ? nil : $0 } ?? moodName(list.kind) ?? list.kind
    }

    /// A decade by its number. This is not a resource. "1970s" is a number with a letter
    /// after it, the same in every locale this app supports.
    public static func decadeName(_ decade: Int) -> String { "\(decade)s" }

    /// The kinds that the computer sends to its owner's phone and to nobody else. These are
    /// the desktop's `SmartPlaylists.OwnerOnly`: Your mix and the listening lists. They are
    /// cut from the owner's listening. The API takes them out of a borrowed cut as well.
    public static let ownerOnly: Set<String> = [
        "RightNow", "OnRepeat", "FavoriteTracks", "FirstListens", "Rediscover",
        "LovedAndForgotten", "LateNight",
    ]

    /// The name this app gives to one of the moods or to "Your mix", or nil for a kind it
    /// has no name for.
    ///
    /// The whole-shelf moods are shown in the app's language. They are the one part of a
    /// generated list's name that is not the computer's to give. A listener who reads their
    /// phone in French should not see the language that their desktop happens to use. The
    /// genre titles under them are not translated anywhere. See ``name``.
    public static func moodName(_ kind: String) -> String? {
        switch kind {
        case "Calm": return Loc.get("Playlists_Calm")
        case "Energetic": return Loc.get("Playlists_Energetic")
        case "Danceable": return Loc.get("Playlists_Danceable")
        case "Focus": return Loc.get("Playlists_Focus")
        case "Sleep": return Loc.get("Playlists_Sleep")
        case "Classical": return Loc.get("Playlists_Classical")
        case "RightNow": return Loc.get("Playlists_RightNow")
        default: return nil
        }
    }

    // ── where one sits ──

    /// The folder chain that a list hangs under. This follows the desktop's tree.
    ///
    /// - A decade sits in Decades.
    /// - A mood with no cuts under it sits in Moods, as a plain row.
    /// - A mood WITH cuts sits in a place of its own, `Moods/<mood>`. **The mood's own list
    ///   sits there too.** So its name is the first row in there, and the cuts follow it.
    ///   The alternative was one row that both played and stepped in. A row that leads to
    ///   two places cannot say which one it opens.
    ///
    /// - Parameter siblings: the rest of the cut, used for the fallback. Which moods have
    ///   cuts under them is the collection's answer, and it changes as the collection
    ///   changes. So a mood with none must not become a folder that holds one thing.
    private static func placed(_ list: CloudMoodList, in siblings: [CloudMoodList]) -> [String] {
        // What the computer said. Blank steps are removed, because a blank step is a folder
        // with no name, and nothing can be put in it.
        let sent = list.folder.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if !sent.isEmpty { return sent }

        // Nothing was sent, so this is an older build. The list is placed the way this app
        // files its own, which is the shape the computer would have sent if it could.
        if list.decade > 0 { return [Loc.get("Playlists_DecadesFolder")] }

        let moods = Loc.get("Playlists_MoodsFolder")
        guard list.genre != nil,
              let pooled = siblings.first(where: {
                  $0.kind == list.kind && $0.genre == nil && $0.decade == 0
              })
        else { return [moods] }

        return [moods, name(pooled)]
    }

    /// Whether a set is a mood's own pooled list. That is the whole list, shown above the
    /// cuts of it, rather than one of those cuts.
    ///
    /// This is read from the row's own shape and not stored. A pooled list is the one whose
    /// name is the name of the place it is in. That is what makes it the row that somebody
    /// opening the folder is looking for, and it is why it sorts to the top.
    static func isPooled(_ set: PlaylistSet) -> Bool {
        set.origin == .generated && set.folder.last.map {
            $0.lowercased(with: .current) == set.name.lowercased(with: .current)
        } ?? false
    }
}
