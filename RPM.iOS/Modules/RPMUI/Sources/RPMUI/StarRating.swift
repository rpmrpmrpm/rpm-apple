import SwiftUI
import RPMKit

/// Five stars, in halves.
///
/// Port of `RPM.Desktop/Presentation/Controls/StarRating.cs`. **Half stars are drawn as
/// their own glyph, not faked with opacity.** A half-lit glyph stays readable at small
/// sizes (about eleven points), which a partly transparent star does not.
///
/// The value is in stars (0 to 5, in steps of 0.5). The API stores it doubled as an
/// integer; that conversion is done by the API layer, not by this control.
///
/// The same control shows an album's average, shows the verdict of a review, and takes
/// the user's own rating. It is interactive only when `onPick` is given.
public struct StarRating: View {
    private let value: Double
    private let size: CGFloat
    private let onPick: ((Double) -> Void)?

    public init(_ value: Double, size: CGFloat = 14, onPick: ((Double) -> Void)? = nil) {
        self.value = value
        self.size = size
        self.onPick = onPick
    }

    private static let gold = Color(red: 0xF2 / 255, green: 0xC1 / 255, blue: 0x4E / 255)

    /// Icon-font code points. A whole star is `f005`. A half star is `f5c0`
    /// (star-half-alt): the left half lit and the right half unlit.
    private static let whole = "\u{f005}"
    private static let half = "\u{f5c0}"

    public var body: some View {
        HStack(spacing: onPick == nil ? 1 : 2) {
            ForEach(0..<5, id: \.self) { at in
                star(at)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard let onPick else { return }
                        Haptics.tick()
                        onPick(Double(at) + 1)
                    }
                    // A long press on a star picks the half value below it. The desktop
                    // uses the pointer position across the glyph. A finger cannot give
                    // that, because a thumb covers the whole star.
                    .onLongPressGesture(minimumDuration: 0.3) {
                        guard let onPick else { return }
                        Haptics.tick()
                        onPick(Double(at) + 0.5)
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Loc.get("Rpm_Album_RatingOutOf", value.formatted()))
    }

    private func star(_ at: Int) -> some View {
        let lit = value - Double(at)

        return Text(lit >= 0.75 ? Self.whole : lit >= 0.25 ? Self.half : Self.whole)
            .font(RPMFont.icon(size))
            .foregroundStyle(lit >= 0.25 ? Self.gold : RPMInk.white(0x44 / 255))
            .frame(minWidth: size * (onPick == nil ? 1.25 : 1.9),
                   minHeight: onPick == nil ? size : size * 1.9)
    }
}
