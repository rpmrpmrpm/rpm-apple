import Foundation

/// What lights a room that is not listening to anything.
///
/// Ported from `CardRoomArt` on the desktop, with the same constants and cycles. The figures are
/// the same room that the full-screen stage draws. This only supplies the envelopes that the
/// stage would take from the music, for a card that has no music.
///
/// **A card is not the thing being played.** Driving one from the player would make every card on a
/// strip pulse to a record that is on none of them. So the three envelopes breathe on slow cycles of
/// their own instead.
///
/// **The envelopes cannot be held at a constant.** With a constant, the room has nothing in it but
/// the drift, and at a card's size it reads as a still picture. What makes the room look alive is
/// not the figures moving but the swell stirring them: bass alone is worth 62% of a lobe's radius.
/// This breathing is that swell, with no record playing.
public enum CardRoomBreath {
    /// How much quicker a card's room runs than the stage's.
    ///
    /// A stage fills a screen and is watched. A card is a fifth of one and is only glanced at.
    /// At the room's own rate a figure crosses about two per cent of a plate in a second, which
    /// is motion nobody sees. The factor is applied to the CLOCK rather than to each rate in
    /// turn, so drift, orbit and wobble keep their proportions to each other.
    public static let rate: Double = 2.2

    /// What the three breathe around, and how far either side. The levels are low, because a card
    /// is a background and not a display. The middles match the desktop's constants.
    static let bass: Double = 0.20, bassSwing: Double = 0.16
    static let middle: Double = 0.16, middleSwing: Double = 0.14
    static let air: Double = 0.12, airSwing: Double = 0.11

    /// The clock a card's room runs on: its own seconds, quickened.
    ///
    /// **The envelopes and the figures read the SAME clock.** `CardRoomArt` computes one `t` and
    /// gives it to both. With two separate clocks, the swell would arrive at a pose that the
    /// figures had already left.
    public static func clock(_ seconds: Double) -> Double { seconds * rate }

    /// The three envelopes at a moment of that clock.
    ///
    /// The cycles are 11.9, 8.8 and 17.0 seconds long at this rate and start out of phase with one
    /// another, so the three never swell together and the room does not appear to beat.
    public static func at(_ t: Double) -> (bass: Float, middle: Float, air: Float) {
        (Float(bass + bassSwing * sin(t * 0.53)),
         Float(middle + middleSwing * sin(t * 0.71 + 1.7)),
         Float(air + airSwing * sin(t * 0.37 + 3.1)))
    }
}
