import SwiftUI
import RPMKit
import RPMDesign

/// The first-run hints: the desktop's coachmarks (`CoachmarkPainter`, `CoachTour`) on the phone.
///
/// One hint shows at a time. It points at a part of the screen with a curved arrow, and the rest of
/// the screen is dimmed around that part. Each hint is answered once, with Next or with the round
/// close key ("Don't show this again"), and is then never shown again (``FirstRun``).
///
/// There are two tours. The app's (``appTour``) points at the tabs and the mini player, and ends
/// with the card "And that's the tour!". The player's (``playerTour``) points at the parts of the
/// player the first time it is opened, and has no card of its own. A hint whose part is not on the
/// screen waits, and is not marked as seen. The keys are the Android app's, so a hint has one name
/// everywhere.
public enum CoachMark: String, CaseIterable, Sendable {
    case home
    case collection
    case radio
    case feed
    case settings
    case miniPlayer = "mini-player"

    case playerCover = "player-cover"
    case playerHeart = "player-heart"
    case playerLyrics = "player-lyrics"
    case playerQueue = "player-queue"
    case playerMenu = "player-menu"
    case playerSpeakers = "player-speakers"
    case playerGrip = "player-grip"

    /// The app's tour, in order. The mini player's hint waits until something is loaded.
    public static let appTour: [CoachMark] = [.home, .collection, .radio, .feed, .settings, .miniPlayer]

    /// The player's tour, in order. The speakers' hint is passed over where the player has no
    /// speaker key.
    public static let playerTour: [CoachMark] = [.playerCover, .playerHeart, .playerLyrics, .playerQueue,
                                                 .playerMenu, .playerSpeakers, .playerGrip]

    /// The key of the closing card, kept with the hints so it shows once. The desktop's `tour-done`.
    public static let done = "tour-done"

    /// The part of the screen the hint points at.
    public var target: CoachTarget {
        switch self {
        case .home: .tabHome
        case .collection: .tabLibrary
        case .radio: .tabRadio
        case .feed: .tabFeed
        case .settings: .tabSettings
        case .miniPlayer: .miniPlayer
        case .playerCover: .playerCover
        case .playerHeart: .playerHeart
        case .playerLyrics: .playerLyrics
        case .playerQueue: .playerQueue
        case .playerMenu: .playerMenu
        case .playerSpeakers: .playerSpeakers
        case .playerGrip: .playerGrip
        }
    }

    /// The key of the hint's words.
    var words: String {
        switch self {
        case .home: "Coach_Phone_Home"
        case .collection: "Coach_Phone_Collection"
        case .radio: "Coach_Phone_Radio"
        case .feed: "Coach_Phone_Feed"
        case .settings: "Coach_Phone_Settings"
        case .miniPlayer: "Coach_Phone_MiniPlayer"
        case .playerCover: "Coach_Player_Cover"
        case .playerHeart: "Coach_Player_Heart"
        case .playerLyrics: "Coach_Player_Lyrics"
        case .playerQueue: "Coach_Player_Queue"
        case .playerMenu: "Coach_Player_Menu"
        case .playerSpeakers: "Coach_Player_Speakers"
        case .playerGrip: "Coach_Player_Grip"
        }
    }
}

/// A part of the screen a hint can point at. A view says it is one with ``SwiftUI/View/coachTarget(_:)``.
public enum CoachTarget: String, Sendable {
    case tabHome = "tab.home"
    case tabLibrary = "tab.library"
    case tabRadio = "tab.radio"
    case tabFeed = "tab.feed"
    case tabSettings = "tab.settings"
    case miniPlayer = "mini-player"
    case playerCover = "player.cover"
    case playerHeart = "player.heart"
    case playerLyrics = "player.lyrics"
    case playerQueue = "player.queue"
    case playerMenu = "player.menu"
    case playerSpeakers = "player.speakers"
    case playerGrip = "player.grip"
}

extension RPMTab {
    /// The name the hints point at this tab by.
    var coachTarget: CoachTarget {
        switch self {
        case .home: .tabHome
        case .library: .tabLibrary
        case .feed: .tabFeed
        case .radio: .tabRadio
        case .settings: .tabSettings
        }
    }
}

/// Where the parts the hints point at are, in the screen's coordinates, by name. Read with
/// `overlayPreferenceValue` by the view that draws the hints (``CoachLayer``).
///
/// A part that is not in the view tree reports nothing, so a hint never points at nothing.
public struct CoachTargetFrames: PreferenceKey {
    public static let defaultValue: [CoachTarget: CGRect] = [:]

    public static func reduce(value: inout [CoachTarget: CGRect], nextValue: () -> [CoachTarget: CGRect]) {
        value.merge(nextValue()) { _, next in next }
    }
}

extension View {
    /// Reports this view's place on the screen to the first-run hints, under `target`.
    public func coachTarget(_ target: CoachTarget) -> some View {
        background {
            GeometryReader { box in
                Color.clear.preference(key: CoachTargetFrames.self,
                                       value: [target: box.frame(in: .global)])
            }
        }
    }
}

/// The look of the hints, which is the desktop's `CoachmarkPainter`.
enum CoachLook {
    /// The desktop's `RpmCyanBrush`: the rings, the arrows, the borders and the links.
    static let accent = RPMInk.cyan

    /// The dim over the rest of the screen: 0xA602050A.
    static let dim = Color(red: 0x02 / 255, green: 0x05 / 255, blue: 0x0A / 255).opacity(0xA6 / 255)

    /// The bubble's and the closing card's fill: the app's ground at 0xF7.
    static let panel = RPMInk.ground.opacity(0xF7 / 255)

    /// The close key's fill: the app's ground, solid.
    static let disc = RPMInk.ground

    /// How wide the bubble is, at most.
    static let bubbleWidth: CGFloat = 270

    /// How far the bubble stands from the part it points at; the arrow crosses this gap.
    static let reach: CGFloat = 48

    /// The least room between the bubble and the edge of the screen.
    static let edge: CGFloat = 14

    /// How far the cut-out reaches past the part on each side.
    static let pad: CGFloat = 6

    /// The ring round the cut-out.
    static let ringRadius: CGFloat = 8
    static let ringWidth: CGFloat = 1.5

    /// The arrow's line and the length of its head.
    static let arrowWidth: CGFloat = 2.5
    static let head: CGFloat = 14

    /// How long a hint takes to fade in.
    static let fade: Double = 0.3
}

/// The arrow from the bubble to the part: one bowed line, and a filled head at the part
/// (`CoachmarkPainter.Arrow`).
struct CoachArrow {
    let from: CGPoint
    let to: CGPoint

    /// Bows the line the other way: for a bubble over the part.
    let flip: Bool

    /// The bowed line, stopping short of the tip, under the head.
    var line: Path {
        guard let bend else { return Path() }
        var path = Path()
        path.move(to: from)
        path.addQuadCurve(to: bend.stop, control: bend.control)
        return path
    }

    /// The head, a filled triangle with its tip at ``to``.
    var tip: Path {
        guard let bend else { return Path() }
        let head = CoachLook.head
        let half = head * 0.55
        let back = CGPoint(x: to.x - bend.ux * head, y: to.y - bend.uy * head)
        var path = Path()
        path.move(to: to)
        path.addLine(to: CGPoint(x: back.x - bend.uy * half, y: back.y + bend.ux * half))
        path.addLine(to: CGPoint(x: back.x + bend.uy * half, y: back.y - bend.ux * half))
        path.closeSubpath()
        return path
    }

    /// The control point of the bow, where the line stops, and the direction it arrives in.
    private var bend: (control: CGPoint, stop: CGPoint, ux: CGFloat, uy: CGFloat)? {
        let dx = to.x - from.x
        let dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length >= 1 else { return nil }

        // The bow, across the line, as on the desktop: a sixth of its length, kept between 2 and 40.
        let bow = min(max(length * 0.16, 2), 40) * (flip ? -1 : 1)
        let control = CGPoint(x: (from.x + to.x) / 2 - dy / length * bow,
                              y: (from.y + to.y) / 2 + dx / length * bow)

        let tx = to.x - control.x
        let ty = to.y - control.y
        let reach = max(hypot(tx, ty), 1)
        let ux = tx / reach
        let uy = ty / reach
        let stop = CGPoint(x: to.x - ux * CoachLook.head * 0.6, y: to.y - uy * CoachLook.head * 0.6)
        return (control, stop, ux, uy)
    }
}
