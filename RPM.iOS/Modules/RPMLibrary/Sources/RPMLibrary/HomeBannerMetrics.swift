import Foundation

/// How tall the home screen's featured card is drawn, and where a face must not be put.
///
/// The card takes the whole width of the strip, so no width is worked out here. The rest is
/// arithmetic with edge cases that are easy to miss. It is kept out of the layout pass,
/// because a test can only check a number that is set in one fixed place.
public enum HomeBannerMetrics {
    /// The plate's height. Everything else about the card is derived from it.
    ///
    /// The plate is 352 points tall. A shorter plate would read as a strip above the lists
    /// rather than as the main thing being offered. The cost is that the rows below it start
    /// further down the screen.
    public static let height: Double = 352

    /// The square cover on the plate. It is larger than a row's card and smaller than an album
    /// page's cover. This is what makes the banner read as one record, not as a wider row.
    public static let sleeve: Double = 124

    /// The padding at the plate's edges and between the cover and the text.
    public static let margin: Double = 22

    /// How much of the plate's left the cover and its padding take.
    public static var sleeveBand: Double { margin + sleeve + margin }

    /// How far across the plate the photo is clear of the text, from 0 to 1.
    ///
    /// The text covers only the foot of the card, not a column of it. So across the card, the
    /// only thing that a face has to clear is the right-hand edge. A face placed against that
    /// edge would be cut in half. The result is kept between 0.2 and 1, because a plate
    /// narrower than its own margins would otherwise give a negative value.
    public static func clearRight(plate: Double) -> Double {
        guard plate > 0 else { return 1 }
        return min(1, max(0.2, (plate - margin) / plate))
    }

    /// How far down the plate the photo is clear of the cover and the text, from 0 to 1.
    ///
    /// The cover and the three lines of text stand at the foot of the card, not in the middle
    /// of it. So everything above them is clear.
    public static var clearBottom: Double { clearBottom(above: 0) }

    /// The same question for a card that reaches up behind the heading. The band of photo
    /// that the text does not cover is taller by exactly the height that the card gained.
    ///
    /// **This is asked with the overhang, not without it,** because the crop decides where a
    /// face lands. A crop made for 352 points and drawn at 500 would push the face into the
    /// clear area behind the status bar.
    public static func clearBottom(above overhang: Double) -> Double {
        let plate = height(above: overhang)
        return min(1, max(0.2, (plate - sleeveBand) / plate))
    }

    /// How far down the card the status bar covers it, from 0 to one half. The card runs up
    /// behind the status bar by the overhang. So the top `statusBar` points of it are behind
    /// the clock and the Dynamic Island. The value is 0 for a card with no overhang, because
    /// that card starts below the bar.
    public static func clearTop(statusBar: Double, above overhang: Double) -> Double {
        let covered = min(max(0, statusBar), max(0, overhang))
        return min(0.5, covered / height(above: overhang))
    }

    // ── the reflection under the card ──

    /// The space under the card, for the dots, and the air above them. It is 0 when there is
    /// one card, because no dots are drawn. See `HomeBannerView.dots`.
    public static func dotsBand(cards: Int) -> Double { cards > 1 ? 10 + 5 : 0 }

    /// The gap between the home screen's rows. This is the first thing under the dots.
    /// `HomePage.scroll` sets the same number on its stack, so a change to one must change
    /// the other too.
    public static let rowsApart: Double = 26

    /// A row's heading and the air under it, down to the top of its first cover. The heading
    /// is one line of the app's font at 19 points. Like the rest of this type, the size is
    /// set as a number, not measured.
    public static let rowHeading: Double = 23 + 10

    /// How far past the foot of that first cover the reflection runs. It ends UNDER the row,
    /// not on the row's last line.
    public static let pastTheRow: Double = 18

    /// How deep the banner's reflection runs, measured from the foot of the card. It is not
    /// measured from the foot of the banner, which is lower by the dots.
    ///
    /// The reflection ends below the first row of covers. It passes the dots, the gap to the
    /// row, the row's heading, the cover, and a little more. The purpose is that the picture
    /// fades into the page, rather than stopping at an edge.
    ///
    /// **The depth stays the same whatever stands under the card.** The quick selection
    /// stands under the card. If the reflection ran down to that selection's foot, the
    /// reflection and its blur would reach about a hundred points further into the page.
    ///
    /// - Parameter rowArt: the cover edge that a home row draws at. It is passed in, not
    ///   written here, because the row owns this number.
    public static func reflection(cards: Int, rowArt: Double) -> Double {
        dotsBand(cards: cards) + rowsApart + rowHeading + max(0, rowArt) + pastTheRow
    }

    /// How tall the card is drawn: the layout height, plus whatever it reaches up behind.
    ///
    /// The overhang is measured, not fixed here. It is the status bar and the heading, and
    /// both differ by phone. A negative overhang is a reading taken before there is a window.
    /// It gives the same card as no overhang at all.
    public static func height(above overhang: Double) -> Double { height + max(0, overhang) }
}
