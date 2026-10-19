import SwiftUI
import RPMAudio
import RPMArt

/// The foot of the app: what is playing, and where to go.
///
/// Two floating Liquid Glass shapes over the page: the mini player as a capsule, and the tabs as
/// a capsule under it. There is no solid bar behind them. The page scrolls underneath and shows
/// through the glass. Before iOS 26 the same two shapes use the app's frost (`RPMFrost`).
public struct RPMChrome: View {
    private let player: Player
    private let art: CoverArt?
    private let onOpen: () -> Void

    @Binding private var showing: RPMTab

    public init(player: Player, art: CoverArt?, showing: Binding<RPMTab>,
                onOpen: @escaping () -> Void) {
        self.player = player
        self.art = art
        self._showing = showing
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(spacing: 8) {
            if MiniPlayer.hasSomethingToSay(player) {
                MiniPlayer(player: player, art: art, onOpen: onOpen)
                    .rpmGlass(Capsule())
            }

            RPMTabBar(showing: $showing)
        }
        .padding(.horizontal, Self.edge)
        // The shapes stand `gapBelow` above the bottom edge of the screen. This is inside the
        // home indicator's inset, not above all of it, as the system tab bar does.
        .padding(.bottom, Self.gapBelow - RPMSafeArea.bottom)
        // The height of the foot, for the pages that a `safeAreaInset` cannot reach. It is
        // measured after the padding above, because a page has to clear the box that the chrome
        // really occupies.
        .background {
            GeometryReader { box in
                Color.clear.preference(key: ChromeHeight.self, value: box.size.height)
            }
        }
    }

    /// How far the shapes stand in from the sides of the screen, and how far the capsule stands up
    /// from the bottom on a phone with rounded corners. The figure is the same both ways, so the
    /// capsule's ends run parallel to the screen's corners, as the system's floating bars do.
    private static let edge: CGFloat = 16

    /// The distance from the bottom of the tab capsule to the bottom of the screen. It is 8 points
    /// on a phone with a home button, whose screen has square corners.
    @MainActor private static var gapBelow: CGFloat {
        RPMSafeArea.bottom > 0 ? edge : 8
    }
}
