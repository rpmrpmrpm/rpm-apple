import SwiftUI
import Observation
import RPMKit
import RPMArt
import RPMDesign

/// The colour the user gives the app's glass: the bubbles, the cards, the buttons, the switches and
/// the sliders. It is chosen on the Appearance settings and in the welcome's look step.
///
/// **The background's colour is the default** (``theme(_:)``): each background has a colour, so a
/// background and the glass on it go together like a theme. Choosing a background goes back to its
/// colour. The user can pick another colour, or none (``none``): the app's white frost on dark
/// glass. A colour is laid over that frost as a light wash, so text on it stays white and readable
/// whichever colour is chosen.
///
/// The colours offered are the profile badge's colours (``RPMProfileBadges/colours``), shown as the
/// same round bubbles as on the profile page, so the app and the badge can match.
///
/// It is stored under ``key`` as `#RRGGBB`, the badge's own form, as ``none``, or empty for the
/// background's colour. Every face that takes the colour
/// reads the key itself (`@AppStorage`), so a new choice shows everywhere at once.
///
/// **An album or a playlist on screen colours the glass with its cover** while it is shown
/// (``PageColour``). That colour comes before the user's: see ``shown(_:)``.
public enum AppColour {
    public static let key = "look.colour"

    /// What is stored for no colour: the app's own white frost. Empty is the background's colour.
    public static let none = "none"

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

    /// The colour the user's choice gives: the background's when nothing is chosen, none for
    /// ``none``, else the colour stored.
    @MainActor
    static func chosen(_ stored: String) -> Color? {
        stored.isEmpty ? Color(rgb: theme(BackdropTheme.shared.picture)) : colour(stored)
    }

    /// The colours offered, as 0xRRGGBB.
    public static var offered: [UInt32] { RPMProfileBadges.colours }

    /// The colour stored, or nil for none. Anything that cannot be read is none.
    public static func colour(_ stored: String) -> Color? {
        guard let value = value(stored) else { return nil }
        return Color(rgb: value)
    }

    /// The colour the glass is drawn in now: the page's on screen (``PageColour``), else the
    /// user's choice (``chosen(_:)``). Every face reads this.
    @MainActor
    static func shown(_ stored: String) -> Color? {
        PageColour.shared.current ?? chosen(stored)
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
        content.tint(AppColour.shown(stored) ?? RPMInk.white(0x88 / 255))
    }
}

extension View {
    /// Colours a switch or a slider in the colour the user chose (``AppColour``).
    public func rpmControlTint() -> some View {
        modifier(ControlColour())
    }
}

/// The round colour bubbles, as the profile page draws them for the badge: the background's own
/// colour first, then no colour, then each colour offered. The one chosen has a thick white ring.
struct AppColourBubbles: View {
    @AppStorage(AppColour.key) private var stored = ""

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                themeBubble
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

    /// The background's own colour, with the palette mark on it: the glass follows the background.
    private var themeBubble: some View {
        let picked = stored.isEmpty

        return Button {
            Haptics.pick()
            stored = ""
        } label: {
            Circle().fill(Color(rgb: AppColour.theme(BackdropTheme.shared.picture)))
                .overlay {
                    Text(Glyph.palette)
                        .font(RPMFont.icon(13))
                        .foregroundStyle(RPMInk.white(0xF2 / 255))
                }
                .frame(width: 34, height: 34)
                .overlay {
                    Circle().strokeBorder(RPMInk.white(picked ? 0xF2 / 255 : 0x44 / 255),
                                          lineWidth: picked ? 3 : 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.get("Settings_ColourTheme"))
        .accessibilityAddTraits(picked ? .isSelected : [])
    }

    /// One bubble. Nil is no colour: the app's own frost, with a line across it.
    private func bubble(_ value: UInt32?) -> some View {
        let picked = value == nil ? stored == AppColour.none : AppColour.value(stored) == value

        return Button {
            Haptics.pick()
            stored = value.map(RPMProfileBadges.wire) ?? AppColour.none
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

/// The colour of the album or playlist on screen, which the app's glass takes while it is shown:
/// the main colour of its cover (``AppColour/shown(_:)``).
///
/// Each page that has one holds it while it is on screen (`coloursGlass(_:page:)`), and lets it go
/// when it leaves. The last page to hold one wins, so a record opened from a playlist colours the
/// glass with the record, and going back gives the playlist's colour again.
///
/// **A page lets go when its back key is pressed**, and not only when it disappears. A page pushed
/// on a stack disappears at the end of the slide back, so the colour would stay on the page under
/// it for the whole slide. A page with a back key calls ``release(_:)`` before it goes back.
@MainActor
@Observable
final class PageColour {
    static let shared = PageColour()

    private var held: [(page: UUID, colour: Color)] = []

    /// The colour of the page shown last that has one, or nil.
    var current: Color? { held.last?.colour }

    /// Holds `colour` for `page`, last. Nil lets it go. Animated, so the glass changes colour
    /// smoothly as a page comes in or its cover arrives. Short, so it keeps up with the slide.
    func hold(_ colour: Color?, for page: UUID) {
        withAnimation(.easeOut(duration: 0.2)) {
            held.removeAll { $0.page == page }
            if let colour { held.append((page, colour)) }
        }
    }

    func release(_ page: UUID) {
        hold(nil, for: page)
    }
}

/// Holds a page's colour while the page is on screen. See ``PageColour``.
private struct HoldsPageColour: ViewModifier {
    let colour: Color?

    /// This page, among the pages on screen.
    let page: UUID

    func body(content: Content) -> some View {
        content
            .onAppear { PageColour.shared.hold(colour, for: page) }
            .onChange(of: colour) { _, now in PageColour.shared.hold(now, for: page) }
            .onDisappear { PageColour.shared.release(page) }
    }
}

extension View {
    /// Colours the app's glass with `colour` while this page is on screen. See ``PageColour``.
    ///
    /// - Parameter page: the page's own identity, kept in its `@State`. Its back key passes the
    ///   same one to ``PageColour/release(_:)``.
    func coloursGlass(_ colour: Color?, page: UUID) -> some View {
        modifier(HoldsPageColour(colour: colour, page: page))
    }
}

/// The background the app is drawn on, for its colour (``AppColour/theme(_:)``). Every face reads
/// the colour through ``AppColour/shown(_:)``, so this is observed: a new background recolours the
/// glass at once. The ground (``VinylGround``) keeps it up to date.
@MainActor
@Observable
final class BackdropTheme {
    static let shared = BackdropTheme()

    var picture: Backdrop.Choice

    private init() {
        picture = Backdrop.standing(stored: UserDefaults.standard.string(forKey: Backdrop.key) ?? "",
                                    gold: SupporterGround.isGold)
    }
}

extension SleeveColours {
    /// The colour a cover gives the glass: its main colour, lifted to the light a tint on dark glass
    /// needs (``GlassInk``), else its most vivid one.
    var glass: Color? {
        (dominant ?? highlight).map { GlassInk($0).color }
    }
}
