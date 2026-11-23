import Foundation
import Observation
import RPMKit
import RPMRadio

/// The lists the radio tab's home is built from, beside the tuner's search (``StationSearch``): the
/// local stations, the world's most played stations, the stations heard most, and the stations of
/// one genre when they are asked for. The Android apps' `RadioRepository` holds the same lists.
///
/// **Kept for 30 minutes.** Each list from the directory is read again only when it is older than
/// that, or after a failure, so the tab can be left and opened again without a new request. The
/// directory is run by volunteers.
///
/// The lists are held as the directory answered, one entry per station. The hidden stations and
/// the admin's edits are applied when a list is drawn (``StationRules/shown(_:)``), because the
/// rules can arrive after the answer.
@MainActor
@Observable
public final class RadioShelves {
    /// The local stations as last read.
    public enum Local: Equatable, Sendable {
        case notRead

        /// `country` is nil when the listener's country has no stations, or the phone names no
        /// country. The world's most played stations are read instead.
        case read([RadioStation], country: String?)

        /// Every mirror failed. The next visit reads again.
        case unavailable
    }

    public private(set) var local: Local = .notRead

    /// The world's most played stations. Empty until read. A failed read keeps what is held.
    public private(set) var popular: [RadioStation] = []

    /// The stations heard most on every device, the most heard first.
    public private(set) var heard: [RadioStation] = []

    @ObservationIgnored private let directory: RadioBrowserClient
    @ObservationIgnored private let listens: RadioListens
    @ObservationIgnored private let now: () -> ContinuousClock.Instant

    @ObservationIgnored private var localAt: ContinuousClock.Instant?
    @ObservationIgnored private var popularAt: ContinuousClock.Instant?
    @ObservationIgnored private var readingLocal = false
    @ObservationIgnored private var readingPopular = false

    /// The directory's answers for one genre, by genre, with when they were read. See
    /// ``stations(of:)``.
    @ObservationIgnored private var genreAnswers: [String: GenreAnswer] = [:]

    private struct GenreAnswer {
        let at: ContinuousClock.Instant
        let stations: [RadioStation]
    }

    /// How long a list from the directory is kept.
    public static let fresh: Duration = .seconds(30 * 60)

    /// The desktop's `RadioEssentialCount`: twelve local stations. Four times as many are asked
    /// for, so that folding and hiding still leave enough.
    public static let localCount = 12

    /// The radio home shows twenty of the world's most played stations. Asked for four times over,
    /// as above.
    public static let popularCount = 20

    /// How many stations a genre's suggestions are chosen from.
    public static let genreCount = 40

    public init(directory: RadioBrowserClient, listens: RadioListens) {
        self.directory = directory
        self.listens = listens
        self.now = { ContinuousClock.now }
    }

    /// Reads again what is out of date: the local and the world's stations after 30 minutes or a
    /// failure, and the stations heard most every time. Called each time the radio home is shown.
    /// The reads run beside one another, so the local stations do not wait for the world's.
    public func refresh() {
        Task { heard = await listens.top(RadioHomePicks.tasteFrom).map(\.station) }
        Task { await readLocal() }
        Task { await readPopular() }
    }

    private func readLocal() async {
        if case .read = local, let localAt, localAt.duration(to: now()) < Self.fresh { return }
        guard !readingLocal else { return }
        readingLocal = true
        defer { readingLocal = false }

        let code = Self.listenerCountry
        let ask = Self.localCount * 4
        do {
            var found = try await directory.search(RadioQuery(countryCode: code, limit: ask))
            var country = code
            if found.isEmpty, code != nil {
                found = try await directory.search(RadioQuery(limit: ask))
                country = nil
            }
            local = .read(RadioResults.onePerStation(found), country: country)
            localAt = now()
        } catch {
            // What was read before stays: a list of stations is better than a message.
            if case .read = local { return }
            local = .unavailable
        }
    }

    private func readPopular() async {
        if !popular.isEmpty, let popularAt, popularAt.duration(to: now()) < Self.fresh { return }
        guard !readingPopular else { return }
        readingPopular = true
        defer { readingPopular = false }

        do {
            let found = try await directory.search(RadioQuery(limit: Self.popularCount * 4))
            popular = RadioResults.onePerStation(found)
            popularAt = now()
        } catch {
            // What is held stays, and the next visit asks again.
        }
    }

    /// The world's most played stations of `genre` (a name from ``RadioGenres/all``), one entry per
    /// station, before the rules are applied. Kept for 30 minutes. Empty for a name that is not a
    /// genre, or when the directory does not answer.
    ///
    /// The directory is asked for the genre's term, and the answer is read through the genre's
    /// sieve, as the tuner does: the term "reggae" also finds reggaeton stations, and the sieve
    /// removes them (``StationSieve``).
    public func stations(of genre: String) async -> [RadioStation] {
        guard let term = RadioGenres.term(genre) else { return [] }
        let asked = now()
        if let held = genreAnswers[genre], held.at.duration(to: asked) < Self.fresh {
            return held.stations
        }
        do {
            let query = RadioQuery(tag: StationTag.holding(term), limit: Self.genreCount)
            let found = try await directory.search(query)
            let stations = StationSieve(genre: genre).through(RadioResults.onePerStation(found))
            genreAnswers[genre] = GenreAnswer(at: asked, stations: stations)
            return stations
        } catch {
            return []
        }
    }

    /// The phone's country as a two-letter code, taken from its region setting. Nil when the
    /// region names no country.
    public static var listenerCountry: String? {
        guard let code = Locale.current.region?.identifier.uppercased(),
              code.count == 2, code.allSatisfy(\.isLetter), code != "ZZ" else { return nil }
        return code
    }
}
