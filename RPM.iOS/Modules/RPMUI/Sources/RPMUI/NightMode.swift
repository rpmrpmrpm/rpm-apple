import SwiftUI

/// Night mode: the darker way to draw the pages that stand on a photograph.
///
/// Off, a page's ground (``ArtGround``) is its picture blurred, a little more colourful than
/// the picture, under a light veil, and the artist page's photograph has no darkening over it.
/// On, the ground has the heavier veil and plain colours, and the artist page's photograph is
/// dimmed and darker toward its foot, as the home banner's card is.
///
/// The switch is in the Background card on the Profile page. It is kept on this phone only.
/// The Android phone app has the same switch under the same key name (`look.night`).
public enum NightMode {
    /// Where the switch is kept, in the standard user defaults. Off when it was never set.
    public static let key = "look.night"
}
