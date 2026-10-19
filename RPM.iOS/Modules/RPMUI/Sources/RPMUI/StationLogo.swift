import SwiftUI
import RPMSharedUI
import UIKit
import RPMRadio
import RPMArt
import RPMDesign

/// The station's logo, on a dark background so that both a transparent PNG and a white
/// square look right.
///
/// Most stations publish a logo. When the logo link is broken, the view shows the
/// antenna glyph instead. A directory of tens of thousands of stations is easier to scan
/// by logo than by name.
///
/// **Fetched here rather than through `ArtworkStore`.** That store belongs to the cloud
/// library: it is keyed by record and shelf and backed by a disk cache of album covers.
/// A station favicon is a small file (a few kilobytes) from a third-party URL, so one
/// request per launch is enough.
struct StationLogo: View {
    let station: RadioStation

    /// The side length of the square logo background, in points.
    static let edge: CGFloat = 40

    var body: some View {
        let well = RoundedRectangle(cornerRadius: 6, style: .continuous)

        return ZStack {
            well.fill(Color.black.opacity(0x22 / 255))

            StationFace(station: station, edge: Self.edge, inset: 3, onWearing: { _ in }) {
                Text(Glyph.radio)
                    .font(RPMFont.icon(15))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: Self.edge, height: Self.edge)
        .clipShape(well)
        .overlay { well.strokeBorder(RPMInk.cardBorder, lineWidth: 1) }
    }
}
