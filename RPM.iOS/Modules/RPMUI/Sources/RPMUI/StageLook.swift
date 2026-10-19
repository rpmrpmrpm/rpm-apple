import SwiftUI
import RPMKit

/// What the stage can draw behind the words.
///
/// This is the desktop's gallery, as the Uno app lists it. The names and the lines under them are
/// the Uno app's own strings (`Rpm_Stage_Artwork`, `Viz_RibbonSeaName` and the rest), copied
/// as written. The line of description is what helps a person choose between a plate of sand
/// and a sea of ribbons, not the name.
public enum StageLook: Int, CaseIterable, Identifiable, Sendable {
    /// The artist's photograph.
    case artwork = 0

    /// The ribbon sea: contour lines over an open swell.
    case ribbon = 1

    /// The flight through the block field.
    case blocks = 2

    /// Chladni's plate of sand: the desktop's own built-in.
    case plate = 3

    /// The slice through a four-dimensional lattice, marched.
    case lattice = 4

    /// Two mirrors and one strut, marched.
    case kaleidoscope = 5

    /// The folded tunnel, cut to the record, marched.
    case tunnel = 6

    /// The spectrum, mirrored into four.
    case butterfly = 7

    /// A flower of light on a golden spiral.
    case bloom = 8

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .artwork: Loc.get("Details_Art")
        case .ribbon: Loc.get("Viz_RibbonSeaName")
        case .blocks: Loc.get("Viz_LowFlowName")
        case .plate: Loc.get("Rpm_Stage_Plate")
        case .lattice: Loc.get("Viz_LatticeName")
        case .kaleidoscope: Loc.get("Viz_KaleidoscopeName")
        case .tunnel: Loc.get("Viz_TunnelName")
        case .butterfly: Loc.get("Viz_ButterflyName")
        case .bloom: Loc.get("Viz_BloomName")
        }
    }

    public var detail: String {
        switch self {
        case .artwork:
            Loc.get("Rpm_Stage_ArtworkDesc")
        case .ribbon:
            Loc.get("Viz_RibbonSeaDesc")
        case .blocks:
            Loc.get("Viz_LowFlowDesc")
        case .plate:
            Loc.get("Viz_ChladniDesc")
        case .lattice:
            Loc.get("Viz_LatticeDesc")
        case .kaleidoscope:
            Loc.get("Viz_KaleidoscopeDesc")
        case .tunnel:
            Loc.get("Viz_TunnelDesc")
        case .butterfly:
            Loc.get("Viz_ButterflyDesc")
        case .bloom:
            Loc.get("Viz_BloomDesc")
        }
    }

    public var glyph: String {
        switch self {
        case .artwork: "\u{f03e}"
        case .ribbon: "\u{f83e}"
        case .blocks: "\u{f1b3}"
        case .plate: "\u{f192}"
        case .lattice: "\u{f00a}"
        case .kaleidoscope: "\u{f2dc}"
        case .tunnel: "\u{f0b2}"
        case .butterfly: "\u{f57b}"
        case .bloom: "\u{f06c}"
        }
    }

    /// Whether this app can draw it. A look that is listed and does nothing is worse than one
    /// that is not listed: the picker is where somebody decides, and a row that shows the
    /// artwork instead looks like a fault.
    ///
    /// Every look is drawn now. The property is kept because the picker asks it, and because a
    /// look that is added later may not be ported on the day it is listed.
    public var isDrawn: Bool { true }

    /// The looks the picker offers, which are the ones that draw.
    public static var offered: [StageLook] { allCases.filter(\.isDrawn) }
}

/// Which look the stage is set to, over everything else on the screen.
///
/// This is the app's own panel and not a menu, and it is the same panel as the speaker picker,
/// because it is the same kind of choice. A system menu looks like nothing else on this screen,
/// it cannot carry the line of description that helps a person choose between a plate of sand
/// and a sea of ribbons, and the check gutter that it forces on every row is a theme resource
/// that an app cannot override.
struct LookPicker: View {
    let showing: StageLook
    let onPick: (StageLook) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0x99 / 255)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack(spacing: 0) {
                header

                Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)

                // **Not `ShortScroll`**, which counts rows at a fixed height and says in its own
                // documentation that a list of wrapping rows must not use it. These rows are a
                // name over a paragraph, and the paragraph is what helps a person choose between
                // a plate of sand and a sea of ribbons.
                //
                // A plain stack inside it, not a lazy one. A `LazyVStack` outside a scroll view
                // lays out and draws correctly but then takes no taps at all, so the panel would
                // open, look right, and do nothing when a row is pressed. There are only nine
                // rows, so being lazy gains nothing in any case.
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(StageLook.offered) { look in
                            Button { onPick(look) } label: { line(look) }
                                .buttonStyle(RowPress())
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
            }
            .frame(width: 340)
            // The panel takes the height that the turned phone leaves and no more. Nine looks
            // with a paragraph each are taller than a landscape screen, so on a phone the screen
            // is the limit. The cap is for larger screens, such as a tablet.
            .frame(maxHeight: 420)
            .padding(.vertical, 24)
            .rpmGlassCard(radius: 18)
        }
    }

    private var header: some View {
        HStack {
            Text(Loc.get("Rpm_Stage_Visualiser"))
                .font(RPMFont.displayBold(15))
                .foregroundStyle(.white)

            Spacer()

            Text(showing.name)
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0x88 / 255))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func line(_ look: StageLook) -> some View {
        let on = look == showing

        return HStack(alignment: .top, spacing: 14) {
            Text(look.glyph)
                .font(RPMFont.icon(15))
                .foregroundStyle(on ? RPMInk.cyan : RPMInk.white(0xB3 / 255))
                .frame(width: 20)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(look.name)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)

                if !look.detail.isEmpty {
                    Text(look.detail)
                        .font(RPMFont.display(12))
                        .foregroundStyle(RPMInk.white(0x88 / 255))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if on {
                Text(Glyph.check)
                    .font(RPMFont.icon(14))
                    .foregroundStyle(.white)
                    .padding(.top, 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}
