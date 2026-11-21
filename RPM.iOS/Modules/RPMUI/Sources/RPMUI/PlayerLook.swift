import SwiftUI
import RPMKit

/// The switch for the moving bars beside the player's cover: the spectrum that moves with the music
/// (``NowPlayingSheet``). Some people find the movement too busy, so it can be turned off. The
/// Android phone has the same switch.
public enum PlayerBars {
    /// Where the switch is kept, in the standard user defaults. On when it was never set.
    public static let key = "player.bars"

    /// The value when the switch was never set.
    public static let initial = true
}

/// The player's look, on the Appearance settings: whether the bars beside the cover move with the
/// music. The card has its controls only, as on the Android phone.
struct PlayerLookCard: View {
    @AppStorage(PlayerBars.key) private var bars = PlayerBars.initial

    var body: some View {
        SettingsCardFrame(Glyph.play, Loc.get("Playlists_NowPlaying")) {
            Toggle(isOn: $bars) {
                Text(Loc.get("Settings_PlayerBars"))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0xB3 / 255))
            }
            .tint(RPMInk.white(0x88 / 255))
            .onChange(of: bars) { _, _ in Haptics.pick() }
        }
    }
}

/// The shape of a card on the settings page, for the cards that live in files of their own: a glyph
/// and a kicker, then the content. It draws the same card as `SettingsPage.card`; change both.
struct SettingsCardFrame<Content: View>: View {
    private let glyph: String
    private let kicker: String
    private let content: Content

    init(_ glyph: String, _ kicker: String, @ViewBuilder content: () -> Content) {
        self.glyph = glyph
        self.kicker = kicker
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                // The glyph has the same faint white as the kicker beside it and a small size, so
                // it works as a quiet mark and does not draw attention as an icon would.
                Text(glyph)
                    .font(RPMFont.icon(12))
                    .foregroundStyle(RPMInk.white(0x66 / 255))

                Text(kicker).rpmKicker()
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .rpmSection()
    }
}
