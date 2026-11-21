import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// The desktop's `MoodClockTests`.
struct MoodClockTests {
    @Test func eachHourAsksForItsOwnMood() {
        let want: [Int: Mood] = [
            0: .sleep, 3: .sleep, 4: .sleep,
            5: .calm, 8: .calm, 9: .calm,
            10: .focus, 16: .focus,
            17: .energetic, 19: .energetic,
            20: .danceable, 21: .danceable,
            22: .sleep, 23: .sleep,
        ]
        for (hour, mood) in want {
            #expect(MoodClock.best(hour) == mood, "hour \(hour)")
        }
    }

    @Test func nightIntoMorningIsCalm() {
        for hour in 5...9 { #expect(MoodClock.best(hour) == .calm) }
    }

    @Test func theNightRunsOnSleep() {
        for hour in [22, 23, 0, 1, 2, 3, 4] { #expect(MoodClock.best(hour) == .sleep) }
    }

    /// A band that named only one mood would give nothing on a collection that cannot fill it.
    @Test func everyBandNamesEveryMood() {
        let moods: Set<Mood> = [.sleep, .calm, .focus, .energetic, .danceable]
        for hour in 0..<24 {
            let order = MoodClock.order(hour)
            #expect(order.count == moods.count)
            #expect(Set(order) == moods)
        }
    }

    @Test func anHourOffTheClockIsWrappedRatherThanRefused() {
        #expect(MoodClock.best(25) == MoodClock.best(1))
        #expect(MoodClock.best(-1) == MoodClock.best(23))
        #expect(MoodClock.best(24) == MoodClock.best(0))
    }
}

/// The desktop's `ListeningProfileTests`, where the day is cut.
struct DayPartsTests {
    @Test func theHourLandsInThePartOfTheDayItBelongsTo() {
        let want: [Int: DayPart] = [
            23: .night, 0: .night, 4: .night,
            5: .morning, 11: .morning,
            12: .afternoon, 17: .afternoon,
            18: .evening, 22: .evening,
        ]
        for (hour, part) in want {
            #expect(DayParts.of(hour) == part, "hour \(hour)")
        }
    }

    @Test func anHourThatIsNotAnHourIsRefused() {
        #expect(DayParts.of(24) == nil)
        #expect(DayParts.of(-1) == nil)
    }

    @Test func theFourPartsCoverTheDayBetweenThem() {
        let seen = Set((0..<24).compactMap(DayParts.of))
        #expect(seen == Set(DayParts.acrossTheDay))
        #expect(seen.count == 4)
    }
}

/// The desktop's `MoodPickTests`, with the lists as this app holds them.
struct MoodPickTests {
    private let tracks = (1...12).map { CloudTrack(rpmId: "t\($0)", title: "t\($0)") }

    /// A generated list of `kind`, cut to `genre` where one is given, of `size` songs.
    private func list(_ kind: String, _ genre: String? = nil, decade: Int = 0,
                      size: Int = 12) -> PlaylistSet {
        PlaylistSet(id: Self.id(kind, genre, decade: decade), name: Self.id(kind, genre, decade: decade),
                    tracks: Array(tracks.prefix(size)), missing: 0, folder: [], stamp: 0,
                    shelf: .own, origin: .generated,
                    cut: GeneratedCut(kind: kind, genre: genre, decade: decade))
    }

    private static func id(_ kind: String, _ genre: String? = nil, decade: Int = 0) -> String {
        "mood/\(kind)|\(genre ?? "")|\(decade)"
    }

    private func offered(_ lists: PlaylistSet...) -> [PlaylistSet] { MoodPick.offered(lists) }

    /// A day that is not the one day in seven, so the usual answer applies.
    private let anOrdinaryDay = 3

    @Test func theCutTheyPlayMostAtThisHourIsWhatIsHeldUp() {
        let pick = MoodPick.pick([.calm], genres: ["Jazz", "Rock"],
                                 offered: offered(list("Calm", "Jazz"), list("Calm", "Rock"), list("Calm")),
                                 dayNumber: anOrdinaryDay)
        #expect(pick?.id == Self.id("Calm", "Jazz"))
    }

    /// They play jazz most, but there is no quiet jazz list: the next genre they play wins.
    @Test func aCutTheCollectionDoesNotOfferIsNotAList() {
        let pick = MoodPick.pick([.calm], genres: ["Jazz", "Rock"],
                                 offered: offered(list("Calm", "Rock"), list("Calm")),
                                 dayNumber: anOrdinaryDay)
        #expect(pick?.id == Self.id("Calm", "Rock"))
    }

    @Test func withNothingListenedToTheWholeCollectionStands() {
        let pick = MoodPick.pick([.calm], genres: [],
                                 offered: offered(list("Calm", "Jazz"), list("Calm")),
                                 dayNumber: anOrdinaryDay)
        #expect(pick?.id == Self.id("Calm"))
    }

    @Test func aMoodThisCollectionCannotFillIsSteppedPast() {
        let pick = MoodPick.pick([.sleep, .calm], genres: ["Jazz"],
                                 offered: offered(list("Calm", "Jazz")), dayNumber: anOrdinaryDay)
        #expect(pick?.id == Self.id("Calm", "Jazz"))
    }

    @Test func aCollectionOfferingNoneOfTheMoodsIsNoPick() {
        #expect(MoodPick.pick([.calm, .focus], genres: ["Jazz"], offered: [],
                              dayNumber: anOrdinaryDay) == nil)
    }

    @Test func oneDayInSevenHoldsUpAnotherOfTheGroup() {
        let lists = offered(list("Calm", "Jazz"), list("Calm", "Rock"), list("Calm"))
        let picks = (0..<70).map { day in
            MoodPick.pick([.calm], genres: ["Jazz", "Rock"], offered: lists, dayNumber: day)?.id
        }
        #expect(picks.filter { $0 == Self.id("Calm", "Jazz") }.count == 60)
        #expect(picks.filter { $0 != Self.id("Calm", "Jazz") }.count == 10)
    }

    @Test func theDaysThatDifferWalkTheGroupRatherThanRepeatingOneOtherList() {
        #expect(MoodPick.which(3, dayNumber: 1) == 0)
        #expect(MoodPick.which(3, dayNumber: 0) == 1)
        #expect(MoodPick.which(3, dayNumber: 7) == 2)
        #expect(MoodPick.which(3, dayNumber: 14) == 1)
        #expect(MoodPick.which(3, dayNumber: 21) == 2)
    }

    @Test func aGroupOfOneHasNowhereToStep() {
        for day in 0..<21 { #expect(MoodPick.which(1, dayNumber: day) == 0) }
    }

    @Test func aDayNumberBelowNoughtStillStepsForwards() {
        #expect((0...2).contains(MoodPick.which(3, dayNumber: -7)))
        #expect((0...2).contains(MoodPick.which(3, dayNumber: -14)))
    }

    @Test func theGroupIsTheCutsInOrderOfPlaysThenTheWholeCollection() {
        let group = MoodPick.group(.calm, genres: ["Rock", "Pop", "Jazz"],
                                   offered: offered(list("Calm"), list("Calm", "Jazz"),
                                                    list("Calm", "Rock"), list("Focus", "Pop")))
        #expect(group.map(\.id) == [Self.id("Calm", "Rock"), Self.id("Calm", "Jazz"), Self.id("Calm")])
    }

    /// Ten songs for a mood over the whole collection, six for a cut, as the desktop's floors.
    @Test func aListTooShortToShowIsNotOffered() {
        #expect(offered(list("Calm", size: 9)).isEmpty)
        #expect(offered(list("Calm", size: 6), list("Calm", "Jazz", size: 6)).map(\.id)
                == [Self.id("Calm", "Jazz")])
    }

    @Test func decadesAndOtherKindsAreNotOffered() {
        #expect(offered(list("Calm", decade: 1990), list("RightNow"), list("Classical")).isEmpty)
    }

    /// A playlist somebody made is never a mood list, whatever it is called.
    @Test func aStoredPlaylistIsNotOffered() {
        let stored = PlaylistSet(id: "x", name: "Calm", tracks: tracks, missing: 0, folder: [],
                                 stamp: 0, shelf: .own, origin: .stored)
        #expect(MoodPick.offered([stored]).isEmpty)
    }

    /// The Made for you card of a mood opens the cut played at this hour, and not the list the
    /// banner holds up where the group has another.
    @Test func aMoodCardOpensTheCutPlayedNowButNotTheBannersList() {
        let lists = offered(list("Calm"), list("Calm", "Jazz"), list("Calm", "Rock"))
        let whole = list("Calm")
        #expect(MoodPick.cut(whole, genres: ["Jazz", "Rock"], offered: lists, taken: nil).id
                == Self.id("Calm", "Jazz"))
        #expect(MoodPick.cut(whole, genres: ["Jazz", "Rock"], offered: lists,
                             taken: list("Calm", "Jazz")).id == Self.id("Calm", "Rock"))
        // Sleep is not cut to genres, so its card keeps its own list.
        let sleep = list("Sleep")
        #expect(MoodPick.cut(sleep, genres: ["Jazz"], offered: lists, taken: nil).id == sleep.id)
    }
}

/// What this device plays at each part of the day.
struct DayPartPlaysTests {
    private func folder() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("day-parts-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The desktop's `What_gets_played_at_night_is_not_what_gets_played_in_the_morning`.
    @Test func whatGetsPlayedAtNightIsNotWhatGetsPlayedInTheMorning() async {
        let log = DayPartPlays(file: nil)
        for _ in 0..<6 { await log.count(userId: "me", genre: "Jazz", part: .night) }
        for _ in 0..<4 { await log.count(userId: "me", genre: "Rock", part: .morning) }
        #expect(await log.genresAt(userId: "me", part: .night) == ["Jazz"])
        #expect(await log.genresAt(userId: "me", part: .morning) == ["Rock"])
        #expect(await log.genresAt(userId: "me", part: .afternoon).isEmpty)
    }

    @Test func mostPlayedFirstAndTheNameBreaksATie() {
        #expect(DayPartPlays.ranked(["Pop": 2, "Jazz": 2, "Rock": 5, "Folk": 0]) == ["Rock", "Jazz", "Pop"])
    }

    @Test func theCountsAreKeptAcrossARestart() async {
        let file = folder().appendingPathComponent("day-part-plays.json")
        let log = DayPartPlays(file: file)
        for _ in 0..<3 { await log.count(userId: "me", genre: "Jazz", part: .evening) }
        await log.count(userId: "me", genre: "Soul", part: .evening)
        #expect(await DayPartPlays(file: file).genresAt(userId: "me", part: .evening) == ["Jazz", "Soul"])
    }

    @Test func anotherAccountStartsTheCountsOver() async {
        let log = DayPartPlays(file: nil)
        await log.count(userId: "me", genre: "Jazz", part: .night)
        #expect(await log.genresAt(userId: "someone else", part: .night).isEmpty)
        await log.count(userId: "someone else", genre: "Rock", part: .night)
        #expect(await log.genresAt(userId: "someone else", part: .night) == ["Rock"])
        #expect(await log.genresAt(userId: "me", part: .night).isEmpty)
    }

    /// A file that does not parse is moved aside and kept, not written over.
    @Test func aFileThatCannotBeReadIsNotWrittenOver() async throws {
        let file = folder().appendingPathComponent("day-part-plays.json")
        try Data("not json".utf8).write(to: file)
        let log = DayPartPlays(file: file)
        await log.count(userId: "me", genre: "Jazz", part: .night)
        let aside = try String(contentsOf: file.appendingPathExtension("unreadable"), encoding: .utf8)
        #expect(aside == "not json")
    }

    /// 2026-01-01 23:30 UTC is half past midnight in Amsterdam.
    @Test func thePlayIsCountedAtTheHourOfThisDevicesClock() throws {
        let at: Int64 = 1_767_310_200
        #expect(DayPartPlays.hourOf(at, in: try #require(TimeZone(identifier: "UTC"))) == 23)
        #expect(DayPartPlays.hourOf(at, in: try #require(TimeZone(identifier: "Europe/Amsterdam"))) == 0)
    }
}
