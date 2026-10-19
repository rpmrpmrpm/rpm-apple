import Foundation

/// How the tuner asks, filters and sorts. Matches `RadioModel` in the desktop app, as its tuner
/// page uses it.
public struct TunerSettings: Equatable, Sendable {
    /// What is typed in the tuner's search field.
    public var text: String
    /// The country asked for, or nil for every country.
    public var country: String?
    public var sieve: StationSieve
    public var order: StationOrdering
    /// The saved stations alone, instead of the directory.
    public var savedOnly: Bool

    public init(text: String, country: String?, sieve: StationSieve, order: StationOrdering,
                savedOnly: Bool) {
        self.text = text; self.country = country; self.sieve = sieve; self.order = order
        self.savedOnly = savedOnly
    }

    /// The question for the directory, made from the three settings that it can answer. The
    /// format filter, the advertising filter and every sort order are applied afterwards, to the
    /// list that the directory returned.
    public var question: TunerQuestion {
        TunerQuestion(text: text.trimmingCharacters(in: .whitespaces),
                      tag: RadioGenres.term(sieve.genre), country: country)
    }
}

/// One question for the directory.
public struct TunerQuestion: Hashable, Sendable {
    public let text: String
    public let tag: String?
    public let country: String?
}

/// The directory's answer to the tuner's last question.
public enum TunerAnswer: Equatable, Sendable {
    case asking
    case listed([RadioStation])
    /// Every mirror failed. Saved stations still play.
    case directoryDown
}

/// The tuner's list as it is drawn, and the reason why it may be empty. Matches `Tuner.listOf` in
/// the Android TV app, which follows `RadioModel.Stations` in the desktop app.
public struct TunerList: Equatable, Sendable {
    public enum Empty: Sendable { case noResults, noFavorites, noFilterMatch }

    public let stations: [RadioStation]
    public let empty: Empty?
    public let asking: Bool
    public let directoryDown: Bool

    /// Builds the list from the directory's stations or from the saved ones. Stations that rpm
    /// hides are removed, and the admin's edits are applied. The list is then filtered, put in the
    /// chosen order, and given full names where two names would look the same.
    public static func of(_ settings: TunerSettings, _ answer: TunerAnswer, saved: [RadioStation],
                          rules: StationRules) -> TunerList {
        let listed: [RadioStation]
        switch (settings.savedOnly, answer) {
        case (true, _): listed = saved
        case (false, .listed(let found)): listed = found
        default: listed = []
        }
        let shown = listed.filter { !rules.hides($0) }.map(rules.edited)
        let kept = settings.sieve.through(shown)
        let stations = RadioNames.distinguish(StationSort.by(settings.order, kept))

        let empty: Empty?
        if !stations.isEmpty {
            empty = nil
        } else if settings.savedOnly, saved.isEmpty {
            empty = .noFavorites
        } else if !shown.isEmpty {
            empty = .noFilterMatch
        } else if settings.savedOnly {
            empty = .noResults
        } else if case .listed = answer {
            empty = .noResults
        } else {
            empty = nil
        }

        return TunerList(stations: stations, empty: empty,
                         asking: !settings.savedOnly && answer == .asking,
                         directoryDown: answer == .directoryDown)
    }
}
