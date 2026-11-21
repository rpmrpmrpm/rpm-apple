import Foundation

/// The title of a song as the lock screen and the control centre show it.
///
/// An explicit song carries a filled square E after its title there, as streaming services show it
/// (U+1F174, after a no-break space so the mark never starts a line of its own). The system's card
/// has no place of its own for the mark, so it goes into the title. Only there: the app's own player
/// and mini player draw the title without it. The Android phone marks its media session the same way.
public enum LockScreenTitle {
    /// The mark put after an explicit song's title.
    public static let explicitMark = "\u{00A0}\u{1F174}"

    /// `title` with the mark after it when `explicit`.
    public static func of(_ title: String, explicit: Bool) -> String {
        guard explicit, !title.isEmpty else { return title }
        return title + explicitMark
    }
}
