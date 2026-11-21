import Foundation
import RPMKit

/// The moods the computer cuts lists for, spelled as the desktop's `SmartPlaylistKind` spells them
/// and as a generated list carries them (``GeneratedCut/kind``).
public enum Mood: String, CaseIterable, Sendable {
    case calm = "Calm"
    case energetic = "Energetic"
    case danceable = "Danceable"
    case focus = "Focus"
    case sleep = "Sleep"
    case melancholy = "Melancholy"
    case happy = "Happy"
    case angry = "Angry"
    case romantic = "Romantic"
    case zen = "Zen"
    case newYearsEve = "NewYearsEve"
    case christmas = "Christmas"
}

/// The four parts of a day that listening is counted in. The desktop's `DayPart`.
public enum DayPart: String, CaseIterable, Sendable, Codable {
    case night = "Night"
    case morning = "Morning"
    case afternoon = "Afternoon"
    case evening = "Evening"
}

/// Which part of the day an hour on the listener's own clock is in. The desktop's `DayParts`, with
/// the same edges: night from 23:00 to 04:59, morning to 11:59, afternoon to 17:59, evening to
/// 22:59. Night uses the same hours as the desktop's "Late night" list.
public enum DayParts {
    public static let nightFrom = 23
    public static let nightUntil = 5
    public static let morningUntil = 12
    public static let afternoonUntil = 18

    /// The four parts in the order a day goes through them, starting from the morning.
    public static let acrossTheDay: [DayPart] = [.morning, .afternoon, .evening, .night]

    /// The part `localHour` (0 to 23) is in. Nil for any other number, which the desktop refuses.
    public static func of(_ localHour: Int) -> DayPart? {
        guard (0...23).contains(localHour) else { return nil }

        // Night is checked first, with two comparisons: it is the one part that runs past midnight.
        if localHour >= nightFrom || localHour < nightUntil { return .night }
        if localHour < morningUntil { return .morning }
        if localHour < afternoonUntil { return .afternoon }
        return .evening
    }
}

/// Which mood the hour asks for. The desktop's `MoodClock`, with the same bands.
///
/// The home banner shows one generated list, and the clock decides which mood it is: something
/// calm in the morning, something to fall asleep to late at night.
///
/// Every band names all five moods, in its own order of preference. A collection only has the
/// mood lists its measured music can fill, so the caller takes the first mood in the band's order
/// that the collection has (``MoodPick``).
///
/// The hour is local time, read when home is worked out. A home that stays on screen past the
/// edge of a band keeps the card it was built with.
public enum MoodClock {
    // One list per band, so two hours in the same band give the same list.
    private static let night: [Mood] = [.sleep, .calm, .focus, .danceable, .energetic]
    private static let morning: [Mood] = [.calm, .focus, .sleep, .energetic, .danceable]
    private static let day: [Mood] = [.focus, .calm, .energetic, .danceable, .sleep]
    private static let evening: [Mood] = [.energetic, .danceable, .focus, .calm, .sleep]
    private static let dancing: [Mood] = [.danceable, .energetic, .focus, .calm, .sleep]

    /// The moods to offer at `hour`, best first. An hour outside 0 to 23 is wrapped into that
    /// range, so a caller that adds or takes away hours cannot pass one that is refused.
    public static func order(_ hour: Int) -> [Mood] {
        switch floorMod(hour, 24) {
        // From ten at night through the small hours: Sleep first.
        case 22...23, 0...4: return night
        // Early morning: Calm first.
        case 5...9: return morning
        // The working day: Focus first.
        case 10...16: return day
        // Evening: Energetic first.
        case 17...19: return evening
        // Between the evening and the night: Danceable first.
        default: return dancing
        }
    }

    /// The mood `hour` asks for before anything is known about what the collection can fill.
    public static func best(_ hour: Int) -> Mood { order(hour)[0] }
}

/// The moment home is worked out for: the hour and the day of the year on the local clock, and the
/// genres this device plays in that part of the day, most played first
/// (``DayPartPlays/genresAt(userId:part:)``).
///
/// Read once and kept: a home on screen does not change because the hour turns. The app reads it
/// again when it comes back to the front.
public struct HomeMoment: Sendable, Equatable {
    public let hour: Int
    public let dayOfYear: Int
    public let genres: [String]

    public init(hour: Int, dayOfYear: Int, genres: [String]) {
        self.hour = hour; self.dayOfYear = dayOfYear; self.genres = genres
    }

    /// The moment `date` is at on `calendar`'s clock, with these genres.
    public static func at(_ date: Date, calendar: Calendar, genres: [String]) -> HomeMoment {
        HomeMoment(hour: calendar.component(.hour, from: date),
                   dayOfYear: calendar.ordinality(of: .day, in: .year, for: date) ?? 1,
                   genres: genres)
    }
}

/// Which generated list the home banner shows: the mood the hour asks for (``MoodClock``), cut to
/// the kind of music this listener plays at that time of day. The desktop's `MoodPick`.
///
/// The clock is a general guess about people. What this device has played in this part of the day
/// is a fact about the listener (``DayPartPlays``). A listener who plays jazz late gets the quiet
/// jazz at midnight, and a listener who plays techno gets the quiet techno.
///
/// On one day in ``otherDayIn`` the pick steps down its own ranking, to another cut of the same
/// mood, and each such day steps one further. A banner that gives the same answer every day stops
/// being looked at. The day is chosen by the date only, so the list does not change while
/// somebody looks at it.
public enum MoodPick {
    /// How often the banner shows something other than the usual answer: one day in seven.
    public static let otherDayIn = 7

    /// The fewest songs a mood list over the whole collection may hold and still be shown. The
    /// desktop's `SmartPlaylists.LeastForWholeShelf`.
    public static let leastForWholeShelf = 10

    /// The same for a mood cut to one genre: a smaller question, so a smaller floor
    /// (`LeastForNarrowedRow`).
    public static let leastForGenreCut = 6

    /// The moods the computer also cuts to each genre: the desktop's
    /// `SmartPlaylists.BrokenOutByGenre`. Sleep is cut over the whole collection only. Zen, New
    /// Year's Eve and Merry Christmas have no genre reading.
    public static let brokenOutByGenre: Set<Mood> = [.calm, .energetic, .danceable, .focus,
                                                     .melancholy, .happy, .angry, .romantic]

    /// The list to show, or nil when `offered` holds none of the `moods`.
    ///
    /// - Parameter moods: the moods that suit the hour, best first: ``MoodClock/order(_:)``.
    /// - Parameter genres: what this listener plays in this part of the day, most played first.
    ///   Empty is normal: with no listening yet, the whole collection's list of the mood is shown.
    /// - Parameter offered: the mood lists this collection has: ``offered(_:)``.
    /// - Parameter dayNumber: a number that goes up by one each day (the day of the year). It
    ///   decides which days are the one in seven, and which other list is shown on them.
    public static func pick(_ moods: [Mood], genres: [String], offered: [PlaylistSet],
                            dayNumber: Int) -> PlaylistSet? {
        for mood in moods {
            let group = group(mood, genres: genres, offered: offered)
            if group.isEmpty { continue }
            return group[which(group.count, dayNumber: dayNumber)]
        }
        return nil
    }

    /// The list the banner shows at `moment`: the desktop's `HomeView.ReadBannerList`. Nil when
    /// the collection has none of the clock's moods.
    public static func bannerList(_ lists: [PlaylistSet], moment: HomeMoment) -> PlaylistSet? {
        pick(MoodClock.order(moment.hour), genres: moment.genres, offered: offered(lists),
             dayNumber: moment.dayOfYear)
    }

    /// Every list `offered` holds for `mood`, best first: the cuts of the mood to the genres this
    /// listener plays, in order of plays, then the whole collection's list of the mood.
    ///
    /// The whole collection's list is last: a listener who plays jazz at night is better served by
    /// the quiet jazz than by every quiet record. It stays in the group, so a listener with no
    /// genres still gets a list, and the one day in seven has somewhere to step to when a mood
    /// has one cut.
    public static func group(_ mood: Mood, genres: [String], offered: [PlaylistSet]) -> [PlaylistSet] {
        let ofMood = offered.filter { $0.cut?.kind == mood.rawValue }
        var group: [PlaylistSet] = []
        for genre in genres where !genre.isEmpty {
            if let cut = ofMood.first(where: { !isWhole($0) && $0.cut?.genre == genre }) {
                group.append(cut)
            }
        }
        if let whole = ofMood.first(where: isWhole) { group.append(whole) }
        return group
    }

    /// Which of a group of `groupSize` to show on `dayNumber`: 0 on six days in seven. On the
    /// seventh it steps down the ranking, and on each such day after that one further, wrapping
    /// round. A group of one has nowhere to step.
    public static func which(_ groupSize: Int, dayNumber: Int) -> Int {
        guard groupSize > 1 else { return 0 }
        // Floored, so a day number below nought still steps forwards.
        guard floorMod(dayNumber, otherDayIn) == 0 else { return 0 }
        return 1 + floorMod(floorDiv(dayNumber, otherDayIn), groupSize - 1)
    }

    /// The list the card of `whole`'s mood on the Made for you row opens: the cut of the mood to
    /// the genre this listener plays most at this time of day, or the whole collection's list
    /// where no cut fits (``group(_:genres:offered:)``). The desktop's `HomeView.Cut`. Only the
    /// moods that are cut to genres (``brokenOutByGenre``). Any other list keeps `whole`.
    ///
    /// Never the list the banner shows (`taken`) where the group has another: the banner takes the
    /// same group's first on six days in seven, and the same list twice, one above the other,
    /// says nothing new. A group of one keeps its only list.
    public static func cut(_ whole: PlaylistSet, genres: [String], offered: [PlaylistSet],
                           taken: PlaylistSet?) -> PlaylistSet {
        guard let kind = whole.cut?.kind, let mood = Mood(rawValue: kind),
              brokenOutByGenre.contains(mood) else { return whole }

        let group = group(mood, genres: genres, offered: offered)
        guard let first = group.first else { return whole }
        if first.id != taken?.id { return first }
        return group.count > 1 ? group[1] : first
    }

    /// The mood lists among `lists` that a pick or a cut may take: the generated lists of a mood,
    /// over the whole collection or cut to a genre (never to a decade, which is not a mood), and
    /// long enough to show. The desktop's `OfferedGeneratedLists(SmartPlaylists.Moods,
    /// withDecades: false)` with its floor.
    public static func offered(_ lists: [PlaylistSet]) -> [PlaylistSet] {
        lists.filter { list in
            guard list.origin == .generated, let cut = list.cut, cut.decade == 0,
                  Mood(rawValue: cut.kind) != nil else { return false }
            return list.tracks.count >= (isWhole(list) ? leastForWholeShelf : leastForGenreCut)
        }
    }

    /// Whether a generated list is the whole collection's list of its mood, and not a cut of it.
    static func isWhole(_ list: PlaylistSet) -> Bool {
        guard let cut = list.cut else { return false }
        return (cut.genre ?? "").isEmpty && cut.decade == 0
    }
}

/// The remainder of `a` divided by `n`, always from 0 to `n` - 1, also for a negative `a`.
func floorMod(_ a: Int, _ n: Int) -> Int {
    let r = a % n
    return r < 0 ? r + n : r
}

/// `a` divided by `n`, rounded down, also for a negative `a`.
func floorDiv(_ a: Int, _ n: Int) -> Int {
    (a - floorMod(a, n)) / n
}
