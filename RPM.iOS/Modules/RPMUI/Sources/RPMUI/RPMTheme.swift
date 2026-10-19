import SwiftUI
import RPMSharedUI
import RPMKit
import CoreText
import Foundation

/// The app's own ink and surfaces. They come from `RPM.Mobile/Themes/RPMTheme.xaml`.
///
/// **Not named `RPM`**, because that is the app target's own module name. A type with that name
/// would be ambiguous with the module in every file of the app itself.
///
/// Every value here is the one in that file, converted from ARGB hex. The values are not
/// re-chosen and not rounded to something tidier: the phone app and the desktop app should look
/// the same, and a card that is a little lighter on one of them looks like a mistake on the
/// other.
public enum RPMInk {
    /// The ground the whole app is drawn on. `#0E1520`.
    public static let ground = Color(red: 0x0E / 255, green: 0x15 / 255, blue: 0x20 / 255)

    /// `#FF6B6B`. It is the only colour in the app that carries a meaning.
    public static let red = Color(red: 1, green: 0x6B / 255, blue: 0x6B / 255)

    /// The one accent colour that the app has of its own. It is used rarely: for the supporter's
    /// metal and nothing else. All other colour comes from the record that is playing.
    public static let cyan = Color(red: 0x04 / 255, green: 0xC8 / 255, blue: 1)

    /// The wash on the selected key of a two-key switch: the desktop's `SelectedSegment`, the
    /// deep end of the brand gradient (`#0371D0`) at alpha 0x3A.
    static let selectedWash = Color(red: 0x03 / 255, green: 0x71 / 255, blue: 0xD0 / 255)
        .opacity(0x3A / 255)

    /// White at some fraction, which is what almost everything here is. The alpha is the leading
    /// hex byte of the XAML value divided by 255, so a value can be read from the theme file and
    /// typed in directly.
    public static func white(_ alpha: Double) -> Color { Color.white.opacity(alpha) }

    // ── glass ──

    /// The wash over the live blur, and the ONE value for it. Every card uses it, and so does the
    /// chrome at the foot before iOS 26 (on iOS 26 the chrome is Liquid Glass).
    ///
    /// It is black and not the desktop's white `#38FFFFFF`, because what is under it is a plain
    /// dark blur (see `RPMFrost`) and not the system's material. A white frost over the material
    /// would be two frosts, and the card would be a grey slab with the record hidden behind it.
    static let glassWash = Color.black.opacity(0x22 / 255)

    /// A settings section's fill: white at 7%, flat, over the page. This is the iOS 26 grouped
    /// section, which is a plain panel and not glass.
    static let sectionFill = white(0x12 / 255)

    /// The card's edge: almost transparent at the top, with a little more light along the bottom.
    /// This is the opposite way round from the sheen, and it makes a flat rectangle look like it
    /// has thickness.
    static let cardBorder = LinearGradient(
        stops: [.init(color: white(0x05 / 255), location: 0),
                .init(color: white(0x12 / 255), location: 0.5),
                .init(color: white(0x24 / 255), location: 1)],
        startPoint: .top, endPoint: .bottom)

    /// The hairline every glass face wears. `#22FFFFFF`.
    static let glassEdge = white(0x22 / 255)

    /// A brighter frost, for the primary button.
    static let primaryFace = white(0x33 / 255)

    /// The quiet one, for any button that is not the single main action of a screen.
    static let ghostFace = white(0x14 / 255)
}

// ── glass on glass ──

/// Whether a view is drawn on a glass surface. Every glass surface in this file sets it for what
/// it holds, and every glass face in this file reads it.
///
/// **No glass on glass.** This is Apple's rule for Liquid Glass (WWDC25, "Meet Liquid Glass"): a
/// control placed on glass uses a fill, not a second layer of the material. So a face on glass
/// draws ``GlassFill`` instead, which is the translucent white and hairline that the faces use
/// before iOS 26. Without this, the buttons, keys and fields of a popup card would be glass on
/// a glass card.
///
/// It is file-private, so only the faces and surfaces in this file can read or set it. A new glass
/// face belongs in this file for that reason.
///
/// The value flows to everything a surface holds, overlays included. Every popup card is mounted
/// over a page or the root view, and that keeps its own card as glass: one mounted inside another
/// card or inside the chrome's capsule is drawn as a fill.
private struct OnGlassKey: EnvironmentKey {
    static let defaultValue = false
}

fileprivate extension EnvironmentValues {
    var onGlass: Bool {
        get { self[OnGlassKey.self] }
        set { self[OnGlassKey.self] = newValue }
    }
}

/// What a glass face draws on glass, and what the button and field faces draw before iOS 26: a
/// flat translucent fill with the glass hairline, and a white veil while pressed.
private struct GlassFill<S: InsettableShape>: ViewModifier {
    let shape: S
    let fill: Color
    let pressed: Bool

    func body(content: Content) -> some View {
        content
            .background {
                shape.fill(fill)
                if pressed { shape.fill(RPMInk.white(0x28 / 255)) }
            }
            .overlay { shape.strokeBorder(RPMInk.glassEdge, lineWidth: 1) }
    }
}

// ── the card ──

/// A panel that floats over the page: a picker, a sheet's body, a notice.
///
/// Liquid Glass on iOS 26 and later. Before iOS 26 it is the app's frost (`RPMFrost`, the same
/// blur that the chrome uses) with the wash and the card's edge over it.
///
/// Everything on the card is on glass, so its buttons, keys and fields draw a fill and not glass.
/// See `OnGlassKey`.
public struct GlassCard: ViewModifier {
    private let radius: CGFloat

    @Environment(\.onGlass) private var onGlass

    public init(radius: CGFloat = 18) { self.radius = radius }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    public func body(content: Content) -> some View {
        let held = content.environment(\.onGlass, true)

        if onGlass {
            held.modifier(GlassFill(shape: shape, fill: RPMInk.ghostFace, pressed: false))
        } else if #available(iOS 26, *) {
            held.glassEffect(.regular, in: shape)
        } else {
            held
                .background {
                    RPMFrost().clipShape(shape)
                    shape.fill(RPMInk.glassWash)
                }
                .overlay { shape.strokeBorder(RPMInk.cardBorder, lineWidth: 1) }
                .clipShape(shape)
        }
    }
}

extension View {
    public func rpmGlassCard(radius: CGFloat = 18) -> some View {
        modifier(GlassCard(radius: radius))
    }

    /// A settings section: a flat translucent panel with no border and no glass, as iOS 26 draws
    /// the section of a grouped list. Use it for content on a page. ``rpmGlassCard(radius:)`` is
    /// for what floats over a page.
    public func rpmSection() -> some View {
        background(RPMInk.sectionFill,
                   in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// ── buttons ──

/// A glass face in the button's own rounded rectangle.
///
/// On iOS 26 and later it is Liquid Glass, which reacts to a press itself. The primary weight is
/// tinted white so that it stands out from the ghost one. Before iOS 26 it is a frosted face with
/// a hairline, and a press shows as a white veil. The stock button lights up in the system
/// accent, which this design does not use, so the stock button is not used.
///
/// On a glass card it is the frosted face on every iOS version. See `OnGlassKey`.
public struct RPMGlassButton: ButtonStyle {
    public enum Weight { case primary, ghost }

    @Environment(\.isEnabled) private var enabled

    private let weight: Weight
    private let radius: CGFloat
    private let height: CGFloat
    private let stretches: Bool
    private let inset: CGFloat

    /// - Parameters:
    ///   - stretches: whether it takes the whole width it is offered. True for the one key that
    ///     a screen is about, such as Play or Sign in. **False beside another key**: a button as
    ///     wide as the space it happens to get has a size that says nothing about what it does.
    public init(_ weight: Weight = .ghost, radius: CGFloat = 10, height: CGFloat = 44,
                stretches: Bool = true, inset: CGFloat = 20, size: CGFloat = 15) {
        self.weight = weight
        self.radius = radius
        self.height = height
        self.stretches = stretches
        self.inset = inset
        self.size = size
    }

    /// Set here and not by the caller: a `ButtonStyle` puts its font on the label, which is inside
    /// whatever the call site asked for, so a `.font` on the button never wins.
    private let size: CGFloat

    private var ink: Color { weight == .primary ? RPMInk.white(0xF5 / 255) : RPMInk.white(0xF0 / 255) }

    public func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return configuration.label
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(ink)
            // The glass stays lit and only the label greys out. This is the desktop's rule: a
            // disabled button that goes dark looks like a hole in the card.
            .opacity(enabled ? 1 : 0.35)
            // Padding INSIDE the fill, not outside it. Done the other way, the button asks for
            // the whole width it was offered and then adds `inset` points on each side. In a
            // scroll view that makes the page too wide, and everything centred in it sits off
            // to one side.
            .padding(.horizontal, inset)
            .frame(maxWidth: stretches ? .infinity : nil, minHeight: height)
            .contentShape(shape)
            .modifier(Face(shape: shape, weight: weight, pressed: configuration.isPressed))
    }

    private struct Face: ViewModifier {
        let shape: RoundedRectangle
        let weight: Weight
        let pressed: Bool

        @Environment(\.onGlass) private var onGlass

        private var fill: GlassFill<RoundedRectangle> {
            GlassFill(shape: shape, fill: weight == .primary ? RPMInk.primaryFace : RPMInk.ghostFace,
                      pressed: pressed)
        }

        func body(content: Content) -> some View {
            let held = content.environment(\.onGlass, true)

            if onGlass {
                held.modifier(fill)
            } else if #available(iOS 26, *) {
                held.glassEffect(weight == .primary
                                     ? .regular.tint(RPMInk.primaryFace).interactive()
                                     : .regular.interactive(),
                                 in: shape)
            } else {
                held.modifier(fill)
            }
        }
    }
}

/// A round glass key: close, back, the stage's keys. The label brings its own glyph, size and
/// colour; this style sets the circle and the glass.
public struct RPMGlassKey: ButtonStyle {
    private let edge: CGFloat

    public init(edge: CGFloat = 40) { self.edge = edge }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: edge, height: edge)
            .contentShape(Circle())
            .rpmGlass(Circle())
            // Liquid Glass reacts to a press itself; the frost before iOS 26 does not.
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// The back key: the chevron on a glass circle. Every page and sheet that steps back uses this
/// one, so they cannot drift apart.
public struct RPMBackKey: View {
    /// The space between the key and a title beside it.
    public static let besideTitle: CGFloat = 12

    private let label: String
    private let action: () -> Void

    /// - Parameter label: what VoiceOver reads. Each page says where back goes, so it is passed in.
    public init(label: String, action: @escaping () -> Void) {
        self.label = label
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(Glyph.back)
                .font(RPMFont.icon(15))
                .foregroundStyle(RPMInk.white(0xB8 / 255))
        }
        .buttonStyle(RPMGlassKey(edge: 40))
        .accessibilityLabel(label)
    }
}

extension View {
    /// Floats a back key over the top left of a page with no header, in the row that
    /// ``RPMLayout/backRow`` keeps free under the status bar.
    public func rpmFloatingBack(_ key: RPMBackKey) -> some View {
        overlay(alignment: .topLeading) {
            key
                .frame(height: RPMLayout.backRow)
                .padding(.leading, RPMLayout.margin)
        }
    }
}

/// The chrome's glass in `shape`. See ``SwiftUI/View/rpmGlass(_:)``.
private struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S

    @Environment(\.onGlass) private var onGlass

    func body(content: Content) -> some View {
        let held = content.environment(\.onGlass, true)

        if onGlass {
            held.modifier(GlassFill(shape: shape, fill: RPMInk.ghostFace, pressed: false))
        } else if #available(iOS 26, *) {
            held.glassEffect(.regular.interactive(), in: shape)
        } else {
            held.background {
                ZStack {
                    RPMFrost()
                    shape.fill(RPMInk.glassWash)
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(RPMInk.white(0x1A / 255), lineWidth: 1) }
            }
        }
    }
}

extension View {
    /// The chrome's glass in `shape`: Liquid Glass on iOS 26 and later, and the app's frost with a
    /// hairline edge before it. On another glass surface it is a fill instead (see `OnGlassKey`).
    func rpmGlass<S: InsettableShape>(_ shape: S) -> some View {
        modifier(GlassSurface(shape: shape))
    }

    /// A row of plain header keys on one glass capsule, the way iOS groups the buttons
    /// in a toolbar. The keys inside keep `.plain` and a 40-point square frame.
    public func rpmGlassGroup() -> some View {
        padding(.horizontal, 2).rpmGlass(Capsule())
    }
}

// ── text ──

extension View {
    /// The small line under a title: quiet, semibold, and set solid.
    ///
    /// **Solid on purpose.** The Uno app's own style asks for 0.08 em of letter spacing here, but
    /// its renderer does not show it: "Continue with" on its sign-in card is drawn with no
    /// spacing at all. If the value is used as written, Core Text spreads every letter apart,
    /// which looks like spaced-out text beside a title that is not. The same applies to
    /// `RPMFont.headerTracking`.
    public func rpmKicker() -> some View {
        font(.system(size: 11, weight: .semibold))
            .tracking(0)
            .foregroundStyle(RPMInk.white(0x88 / 255))
    }
}

/// A text field's face: the ghost button's glass, in the field's own rounded rectangle.
///
/// Liquid Glass on iOS 26 and later, as every key in the app is, so a field and the button
/// beside it are one material. Before iOS 26 it is the ghost button's frosted face and hairline.
/// The field does not draw its own dark fill or a hairline that brightens towards the bottom,
/// because that looks like altered glass.
///
/// On a glass card it is the ghost face on every iOS version, as the buttons beside it are.
/// See `OnGlassKey`.
public struct RPMFieldFace: ViewModifier {
    private let radius: CGFloat

    @Environment(\.onGlass) private var onGlass

    public init(radius: CGFloat) { self.radius = radius }

    public func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let held = content.environment(\.onGlass, true)

        if onGlass {
            held.modifier(GlassFill(shape: shape, fill: RPMInk.ghostFace, pressed: false))
        } else if #available(iOS 26, *) {
            held.glassEffect(.regular.interactive(), in: shape)
        } else {
            held.modifier(GlassFill(shape: shape, fill: RPMInk.ghostFace, pressed: false))
        }
    }
}

/// A field on its glass face, sized to the 44pt touch target.
///
/// **A fixed height, not a minimum.** A field never changes height between empty and typed in.
public struct RPMFieldStyle: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
        content
            .font(.system(size: 15))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .modifier(RPMFieldFace(radius: 10))
    }
}

/// The search box with a clear key inside it, shared by the records wall and the artists page.
///
/// **One height, empty or typed in.** The clear key shows only while there is text. If the key
/// were taller than the line of text, the box would grow on the first letter typed. The height is
/// set here and the key is drawn inside it, so a field never grows.
public struct RPMSearchBox: View {
    /// The box's height, the same as the glass close key that the pages put beside it.
    public static let height: CGFloat = 38

    @Binding private var text: String
    private let prompt: String
    private let clearLabel: String
    private let typing: FocusState<Bool>.Binding

    public init(text: Binding<String>, prompt: String, clearLabel: String,
                typing: FocusState<Bool>.Binding) {
        _text = text
        self.prompt = prompt
        self.clearLabel = clearLabel
        self.typing = typing
    }

    public var body: some View {
        HStack(spacing: 6) {
            TextField("", text: $text,
                      prompt: Text(prompt).foregroundStyle(RPMInk.white(0x77 / 255)))
                .font(RPMFont.display(14))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(typing)
                .submitLabel(.search)
                // The words are searched as they are typed, so Return has nothing left to
                // submit: it hides the keyboard and leaves the results visible.
                .onSubmit { typing.wrappedValue = false }

            // Only with something in it, as the system's own search field does: a cross on an
            // empty box is a key that cannot do anything.
            if !text.isEmpty {
                Button {
                    text = ""
                    typing.wrappedValue = true
                } label: {
                    Text("\u{f057}")
                        .font(RPMFont.icon(13))
                        .foregroundStyle(RPMInk.white(0x77 / 255))
                        .frame(width: 28, height: Self.height)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(clearLabel)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .frame(height: Self.height)
        .rpmFieldFace(radius: 8)
    }
}

extension View {
    public func rpmField() -> some View { modifier(RPMFieldStyle()) }

    /// The face alone, for a field that lays out its own insides: a search box with a clear
    /// key in it.
    public func rpmFieldFace(radius: CGFloat) -> some View { modifier(RPMFieldFace(radius: radius)) }
}

// ── type ──

/// The app's faces, and the two glyph sets.
///
/// **Registered at runtime and not declared in the app's plist.** The fonts belong to this
/// package, and a package cannot write the app's `Info.plist`. The documented way in is
/// `CTFontManagerRegisterFontsForURL`, and the name to use afterwards is read from the file and
/// not written in the code. A family name with one wrong character falls back to the system
/// face and gives no warning.
public enum RPMFont {
    /// The body and display face. `Cabin`, the desktop's own.
    public static func display(_ size: CGFloat) -> Font { face(.cabinMedium, size) }
    public static func displayBold(_ size: CGFloat) -> Font { face(.cabinBold, size) }

    /// The tab and page titles. `Thiamine RPM` draws its capitals at 0.247 of the em, against
    /// 0.70 for Cabin. The same size number is therefore nearly three times smaller in it, so
    /// this face is never given a body-text size.
    public static func header(_ size: CGFloat = 96) -> Font { face(.thiamine, size) }

    /// The letter spacing for the title face, which is none.
    ///
    /// **The face is already fitted.** The Uno app asks for 0.06 em on this same style, and the
    /// desktop app asks for the same on its dial labels, but neither renders it the way Core Text
    /// does. Here, even a third of that value spells the title out letter by letter. Drawn solid,
    /// "library" reads as a word and the tight letter pairs that the face was drawn with stay
    /// intact.
    ///
    /// It is kept as a function and not removed from the pages, so the spacing is one value in
    /// one place if this face is ever replaced by one that needs some.
    public static func headerTracking(_ size: CGFloat = 96) -> CGFloat { 0 }

    /// How much of the title face's descent a word leaves unused, in points.
    ///
    /// **The face reserves its descent for every word.** Thiamine's descent is 0.185 of the em,
    /// and the letters y, g and j reach all of it, so "library" uses the whole descent and
    /// "artists" uses none. If this is not corrected, the line under a title with no descender
    /// sits as far below the letters as the line under "library" sits below the tail of the y,
    /// and the two pages look like two different layouts.
    ///
    /// It is measured from the word's own glyphs and not assumed, so a title in any of the five
    /// languages gives its own answer.
    public static func headerDescentSlack(_ said: String, size: CGFloat = 96) -> CGFloat {
        loaded.descentSlack(said, size: size)
    }

    /// How far across the word the last letter that reaches below the baseline ends, in points
    /// from the word's start. Zero for a word with no descender.
    ///
    /// For ``PageHeading``, which sets the line under a title beside the last descender and not
    /// below it. It is measured from the word's own glyphs, like the slack above.
    public static func headerDescenderEnd(_ said: String, size: CGFloat = 96) -> CGFloat {
        loaded.descenderEnd(said, size: size)
    }

    /// Font Awesome, solid and hollow. They are two separate faces, which is how a heart can show
    /// filled or empty without a change of colour, size or place.
    public static func icon(_ size: CGFloat) -> Font { face(.solid, size) }
    public static func iconOutline(_ size: CGFloat) -> Font { face(.regular, size) }

    /// The brand marks. They have their own face, separate from the solid one.
    public static func brand(_ size: CGFloat) -> Font { face(.brands, size) }

    public static var brandAvailable: Bool { name(of: .brands) != nil }

    // ── the files ──

    enum Face: String, CaseIterable {
        case cabinMedium = "Cabin-Medium"
        case cabinBold = "Cabin-Bold"
        case thiamine = "ThiamineRPM"
        case solid = "fa-solid-900"
        case regular = "fa-regular-400"
        case brands = "fa-brands-400"

        var suffix: String { self == .thiamine ? "otf" : "ttf" }
    }

    /// The registered name of the bold body face, for the one drawing that sets text into a
    /// picture and not into a view: see ``PlaylistFrame``.
    ///
    /// **The name and not a `Font`.** A cover's name is measured before it is drawn (the size is
    /// whatever makes a gauge as tall as the band), and SwiftUI's `Font` cannot be measured. It
    /// is nil where the face did not load, and the caller then asks for the system face instead
    /// of drawing nothing.
    static var boldFace: String? { name(of: .cabinBold) }

    private static func face(_ which: Face, _ size: CGFloat) -> Font {
        guard let name = name(of: which) else { return .system(size: size) }
        return .custom(name, size: size)
    }

    /// Each face is loaded once, on first use. A face that nobody asks for is never read from
    /// disk. On a phone that is the difference between a launch that reads about two megabytes
    /// of fonts and one that reads about eighty kilobytes.
    private static let loaded = Registry()

    private static func name(of face: Face) -> String? { loaded.name(of: face) }

    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var known: [Face: String?] = [:]

        /// Measured words, by what was measured and at what size. A title is measured on every
        /// pass of its header's body, and the answer for one word never changes.
        private var measured: [String: CGFloat] = [:]

        func name(of face: Face) -> String? {
            lock.withLock { name(of: face, locked: true) }
        }

        /// - Parameter locked: passed in and not defaulted, because the lock is not recursive
        ///   and only the caller knows whether it already holds the lock. `descentSlack` measures
        ///   inside the lock and needs the face's name there.
        func name(of face: Face, locked: Bool) -> String? {
            if let already = known[face] { return already }

            let found = Self.register(face)
            known[face] = found
            return found
        }

        /// The part of the face's descent that this word does not reach into.
        ///
        /// `useGlyphPathBounds` asks for the ink and not the line box. That is the whole point:
        /// the line box has the same depth for every word.
        func descentSlack(_ said: String, size: CGFloat) -> CGFloat {
            lock.withLock {
                let asked = "\(size)|\(said)"
                if let already = measured[asked] { return already }

                let answer = Self.slack(said, size: size, name: name(of: .thiamine, locked: true))
                measured[asked] = answer
                return answer
            }
        }

        func descenderEnd(_ said: String, size: CGFloat) -> CGFloat {
            lock.withLock {
                let asked = "end|\(size)|\(said)"
                if let already = measured[asked] { return already }

                let answer = Self.end(said, size: size, name: name(of: .thiamine, locked: true))
                measured[asked] = answer
                return answer
            }
        }

        /// The right-hand edge of the ink of the last glyph whose ink goes below the baseline.
        /// The font of each run is used, so a letter drawn from a fallback face is measured in
        /// that face.
        private static func end(_ said: String, size: CGFloat, name: String?) -> CGFloat {
            guard let name else { return 0 }

            let font = CTFontCreateWithName(name as CFString, size, nil)
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: said, attributes: [.font: font]))

            var end: CGFloat = 0
            for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
                let count = CTRunGetGlyphCount(run)
                guard count > 0 else { continue }

                let attributes = CTRunGetAttributes(run) as NSDictionary
                let runFont = attributes[kCTFontAttributeName] as! CTFont? ?? font

                var glyphs = [CGGlyph](repeating: 0, count: count)
                var positions = [CGPoint](repeating: .zero, count: count)
                var ink = [CGRect](repeating: .zero, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
                CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
                CTFontGetBoundingRectsForGlyphs(runFont, .horizontal, glyphs, &ink, count)

                // Half a point below the baseline, so a round letter that dips slightly under it
                // is not counted as a descender.
                for i in 0..<count where ink[i].minY < -0.5 {
                    end = max(end, positions[i].x + ink[i].maxX)
                }
            }
            return end
        }

        private static func slack(_ said: String, size: CGFloat, name: String?) -> CGFloat {
            guard let name else { return 0 }

            let font = CTFontCreateWithName(name as CFString, size, nil)
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: said, attributes: [.font: font]))
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)

            return max(0, CTFontGetDescent(font) - max(0, -ink.minY))
        }

        private static func register(_ face: Face) -> String? {
            // Cabin Bold ships in RPMSharedUI, which uses it to set the text in the generated
            // lists' frames.
            guard let url = Bundle.module.url(forResource: face.rawValue, withExtension: face.suffix)
                    ?? SharedFaces.url(face.rawValue, extension: face.suffix),
                  let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                    as? [CTFontDescriptor],
                  let first = descriptors.first
            else { return nil }

            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            return CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
        }
    }
}

/// The glyphs this app draws, named by what they are and not by their codepoint.
///
/// They are escaped and not pasted: these are private-use codepoints, and a raw one in a source
/// file is lost as soon as an editor changes the file's encoding.
public enum Glyph {
    public static let apple = "\u{f179}"
    public static let google = "\u{f1a0}"
    public static let play = "\u{f04b}"
    public static let shuffle = "\u{f074}"
    public static let heart = "\u{f004}"
    public static let record = "\u{f51f}"
    public static let back = "\u{f053}"
    public static let explicit = "\u{f26c}"
    public static let pause = "\u{f04c}"

    /// Step to the next track, for a bar with no room. The transport's own keys are the wider
    /// pair below.
    public static let next = "\u{f051}"
    public static let previous = "\u{f048}"

    public static let forward = "\u{f04e}"
    public static let backward = "\u{f04a}"

    /// Stop. This is a decision and not a transport key, and the stage is the one screen with
    /// room to offer it.
    public static let stop = "\u{f04d}"

    /// Back to portrait, off the stage.
    public static let compress = "\u{f066}"

    /// Keeps the stage's chrome visible instead of letting it hide.
    public static let pin = "\u{f08d}"
    public static let more = "\u{f141}"
    public static let search = "\u{f002}"
    public static let sort = "\u{f0dc}"

    /// Which order a list is in. ``sort`` is different: it is the caret on a box that opens a
    /// menu. The desktop's radio pane uses this glyph for the same button.
    public static let sortAmount = "\u{f160}"
    /// Font Awesome's `tags`, for the genres view of the library.
    public static let genres = "\u{f02c}"
    public static let refresh = "\u{f2f1}"

    /// A tick, for the row that is already the current choice.
    public static let check = "\u{f00c}"

    /// The download key on an album page, and the other two glyphs for its three states.
    public static let download = "\u{f019}"
    public static let downloaded = "\u{f058}"
    public static let stuck = "\u{f06a}"
    public static let home = "\u{f015}"
    public static let library = "\u{f001}"

    /// One song. This is the desktop's mark for a track in the quick selection, and it is the
    /// same note that the library tab uses.
    public static let song = "\u{f001}"
    public static let playlists = "\u{f8c9}"

    /// A place and not a list. It is the only row on the playlists tab that goes somewhere
    /// instead of opening something.
    public static let folder = "\u{f07b}"

    /// The chevron on a row that steps into something.
    public static let into = "\u{f054}"

    /// The two ways the playlists are read: covers in a grid, or rows in a list. This is the
    /// desktop's own pair, on the segment above its tree.
    public static let grid = "\u{f00a}"
    public static let rows = "\u{f03a}"

    public static let plus = "\u{f067}"
    public static let grip = "\u{f7a4}"
    public static let remove = "\u{f2ed}"

    /// What is playing, as a list. It is not the transport's play mark: this stands for the queue
    /// itself.
    public static let queue = "\u{f8d9}"

    public static let cloud = "\u{f0c2}"

    /// A picture, for the card that chooses the app's background.
    public static let picture = "\u{f03e}"
    public static let speaker = "\u{f028}"

    /// A balance scale, for volume levelling. The desktop's Sound settings put the same glyph
    /// beside it.
    public static let levelling = "\u{f24e}"
    public static let phone = "\u{f3cd}"
    public static let about = "\u{f05a}"

    /// The About screen's links. A sheet of paper for a licence whose text ships, an arrow out of
    /// a box for terms that are only ever hosted by their publisher, a chain for a project's own
    /// page, and a terminal for an offer of source.
    public static let license = "\u{f15c}"
    public static let outward = "\u{f35d}"
    public static let link = "\u{f0c1}"
    public static let code = "\u{f121}"
    public static let radio = "\u{f519}"
    public static let profile = "\u{f007}"
}


// ── where the phone is ──



// ── what can be played here ──

/// Which records can be played **right now**: all of them while the phone is online, and only
/// the ones with a track on the phone while it is not.
///
/// It is one value handed down the tree and not a question that each tile works out, so every
/// tile and every row greys out by the same rule. The rule reads two facts that each hold
/// whenever they are asked, the settled network reading and what the download book holds, so a
/// tile drawn at any moment shows the right answer.
public struct PlayableHere: Equatable, Sendable {
    public let isOnline: Bool

    /// The keys of albums with at least one track on the phone.
    public let onPhone: Set<String>

    public init(isOnline: Bool, onPhone: Set<String>) {
        self.isOnline = isOnline
        self.onPhone = onPhone
    }

    /// Everything plays. A preview, or a screen drawn before the app has the real answer, must
    /// assume this, or it greys out a whole wall that works.
    public static let everything = PlayableHere(isOnline: true, onPhone: [])

    public func canPlay(_ albumKey: String) -> Bool { isOnline || onPhone.contains(albumKey) }
}

private struct PlayableHereKey: EnvironmentKey {
    static let defaultValue = PlayableHere.everything
}

extension EnvironmentValues {
    public var rpmPlayable: PlayableHere {
        get { self[PlayableHereKey.self] }
        set { self[PlayableHereKey.self] = newValue }
    }
}

/// The drag handle at the top of a panel that is pulled down to close: the system sheet's own
/// grabber, 36 by 5 points in the tertiary label colour. It is drawn here because the player and
/// the queue are not system sheets and so do not get the system's one.
struct Grabber: View {
    var body: some View {
        Capsule()
            .fill(Color(uiColor: .tertiaryLabel))
            .frame(width: 36, height: 5)
    }
}
