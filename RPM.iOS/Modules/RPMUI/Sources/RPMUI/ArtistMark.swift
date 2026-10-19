import SwiftUI
import RPMDesign

/// A performer: head and shoulders with a microphone standing in front of them.
///
/// The desktop's `ArtistIcon`, path for path: the same string that is in
/// `RPM.Desktop/Themes/Generic.xaml` and in `Assets/Svg/artist.svg`. It is a drawing
/// rather than a glyph because Font Awesome has no such icon. The closest are
/// `user-music`, whose note reads as a listener, and `user-headset`, which reads as a
/// support desk. So the desktop built one from two glyphs the font does have: the body of
/// `user-music` (its right shoulder is already cut back to leave room for a second mark)
/// and Font Awesome's `microphone` placed where the note was. Both come from
/// fa-solid-900.ttf at their native 512-unit scale, so the mark has the same grid, stroke
/// weight and corner radii as the app's other icons.
///
/// Copied here rather than approximated with a glyph. The microphone alone (`f130`) is the
/// mark the desktop's artists wall shows for its EMPTY state, not the mark for an artist.
///
/// Nonzero winding, which is what `Path` fills with by default and what the desktop's
/// `F1` prefix says. With even-odd the head and the shoulder cancel where they overlap
/// and the microphone's capsule punches a hole through its own cradle.
struct ArtistMark: Shape {
    /// `nonisolated(unsafe)` because `CGPath` has no `Sendable` conformance. It is safe
    /// because what `parse` returns is a copy that nothing else can change, and every
    /// reader here only measures it. ``CastMark`` and the wordmark are held the same way.
    private nonisolated(unsafe) static let drawn = VectorPath.parse(
        "M254.8 225.6Q224.4 256 181.5 256Q138.5 256 108.2 225.6Q77.8 195.2 77.8 152.3" +
        "Q77.8 109.4 108.2 79Q138.5 48.6 181.5 48.6Q224.4 48.6 254.8 79Q285.2 109.4 285.2 152.3" +
        "Q285.2 195.2 254.8 225.6ZM233.3 398.6Q233.3 436.7 267.3 463.4H38.9Q22.7 463.4 11.3 452.1" +
        "Q0 440.7 0 424.5V390.5Q0 345.9 32 313.9Q64 281.9 108.6 281.9H122.3Q150.7 294.9 181.5 294.9" +
        "Q212.3 294.9 240.6 281.9H254.4Q294.9 281.9 325.7 309.5Q285.2 315.9 259.2 340.7" +
        "Q233.3 365.4 233.3 398.6ZM353.3 303.5V210.2Q353.3 186.9 369.7 170.5Q386 154.2 409.3 154.2" +
        "Q432.7 154.2 449 170.5Q465.3 186.9 465.3 210.2V303.5Q465.3 326.9 449 343.2" +
        "Q432.7 359.5 409.3 359.5Q386 359.5 369.7 343.2Q353.3 326.9 353.3 303.5ZM502.7 266.2" +
        "Q506.8 266.2 509.4 268.8Q512 271.5 512 275.5V303.5Q512 342 486.6 370.9Q461.3 399.8 423.3 405" +
        "V424.9H456Q460.1 424.9 462.7 427.5Q465.3 430.1 465.3 434.2V443.5Q465.3 447.6 462.7 450.2" +
        "Q460.1 452.9 456 452.9H362.7Q358.6 452.9 356 450.2Q353.3 447.6 353.3 443.5V434.2" +
        "Q353.3 430.1 356 427.5Q358.6 424.9 362.7 424.9H395.3V405Q357.4 399.8 332.1 369.2" +
        "Q306.7 338.5 306.7 298.9V275.5Q306.7 271.5 309.3 268.8Q311.9 266.2 316 266.2H325.3" +
        "Q329.4 266.2 332.1 268.8Q334.7 271.5 334.7 275.5V300Q334.7 329.8 353.9 352.5" +
        "Q373.2 375.3 401.8 377.6Q435 381.1 459.5 358.7Q484 336.2 484 303.5V275.5" +
        "Q484 271.5 486.6 268.8Q489.3 266.2 493.3 266.2Z")

    func path(in rect: CGRect) -> Path { Path(VectorPath.fitted(Self.drawn, in: rect)) }
}

extension ArtistMark {
    /// The mark at the size a header key's glyph is drawn, painted the way a glyph is.
    ///
    /// A shape fills with the foreground style, so it takes the colour of its surroundings
    /// exactly as `Text(Glyph.record)` beside it does. `size` is the box, not a font size:
    /// the desktop pairs a 16-point `FontIcon` with a 16 by 16 `ArtistIcon`, and this is
    /// the same pairing.
    static func key(_ size: CGFloat) -> some View {
        ArtistMark().frame(width: size, height: size)
    }
}
