import SwiftUI
import RPMKit

/// "AD" cut out of a small filled rectangle, beside a station that carries advertising.
///
/// The desktop's `AdsBadge` (RPM.Desktop/Themes/Generic.xaml): 19 by 13 in the radio
/// list, corner 2.5, filled at 0x8C white, bold letters. The desktop paints the letters
/// in the colour of the pane behind them; here they are cut out of the fill, so the
/// surface shows through whatever it is.
///
/// Its absence means nothing: most stations say nothing either way. See `RadioAds`.
struct AdsBadge: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(RPMInk.white(0x8C / 255))

            Text("AD")
                .font(RPMFont.text(9, weight: .bold))
                .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: 19, height: 13)
        .accessibilityElement()
        .accessibilityLabel(Loc.get("Radio_CarriesAds"))
    }
}

extension View {
    /// The AD mark in the bottom-right corner of a station's square, for a tile whose name is
    /// centred or narrow and has no room for the mark beside it. The mark sits on a dark plate,
    /// because the square can be any colour and the letters are cut out of the mark.
    @ViewBuilder
    func adsCorner(_ shown: Bool, inset: CGFloat = 6) -> some View {
        overlay(alignment: .bottomTrailing) {
            if shown {
                AdsBadge()
                    .padding(3)
                    .background(Color.black.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(inset)
            }
        }
    }
}
