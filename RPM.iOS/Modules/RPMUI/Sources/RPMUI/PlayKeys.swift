import SwiftUI
import RPMKit

/// The row of keys under the name on the artist page and the album page: Play as a round glass key
/// in the middle, and on each side of it a key that is its glyph alone, with no glass. Play is
/// then the key the eye finds first. The Android phone app draws the same row with the same sizes.
enum PlayKeys {
    /// Play's diameter, and the height of the keys beside it.
    static let height: Double = 50

    /// The width a key beside Play answers taps in.
    static let sideWidth: Double = 56

    /// The space between Play and each key beside it.
    static let apart: Double = 12

    /// The empty place of a key beside Play that the page cannot offer, so Play stays in the middle.
    static var emptySide: some View {
        Color.clear.frame(width: sideWidth, height: height)
    }
}

/// Play, as a round glass key. See ``PlayKeys``.
struct PlayKey: View {
    /// What VoiceOver reads. Each page names what it plays.
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // The triangle's weight is left of its middle, so it is moved right a little to look
            // centred in the circle.
            Text(Glyph.play)
                .font(RPMFont.icon(18))
                .foregroundStyle(RPMInk.white(0xF5 / 255))
                .offset(x: 2)
        }
        .buttonStyle(RPMGlassKey(edge: PlayKeys.height))
        .accessibilityLabel(label)
    }
}

extension View {
    /// A key beside Play: what it shows, in a box as tall as Play, which is the part that answers
    /// a tap. Use it with `.buttonStyle(.plain)`. See ``PlayKeys``.
    func playSideKey() -> some View {
        font(RPMFont.icon(17))
            .foregroundStyle(RPMInk.white(0xF0 / 255))
            .frame(width: PlayKeys.sideWidth, height: PlayKeys.height)
            .contentShape(Rectangle())
    }
}
