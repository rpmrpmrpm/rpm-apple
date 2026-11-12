import Foundation

/// The switch for karaoke lyrics: the sung line lights letter by letter as it is sung. See
/// ``LyricView``.
///
/// It is a supporter feature, as on the computer and the TV. The switch is kept for everyone, but
/// it has an effect only for a supporter: the owner of the player combines the two.
public enum KaraokeSetting {
    /// Where the switch is kept, in the standard user defaults. On when it was never set, so a
    /// supporter sees the feature without looking for it.
    public static let key = "lyrics.karaoke"

    /// The value when the switch was never set.
    public static let initial = true
}
