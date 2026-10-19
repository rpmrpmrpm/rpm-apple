import Foundation
import RPMKit
import RPMRadio

/// The station directory as the radio screens read it: a search, its answer less the stations
/// hidden in the admin, and the countries to pick from.
@MainActor
@Observable
public final class StationSearch {
    public let directory: RadioBrowserClient

    /// Which stations rpm hides and the stamp a changed logo moves. Read by every station logo.
    public let radioState: RadioState

    /// What the directory answered, one row per station.
    private var found: [RadioStation] = []

    /// The stations to list, less any hidden in the admin and carrying the admin's edits. The rules
    /// are applied when this is read, not when `found` is stored, because the state usually arrives
    /// after the first search.
    public var stations: [RadioStation] {
        let rules = radioState.rules
        return found.filter { !rules.hides($0) }.map(rules.edited)
    }

    public private(set) var countries: [RadioFacet] = []
    public private(set) var standing: DirectoryStanding = .reading

    /// Which search is the current one. A person typing starts several searches at once, and an
    /// older answer that arrives last would replace what they asked for.
    private var searching = 0

    public init(directory: RadioBrowserClient, radioState: RadioState) {
        self.directory = directory
        self.radioState = radioState
    }

    public func search(_ asked: String, genre: String?, country: String?) async {
        searching += 1
        let mine = searching

        standing = .reading

        // At most once an hour.
        Task { await radioState.refresh() }

        // The genre goes to the directory as a tag that the station's tags hold. The answer is
        // then read through StationSieve. See RadioGenres.term.
        let query = RadioQuery(name: asked.isEmpty ? nil : asked,
                               tag: RadioGenres.term(genre).map(StationTag.holding),
                               countryCode: country)

        do {
            let answer = await withRetagged(try await directory.search(query), genre: genre, query: query)
            guard mine == searching else { return }

            // One row per station, not one per stream. See RadioResults.
            found = RadioResults.onePerStation(answer)
            standing = .showing
        } catch is CancellationError {
            // The user changed the search, so this answer is not wanted.
        } catch {
            guard mine == searching else { return }
            standing = .directoryDown
        }

        // Once: the countries, with the desktop's names and order, and the current list of
        // directory mirrors (not the list that ships with the app).
        if countries.isEmpty {
            countries = RadioCountries.forPicker((try? await directory.countries()) ?? [])
            await directory.refreshMirrors()
        }
    }

    /// `answer` with the stations the admin filed under `genre` added, where the question lets them
    /// through (``RadioResults/withRetagged(_:_:_:)``). The directory is asked by its own tags, so it
    /// never returns them. If they cannot be fetched, the answer is returned unchanged.
    public func withRetagged(_ answer: [RadioStation], genre: String?, query: RadioQuery) async -> [RadioStation] {
        let rules = radioState.rules
        guard let genre, case let uuids = rules.retagged(into: genre), !uuids.isEmpty,
              let fetched = try? await directory.byUuid(uuids) else { return answer }
        // The admin's edits are applied, so a searched text can match the admin's title.
        return RadioResults.withRetagged(answer, fetched.map(rules.edited), query)
    }

    /// Tells the directory a station was tuned. Its ranking is fed by these calls.
    public func reportTuned(_ station: RadioStation) {
        Task { await directory.reportPlayed(station.uuid) }
    }
}
