import Testing
@testable import RPMLibrary

@Test func bothTagsGiveTwoLinesCopyrightFirst() {
    let credits = AlbumCredits(copyright: "\u{2117} 2012 Downtown Records", label: "Atlantic")
    #expect(credits.lines == ["\u{2117} 2012 Downtown Records", "Atlantic"])
}

@Test func aLabelTheCopyrightAlreadyNamesIsNotRepeated() {
    let credits = AlbumCredits(copyright: "1998 Warp Records Limited", label: "warp records")
    #expect(credits.lines == ["\u{00A9} 1998 Warp Records Limited"])
}

@Test func aCopyrightWithoutAMarkGetsOne() {
    #expect(AlbumCredits(copyright: "1990 RCA", label: nil).lines == ["\u{00A9} 1990 RCA"])
    #expect(AlbumCredits(copyright: "(P) 1990 RCA", label: nil).lines == ["(P) 1990 RCA"])
    #expect(AlbumCredits(copyright: "Copyright 1990 RCA", label: nil).lines == ["Copyright 1990 RCA"])
    #expect(AlbumCredits(copyright: "\u{00A9} 1990 RCA", label: nil).lines == ["\u{00A9} 1990 RCA"])
}

@Test func aLabelAloneIsOneLine() {
    #expect(AlbumCredits(copyright: nil, label: "Verve").lines == ["Verve"])
}

@Test func blankTagsAreNothing() {
    let credits = AlbumCredits(copyright: "  ", label: "\n")
    #expect(credits.lines.isEmpty)
    #expect(credits.isEmpty)
    #expect(credits == AlbumCredits(copyright: nil, label: nil))
}
