import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// Home on the person's own shelf follows the time of day: the banner's list is the mood the hour
/// asks for, cut to what is played then, and the Made for you cards open the cuts played now. The
/// Android app's `HomeShelfTest` and the desktop's `HomeView` tests.
struct HomeMomentTests {
    private let tracks = (1...12).map { CloudTrack(rpmId: "t\($0)", title: "t\($0)") }

    private func shelf() -> [HomeAlbum] {
        (0..<30).map {
            HomeAlbum(key: "a\($0)", album: "a\($0)", artist: "Act \($0 % 9)", genres: ["Rock"],
                      year: 1980, addedAt: Int64($0), plays: 0, lastPlayedAt: 0)
        }
    }

    /// The generated lists of these (kind, genre) pairs, twelve songs each, named after their cut.
    private func lists(_ cuts: [(String, String?)]) -> [PlaylistSet] {
        cuts.map { kind, genre in
            let name = "\(kind)|\(genre ?? "")"
            return PlaylistSet(id: "mood/" + name, name: name, tracks: tracks, missing: 0,
                               folder: [], stamp: 0, shelf: .own, origin: .generated,
                               cut: GeneratedCut(kind: kind, genre: genre, decade: 0))
        }
    }

    private func build(_ sets: [PlaylistSet], _ moment: HomeMoment?) -> HomeScreen {
        HomeScreen.build(shelf: shelf(), songs: [], lists: sets.map(\.name), stations: [], draw: 1,
                         moment: moment, sets: sets)
    }

    private func bannerLists(_ screen: HomeScreen) -> [String] {
        screen.strip.filter { $0.kind == .madeForYou }.map(\.key)
    }

    @Test func theBannersListIsTheMoodTheHourAsksForCutToWhatIsPlayedThen() {
        let sets = lists([("RightNow", nil), ("Calm", nil), ("Calm", "Jazz"), ("Sleep", nil), ("Focus", nil)])
        // Late at night: Sleep. It has no cut, so the whole collection's Sleep list.
        #expect(bannerLists(build(sets, HomeMoment(hour: 23, dayOfYear: 3, genres: ["Jazz"]))) == ["Sleep|"])
        // Early morning: Calm, cut to the jazz played in the morning.
        #expect(bannerLists(build(sets, HomeMoment(hour: 8, dayOfYear: 3, genres: ["Jazz"]))) == ["Calm|Jazz"])
        // The same hour with nothing played then: the whole collection's Calm list.
        #expect(bannerLists(build(sets, HomeMoment(hour: 8, dayOfYear: 3, genres: []))) == ["Calm|"])
        // The working day: Focus.
        #expect(bannerLists(build(sets, HomeMoment(hour: 14, dayOfYear: 3, genres: []))) == ["Focus|"])
        // The one day in seven: the next of Calm's group.
        #expect(bannerLists(build(sets, HomeMoment(hour: 8, dayOfYear: 7, genres: ["Jazz"]))) == ["Calm|"])
    }

    @Test func withNoMoodListTheBannerShowsTheFirstList() {
        let sets = lists([("RightNow", nil)])
        #expect(bannerLists(build(sets, HomeMoment(hour: 23, dayOfYear: 3, genres: []))) == ["RightNow|"])
    }

    /// Without a clock the banner and the row stay as the lists came.
    @Test func withNoClockNothingIsCut() {
        let sets = lists([("RightNow", nil), ("Calm", nil), ("Calm", "Jazz")])
        let screen = build(sets, nil)
        #expect(screen.lists == sets.map(\.name))
        #expect(bannerLists(screen).first == "RightNow|")
    }

    @Test func madeForYouOpensTheCutsPlayedAtThisHourAndNotTheBannersList() {
        let sets = lists([("RightNow", nil), ("Calm", nil), ("Focus", nil), ("Sleep", nil),
                          ("Melancholy", nil), ("Calm", "Jazz"), ("Calm", "Rock"), ("Focus", "Jazz"),
                          ("Melancholy", "Rock")])
        let offered = ["RightNow|", "Calm|", "Focus|", "Sleep|", "Melancholy|"]
        let screen = HomeScreen.build(shelf: shelf(), songs: [], lists: offered, stations: [],
                                      draw: 1, moment: HomeMoment(hour: 8, dayOfYear: 3,
                                                                  genres: ["Jazz", "Rock"]),
                                      sets: sets)
        // The banner holds up the quiet jazz, so the row's Calm opens the next cut. Focus opens its
        // jazz. Sleep has no cut. Melancholy has no jazz cut, so it opens the rock.
        #expect(bannerLists(screen) == ["Calm|Jazz"])
        #expect(screen.lists == ["RightNow|", "Calm|Rock", "Focus|Jazz", "Sleep|", "Melancholy|Rock"])
    }

    /// A cut the row already holds is not taken a second time: the card keeps its own list.
    @Test func aCutTheRowAlreadyHoldsIsNotRepeated() {
        let sets = lists([("Calm", nil), ("Calm", "Jazz")])
        let screen = HomeScreen.build(shelf: shelf(), songs: [], lists: ["Calm|", "Calm|Jazz"],
                                      stations: [], draw: 1,
                                      moment: HomeMoment(hour: 14, dayOfYear: 3, genres: ["Jazz"]),
                                      sets: sets)
        #expect(screen.lists == ["Calm|", "Calm|Jazz"])
    }

    @Test func theMomentIsReadFromTheLocalClock() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        // 2026-02-01 23:30 UTC: the 32nd day of the year.
        let moment = HomeMoment.at(Date(timeIntervalSince1970: 1_769_988_600), calendar: calendar,
                                   genres: ["Jazz"])
        #expect(moment == HomeMoment(hour: 23, dayOfYear: 32, genres: ["Jazz"]))
    }
}
