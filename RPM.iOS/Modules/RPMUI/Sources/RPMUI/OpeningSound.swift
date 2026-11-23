import AVFoundation
import SwiftUI
import RPMKit

/// The short sound rpm plays as it opens: the desktop's opening sound (`AppSound.PlayOpen`,
/// `rpm-open.wav`), at the same seven tenths of full volume. The Android phone plays it the same way.
///
/// It plays once per start of the app, as the opening screen shows, and only when:
///
/// - the setting is on (``key``);
/// - no other app plays sound: a sound over somebody else's music is noise;
/// - the ring switch is not on silent. The sound plays in the ambient category, which the switch
///   silences, and which mixes with other apps' sound, so it never stops another app.
///
/// It stops, fading over a fifth of a second, as soon as rpm's own music starts (``stop()``), as the
/// desktop's stops when a track starts.
@MainActor
public enum OpeningSound {
    /// Where the setting is kept, in the standard user defaults. On when it was never set.
    public static let key = "sound.opening"

    /// The value when the setting was never set.
    public static let initial = true

    /// The desktop's `Softer`: the sound at seven tenths of full volume.
    static let volume: Float = 0.7

    /// How long the sound takes to fade away when the music starts, in seconds.
    static let fade: TimeInterval = 0.2

    /// Whether it was played in this process already. A new window does not play it again.
    private static var played = false

    /// The sound while it plays.
    private static var sound: AVAudioPlayer?

    /// Plays the sound if it may.
    public static func play() {
        guard !played else { return }
        played = true
        guard UserDefaults.standard.object(forKey: key) as? Bool ?? initial else { return }

        // **The session is left alone when the player already holds it.** The player sets the
        // playback category when music starts; the ambient category under the music would let the
        // ring switch silence it and stop it when the screen locks.
        let session = AVAudioSession.sharedInstance()
        guard !session.isOtherAudioPlaying, session.category != .playback,
              let url = Bundle.module.url(forResource: "rpm-open", withExtension: "m4a")
        else { return }

        do {
            try session.setCategory(.ambient, mode: .default)
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            guard player.play() else { return }
            sound = player

            // Let go of it once it has played out.
            let length = player.duration
            Task {
                try? await Task.sleep(for: .seconds(length + 0.5))
                if Self.sound === player { Self.sound = nil }
            }
        } catch {
            // No sound is no harm: the app opens as it would without it.
        }
    }

    /// Stops the sound if it still plays, with a short fade.
    public static func stop() {
        guard let playing = sound else { return }
        sound = nil
        playing.setVolume(0, fadeDuration: fade)
        Task {
            try? await Task.sleep(for: .seconds(Self.fade))
            playing.stop()
        }
    }
}

/// The opening sound, on the General settings. The card has its switch only, as on the Android
/// phone.
struct OpeningSoundCard: View {
    @AppStorage(OpeningSound.key) private var on = OpeningSound.initial

    var body: some View {
        SettingsCardFrame(Glyph.speaker, Loc.get("Settings_Sound")) {
            Toggle(isOn: $on) {
                Text(Loc.get("Settings_StartupSound"))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0xB3 / 255))
            }
            .rpmControlTint()
            .onChange(of: on) { _, _ in Haptics.pick() }
        }
    }
}
