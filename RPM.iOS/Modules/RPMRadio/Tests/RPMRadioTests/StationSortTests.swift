import Testing
@testable import RPMRadio

/// The same rules are tested in `RPM.Core.Tests/StationSortTests.cs`. Change both files together.
/// Every order is total, so the same input always gives the same list.

private func station(_ uuid: String, _ name: String,
                     votes: Int = 0, bitrate: Int = 0) -> RadioStation {
    var made = RadioStation(uuid: uuid, name: name, streamUrl: "http://example.test/\(uuid)")
    made.votes = votes
    made.bitrateKbps = bitrate
    return made
}

private let dial = [
    station("c", "Zeta FM", votes: 5, bitrate: 128),
    station("a", "Alpha Radio", votes: 9, bitrate: 320),
    station("b", "Mid FM", votes: 5, bitrate: 320),
]

@Test func theDirectorysOwnOrderIsLeftAsItCame() {
    #expect(StationSort.by(.listed, dial).map(\.uuid) == ["c", "a", "b"])
}

@Test func byNameGoesAToZ() {
    #expect(StationSort.by(.nameUp, dial).map(\.display) == ["Alpha Radio", "Mid FM", "Zeta FM"])
}

@Test func byNameBackwardsGoesZToA() {
    #expect(StationSort.by(.nameDown, dial).map(\.display) == ["Zeta FM", "Mid FM", "Alpha Radio"])
}

@Test func byVotesPutsTheShowOfHandsFirst() {
    #expect(StationSort.by(.votes, dial).map(\.uuid) == ["a", "b", "c"])
}

@Test func byQualityPutsTheHighestBitrateFirst() {
    #expect(StationSort.by(.quality, dial).map(\.uuid) == ["a", "b", "c"])
}

/// **The tie-break matters most.** Two stations with the same values would otherwise appear in
/// arrival order. The list would then change while the user scrolls.
@Test func aTieIsBrokenByTheNameAndThenByTheId() {
    let tied = [
        station("z", "Same FM", votes: 3, bitrate: 128),
        station("a", "Same FM", votes: 3, bitrate: 128),
    ]

    for order in StationOrdering.allCases where order != .listed {
        #expect(StationSort.by(order, tied).map(\.uuid) == ["a", "z"],
                "\(order) did not settle the tie")
    }
}

/// A station is sorted by the name shown in its row, not by the raw directory name. A raw name
/// with a prefix such as "[HQ]" would sort under the prefix.
@Test func aStationSortsByTheNameThatIsShown() {
    let messy = [
        station("1", "Zeta"),
        station("2", "Beta (MP3 320k)"),
    ]

    #expect(StationSort.by(.nameUp, messy).map(\.uuid) == ["2", "1"])
}

@Test func anEmptyDialSortsToNothing() {
    for order in StationOrdering.allCases {
        #expect(StationSort.by(order, []).isEmpty)
    }
}
