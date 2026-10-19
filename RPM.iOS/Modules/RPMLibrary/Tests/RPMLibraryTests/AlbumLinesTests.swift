import Testing
import Foundation
import RPMKit
@testable import RPMLibrary

/// A record's track list as lines, using the desktop's rules. On a record marked classical, works are
/// shown with their movements under them. Every other record is a plain list.

private func song(_ id: String, _ title: String, track: Int, disc: Int = 0,
                  work: String? = nil, movement: String? = nil, composer: String? = nil,
                  seconds: Double = 0) -> CloudTrack {
    var tags = CloudTrackTags()
    tags.trackNumber = track
    tags.discNumber = disc
    tags.work = work
    tags.movementName = movement
    tags.composer = composer
    tags.durationSeconds = seconds
    return CloudTrack(rpmId: id, relativePath: "Mozart/Sonatas/\(id).flac", title: title,
                      artist: "Uchida", album: "Sonatas", tags: tags)
}

private let sonata = "Sonata In C Major, KV. 330"

private let mozart: [CloudTrack] = [
    song("a", "\(sonata): Allegro moderato", track: 1, work: sonata, composer: "Mozart", seconds: 300),
    song("b", "\(sonata): Andante cantabile", track: 2, work: sonata, composer: "Mozart", seconds: 400),
    song("c", "\(sonata): Allegretto", track: 3, work: sonata, composer: "Mozart", seconds: 200),
    song("d", "Fantasia In D Minor, KV. 397", track: 4, work: "Fantasia In D Minor, KV. 397",
         composer: "Mozart", seconds: 360),
]

private func titles(_ lines: [AlbumLine]) -> [String] {
    lines.map {
        switch $0 {
        case .disc(let n): return "disc \(n)"
        case .work(let heading): return "# \(heading.title)"
        case .song(let line): return line.title
        }
    }
}

private func songs(_ lines: [AlbumLine]) -> [AlbumSongLine] {
    lines.compactMap { if case .song(let line) = $0 { line } else { nil } }
}

@Test func aClassicalRecordIsWorksWithTheirMovementsUnderThem() {
    let lines = AlbumLines.build(mozart, classical: true)

    #expect(titles(lines) == [
        "# \(sonata)", "Allegro moderato", "Andante cantabile", "Allegretto",
        "Fantasia In D Minor, KV. 397",
    ])
    #expect(songs(lines).map(\.level) == [.movement, .movement, .movement, .piece])
}

@Test func aWorkHeadingSaysWhoWroteItAndHowLongItRuns() throws {
    guard case .work(let heading) = AlbumLines.build(mozart, classical: true)[0] else {
        Issue.record("no heading"); return
    }
    #expect(heading.composer == "Mozart")
    #expect(heading.duration == .seconds(900))
}

/// The work heading already names the composer, so a movement does not repeat it. A piece on its own line
/// names its composer.
@Test func aMovementSaysNothingUnderItsTitleAndAPieceNamesItsComposer() {
    let lines = songs(AlbumLines.build(mozart, classical: true))
    #expect(lines[0].subtitle == nil)
    #expect(lines[3].subtitle == "Mozart")
}

/// A record is shown as works only when it is marked classical. MusicBrainz also gives a work to many pop
/// songs, so the work tag alone is not enough.
@Test func aRecordNobodyMarkedClassicalIsThePlainList() {
    let lines = AlbumLines.build(mozart, classical: false)

    #expect(titles(lines) == mozart.map { $0.title! })
    #expect(songs(lines).allSatisfy { $0.level == .plain && $0.subtitle == nil })
}

@Test func theMovementTagBeatsWhatTheTitleLeaves() {
    let tracks = [
        song("a", "\(sonata): Allegro moderato", track: 1, work: sonata, movement: "I. Allegro moderato"),
        song("b", "\(sonata): Andante cantabile", track: 2, work: sonata),
    ]

    #expect(titles(AlbumLines.build(tracks, classical: true)).dropFirst()
        == ["I. Allegro moderato", "Andante cantabile"])
}

/// A title that does not start with the work name is shown in full, so it never becomes blank.
@Test func aTitleThatDoesNotStartWithTheWorkIsShownWhole() {
    let tracks = [
        song("a", "Allegro", track: 1, work: sonata),
        song("b", sonata, track: 2, work: sonata),
    ]

    #expect(titles(AlbumLines.build(tracks, classical: true)).dropFirst() == ["Allegro", sonata])
}

/// If the composers differ, no composer is shown. The first one is not picked.
@Test func aHeadingOverComposersWhoDisagreeNamesNone() throws {
    let tracks = [
        song("a", "Pasticcio: I", track: 1, work: "Pasticcio", composer: "Handel"),
        song("b", "Pasticcio: II", track: 2, work: "Pasticcio", composer: "handel"),
        song("c", "Pasticcio: III", track: 3, work: "Pasticcio", composer: "Vinci"),
    ]
    guard case .work(let heading) = AlbumLines.build(tracks, classical: true)[0] else {
        Issue.record("no heading"); return
    }
    #expect(heading.composer == nil)
}

/// A work never spans two discs. A symphony whose last movement is on the next disc of a box set gets one
/// heading per disc, as the discs are physically separate.
@Test func aWorkSplitAcrossDiscsIsAHeadingOnEach() {
    let tracks = [
        song("a", "Symphony: I", track: 1, disc: 1, work: "Symphony"),
        song("b", "Symphony: II", track: 2, disc: 1, work: "Symphony"),
        song("c", "Symphony: III", track: 1, disc: 2, work: "Symphony"),
        song("d", "Symphony: IV", track: 2, disc: 2, work: "Symphony"),
    ]

    #expect(titles(AlbumLines.build(tracks, classical: true)) == [
        "disc 1", "# Symphony", "I", "II",
        "disc 2", "# Symphony", "III", "IV",
    ])
}

@Test func everyLineHasItsOwnId() {
    let tracks = mozart + [
        song("e", "Symphony: I", track: 1, disc: 2, work: "Symphony"),
        song("f", "Symphony: II", track: 2, disc: 2, work: "Symphony"),
    ]
    let ids = AlbumLines.build(tracks, classical: true).map(\.id)
    #expect(Set(ids).count == ids.count)
}
