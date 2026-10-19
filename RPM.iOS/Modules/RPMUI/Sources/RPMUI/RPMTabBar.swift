import SwiftUI
import RPMKit

/// Which screen the app is on.
///
/// Home, the records, the radio and the account: four tabs. The playlists are not a tab. They are
/// a way of reading the library, beside the records and the artists. See ``LibraryMode``.
public enum RPMTab: String, CaseIterable, Sendable {
    case home
    case library
    case radio
    case profile

    var glyph: String {
        switch self {
        case .home: return Glyph.home
        case .library: return Glyph.library
        case .radio: return Glyph.radio
        case .profile: return Glyph.profile
        }
    }

    var name: String {
        switch self {
        case .home: return Loc.get("Home_Heading")
        case .library: return Loc.get("Settings_Library")
        case .radio: return Loc.get("Rpm_Tab_Radio")
        case .profile: return Loc.get("Rpm_Tab_Profile")
        }
    }
}

/// Where to go: four tabs in a floating glass capsule, laid out by `RPMChrome`.
///
/// This is not a `TabView`: the mini player floats directly above the capsule, and the system tab
/// bar owns the bottom of the screen and leaves no room for it.
public struct RPMTabBar: View {
    @Binding private var showing: RPMTab

    /// Shared by the tabs so the selection pill slides from the old tab to the new one.
    @Namespace private var pill

    public init(showing: Binding<RPMTab>) { self._showing = showing }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(RPMTab.allCases, id: \.self) { tab in
                Button { showing = tab } label: { face(tab) }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(showing == tab ? .isSelected : [])
            }
        }
        // Animated here and not with `withAnimation` at the tap, so the pill slides and the page
        // that the tab opens does not.
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showing)
        .padding(4)
        .rpmGlass(Capsule())
    }

    private func face(_ tab: RPMTab) -> some View {
        TabFace(lit: showing == tab, label: tab.name, layout: .stacked, pill: pill) {
            Text(tab.glyph).font(RPMFont.icon(17))
        }
    }
}

/// One tab: a mark over its name, on a white pill while it is the one showing. The app's tab
/// capsule and the library's row of views both use this view, so the two look like the same
/// kind of control.
struct TabFace<Mark: View>: View {
    /// How the mark and the name are arranged.
    enum Layout {
        /// The mark over the name, in the app's tab capsule.
        case stacked

        /// The mark beside the name, smaller. The name shows only while the tab is chosen: the
        /// chosen tab takes the room that is left, and the other tabs are as wide as their mark.
        /// This is the library's row of views.
        case inline
    }

    let lit: Bool
    let label: String
    let layout: Layout

    /// The container's namespace. The pill is matched on it, so a change of tab slides the pill
    /// across instead of fading one out and another in.
    let pill: Namespace.ID
    @ViewBuilder let mark: () -> Mark

    var body: some View {
        let marked = mark()
            .foregroundStyle(lit ? .white : RPMInk.white(0x99 / 255))

        // The system font and not Cabin, to match the Uno app's tab labels, which use the system
        // font.
        let named = Text(label)
            .font(.system(size: layout == .stacked ? 10 : 12, weight: lit ? .semibold : .regular))
            .foregroundStyle(lit ? .white : RPMInk.white(0x80 / 255))
            .lineLimit(1)

        return Group {
            switch layout {
            case .stacked: VStack(spacing: 2) { marked; named }
            case .inline: HStack(spacing: 6) { marked; if lit { named } }
            }
        }
        .frame(width: layout == .inline && !lit ? 52 : nil)
        .frame(maxWidth: layout == .inline && !lit ? nil : .infinity,
               minHeight: layout == .stacked ? 52 : 32)
        .background {
            if lit {
                Capsule()
                    .fill(RPMInk.white(0x24 / 255))
                    .matchedGeometryEffect(id: "pill", in: pill)
            }
        }
        .contentShape(Rectangle())
    }
}
