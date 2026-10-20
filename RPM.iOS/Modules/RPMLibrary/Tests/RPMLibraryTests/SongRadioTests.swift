import Testing
import Foundation
@testable import RPMLibrary
import RPMKit

/// What a song radio picks next, as the desktop's SongRadioTests and the Android app's
/// SongRadioTest check it, with what the phone has to go on.
struct SongRadioTests {
    /// A fixed random source, so a test gives one answer.
    private struct Seeded: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// A song with its own record and its own act unless told otherwise, so spacing stays out
    /// of tests not about it.
    private func song(_ id: String, year: Int = 1975, genre: String? = "Rock", styles: Set<String> = [],
                      moods: Set<String> = [], artist: String? = nil, record: String? = nil,
                      plays: Int = 0, offered: Bool = true) -> RadioSong {
        let act = artist ?? "act \(id)"
        return RadioSong(id: id, record: record ?? id, artist: act, song: "\(act)\n\(id)", year: year,
                         genre: genre, styles: styles, moods: moods, offered: offered, plays: plays)
    }

    private func pick(_ crate: RadioCrate, _ seed: String, _ count: Int, history: [String] = [],
                      origin: String? = nil, inQueue: Set<String> = [], random: UInt64 = 7) -> [String] {
        var rng = Seeded(state: random)
        return SongRadio.pick(crate, seed: seed, origin: origin ?? seed, inQueue: inQueue,
                              history: history, count: count, using: &rng)
    }

    // ── what is close ──

    @Test func aSongOfTheSameStyleComesBeforeAnUnfiledOneAndThatBeforeAnotherStyle() {
        let seed = song("seed", genre: "Electronic / Dance", styles: ["Trip Hop"])
        let same = SongRadio.apart(song("same", genre: "Electronic / Dance", styles: ["Trip Hop"]), seed)
        let unfiled = SongRadio.apart(song("unfiled", genre: "Electronic / Dance"), seed)
        let electro = SongRadio.apart(song("electro", genre: "Electronic / Dance", styles: ["Electro"]), seed)
        #expect(same < unfiled)
        #expect(unfiled < electro)
    }

    @Test func kinStylesAreCloserThanStylesWithNothingInCommon() {
        let lofi = song("lofi", genre: "Electronic / Dance", styles: ["Lo-fi Beats"])
        #expect(SongRadio.genreApart(song("d", genre: "Electronic / Dance", styles: ["Downtempo"]), lofi) == SongRadio.kinStyle)
        #expect(SongRadio.genreApart(song("e", genre: "Electronic / Dance", styles: ["Electro"]), lofi) == SongRadio.otherStyle)
    }

    @Test func twoSongsInOneMoodAreCloserThanTwoInDifferentMoods() {
        let seed = song("seed", moods: ["Calm"])
        #expect(SongRadio.moodApart(song("calm", moods: ["Calm"]), seed)
                < SongRadio.moodApart(song("none"), song("other")))
        #expect(SongRadio.moodApart(song("none"), song("other"))
                < SongRadio.moodApart(song("energetic", moods: ["Energetic"]), seed))
    }

    @Test func betweenTwoClassicalRecordsTheRecordingYearIsNotAnEra() {
        let mozart = song("mozart", year: 1987, genre: "Classical")
        #expect(SongRadio.eraApart(song("bach", year: 2000, genre: "Classical"), mozart) == 0)
        #expect(SongRadio.eraApart(song("undated", year: 0), mozart) == SongRadio.unknown)
    }

    @Test func everyStyleInAFamilyIsAStyleRpmKnows() {
        let known = Set(SubgenreTable.styles.map(\.name))
        for style in SongRadio.styleFamilies.flatMap({ $0 }) { #expect(known.contains(style), "\(style)") }
    }

    // ── picking ──

    @Test func aRadioOnTripHopDoesNotPickElectroWhileTripHopIsLeft() {
        let chill = (0..<(SongRadio.shortlist + 3)).map { song("chill\($0)", genre: "Electronic / Dance", styles: ["Trip Hop"]) }
        let club = (0..<SongRadio.shortlist).map { song("club\($0)", genre: "Electronic / Dance", styles: ["Electro"]) }
        let crate = RadioCrate([song("seed", genre: "Electronic / Dance", styles: ["Trip Hop"])] + chill + club)
        for r in 0..<20 {
            #expect(pick(crate, "seed", 3, random: UInt64(r)).allSatisfy { $0.hasPrefix("chill") })
        }
    }

    @Test func aClassicalRadioKeepsToClassicalMusic() {
        let classical = (0..<(SongRadio.shortlist + 4)).map { song("classical\($0)", year: 1990 + $0, genre: "Classical") }
        let pop = (0..<SongRadio.shortlist).map { song("pop\($0)", year: 1987, genre: "Pop") }
        let crate = RadioCrate([song("seed", year: 1987, genre: "Classical")] + classical + pop)
        for r in 0..<20 {
            #expect(pick(crate, "seed", 4, random: UInt64(r)).allSatisfy { $0.hasPrefix("classical") })
        }
    }

    @Test func aSongInTheQueueOrAlreadyQueuedIsNotPicked() {
        let crate = RadioCrate([song("seed"), song("queued"), song("played"), song("fresh")])
        #expect(pick(crate, "seed", 3, history: ["played"], inQueue: ["seed", "queued"]) == ["fresh"])
    }

    @Test func anInterludeCanStartARadioButIsNeverPicked() {
        let crate = RadioCrate([song("interlude", offered: false), song("song"), song("other", offered: false)])
        #expect(pick(crate, "interlude", 5) == ["song"])
    }

    @Test func anActDoesNotComeBackUntilOthersHavePlayed() {
        let same = (0..<6).map { song("same\($0)", artist: "Band") }
        let others = (0..<6).map { song("other\($0)", year: 1980) }
        let crate = RadioCrate([song("seed", artist: "Band")] + same + others)
        #expect(pick(crate, "seed", SongRadio.artistGap).allSatisfy { $0.hasPrefix("other") })
    }

    @Test func spacingGivesWayWhenOneActIsAllThereIs() {
        let crate = RadioCrate((0..<5).map { song("s\($0)", artist: "Band", record: "album") })
        #expect(pick(crate, "s0", 4).count == 4)
    }

    // ── favourites ──

    /// Ten songs closest, then the favourite, then a crowd further off in era: enough that
    /// the favourite is within the fit without being in the closest shortlist.
    private func favouriteCrate() -> RadioCrate {
        RadioCrate([song("seed")] + (0..<10).map { song("near\($0)") }
                   + [song("favourite", year: 1977, plays: 50)]
                   + (0..<300).map { song("crowd\($0)", year: 1995) })
    }

    @Test func everyFifthSongIsAFavouriteThatFits() {
        let history = ["seed", "near0", "near1", "near2", "near3"]
        for r in 0..<10 {
            #expect(pick(favouriteCrate(), "near3", 1, history: history, origin: "seed", random: UInt64(r)) == ["favourite"])
        }
    }

    @Test func aFavouriteWaitsForItsTurn() {
        let picked = pick(favouriteCrate(), "near0", 4, history: ["seed", "near0"], origin: "seed", random: 1)
        #expect(!picked.prefix(3).contains("favourite"))
        #expect(picked.last == "favourite")
    }

    @Test func aFavouriteThatDoesNotFitIsNotPlayed() {
        let crate = RadioCrate([song("seed")] + (0..<40).map { song("close\($0)") }
                               + [song("favourite", year: 2020, genre: "Classical", plays: 50)])
        let history = ["seed", "close0", "close1", "close2", "close3"]
        for r in 0..<10 {
            #expect(!pick(crate, "close3", 6, history: history, origin: "seed", random: UInt64(r)).contains("favourite"))
        }
    }

    // ── what the crate reads ──

    @Test func stylesAreReadFromEveryEntryOfATag() {
        #expect(Genres.styles("classical, romantic classical, classical period") == ["Romantic Classical", "Classical Period"])
        #expect(Genres.styles("Rock").isEmpty)
    }

    @Test func theMoodsAreReadFromEveryWindowOfThePlainMoods() {
        let cut = CloudMoodLists(recipe: 0, computedAt: 0, lists: [
            CloudMoodList(kind: "Calm", trackIds: ["a", "b", "c"], shows: 1),
            CloudMoodList(kind: "Energetic", decade: 1980, trackIds: ["e"]),
            CloudMoodList(kind: "RightNow", trackIds: ["f"]),
        ])
        let moods = SongRadio.moods(in: cut)
        #expect(moods["c"] == ["Calm"])
        #expect(moods["e"] == nil)
        #expect(moods["f"] == nil)
    }

    @Test func anEditionNoteDoesNotMakeAnotherSong() {
        let a = CloudTrack(rpmId: "a", title: "Song", artist: "Band")
        let b = CloudTrack(rpmId: "b", title: "Song (2011 Remaster)", artist: "Band")
        let c = CloudTrack(rpmId: "c", title: "Song (Part 2)", artist: "Band")
        #expect(RadioCrate.songOf(a) == RadioCrate.songOf(b))
        #expect(RadioCrate.songOf(a) != RadioCrate.songOf(c))
    }

    // ── home ──

    @Test func theSecondRadioIsOnTheMostPlayedSongByAnotherAct() {
        #expect(QuickPicks.radioSeeds([("s1", "Sting"), ("s2", "sting"), ("s3", "Björk"), ("s4", "Prince")]) == ["s1", "s3"])
        #expect(QuickPicks.radioSeeds([("s1", "Sting"), ("s2", "Sting")]) == ["s1"])
    }
}
