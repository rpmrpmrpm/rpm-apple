import Foundation

/// The colour the user gives the app's glass, read from what is stored under ``key``.
///
/// **Nothing stored is no colour**: the app's white frost on dark glass. The user can pick the
/// background's own colour (``background``), so the glass and the background look like one theme,
/// or one of the profile badge's colours (``RPMProfileBadges/colours``), stored as `#RRGGBB`, the
/// badge's own form. Anything else that is stored is no colour too, so a value this version does not
/// know still shows the frost.
///
/// **A colour is a supporter feature.** For an account that is not a supporter's, every choice
/// shows as no colour (``value(on:supporter:)``).
public enum GlassColour: Equatable, Sendable {
    /// The app's white frost, with no colour.
    case none

    /// The colour of the background the app is drawn on (``theme(_:)``).
    case background

    /// One colour, as 0xRRGGBB.
    case colour(UInt32)

    /// Where the choice is kept. **Nowhere else names this string.**
    public static let key = "look.colour"

    /// What is stored for ``background``.
    public static let matchesBackground = "background"

    public init(stored: String) {
        if stored == Self.matchesBackground {
            self = .background
        } else if stored.count == 7, stored.hasPrefix("#"),
                  let value = UInt32(stored.dropFirst(), radix: 16) {
            self = .colour(value)
        } else {
            self = .none
        }
    }

    /// What is stored for this choice. No colour is stored as nothing, the default.
    public var stored: String {
        switch self {
        case .none: ""
        case .background: Self.matchesBackground
        case .colour(let value): RPMProfileBadges.wire(value)
        }
    }

    /// The colour as 0xRRGGBB when the app is drawn on `picture`, or nil for no colour.
    ///
    /// - Parameter supporter: whether the account has the supporter features
    ///   (``SupporterPlan/isSupporter``). A colour is a supporter feature, so for anyone else every
    ///   choice is no colour. The choice stays stored, and it comes back if the account becomes a
    ///   supporter. No default, so each caller says which plan it means.
    public func value(on picture: Backdrop.Choice, supporter: Bool) -> UInt32? {
        guard supporter else { return nil }

        return switch self {
        case .none: nil
        case .background: Self.theme(picture)
        case .colour(let value): value
        }
    }

    /// The colour each background gives the glass, so the two look like one theme. The colours are
    /// the badge's own blue, red, orange and yellow, and a grey for the grey background.
    public static func theme(_ picture: Backdrop.Choice) -> UInt32 {
        switch picture {
        case .standard, .vinyl: 0x2563EB
        case .pegasus: 0xD12A4E
        case .sheetMusic, .cocoa: 0xE0701B
        case .aero, .gold: 0xB8901F
        case .graphite: 0x8E939B
        }
    }
}
