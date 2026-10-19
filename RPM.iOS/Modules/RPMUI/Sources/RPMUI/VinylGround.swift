import SwiftUI
import RPMSharedUI
import UIKit
import RPMKit
import RPMArt

/// The background of the whole app: the backdrop chosen in the profile. The default is
/// RPaMp's ground (``Backdrop/Choice/standard``). The name comes from the vinyl picture,
/// which is now one of the choices (the Vinyl tile).
///
/// The vinyl picture is the same one the Uno app uses. It is **drawn, not photographed**
/// (`scripts/make_vinyl_ground.py`). It is rendered at 1320 by 2868 from the geometry of
/// a real record: one groove pitch throughout, tracks separated by a single deeper
/// groove, and light that spreads out from the centre across the grooves, not along
/// them. The duotone matches the desktop's dialog headers, so both apps use the same
/// material.
///
/// Only one dark veil is drawn over the picture, 20 per cent black, the same as the
/// desktop. Do not add more overlays: stacked scrims make the app look like it is
/// behind smoked glass.
///
/// **There are two vinyl pressings, each with its own tile, and one is for supporters.**
/// Vinyl is the blue one, for everybody. Gold is the same picture in a different colour:
/// the same three records and the same lights in the same places, with the colour taken
/// from the desktop supporter backdrop `RPM.Desktop/Assets/background-gold.jpg`. A
/// supporter can use either. Whether this launch may use the gold is decided before
/// anything is drawn. It changes only at sign-in, never while the user is looking at a
/// screen: see ``SupporterGround``.
///
/// **The other choices are the desktop's own**: RPaMp's ground (the default) or the
/// Pegasus room, cut to this shape by `scripts/make_phone_backdrops.py`, and the sheet
/// music, cut by `scripts/make_sheet_music.py`. The desktop's table of records has no
/// tile here, because the vinyl is the phone's version of it. A choice is a tap by the
/// user, not data from the network, so it applies at once instead of at the next launch.
/// The launch-settled rule exists only to stop the picture changing under a user who did
/// not ask for it.
///
/// It shows only where a page has not drawn its own picture over it. An album page and
/// the player each show their own cover.
///
/// **Each page includes its own ground; the app does not include it once.** A
/// `NavigationStack` paints an opaque background over whatever is behind it, so a ground
/// placed under the whole app would never be seen. The image is decoded once and shared,
/// so drawing it on four pages costs four draws and one decoded picture.
@MainActor
public struct VinylGround: View {
    /// Which pressing this ground is. It is read when the view is created, not when it
    /// is drawn.
    ///
    /// It is stored instead of being looked up in `body` because a view with no fields
    /// compares equal to the previous one, so SwiftUI would never redraw it. A sign-in
    /// that switches to gold changes this value, so the new ground is a different view
    /// and is drawn. See ``SupporterGround``.
    private let gold: Bool

    /// Which picture was chosen. It is read from the user defaults, not passed down.
    ///
    /// Every page includes its own ground, so passing the choice down would mean passing
    /// it through eight pages. `AppStorage` watches the one key, and every ground on
    /// screen redraws when it changes.
    @AppStorage(Backdrop.key) private var chosen = ""

    public init() { gold = SupporterGround.isGold }

    public var body: some View {
        ZStack {
            // Under the plate, so any screen area the picture does not cover shows the
            // app's colour.
            RPMInk.ground

            Plate(picture: Backdrop.standing(stored: chosen, gold: gold))

            Rectangle().fill(Color.black.opacity(0x33 / 255))
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The background picture, laid out relative to the WINDOW and not to the view that
/// draws it.
///
/// **Why it is not simply `.aspectRatio(contentMode: .fill)`.** Fill crops against the
/// container, and the containers differ: the library screen is the whole window, while a
/// page inside the navigation stack is the window minus the navigation bars. The two
/// containers have different heights, and fill centres the part it cannot show, so the
/// arcs would sit about forty points higher on one screen than on the other and jump
/// when the screen changed.
///
/// So the picture is scaled to the window, and each view is told where the window is.
/// Every screen then uses the same scale and the same origin, and the background is one
/// picture instead of a separate crop per screen.
///
/// **The picture is aligned to the top of the window, not centred.** Any overflow (the
/// part beyond the tallest phone shape) goes at the bottom, because the quiet dark corner
/// at the top is where every page puts its title.
private struct Plate: View {
    let picture: Backdrop.Choice

    var body: some View {
        GeometryReader { proxy in
            if let plate = Vinyl.ground(picture) {
                // Where this container sits in the window. `.global` measures against
                // the window.
                let here = proxy.frame(in: .global)

                // Before the app has a key window, fall back to the container size.
                let window = RPMSafeArea.window == .zero ? proxy.size : RPMSafeArea.window

                let fill = max(window.width / plate.size.width,
                               window.height / plate.size.height)
                let size = CGSize(width: plate.size.width * fill,
                                  height: plate.size.height * fill)

                Image(uiImage: plate)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    // Start at the container's own corner, then move the picture to the
                    // window's: centred horizontally and aligned to the top.
                    .offset(x: (window.width - size.width) / 2 - here.minX, y: -here.minY)
                    .frame(width: proxy.size.width, height: proxy.size.height,
                           alignment: .topLeading)
            }
        }
        .clipped()
    }
}

/// The background pictures of the app.
///
/// Only the ground is loaded here. The record draws its own vinyl: see `VinylPressing`.
@MainActor
enum Vinyl {
    /// The requested picture. It is decoded on the first request and kept for the
    /// life of the app. One picture is behind every screen, and decoding about 800 KB of
    /// JPEG again on every tab change would waste time.
    ///
    /// **Only one picture is kept, not all five.** Each decoded picture is about 15 MB,
    /// and the user looks at only one. Keeping the ones they browsed past would hold about
    /// 60 MB of unused pictures. Browsing in the picker costs one decode per tile.
    static func ground(_ picture: Backdrop.Choice) -> UIImage? {
        let named = file(picture)
        if held?.named == named { return held?.image }

        guard let image = decode(named) else { return nil }
        held = (named, image)
        return image
    }

    private static var held: (named: String, image: UIImage)?

    /// The file for each choice. Vinyl and Gold are two colourings of one picture.
    /// Whether Gold is allowed is decided before this is called
    /// (``Backdrop/standing(stored:gold:)``).
    ///
    /// **Watch for moiré rings.** The pictures are 1320 pixels wide and a phone screen is
    /// narrower. The Uno app showed moiré when it scaled the groove pattern at paint
    /// time. It does not appear here, so the picture is drawn as it is. If rings appear,
    /// decode to the screen's own pixel width instead of using a filter.
    static func file(_ picture: Backdrop.Choice) -> String {
        switch picture {
        case .standard: "background-rpamp"
        case .vinyl: "background-vinyl"
        case .pegasus: "background-pegasus"
        case .sheetMusic: "background-sheet-music"
        case .gold: "background-vinyl-gold"
        }
    }

    /// The file bytes, for a tile that wants a small copy instead of the whole picture.
    ///
    /// `nonisolated` because it only reads a file. The tiles decode off the main thread,
    /// and a main-actor version would move the file read onto the thread that draws.
    nonisolated static func bytes(_ named: String) -> Data? {
        guard let url = Bundle.module.url(forResource: named, withExtension: "jpg") else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func decode(_ named: String) -> UIImage? {
        guard let data = bytes(named) else { return nil }
        return UIImage(data: data)
    }
}

/// One small backdrop for the row of tiles in the profile.
///
/// **It decodes its own small copy and does not use the full picture.** A ground is
/// 1320 by 2868 pixels and about 15 MB once decoded. Five of those, for a row of tiles
/// 62 points wide, would be about 75 MB for pictures nobody is using. This view decodes
/// each one at the size it is drawn, as `Thumbnail.of` does for every album cover on the
/// wall.
struct BackdropTile: View {
    let choice: Backdrop.Choice
    let width: Double
    let height: Double

    /// The size passed to the decode: the tile's LONG side in pixels, for the densest
    /// screen this app runs on. `Thumbnail.of` fits the whole picture inside the given
    /// number, so the short side would give a thumbnail smaller than the tile and it would
    /// be scaled up. The tile is decoded once for all phones, because the difference
    /// between 2x and 3x is only a few kilobytes.
    private var pixels: Int { Int(max(width, height) * 3) }

    @State private var picture: CGImage?

    /// A decoded picture returned from the detached decode task. A `CGImage` is immutable
    /// once created, and CoreGraphics allows reading it from another thread. The compiler
    /// cannot see that, so the wrapper is `@unchecked Sendable` (`CoverArt` does the same).
    private struct Decoded: @unchecked Sendable {
        let image: CGImage?
    }

    var body: some View {
        // The picture fills the tile and is clipped here, not by the caller: a
        // `scaledToFill` clipped only by its container still overflows the layout.
        ZStack {
            if let picture {
                Image(decorative: picture, scale: 1)
                    .resizable()
                    .scaledToFill()
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .task(id: choice) {
            let named = Vinyl.file(choice)

            // Off the main thread: this is a JPEG decode, and the row has five of them.
            let edge = pixels
            picture = await Task.detached(priority: .userInitiated) {
                guard let data = Vinyl.bytes(named) else { return Decoded(image: nil) }
                return Decoded(image: Thumbnail.of(data, edge: edge))
            }.value.image
        }
    }
}
