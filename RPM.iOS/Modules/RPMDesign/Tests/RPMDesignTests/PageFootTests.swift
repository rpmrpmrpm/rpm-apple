import Testing
import Foundation
@testable import RPMDesign

/// What a page reserves at the foot of the screen, and what a list inside it reserves for the
/// keyboard above it.
struct PageFootTests {
    private let chrome = 110.0
    private let below = 34.0
    private let keys = 330.0

    // ── the keys down ──

    /// The shell's own inset already covers the bar and the indicator below it.
    @Test func aPageUnderTheChromeReservesNothingOfItsOwn() {
        #expect(PageFootRoom.chrome(chrome, below: below, keys: 0, at: .underTheChrome) == 0)
    }

    /// A stack gives its content the window's insets and nothing else, so the page reserves the
    /// whole bar. **The indicator's inset is not taken off the bar.** That inset sits under the
    /// bar, not instead of it. Taking it off left the last row of every wall behind the mini
    /// player.
    @Test func aPageInAStackReservesTheWholeBar() {
        #expect(PageFootRoom.chrome(chrome, below: below, keys: 0, at: .insideAStack) == chrome)
    }

    /// Both places end the content on the same line of the screen. A page in a stack starts with
    /// the window's inset and adds the bar. A page under the chrome gets both.
    @Test func bothPlacesEndTheContentOnTheSameLine() {
        let under = chrome + below
            + PageFootRoom.chrome(chrome, below: below, keys: 0, at: .underTheChrome)
        let stacked = below
            + PageFootRoom.chrome(chrome, below: below, keys: 0, at: .insideAStack)

        #expect(under == stacked)
    }

    /// With the keyboard down, no space is needed. The frame notification gives this answer as
    /// the keyboard leaves the screen, as well as the hide notification.
    @Test func noKeyboardAsksForNothing() {
        #expect(PageFootRoom.keyboard(0, chrome: chrome, below: below,
                                      at: .underTheChrome) == 0)
    }

    // ── the keys up ──

    /// The keyboard comes up over the bar, not under it. So a list needs only the part of the
    /// keyboard that reaches past the space already reserved below it. Reserving the whole
    /// keyboard ends the list one bar's height above the keys.
    @Test func aListUnderTheChromeOwesOnlyTheKeyboardPastTheBar() {
        #expect(PageFootRoom.keyboard(keys, chrome: chrome, below: below,
                                      at: .underTheChrome) == keys - chrome - below)
    }

    /// A keyboard shallower than the bar is already covered by the bar.
    @Test func aKeyboardShallowerThanTheBarAsksForNothing() {
        #expect(PageFootRoom.keyboard(40, chrome: chrome, below: below,
                                      at: .underTheChrome) == 0)
    }

    /// The shell's `ignoresSafeArea(.keyboard)` does not reach inside a stack. So the stack has
    /// already ended the page at the top of the keyboard. A list that reserved the keyboard again
    /// would leave a gap as tall as the keyboard under its last row.
    @Test func aListInAStackOwesTheKeyboardNothing() {
        #expect(PageFootRoom.keyboard(keys, chrome: chrome, below: below,
                                      at: .insideAStack) == 0)
    }

    /// The page stops reserving the bar, because the keyboard is drawn over it. Reserving the bar
    /// as well would leave a bar-height gap between the content and the keyboard.
    @Test func aPageInAStackDropsTheBarWhenTheKeysCoverIt() {
        #expect(PageFootRoom.chrome(chrome, below: below, keys: keys,
                                    at: .insideAStack) == 0)
    }

    /// A keyboard that reaches less far than the bar and the indicator together leaves the part
    /// of the bar above it to reserve.
    @Test func aPageInAStackReservesWhatTheKeysDoNotCover() {
        #expect(PageFootRoom.chrome(chrome, below: below, keys: 100,
                                    at: .insideAStack) == chrome + below - 100)
    }

    /// The page under the chrome does not move for the keyboard at all. The shell ignores it.
    @Test func aPageUnderTheChromeIsTheSameWithTheKeysUp() {
        #expect(PageFootRoom.chrome(chrome, below: below, keys: keys,
                                    at: .underTheChrome) == 0)
    }

    // ── before the numbers have arrived ──

    /// This is the time before the chrome has reported its height. A list drawn at that moment
    /// reserves the keyboard itself, not a negative band.
    @Test func aBarThatHasNotReportedYetAnswersWithoutGoingNegative() {
        #expect(PageFootRoom.chrome(0, below: below, keys: 0, at: .insideAStack) == 0)
        #expect(PageFootRoom.keyboard(keys, chrome: 0, below: below,
                                      at: .underTheChrome) == keys - below)
    }

    /// A figure that is not a number at all. A frame read before there is a window can return one.
    @Test func nothingReadableAsksForNothing() {
        #expect(PageFootRoom.chrome(.nan, below: below, keys: 0, at: .insideAStack) == 0)
        #expect(PageFootRoom.keyboard(.infinity, chrome: chrome, below: below,
                                      at: .underTheChrome) == 0)
    }
}
