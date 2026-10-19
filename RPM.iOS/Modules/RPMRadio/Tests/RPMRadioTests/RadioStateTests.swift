import Testing
import Foundation
import RPMKit
@testable import RPMRadio

/// How the phone uses the `radio/state` response. The desktop's `RadioState` does the same.
@MainActor
struct RadioStateTests {
    /// A fake record. The test sets its answers, and it records each request.
    final class Record: RadioRecord, @unchecked Sendable {
        private let lock = NSLock()
        private var _answers: [Result<RadioRepositoryClient.State, any Error>] = []
        private var _readings: [RadioRepositoryClient.Reading] = []
        private var _stamps: [String] = []

        func answer(_ result: Result<RadioRepositoryClient.State, any Error>) {
            lock.withLock { _answers.append(result) }
        }

        var readings: [RadioRepositoryClient.Reading] { lock.withLock { _readings } }
        var stamps: [String] { lock.withLock { _stamps } }

        func state(_ reading: RadioRepositoryClient.Reading) async throws -> RadioRepositoryClient.State {
            let next = lock.withLock { () -> Result<RadioRepositoryClient.State, any Error> in
                _readings.append(reading)
                return _answers.isEmpty ? .success(.init(logos: "", hidden: [])) : _answers.removeFirst()
            }
            return try next.get()
        }

        func logo(station uuid: String, stamp: String) async throws -> RadioRepositoryClient.Logo {
            lock.withLock { _stamps.append(stamp) }
            return .none
        }
    }

    /// A clock that the test controls.
    final class Clock: @unchecked Sendable {
        private let start = ContinuousClock.now
        var passed: Duration = .zero
        var now: ContinuousClock.Instant { start.advanced(by: passed) }
    }

    private let station = RadioStation(uuid: "ABC", name: "Radio One",
                                       streamUrl: "https://streams.example/one.mp3")

    @Test func nothingIsHiddenAndThereIsNoStampBeforeTheFirstAnswer() {
        let state = RadioState(record: Record())

        #expect(state.isHidden(station) == false)
        #expect(state.logoStamp.isEmpty)
    }

    @Test func anAnswerHidesItsStationsWhateverTheirCase() async {
        let record = Record()
        record.answer(.success(.init(logos: "20260928", hidden: ["ABC-def"])))
        let state = RadioState(record: record)

        await state.refresh()

        #expect(state.isHidden(RadioStation(uuid: "abc-DEF", name: "One", streamUrl: "https://a/1")))
        #expect(state.isHidden(RadioStation(uuid: "other", name: "Two", streamUrl: "https://a/2")) == false)
        #expect(state.logoStamp == "20260928")
    }

    /// A station is hidden only when every row merged into it is hidden, whichever uuid the kept row has.
    @Test func aStationIsHiddenWhenEveryRowItIsFiledAsIsHidden() async {
        let record = Record()
        record.answer(.success(.init(logos: "", hidden: ["npo-2", "npo-radio-2"])))
        let state = RadioState(record: record)
        var folded = RadioStation(uuid: "npo-2", name: "NPO 2", streamUrl: "https://a/npo2")
        folded.alsoFiledAs = ["NPO-RADIO-2"]

        await state.refresh()

        #expect(state.isHidden(folded))
    }

    /// Example: NPO Radio 1 has two hidden 32k AAC rows and one shown 192k MP3 row. The station
    /// stays in the list, as it does on the desktop.
    @Test func aStationWithOneRowStillShownIsListed() async {
        let record = Record()
        record.answer(.success(.init(logos: "", hidden: ["radio1-aac-a", "radio1-aac-b"])))
        let state = RadioState(record: record)

        var keptTheShownRow = RadioStation(uuid: "radio1-mp3", name: "NPO Radio 1",
                                           streamUrl: "http://icecast.omroep.nl/radio1-bb-mp3")
        keptTheShownRow.alsoFiledAs = ["radio1-aac-a", "radio1-aac-b"]

        var keptAHiddenRow = RadioStation(uuid: "radio1-aac-a", name: "NPO Radio 1",
                                          streamUrl: "http://icecast.omroep.nl/radio1-sb-aac")
        keptAHiddenRow.alsoFiledAs = ["radio1-mp3", "radio1-aac-b"]

        await state.refresh()

        #expect(state.isHidden(keptTheShownRow) == false)
        #expect(state.isHidden(keptAHiddenRow) == false)
    }

    /// The first request after launch goes past the local store, so a change made in the admin
    /// shows after a restart. Later requests read the stored copy.
    @Test func theFirstAskOfALaunchGoesPastTheStoreAndLaterOnesDoNot() async {
        let record = Record()
        let clock = Clock()
        let state = RadioState(record: record, now: { clock.now })

        await state.refresh()
        clock.passed = RadioState.fresh + .seconds(1)
        await state.refresh()

        #expect(record.readings == [.pastTheStore, .stored])
    }

    @Test func anAnswerUnderAnHourOldIsNotAskedAgain() async {
        let record = Record()
        let clock = Clock()
        let state = RadioState(record: record, now: { clock.now })

        await state.refresh()
        clock.passed = .seconds(3599)
        await state.refresh()

        #expect(record.readings.count == 1)
    }

    /// If the phone is offline, that is not an answer from the server, so the next screen that asks
    /// sends a new request.
    @Test func offlineIsNotAnAnswer() async {
        let record = Record()
        record.answer(.failure(RPMError.offline))
        let state = RadioState(record: record)

        await state.refresh()
        await state.refresh()

        #expect(record.readings == [.pastTheStore, .pastTheStore])
    }

    /// After a server error, the last known answer is kept, and the server is not asked again for
    /// an hour.
    @Test func aFailureKeepsTheLastAnswerAndWaitsTheHour() async {
        let record = Record()
        let clock = Clock()
        record.answer(.success(.init(logos: "one", hidden: ["abc"])))
        record.answer(.failure(RPMError.status(502)))
        let state = RadioState(record: record, now: { clock.now })

        await state.refresh()
        clock.passed = RadioState.fresh + .seconds(1)
        await state.refresh()
        await state.refresh()

        #expect(record.readings.count == 2)
        #expect(state.isHidden(RadioStation(uuid: "abc", name: "One", streamUrl: "https://a/1")))
        #expect(state.logoStamp == "one")
    }

    @Test func aLogoIsAskedForAtTheStampInHand() async throws {
        let record = Record()
        record.answer(.success(.init(logos: "stamp-2", hidden: [])))
        let state = RadioState(record: record)

        _ = try await state.logo(for: station)
        await state.refresh()
        _ = try await state.logo(for: station)

        #expect(record.stamps == ["", "stamp-2"])
    }
}
