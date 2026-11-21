import Testing
import Foundation
@testable import RPMAudio

@Test func anExplicitSongWearsTheSquareEOnTheLockScreen() {
    #expect(LockScreenTitle.of("Alter Ego", explicit: true) == "Alter Ego\u{00A0}\u{1F174}")
}

@Test func aCleanSongKeepsItsTitle() {
    #expect(LockScreenTitle.of("Alter Ego", explicit: false) == "Alter Ego")
}

@Test func aSongWithNoTitleGetsNoMarkOnItsOwn() {
    #expect(LockScreenTitle.of("", explicit: true) == "")
}
