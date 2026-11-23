import SwiftUI
import RPMKit

/// How the player looks when the phone is turned on its side. It is kept per device, under
/// ``key``. The Android phone has the same choice under the same key and values.
///
/// - ``classic``: the stage (``StageView``), with the turning record and its full-screen looks.
/// - ``modern``: the player itself (``NowPlayingSheet``), laid out for landscape: the cover on the
///   left half and the title, the seek bar and the keys on the right half, over the moving room.
public enum LandscapePlayer: String, CaseIterable, Sendable {
    case classic
    case modern

    /// Where the choice is kept, in the standard user defaults.
    public static let key = "player.landscape"

    /// The value when the choice was never made.
    public static let initial = LandscapePlayer.classic

    /// The name of the choice, as the settings card shows it.
    var name: String {
        switch self {
        case .classic: Loc.get("Settings_LandscapeClassic")
        case .modern: Loc.get("Settings_LandscapeModern")
        }
    }
}

/// What the Modern player on its side draws behind its cover, text and keys: the app's own room
/// (named Lava), or one of the stage's looks. It is kept per device, under ``key``.
///
/// The stored value is ``room`` for the room, and the look's raw value as text for a look. A stored
/// value that this build does not know reads as the room.
enum LandscapeVisual {
    /// Where the choice is kept, in the standard user defaults.
    static let key = "player.landscape.visual"

    /// The stored value of the room, which is also the value when nothing was chosen.
    static let room = "room"

    /// The looks offered: every look the stage offers, except the artwork. The cover is already
    /// on the screen, and the artist's photograph belongs to the stage.
    static var looks: [StageLook] { StageLook.offered.filter { $0 != .artwork } }

    /// The stored value of a look.
    static func stored(_ look: StageLook) -> String { String(look.rawValue) }

    /// The look a stored value names, or nil for the room.
    static func look(_ stored: String) -> StageLook? {
        guard let raw = Int(stored), let look = StageLook(rawValue: raw),
              looks.contains(look) else { return nil }
        return look
    }
}

/// The choice of how the player looks on its side, on the Appearance settings: Classic or Modern,
/// as a segmented pair under one line that says what the choice is for.
struct LandscapePlayerCard: View {
    @AppStorage(LandscapePlayer.key) private var chosen = LandscapePlayer.initial

    var body: some View {
        SettingsCardFrame(Glyph.phone, Loc.get("Settings_LandscapePlayer")) {
            Text(Loc.get("Settings_LandscapePlayerHint"))
                .font(RPMFont.display(13))
                .foregroundStyle(RPMInk.white(0xB3 / 255))
                .fixedSize(horizontal: false, vertical: true)

            Picker(Loc.get("Settings_LandscapePlayer"), selection: $chosen) {
                ForEach(LandscapePlayer.allCases, id: \.self) { style in
                    Text(style.name).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: chosen) { _, _ in Haptics.pick() }
        }
    }
}
