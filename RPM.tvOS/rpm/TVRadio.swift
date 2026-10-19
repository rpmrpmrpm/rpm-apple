import Foundation
import RPMKit
import RPMRadio
import RPMSession

/// The radio data that the TV shows: the essential stations for the TV's country, the favourites,
/// the stations heard most, the station descriptions, and the tuner's questions and answers. Each
/// is kept here, so the user can leave the radio screen and open it again without a new request.
/// Matches `RadioRepository` and `Tuner` in the Android TV app.
@MainActor
@Observable
final class TVRadio {
    let search: StationSearch
    let saved = RadioFavorites()

    /// The saved stations of the shared collections that were opened in this session. They are
    /// read only. See ``SharedStations``.
    let shared = SharedStations()
    let blurbs: StationBlurbs
    private let listens: RadioListens

    /// The essential stations as last read.
    enum Essential: Equatable {
        case notRead
        /// `country` is nil when the TV's country has no stations. The world's most popular
        /// stations are used instead.
        case read([RadioStation], country: String?, at: Date)
        /// Every mirror failed. The next visit requests the stations again.
        case unavailable
    }

    private(set) var essential: Essential = .notRead

    /// The stations heard most on every device, the most heard first.
    private(set) var heard: [RadioStation] = []

    /// Matches `RadioEssentialCount` in the desktop app: twelve cards. Four times as many stations
    /// are requested, so that after folding and hiding there are still twelve.
    static let essentialCount = 12
    private static let essentialFor: TimeInterval = 30 * 60

    init(search: StationSearch, listens: RadioListens, reach: NetworkReach) {
        self.search = search
        self.listens = listens
        blurbs = StationBlurbs(reach: reach)
        tuner = TunerSettings(text: "", country: Self.listenerCountry, sieve: .off, order: .listed,
                              savedOnly: false)
    }

    var radioState: RadioState { search.radioState }

    /// The stations without the ones that rpm hides, with the admin's edits applied, and with full
    /// names where two names would be the same. This is applied when a row is drawn and never when
    /// an answer is stored, because the rules can arrive after the answer.
    func shown(_ stations: [RadioStation]) -> [RadioStation] {
        radioState.rules.shown(stations)
    }

    /// Reads again what is out of date: the essential stations after 30 minutes or after a failure,
    /// the hidden list once an hour (the rule of `RadioState`), and the stations heard most.
    func refresh() {
        Task { await radioState.refresh() }
        Task { heard = await listens.top(QuickPicksStations.count).map(\.station) }
        if case .read(_, _, let at) = essential, Date().timeIntervalSince(at) < Self.essentialFor { return }
        Task { await readEssential() }
    }

    private var readingEssential = false

    private func readEssential() async {
        guard !readingEssential else { return }
        readingEssential = true
        defer { readingEssential = false }

        let code = Self.listenerCountry
        let ask = Self.essentialCount * 4
        do {
            var found = try await search.directory.search(RadioQuery(countryCode: code, limit: ask))
            var country = code
            if found.isEmpty, code != nil {
                found = try await search.directory.search(RadioQuery(limit: ask))
                country = nil
            }
            essential = .read(RadioResults.onePerStation(found), country: country, at: Date())
        } catch {
            essential = .unavailable
        }
    }

    /// The country of the TV as a two-letter code, taken from its region setting.
    static var listenerCountry: String? {
        guard let code = Locale.current.region?.identifier.uppercased(),
              code.count == 2, code.allSatisfy(\.isLetter), code != "ZZ" else { return nil }
        return code
    }

    // MARK: The tuner

    /// How the tuner asks, filters and sorts. It is kept while the app runs, so the tuner opens as
    /// the user left it.
    var tuner: TunerSettings {
        didSet { if tuner.question != oldValue.question { ask(typed: tuner.text != oldValue.text) } }
    }

    private(set) var answer: TunerAnswer = .asking
    private(set) var countries: [RadioFacet] = []

    /// The station that was last tuned from the tuner. The play key tunes it again.
    var lastTuned: RadioStation?

    private var asking: Task<Void, Never>?
    private var kept: [TunerQuestion: (at: Date, stations: [RadioStation])] = [:]
    private var tunerStarted = false

    /// Starts asking the directory. Only the first call has an effect.
    func startTuner() {
        guard !tunerStarted else { return }
        tunerStarted = true
        ask(typed: false)
        Task {
            if countries.isEmpty {
                countries = RadioCountries.forPicker((try? await search.directory.countries()) ?? [])
            }
        }
    }

    /// Only one question runs at a time. A new question cancels the one before, so an older answer
    /// cannot replace a newer one. While the user types, the question waits 450 ms after the last
    /// key. Answers are kept for 30 minutes.
    private func ask(typed: Bool) {
        guard tunerStarted else { return }
        asking?.cancel()
        let question = tuner.question
        asking = Task {
            if typed {
                try? await Task.sleep(for: .milliseconds(450))
                if Task.isCancelled { return }
            }
            if let held = kept[question], Date().timeIntervalSince(held.at) < Self.essentialFor {
                answer = .listed(held.stations)
                return
            }
            answer = .asking
            do {
                let query = RadioQuery(name: question.text.isEmpty ? nil : question.text,
                                       tag: question.tag.map(StationTag.holding),
                                       countryCode: question.country, limit: 120)
                // Includes the stations that the admin filed under the genre. The directory never
                // returns these.
                let found = await search.withRetagged(try await search.directory.search(query),
                                                      genre: tuner.sieve.genre, query: query)
                if Task.isCancelled { return }
                let one = RadioResults.onePerStation(found)
                kept[question] = (Date(), one)
                answer = .listed(one)
            } catch {
                if Task.isCancelled { return }
                answer = .directoryDown
            }
        }
    }

    /// The tuner's list. `saved` is the list of saved stations that the heart key narrows the
    /// list to.
    func tunerList(saved: [RadioStation]) -> TunerList {
        TunerList.of(tuner, answer, saved: saved, rules: radioState.rules)
    }
}

/// How many of the most heard stations the banner and the quick selection use. Matches the
/// desktop app, which uses seven.
enum QuickPicksStations {
    static let count = 7
}
