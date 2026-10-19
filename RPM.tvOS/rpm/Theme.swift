import SwiftUI
import RPMKit
import RPMSharedUI

/// The TV's colours. They match the desktop app's inks: white at the opacities the desktop uses for
/// its lines.
enum Ink {
    static let words = Color.white
    static let card = Color.white.opacity(0xF2 / 255)
    static let artist = Color.white.opacity(0xB3 / 255)
    static let dim = Color.white.opacity(0x99 / 255)
    static let album = Color.white.opacity(0x80 / 255)
    static let well = Color.white.opacity(0x22 / 255)
    static let hairline = Color.white.opacity(0x26 / 255)

    /// The background colour under everything. It is used before the room is drawn.
    static let ground = Color(red: 0x0E / 255, green: 0x15 / 255, blue: 0x20 / 255)

    /// The flat shade that every collection screen sits on over the room. It is the same as the
    /// desktop's `#73000000`.
    static let scrim = Color.black.opacity(0x73 / 255)

    static let loved = Color(red: 1, green: 0x3B / 255, blue: 0x5C / 255)
    /// The colour of the tuned station's square on the dial. No other icon uses it. Every other
    /// icon is white.
    static let cyan = Color(red: 0x04 / 255, green: 0xC8 / 255, blue: 1)
    /// The colour of a review's stars.
    static let gold = Color(red: 0xE8 / 255, green: 0xC0 / 255, blue: 0x6A / 255)
    /// The colour of a station's mark on the dial while it reconnects. It matches the Android TV
    /// app's `#FFA82B`.
    static let amber = Color(red: 1, green: 0xA8 / 255, blue: 0x2B / 255)
    static let failed = Color(red: 1, green: 0x8A / 255, blue: 0x80 / 255)
}

/// Type sizes in points, for a 1920 x 1080 TV screen read from about three metres. They match the
/// Android TV sizes at the same scale, set in SF Pro, the system font.
enum Size {
    static let heading: CGFloat = 38
    static let cardTitle: CGFloat = 27
    static let cardLine: CGFloat = 24
    static let row: CGFloat = 29
    static let rowLine: CGFloat = 24
    static let note: CGFloat = 29
    static let small: CGFloat = 22

    /// The screen margins. tvOS keeps 80 points clear at the sides and 60 at the top and bottom.
    static let side: CGFloat = 80
    static let top: CGFloat = 60
    /// Where a page that does not scroll starts. It is below the sidebar's pill, which ends at 110
    /// points, with the same gap that scrolled screens leave under it.
    static let belowPill: CGFloat = 140
}

extension Font {
    static func tv(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// The top bar of a screen. The count of items is on the left, and the keys (such as order and
/// favourites) are on the right. The sidebar pill above it already names the screen, so the screen
/// has no title of its own. Every screen has the same height, with keys or without, so the content
/// starts at the same place.
struct PageBar<Keys: View>: View {
    static var height: CGFloat { 66 }

    let count: String
    @ViewBuilder let keys: () -> Keys

    init(_ count: String, @ViewBuilder keys: @escaping () -> Keys) {
        self.count = count
        self.keys = keys
    }

    var body: some View {
        HStack(spacing: 20) {
            Text(count)
                .font(.tv(Size.row))
                .foregroundStyle(Ink.dim)
            Spacer()
            keys()
        }
        .frame(height: Self.height)
        .padding(.horizontal, Size.side)
        .focusSection()
    }
}

extension PageBar where Keys == EmptyView {
    init(_ count: String) {
        self.init(count) { EmptyView() }
    }
}

/// A section heading on the collection screens.
struct Heading: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.tv(Size.heading, .semibold))
            .foregroundStyle(Ink.card)
            .padding(.horizontal, Size.side)
    }
}

/// A message on a screen, such as an empty state. The text is centred.
struct Message: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.tv(Size.note))
            .foregroundStyle(Ink.dim)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 120)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The E mark shown after the title of an explicit track.
struct ExplicitMark: View {
    var side: CGFloat = 26

    var body: some View {
        Text("E")
            .font(.system(size: side * 0.62, weight: .bold))
            .foregroundStyle(.black.opacity(0.85))
            .frame(width: side, height: side)
            .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

/// The mark beside a supporter's name: a heart and the word, in gold. It uses the same metal as the
/// desktop's `SupporterBadge` and the phone's `SupporterMark` (`SupporterMetal`). It is twice the
/// phone's size, to match a name at row size. The caller decides whether to show it. There is no
/// look for a non-supporter.
struct SupporterMark: View {
    var body: some View {
        let pill = Capsule(style: .continuous)
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 16))
            Text(Loc.get("Rpm_Profile_PlanSupporter"))
                .font(.tv(20, .medium))
        }
        .foregroundStyle(SupporterMetal.ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background { pill.fill(SupporterMetal.face) }
        .overlay { pill.strokeBorder(SupporterMetal.rim, lineWidth: 2) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Loc.get("Rpm_Profile_PlanSupporter"))
    }
}

/// Formats a time as a track list shows it: minutes and seconds, with hours when there are any.
func clock(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
}

/// Formats the time left as the seek bar shows it. Minutes always have two digits, with hours when
/// there are any.
func remaining(_ seconds: Double) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    let hours = total / 3600, minutes = (total % 3600) / 60, rest = total % 60
    return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%02d:%02d", minutes, rest)
}

extension View {
    /// Colours a glass key's icon with `tint` when the colour carries a meaning, such as a
    /// favourite or an active filter. Nil keeps the key's own colour. That colour turns dark when
    /// the focus lights the glass. A white icon stays white on the lit glass and is hard to read,
    /// so use a tint instead.
    @ViewBuilder
    func keyTint(_ tint: Color?) -> some View {
        if let tint { foregroundStyle(tint) } else { self }
    }
}
