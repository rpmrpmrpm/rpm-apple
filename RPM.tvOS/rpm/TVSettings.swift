import Foundation
import Observation
import RPMAudio
import RPMKit

/// The player's layouts, in the order the settings step through them (as the desktop's PegasusLayout).
enum PlayerView: String, CaseIterable, Sendable {
    /// The record in the middle, the words down the left, the spectrum to the right.
    case spread
    /// The record in the middle and the words under it.
    case centred
    /// The room alone.
    case room
}

/// How bright and how saturated the screens are drawn (as the Android TV's `PictureLook`). The
/// softer looks exist because colours can look too bright on an HDR television, which shows SDR at
/// its own brightness. `light` multiplies every colour, so white is that share of full; `saturation`
/// pulls colours toward grey.
enum PictureLook: String, CaseIterable, Sendable {
    case standard, softer, muted

    var light: Double {
        switch self {
        case .standard: 1
        case .softer: 0.85
        case .muted: 0.78
        }
    }

    var saturation: Double { self == .muted ? 0.8 : 1 }
}

/// What the collection screens are drawn on (as the Android TV's `PageBackground`). The moving room
/// is meant for the now playing screen and the desktop's still backdrops for the pages. The
/// player always has the moving room. `still` and `pegasus` are the desktop's backdrops of those names,
/// `dark` is a flat anthracite, `moving` the room.
enum PageBackground: String, CaseIterable, Sendable {
    /// The desktop's Default backdrop (`background-rpamp.jpg`).
    case still
    case pegasus
    case dark
    case moving

    /// The picture's resource name in the app, or nil for a background that is not a picture.
    var picture: String? {
        switch self {
        case .still: "backdrop-default"
        case .pegasus: "backdrop-pegasus"
        case .dark, .moving: nil
        }
    }
}

/// The settings the TV keeps: the layout the player opens on, whether the performance stats show,
/// after how many minutes without a key the screens make way for the room (as on the Android TV),
/// and volume levelling (as on the phone). All are stored in the user defaults.
///
/// The levelling is changed through ``TVModel``, which tells the engine at the same time; the
/// setters here only store.
@MainActor
@Observable
final class TVSettings {
    private let store: UserDefaults

    /// The screensaver's choices in minutes, in the order a key press steps through them. 0 is off.
    static let screensaverChoices = [0, 1, 2, 5, 10, 15, 30]
    private static let screensaverDefault = 2

    private(set) var defaultView: PlayerView
    private(set) var showStats: Bool
    private(set) var screensaverMinutes: Int
    /// Standard by default, which lays nothing over the screens.
    private(set) var picture: PictureLook
    /// The desktop's Default backdrop is the default, as on the Android TV.
    private(set) var background: PageBackground
    /// Whether the albums screen is the carousel rather than the grid. The default is the grid.
    private(set) var albumCarousel: Bool
    /// Whether the sung lyric line lights word by word. Off by default, and for supporters only
    /// (``TVModel/karaokeOn``). The setting is stored for anyone else, but has no effect.
    private(set) var karaoke: Bool
    /// Album is the default, as on the phone and the desktop.
    var levelling: NormalizeMode {
        didSet { store.set(levelling.rawValue, forKey: "tv.levelling") }
    }
    /// Off is the default, as on the desktop.
    var levelsClassical: Bool {
        didSet { store.set(levelsClassical, forKey: "tv.levelling.classical") }
    }
    /// The rate asked for, in kilobits. ``AudioLadder/original`` (0) means the original file, which
    /// is also the phone's default. The rate that is served is this value checked against what the
    /// account may have (``TVModel/settleTheRate()``), so the stored value is the rate asked for,
    /// not the rate served.
    var kilobits: Int {
        didSet { store.set(kilobits, forKey: "tv.kilobits") }
    }

    init(store: UserDefaults) {
        self.store = store
        defaultView = store.string(forKey: "tv.player.view").flatMap(PlayerView.init(rawValue:)) ?? .centred
        showStats = store.bool(forKey: "tv.stats.shown")
        let minutes = store.object(forKey: "tv.screensaver.minutes") as? Int
        screensaverMinutes = minutes.flatMap { Self.screensaverChoices.contains($0) ? $0 : nil }
            ?? Self.screensaverDefault
        picture = store.string(forKey: "tv.picture").flatMap(PictureLook.init(rawValue:)) ?? .standard
        background = store.string(forKey: "tv.background").flatMap(PageBackground.init(rawValue:)) ?? .still
        albumCarousel = store.bool(forKey: "tv.albums.carousel")
        karaoke = store.bool(forKey: "tv.karaoke")
        levelling = store.string(forKey: "tv.levelling").flatMap(NormalizeMode.init(rawValue:)) ?? .album
        levelsClassical = store.bool(forKey: "tv.levelling.classical")
        kilobits = (store.object(forKey: "tv.kilobits") as? Int) ?? AudioLadder.original
    }

    func nextDefaultView() {
        let all = PlayerView.allCases
        defaultView = all[(all.firstIndex(of: defaultView)! + 1) % all.count]
        store.set(defaultView.rawValue, forKey: "tv.player.view")
    }

    func switchStats() {
        showStats.toggle()
        store.set(showStats, forKey: "tv.stats.shown")
    }

    func switchKaraoke() {
        karaoke.toggle()
        store.set(karaoke, forKey: "tv.karaoke")
    }

    func switchAlbumView() {
        albumCarousel.toggle()
        store.set(albumCarousel, forKey: "tv.albums.carousel")
    }

    func nextPicture() {
        let all = PictureLook.allCases
        picture = all[(all.firstIndex(of: picture)! + 1) % all.count]
        store.set(picture.rawValue, forKey: "tv.picture")
    }

    func nextBackground() {
        let all = PageBackground.allCases
        background = all[(all.firstIndex(of: background)! + 1) % all.count]
        store.set(background.rawValue, forKey: "tv.background")
    }

    func nextScreensaver() {
        let all = Self.screensaverChoices
        screensaverMinutes = all[((all.firstIndex(of: screensaverMinutes) ?? 0) + 1) % all.count]
        store.set(screensaverMinutes, forKey: "tv.screensaver.minutes")
    }
}
