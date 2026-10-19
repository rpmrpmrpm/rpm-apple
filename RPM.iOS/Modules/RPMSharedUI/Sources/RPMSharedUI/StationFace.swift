import SwiftUI
import UIKit
import RPMKit
import RPMRadio
import RPMArt
import RPMDesign

/// A station's own logo, shown wherever a sleeve image would go: in a row, in the mini player, and
/// in the player's large tile.
///
/// **Every caller provides what to draw instead**, because most stations publish a logo, but
/// some logo addresses no longer work. An empty area looks like a hole, not a placeholder, and
/// the right placeholder differs between a 40-point row and a 260-point tile.
///
/// **A logo that comes with no background gets a generated background**, as on the desktop: a soft
/// figure in the logo's own hues, shifted away from its tone, that fills the whole square while
/// ``inset`` keeps the logo away from the edges. See ``StationGround``. The caller clips the square
/// to its own shape. This is done wherever a logo is shown, so the room behind it has something to
/// react to.
public struct StationFace<Fallback: View>: View {
    let station: RadioStation

    /// The size it is drawn at. It is also the size the image is kept at: images at these addresses
    /// range from a 16-pixel favicon to a 2000-pixel logo.
    let edge: CGFloat

    /// How far the logo is kept from the square's edges. The generated background fills the square.
    let inset: CGFloat

    /// Called with the colours of everything the square shows, including the generated background,
    /// once the logo has loaded. Where a room is lit from the square (the banner's card, the
    /// player), it uses these colours, because a station has no sleeve to read them from. Every
    /// caller must provide it, because only some callers light a room.
    let onWearing: (SleeveColours) -> Void

    @ViewBuilder var fallback: () -> Fallback

    public init(station: RadioStation, edge: CGFloat, inset: CGFloat,
                onWearing: @escaping (SleeveColours) -> Void,
                @ViewBuilder fallback: @escaping () -> Fallback) {
        self.station = station
        self.edge = edge
        self.inset = inset
        self.onWearing = onWearing
        self.fallback = fallback
    }

    @State private var logo: UIImage?

    /// The generated background behind a logo that has none of its own. It is nil for a logo that
    /// already fills its own square.
    @State private var ground: CGImage?

    /// The station that ``logo`` belongs to. A changed stamp keeps the old logo shown while the new
    /// one is fetched, and a different station clears it.
    @State private var logoOf: String?

    /// Whether it is worth making the request at all. See ``SmallPictures/of(_:edge:reach:)``.
    @Environment(\.rpmReach) private var reach

    /// The shared station state, including the stamp that changes when a logo changes. It is set at
    /// the root.
    @Environment(RadioState.self) private var radioState

    /// The identity of the fetch below. A new stamp means a new request, because the logo was
    /// changed in the admin.
    private struct Ask: Hashable {
        let station: String
        let stamp: String
    }

    public var body: some View {
        // What this face last wore is drawn on the first frame while the task below asks again. A
        // card that is built again (a carousel step, a row scrolled back) then shows its previous
        // logo and not the fallback for one frame. Only this station's logo is used: a recycled
        // row's state belongs to the previous station until the task clears it.
        let own = logoOf == station.uuid ? self.logo : nil
        let last = own == nil ? StationDress.last(station.uuid, edge: edge) : nil
        let drawnLogo = own ?? last?.logo
        let drawnGround = own != nil ? ground : last?.worn.ground

        ZStack {
            if let drawnGround {
                // Inside a `Color.clear` so the filled picture reports the square's size and not
                // its own. See the note in `HomeFeatureCard.face`.
                Color.clear
                    .overlay {
                        Image(decorative: drawnGround, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .clipped()
                    .transition(.opacity)
            }

            Group {
                if let drawnLogo {
                    Image(uiImage: drawnLogo)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    fallback()
                }
            }
            .padding(inset)
        }
        // The task is keyed on the station and not run on appear: rows are recycled as the list
        // scrolls, and the mini player stays in place while the dial moves. A logo fetched for the
        // previous station would be the wrong mark under this station's name. It is also keyed on
        // the stamp, so a logo changed in the admin is fetched again wherever it is on screen.
        .task(id: Ask(station: station.uuid, stamp: radioState.logoStamp)) {
            if logoOf != station.uuid {
                logo = nil
                ground = nil
            }
            let drawn = logoOf == station.uuid && logo != nil
                || StationDress.last(station.uuid, edge: edge) != nil

            guard let dressed = await StationDress.dress(station, edge: edge, state: radioState, reach: reach),
                  !Task.isCancelled
            else { return }

            // The logo and its background are set together. They fade in only if the first frame
            // did not already draw them from the last dressing. The same picture shown again
            // changes nothing on the screen.
            var put = Transaction()
            if !drawn { put.animation = .easeOut(duration: 0.25) }
            withTransaction(put) {
                logo = dressed.logo
                logoOf = station.uuid
                ground = dressed.worn.ground
            }
            onWearing(dressed.worn.colours)
        }
    }
}

/// What a station's square shows besides its logo: the generated background behind a logo that has
/// none, and the colours of the whole square for a room lit from them. It is computed once per logo
/// per launch, off the main thread, because the background is a blurred 320-pixel figure.
public enum StationDress {
    public struct Worn: Sendable {
        public let ground: CGImage?
        public let colours: SleeveColours
    }

    /// `NSCache` is thread-safe; `nonisolated(unsafe)` is needed for the reason ``SmallPictures``
    /// gives.
    private nonisolated(unsafe) static let held = NSCache<NSString, Held>()

    /// What a station's face last showed at a size: its logo and its dressing.
    public struct Last {
        public let logo: UIImage
        public let worn: Worn
    }

    private final class Kept {
        let last: Last
        init(_ last: Last) { self.last = last }
    }

    /// The last dressing of each station at each size. The key does not include the logo's stamp,
    /// so a face can read it before any request is made. If the logo has changed since, the new one
    /// is shown when the face's own request completes.
    private nonisolated(unsafe) static let lastWorn = NSCache<NSString, Kept>()

    /// What `station`'s face at `edge` points last showed, or nil. It is used for a face's first
    /// frame, and for a room lit from the face that is built in the same frame.
    public static func last(_ station: String, edge: CGFloat) -> Last? {
        lastWorn.object(forKey: "\(station)|\(Int(edge))" as NSString)?.last
    }

    /// A station's logo for a face of `edge` points, and its dressing, stored as the station's last
    /// dressing. It returns nil if no logo loads. Every ``StationFace`` calls it, and a screen can
    /// call it to have a face ready before the face is shown (the home banner).
    ///
    /// RPM's own copy is tried first, and is usually the only one needed: it is the logo that the
    /// API's crawl chose for the station, a 512-pixel image, available for about 72% of the
    /// directory's stations (42,750 of 59,654 at the time of writing). It comes before the
    /// directory's own addresses and does not replace them, as on the desktop, because the
    /// directory sometimes has a logo that the crawl could not choose. It goes through the API's
    /// transport, so it sends the app key and waits for a network like every other call.
    @MainActor
    public static func dress(_ station: RadioStation, edge: CGFloat, state: RadioState, reach: Reach) async -> Last? {
        let stamp = state.logoStamp
        if let own = await SmallPictures.of(
            key: "rpm|\(station.uuid)|\(stamp)", edge: edge * 3,
            fetch: { @MainActor in
                switch try await state.logo(for: station) {
                case .found(let data): return data
                case .none: return nil
                }
            }) {
            return await kept(station, edge: edge, logo: own, key: "rpm|\(stamp)")
        }

        // Try every logo that the directory lists, not just the first. A station usually has more
        // than one, and the first often fails to load. For example, NPO Radio 1's best stream
        // points at a Wikimedia file that refuses requests that do not come from a browser, while
        // a plain PNG on the station's own site is also in the list. See RadioResults.
        for said in station.logos {
            // Cancellation does not stop this loop by itself. A face recycled onto another station
            // would otherwise fetch the next address for nobody.
            guard !Task.isCancelled else { return nil }

            // Request the size that will be drawn, where the host resizes on request. A directory
            // entry names a picture at one size, and that size is whatever the contributor pasted.
            // iHeart's entries often ask for 32 pixels, which gives a blocky logo in a 40-point
            // area, even though the original image is larger. See RadioLogo.sized.
            let want = Int((edge * 3).rounded())
            guard let asked = RadioLogo.sized(said, edge: want),
                  let url = URL(string: asked)
            else { continue }

            if let found = await SmallPictures.of(url, edge: edge * 3, reach: reach) {
                return await kept(station, edge: edge, logo: found, key: url.absoluteString)
            }
        }
        return nil
    }

    @MainActor
    private static func kept(_ station: RadioStation, edge: CGFloat, logo: UIImage, key: String) async -> Last {
        let last = Last(logo: logo, worn: await of(station.uuid, logo: logo, key: key))
        lastWorn.setObject(Kept(last), forKey: "\(station.uuid)|\(Int(edge))" as NSString)
        return last
    }

    private final class Held {
        let worn: Worn
        init(_ worn: Worn) { self.worn = worn }
    }

    /// - Parameter key: identifies which picture of the station this is, so a changed logo is
    ///   dressed again.
    public static func of(_ station: String, logo: UIImage, key: String) async -> Worn {
        let name = "\(station)|\(key)" as NSString
        if let known = held.object(forKey: name) { return known.worn }

        guard let picture = logo.cgImage else { return Worn(ground: nil, colours: .none) }

        let worn = await Task.detached(priority: .utility) { () -> Worn in
            if StationGround.standsAlone(picture),
               let made = StationGround.ground(for: picture, identity: station) {
                return Worn(ground: made, colours: Thumbnail.colours(of: made))
            }
            return Worn(ground: nil, colours: Thumbnail.colours(of: picture))
        }.value

        held.setObject(Held(worn), forKey: name)
        return worn
    }
}
