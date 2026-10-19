import Foundation

/// What colours a generated list is drawn in, based on what the list is.
///
/// The desktop app does the same job in three files. `SmartPlaylistFace.Look` and `.Cover` pick a hue
/// and roll a seed. `PlaylistFigure.Colourway.From` takes three neighbours off the palette's ring.
/// `CoverOverlay.Ink` turns those three into the two colours that a cover's frame is drawn in.
///
/// **Rolled here, not sent.** The cut carries the kind, the genre and the decade. Those are everything the
/// seed is made from. So both apps reach the same three colours, and no colour has to cross the network.
/// The alternative would be a phone drawing a list in colours the computer does not agree with, with no way
/// to tell which of them is wrong.
///
/// **Nothing is mixed, rotated or lifted.** Both inks come from ``RPMPalette``. The border is the darkest
/// stop of the ramp that the asset ships beside the list's shadow colour. The name is set in whichever of
/// the list's three tints reads best on that border. A cover can only carry colours that the app owns.
public enum GeneratedListLook {
    /// The three colours one list was rolled, as the palette lists them.
    ///
    /// **Sorted by light, which is the point.** The ring is ordered by hue, and it says nothing about which
    /// of three neighbours is the brightest. Without sorting, a room could be lit from its own shadow.
    public struct Trio: Equatable, Sendable {
        /// The brightest. This is the colour of the light in the picture.
        public let hot: RGB

        /// The middle one. It is most of what is actually seen.
        public let mid: RGB

        /// The darkest. This is the shadow, and the frame's border is taken from it.
        public let deep: RGB
    }

    /// One list's whole look: its three colours, and the two inks its frame is drawn in.
    public struct Look: Equatable, Sendable {
        public let trio: Trio

        /// Everything the drawing paints black.
        public let border: RGB

        /// Everything it paints white: the list's name down the band, and the app's own name in the corner.
        public let text: RGB

        /// Whether this list has nothing of its own to put behind the frame's window, and so stands on the
        /// room instead. See ``roomed(kind:)``.
        public let roomed: Bool

        /// The colour a photograph behind the window is washed in. It is the palette entry the seed lands
        /// on, before the three are sorted by light. The desktop's `SmartPlaylistFace.Tint` sets the same
        /// value. `GeneratedCoverService` uses it to wash the same photographs.
        public let tint: RGB
    }

    /// The look of the list that the computer keyed on these three fields.
    ///
    /// Nil where the kind is not one this build has a picture for. That happens on an older phone reading a
    /// newer cut. The list itself still shows, in the plain colours it has without a frame.
    public static func of(kind: String, genre: String?, decade: Int) -> Look? {
        guard let hue = hue(of: kind) else { return nil }
        let seed = seed(hue: hue, genre: genre, decade: decade)
        guard let trio = trio(seed: seed), let tint = anchor(seed: seed) else { return nil }

        let border = foot(of: trio.deep)

        // Three candidates, sorted by light. The brightest is not always the readable one.
        // For the two crimson lists, Magenta is the brightest, at 2.95:1 contrast with the
        // border. Crimson, the middle one, is 3.15:1.
        var text = trio.hot
        for candidate in [trio.mid, trio.deep] where contrast(candidate, border) > contrast(text, border) {
            text = candidate
        }

        return Look(trio: trio, border: border, text: text, roomed: roomed(kind: kind), tint: tint)
    }

    /// Which lists stand on the room, and which keep the picture they already have.
    ///
    /// **Not the same question as whether a list is framed.** Every generated list is framed. These five have
    /// nothing else to put behind the window. They get the frame and its styling only, and not the metaball
    /// picture.
    public static func roomed(kind: String) -> Bool {
        switch kind {
        case "RightNow", "OnRepeat", "FavoriteTracks", "FirstListens", "LovedAndForgotten": return true
        default: return false
        }
    }

    // ── the seed ──

    /// Which colour off the ring each kind wears.
    ///
    /// The desktop app's `SmartPlaylistFace.Look` sets the same hues. Only the hues are here. The family of
    /// colours a list's figure is drawn in does not reach a frame. The figure itself is drawn on
    /// the computer.
    ///
    /// Kinds are matched by name, not by number, as the whole cut is. So a kind added on the computer still
    /// reaches an older phone as a list that the phone can show.
    static func hue(of kind: String) -> UInt32? {
        switch kind {
        case "Calm": return 5                // Azure
        case "Energetic": return 9           // Red
        case "Danceable": return 7           // Magenta
        case "Focus": return 4               // Forest
        case "Sleep": return 6               // Indigo
        case "Decade": return 1              // Rust
        case "Classical": return 3           // Lime
        case "FavoriteTracks": return 8      // Crimson
        case "MostPlayed": return 0          // Vermilion
        case "OnRepeat": return 1            // Rust
        case "RecentlyPlayed": return 2      // Gold
        case "RecentlyAdded": return 3       // Lime
        case "FirstListens": return 4        // Forest
        case "LateNight": return 6           // Indigo
        case "Rediscover": return 7          // Magenta
        case "LovedAndForgotten": return 8   // Crimson
        case "PlayedNotLoved": return 9      // Red
        case "NeverPlayed": return 5         // Azure
        case "KeepSkipping": return 1        // Rust
        case "RightNow": return 5            // Azure
        default: return nil
        }
    }

    /// The seed: the hue in the low digit, and the variation above it.
    ///
    /// `Colourway` anchors on `seed % count`. It reads bit 11 to see how far apart the three colours sit.
    /// So a seed built as `variation * 10 + hue` lands on the wanted colour, and leaves the rest to arrange
    /// the picture.
    ///
    /// A decade varies the seed in the same way a genre does. The value is scattered through the same hash,
    /// rather than added as a raw number. Ten apart in the seed gives the same picture in almost the same
    /// colours. Without scattering, 1960 and 1970 would be neighbours.
    static func seed(hue: UInt32, genre: String?, decade: Int) -> UInt32 {
        let variation: UInt32 = decade > 0 ? 977 &+ scatter("\(decade)s")
                              : genre == nil ? 977
                              : 977 &+ scatter(genre!)

        return (variation &* UInt32(RPMPalette.accents.count)) &+ hue
    }

    /// FNV-1a hash over the name's UTF-16 units. A C# `char` is one UTF-16 unit, so the desktop app walks a
    /// `string` the same way. Both apps must get the same number for the same genre.
    static func scatter(_ text: String) -> UInt32 {
        var hash: UInt32 = 2166136261
        for unit in text.utf16 {
            hash = (hash ^ UInt32(unit)) &* 16777619
        }
        return hash % 4096
    }

    /// The one palette entry the seed lands on. ``trio(seed:)`` takes its neighbours from it.
    static func anchor(seed: UInt32) -> RGB? {
        let ring = RPMPalette.accents.map(\.base)
        guard !ring.isEmpty else { return nil }
        return ring[Int(seed % UInt32(ring.count))]
    }

    /// Three neighbours off the ring, chosen by the seed, in light order.
    static func trio(seed: UInt32) -> Trio? {
        let ring = RPMPalette.accents.map(\.base)
        guard !ring.isEmpty else { return nil }

        // How far round the ring the other two sit. One step is the closest harmony there is. Two steps is a
        // visibly wider set. The span is rolled from the seed. If it were fixed, every generated cover in the
        // app would have the same span.
        let span = 1 + Int((seed >> 11) % 2)
        let at = Int(seed % UInt32(ring.count))

        var three = [ring[at],
                     ring[(at + span) % ring.count],
                     ring[((at - span) % ring.count + ring.count) % ring.count]]

        three.sort { light(of: $0) < light(of: $1) }

        return Trio(hot: three[2], mid: three[1], deep: three[0])
    }

    // ── the inks ──

    /// The darkest stop of the ramp that the palette ships beside this colour.
    ///
    /// The stop is read from the asset, not calculated. The three stops are as much a part of the curated
    /// set as the tint is. A calculation here would be a second answer, and it would drift as soon as someone
    /// re-curated the first. If there is no ramp to read, each channel of the tint is scaled to 40%. That is the
    /// figure the asset's own gradient uses for its foot.
    static func foot(of colour: RGB) -> RGB {
        if let ramp = RPMPalette.accents.first(where: { $0.base == colour })?.gradient,
           let last = ramp.last {
            return last
        }

        return toward(colour, 0.40)
    }

    /// A colour taken toward black, channel by channel. The aim is the same colour with less light in it.
    /// An HSL lightness would pull a saturated hue toward grey on the way.
    static func toward(_ colour: RGB, _ light: Double) -> RGB {
        RGB(UInt8(clamping: Int((Double(colour.r) * light).rounded())),
            UInt8(clamping: Int((Double(colour.g) * light).rounded())),
            UInt8(clamping: Int((Double(colour.b) * light).rounded())))
    }

    /// The plain weighted sum that the trio is sorted by. It is not the same figure as ``contrast(_:_:)``,
    /// which is WCAG's and needs each channel linearised first.
    static func light(of colour: RGB) -> Double {
        0.2126 * Double(colour.r) + 0.7152 * Double(colour.g) + 0.0722 * Double(colour.b)
    }

    /// How far apart two colours are to read, as a ratio from 1 to 21. This is WCAG's relative luminance
    /// ratio, which anyone can check this against.
    ///
    /// **Held to 3:1 here, not 4.5:1.** The palette is the reason. Its brightest entry is Lime, at 0.54
    /// relative luminance. So a palette tint on a palette shadow cannot reach the 4.5:1 that body text needs,
    /// whichever pair is chosen. The band is set in bold at about a twelfth of the cover's edge.
    /// That is large text, and WCAG requires only 3:1 for large text.
    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let one = luminance(a), two = luminance(b)
        let (light, dark) = one >= two ? (one, two) : (two, one)
        return (light + 0.05) / (dark + 0.05)
    }

    static func luminance(_ colour: RGB) -> Double {
        0.2126 * channel(colour.r) + 0.7152 * channel(colour.g) + 0.0722 * channel(colour.b)
    }

    private static func channel(_ value: UInt8) -> Double {
        let v = Double(value) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
}
