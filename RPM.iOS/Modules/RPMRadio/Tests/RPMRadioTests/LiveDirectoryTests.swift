import Testing
import Foundation
import RPMKit
@testable import RPMRadio

/// Tests that call the live Radio Browser directory.
///
/// These tests run only when `RPM_TEST_RADIO` is set. Without it, an ordinary `swift test`
/// stays offline and fast:
///
///     RPM_TEST_RADIO=1 swift test --filter LiveDirectory
///
/// **These tests are read-only.** They never call `reportPlayed`, because that would add a
/// play for a station nobody played to the directory's ranking.
///
/// Only these tests detect a change in the directory's field names. The decode tests use a
/// saved fixture, and Radio Browser is run by volunteers with no versioned API contract.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["RPM_TEST_RADIO"] != nil))
struct LiveDirectoryTests {
    /// Runs a whole search and checks the result. For example, "kiss fm" returns the Spanish
    /// Kiss FM several times, at 56k and at 128k. The folded list must show it once, at 128k.
    ///
    /// The directory changes often, so these tests check the shape of the result, not exact
    /// counts. The fold removes rows, and no returned row is a duplicate of another.
    @Test func aSearchIsFoldedToOneRowPerStation() async throws {
        let found = try await RadioBrowserClient(reach: NetworkReach())
            .search(RadioQuery(name: "kiss fm"))
        try #require(found.count > 20, "the directory answered with too little to judge")

        let picked = RadioResults.onePerStation(found)
        #expect(picked.count < found.count, "nothing was folded out of a search that has duplicates")

        var seen = Set<String>()
        for station in picked {
            let key = "\(NameMatch.squash(station.name))|\(station.countryCode ?? "")"
            #expect(seen.insert(key).inserted, "\(station.name) is listed twice")
        }

        // The kept stream has the highest bitrate among its reachable duplicates.
        for station in picked where station.bitrateKbps > 0 {
            let twins = found.filter {
                NameMatch.squash($0.name) == NameMatch.squash(station.name)
                    && $0.countryCode == station.countryCode && $0.reachable
            }
            #expect(station.bitrateKbps >= twins.map(\.bitrateKbps).max() ?? 0,
                    "\(station.name) kept \(station.bitrateKbps)k over a better twin")
        }
    }

    @Test func aSearchComesBackWithPlayableStations() async throws {
        let found = try await RadioBrowserClient(reach: NetworkReach()).search(RadioQuery(name: "jazz", limit: 20))

        #expect(!found.isEmpty, "the directory answered with nothing at all")

        for station in found {
            #expect(!station.uuid.isEmpty)
            #expect(!station.name.isEmpty)
            #expect(URL(string: station.streamUrl) != nil, "\(station.name) has no usable address")
        }
    }

    /// The fields a row prints. A field can be missing on one station, but not on all of the
    /// first 40 results.
    @Test func theRowsHaveSomethingToPrint() async throws {
        let found = try await RadioBrowserClient(reach: NetworkReach()).search(RadioQuery(limit: 40))

        #expect(found.contains { !$0.quality.isEmpty }, "not one station declared a codec")
        #expect(found.contains { $0.country?.isEmpty == false }, "not one station named a country")
        #expect(found.contains { !$0.genres.isEmpty }, "not one station carried a genre tag")
        #expect(found.contains { $0.favicon?.isEmpty == false }, "not one station published a logo")
    }

    @Test func theCountriesComeBackWithCodesToFilterOn() async throws {
        let countries = try await RadioBrowserClient(reach: NetworkReach()).countries()

        #expect(countries.count > 50)
        #expect(countries.allSatisfy { $0.code.count == 2 })
        #expect(countries.first!.stationCount >= countries.last!.stationCount,
                "the biggest is not first")
    }

    /// Most tags in the directory have only one station, so the tag list keeps only tags with at
    /// least 500 stations.
    @Test func theTagsAreCutToTheOnesWorthOffering() async throws {
        let tags = try await RadioBrowserClient(reach: NetworkReach()).tags(atLeast: 500)

        #expect(!tags.isEmpty)
        #expect(tags.allSatisfy { $0.stationCount >= 500 })
    }

    /// Runs a page of real station names through the cleaning rule. The test checks no single
    /// name, because the directory changes daily. It checks that no name is cleaned to nothing.
    @Test func noRealNameIsCleanedAwayToNothing() async throws {
        let found = try await RadioBrowserClient(reach: NetworkReach()).search(RadioQuery(limit: 100))

        for station in RadioNames.distinguish(found) {
            #expect(!station.display.isEmpty, "\(station.name) cleaned away to nothing")
            #expect(!station.sign.isEmpty, "\(station.name) signed as nothing")
            #expect(station.sign.count <= 4)
        }
    }
}
