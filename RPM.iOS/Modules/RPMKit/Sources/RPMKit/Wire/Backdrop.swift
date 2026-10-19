import Foundation

/// Which picture the app is drawn on.
///
/// The desktop offers five built-in backdrops and stores the choice as an id (`Backdrop.cs`). The
/// phone offers the same list, but its pressed vinyl replaces the desktop's table of records. So the
/// desktop's Night has no phone tile, and Gold, which is the table pressed in gold on the desktop,
/// is the vinyl pressed in gold on the phone. The default on both is RPaMp's ground. Pegasus and
/// RPaMp are cut to the phone's shape by `scripts/make_phone_backdrops.py`, the sheet music by
/// `make_sheet_music.py` from its own render, and both vinyl pressings are drawn for a phone by
/// `make_vinyl_ground.py`.
///
/// **One of them is a supporter's**, which is why ``standing(stored:gold:)`` takes `gold` and has
/// no default for it: a stored id outlives the support that bought it, and a gate on the picker
/// alone would leave a lapsed supporter looking at gold for ever.
///
/// It lives beside ``SupporterGround`` for the reason that type gives: two things have to agree on
/// what a supporter may have, and neither of them owns it.
public enum Backdrop {
    /// Where the choice is kept. **Nowhere else names this string**: the ground reads it before the
    /// first frame and the profile writes it, and a second spelling would be a picker that changes
    /// nothing.
    public static let key = "backdrop.picture"

    /// The built-in pictures, by the id that is stored.
    public enum Choice: String, CaseIterable, Sendable {
        /// The default: RPaMp's ground, bands of cyan light in deep blue.
        case standard = ""

        /// Three records, lit, drawn for a phone, in the blue pressing.
        case vinyl

        /// The visualizer's own room, shot against a red record.
        case pegasus

        /// A printed score in warm sepia, sharp along the top. Stored as the desktop stores it.
        case sheetMusic = "sheet-music"

        /// The same three records pressed in gold. The supporter's. The desktop stores its gold
        /// table under the same id.
        case gold

        /// Whether supporting rpm is what this one is for. The tile is shown to everybody, so that
        /// people can see what supporting gives them.
        public var isSupporters: Bool { self == .gold }

        /// The resource key for its name in the picker.
        public var nameKey: String {
            switch self {
            case .standard: "Settings_BackgroundDefault"
            case .vinyl: "Settings_BackgroundVinyl"
            case .pegasus: "Settings_BackgroundPegasus"
            case .sheetMusic: "Settings_BackgroundSheetMusic"
            case .gold: "Settings_BackgroundGold"
            }
        }
    }

    /// Which backdrop is actually shown, given what is stored and what the account may have.
    ///
    /// Anything unrecognised is the default, so a settings file from a later version still shows a
    /// backdrop.
    ///
    /// ``formerRPaMp`` is the default too: it is the id that older settings hold for RPaMp's
    /// ground, so a stored "rpamp" shows the same picture and lights the Default tile.
    ///
    /// ``formerNight`` is the vinyl: it is the id that older settings hold for the night table,
    /// and the vinyl is the phone's version of that table.
    ///
    /// Gold asked for by an account that is not a supporter is the vinyl as well, in blue: the
    /// same picture in the pressing everybody has, rather than a different backdrop.
    ///
    /// **What is stored is left alone.** Support that lapses takes the gold down; it does not
    /// throw away the choice, so when support comes back the same backdrop is shown again without
    /// anybody having to remember what it was.
    ///
    /// - Parameter gold: whether this launch may show a supporter's picture. ``SupporterGround`` is
    ///   what answers it on the phone, and it is settled before the first frame.
    public static func standing(stored: String, gold: Bool) -> Choice {
        if stored == formerRPaMp { return .standard }
        if stored == formerNight { return .vinyl }

        return switch Choice(rawValue: stored) {
        case .gold: gold ? .gold : .vinyl
        case .some(let chosen): chosen
        case nil: .standard
        }
    }

    /// The id that older settings hold for RPaMp's ground.
    public static let formerRPaMp = "rpamp"

    /// The id that older settings hold for the night table.
    public static let formerNight = "night"
}
