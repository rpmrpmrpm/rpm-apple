import SwiftUI
import RPMKit
import RPMAudio
import RPMSharedUI

/// The sleep timer while it runs: the time left, buttons that add time, and the way to turn it
/// off.
///
/// It is the same glass card over a dimmed screen as ``SpeakerSheet`` and ``PlaylistPickSheet``.
/// It opens from the player's menu once a timer is running; a timer is started from the menu
/// itself.
public struct SleepTimerSheet: View {
    private let player: Player
    private let onClose: () -> Void

    public init(player: Player, onClose: @escaping () -> Void) {
        self.player = player
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            // Tap anywhere off the panel to close it.
            Color.black.opacity(0x99 / 255)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            // Once a second for the countdown. A timer set to the end of the song also follows
            // the player's own position, which it reads on every tick.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                panel(left: player.sleepTimeLeft(at: .now))
            }
            .frame(width: 320)
            .rpmGlassCard(radius: 18)
        }
    }

    private func panel(left: Duration?) -> some View {
        VStack(spacing: 0) {
            header(left: left)

            divider

            Text(left.map(SleepWords.clock) ?? "")
                .font(RPMFont.displayBold(44))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .accessibilityLabel(left.map { Loc.get("Rpm_Sleep_Left", SleepWords.clock($0)) } ?? "")

            divider

            adding

            divider

            deed
        }
    }

    private var divider: some View {
        Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)
    }

    private func header(left: Duration?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(Loc.get("Rpm_Sleep_Title"))
                    .font(RPMFont.displayBold(19))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(stops(left: left)).rpmKicker().lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Text("\u{f00d}")
                    .font(RPMFont.icon(15))
                    .foregroundStyle(RPMInk.white(0xB8 / 255))
            }
            .buttonStyle(RPMGlassKey(edge: 40))
            .accessibilityLabel(Loc.get("Rpm_Sleep_Close"))
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    /// When playback stops, as a clock time, or the end of the song.
    private func stops(left: Duration?) -> String {
        if player.sleepTimer.endsWithTheTrack { return Loc.get("Rpm_Sleep_StopsAtEndOfSong") }
        guard let left else { return "" }

        let at = Date.now.addingTimeInterval(left.seconds)
        return Loc.get("Rpm_Sleep_StopsAt", at.formatted(date: .omitted, time: .shortened))
    }

    /// The same durations the menu offers, each added to the time left.
    private var adding: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Loc.get("Rpm_Sleep_AddTime")).rpmKicker()

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                ForEach(SleepTimer.durations, id: \.self) { wait in
                    Button(SleepWords.adding(wait)) {
                        Haptics.tick()
                        player.addSleepTime(wait)
                    }
                    .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 42, inset: 8, size: 14))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var deed: some View {
        VStack(spacing: 10) {
            // Offered only where it means something: not when the timer already waits for the
            // end of the song, and not on a station, which has no end.
            if !player.sleepTimer.endsWithTheTrack, !player.onTheRadio, player.current != nil {
                Button(Loc.get("Rpm_Sleep_EndOfSong")) {
                    Haptics.pick()
                    player.setSleepTimer(.endOfTrack)
                }
                .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 42, size: 14))
            }

            Button(Loc.get("Rpm_Sleep_TurnOff")) {
                Haptics.commit()
                player.turnOffSleepTimer()
                onClose()
            }
            .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 42, size: 14))
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }
}
