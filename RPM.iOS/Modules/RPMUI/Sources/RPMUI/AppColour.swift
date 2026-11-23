import SwiftUI
import RPMKit

/// The colour the user gives the app's glass: the bubbles, the cards, the buttons, the switches and
/// the sliders. It is chosen on the Appearance settings and in the welcome's look step.
///
/// **None is the default**, and it is the app as it is drawn without a choice: white frost on dark
/// glass. A colour is laid over that frost as a light wash, so text on it stays white and readable
/// whichever colour is chosen.
///
/// The colours offered are the profile badge's colours (``RPMProfileBadges/colours``), shown as the
/// same round bubbles as on the profile page, so the app and the badge can match.
///
/// It is stored as `#RRGGBB`, the badge's own form, under ``key``. Every face that takes the colour
/// reads the key itself (`@AppStorage`), so a new choice shows everywhere at once.
public enum AppColour {
    public static let key = "look.colour"

    /// The colours offered, as 0xRRGGBB.
    public static var offered: [UInt32] { RPMProfileBadges.colours }

    /// The colour stored, or nil for none. Anything that cannot be read is none.
    public static func colour(_ stored: String) -> Color? {
        guard let value = value(stored) else { return nil }
        return Color(rgb: value)
    }

    /// The stored colour as 0xRRGGBB, or nil for none.
    public static func value(_ stored: String) -> UInt32? {
        guard stored.count == 7, stored.hasPrefix("#"),
              let value = UInt32(stored.dropFirst(), radix: 16) else { return nil }
        return value
    }

    /// How strongly each kind of face takes the colour. Light washes, because white text and
    /// marks stand on every one of them.
    static let onGlass = 0.35
    static let onFill = 0.22
    static let onSection = 0.16
    static let onPill = 0.55
}

/// The colour of a switch: the chosen colour, or the quiet grey the app uses without one.
private struct ControlColour: ViewModifier {
    @AppStorage(AppColour.key) private var stored = ""

    func body(content: Content) -> some View {
        content.tint(AppColour.colour(stored) ?? RPMInk.white(0x88 / 255))
    }
}

extension View {
    /// Colours a switch or a slider in the colour the user chose (``AppColour``).
    public func rpmControlTint() -> some View {
        modifier(ControlColour())
    }
}

/// The round colour bubbles, as the profile page draws them for the badge: no colour first, then
/// each colour offered. The one chosen has a thick white ring.
struct AppColourBubbles: View {
    @AppStorage(AppColour.key) private var stored = ""

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                bubble(nil)
                ForEach(AppColour.offered, id: \.self) { value in
                    bubble(value)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    /// One bubble. Nil is no colour: the app's own frost, with a line across it.
    private func bubble(_ value: UInt32?) -> some View {
        let picked = AppColour.value(stored) == value

        return Button {
            Haptics.pick()
            stored = value.map(RPMProfileBadges.wire) ?? ""
        } label: {
            ZStack {
                if let value {
                    Circle().fill(Color(rgb: value))
                } else {
                    Circle().fill(RPMInk.white(0x24 / 255))
                    Capsule()
                        .fill(RPMInk.white(0x99 / 255))
                        .frame(width: 2, height: 22)
                        .rotationEffect(.degrees(45))
                }
            }
            .frame(width: 34, height: 34)
            .overlay {
                Circle().strokeBorder(RPMInk.white(picked ? 0xF2 / 255 : 0x44 / 255),
                                      lineWidth: picked ? 3 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == nil ? Loc.get("Settings_ColourNone")
                                         : RPMProfileBadges.wire(value ?? 0))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }
}

/// The settings card that chooses the colour of the app's glass.
struct AppColourCard: View {
    var body: some View {
        SettingsCardFrame(Glyph.palette, Loc.get("Settings_Colour")) {
            AppColourBubbles()
        }
    }
}
