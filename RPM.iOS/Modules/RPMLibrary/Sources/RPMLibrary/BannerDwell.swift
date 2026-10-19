import Foundation

/// The home banner's strip as a loop, as the desktop's ring is: after the last card comes the first.
///
/// A paged scroll has an end, so the strip draws one slot more than it has cards: a copy of the
/// first card after the last. A step from the last card moves forward onto the copy, and once the
/// strip is at rest there it is put on the first card itself without animation (``rest(at:)``). The
/// two look the same, so the reader sees the first card come in from the right.
///
/// **The copy needs to know when the strip is at rest**, which is iOS 18's scroll phase. Without it
/// (``loops`` false) there is no copy, and the step from the last card scrolls back to the first.
public struct BannerRing: Hashable, Sendable {
    /// How many cards the strip has.
    public let cards: Int

    /// Whether the strip carries the copy of its first card. No default: see the type.
    public let loops: Bool

    public init(cards: Int, loops: Bool) {
        self.cards = cards
        self.loops = loops
    }

    /// How many slots the strip draws: the cards, and the copy of the first where there is one.
    /// One card has nowhere to loop to and gets no copy.
    public var slots: Int { loops && cards > 1 ? cards + 1 : cards }

    /// Which card a slot shows. The copy shows the first.
    public func card(at slot: Int) -> Int { cards > 0 ? slot % cards : 0 }

    /// Where a strip at rest on `slot` is put instead, without animation, or nil where it is
    /// already on a card. The copy goes to the first card. So does a slot past the end, which is
    /// where a strip dealt again with fewer cards can be left.
    public func rest(at slot: Int) -> Int? {
        guard cards > 0, slot >= cards else { return nil }
        return slot % cards
    }

    /// The slot a step lands on: the next one, which after the last card is the copy of the first.
    /// Without the copy, the first card itself.
    public func next(after slot: Int) -> Int { slots > 0 ? (slot + 1) % slots : 0 }
}

/// When the home banner steps to its next card on its own.
///
/// The desktop's rule on the desktop's clock: a card is held for ``hold``, then the banner steps one
/// card on. See `HomeBanner.DwellMs` and `HomeView.Rewind` in RPM.Desktop.
///
/// The banner uses this value as the id of the task that counts down, so a change to any field
/// cancels the countdown in progress and starts a new one. That is what restarts the countdown after
/// every step, the reader's own swipe included: a swipe changes ``at``. No call site has to remember
/// to restart it.
public struct BannerDwell: Hashable, Sendable {
    /// How long a card is held before the banner steps. Read from the desktop's
    /// `HomeBanner.DwellMs` by `BannerDwellTests`, which fails if the two differ.
    public static let hold: Duration = .milliseconds(7000)

    /// The slot in front. See ``BannerRing``.
    public let at: Int

    /// The strip the slot is in.
    public let ring: BannerRing

    /// Whether the home screen is the one showing and the app is in the foreground.
    public let onScreen: Bool

    /// Whether the home page is scrolled to its top. The page's background is dressed from the card
    /// in front, so a step while the reader is looking at the rows below would change the
    /// background behind them.
    public let pageAtTop: Bool

    /// Whether the strip is at rest: no finger on it and no scroll settling. A step while the
    /// reader is dragging would move the card out from under the finger.
    public let still: Bool

    public init(at: Int, ring: BannerRing, onScreen: Bool, pageAtTop: Bool, still: Bool) {
        self.at = at
        self.ring = ring
        self.onScreen = onScreen
        self.pageAtTop = pageAtTop
        self.still = still
    }

    /// Whether the countdown runs. Not on a strip of one card, not on a screen nobody is looking at,
    /// not with the page scrolled down, not while the strip is moving, and not on the copy of the
    /// first card, which is put on the first card as soon as the strip is at rest and counts from
    /// there. The desktop's gate is the first two; the strip moving is its pointer resting on the
    /// strip.
    public var counts: Bool { ring.cards > 1 && onScreen && pageAtTop && still && at < ring.cards }

    /// The slot the step lands on. See ``BannerRing/next(after:)``.
    public var next: Int { ring.next(after: at) }
}
