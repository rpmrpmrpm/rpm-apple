import SwiftUI
import RPMKit
import RPMCast
import RPMAudio

/// Chooses where the sound plays. The phone app's `SpeakerSheet` is the equivalent. The list shows
/// this Apple TV, then the speakers that answered on the network. The one playing has a tick. While
/// a speaker plays, its volume control is shown. The sheet opens from the player's More key and
/// looks for speakers when it opens. The Look again button searches again.
///
/// **A speaker that is paired with another is still in this list, and it still refuses casts.** It
/// keeps advertising itself as before. Google does not allow casting to a member of a pair, so the
/// group next to it is the one that works. The refusal message says so.
struct PlayOnSheet: View {
    @Environment(TVModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    /// The sheet has a fixed size, so it does not grow when speakers answer.
    private static let size = CGSize(width: 820, height: 860)

    var body: some View {
        let speakers = model.speakers
        let playingOn = model.player.castingTo
        VStack(alignment: .leading, spacing: 0) {
            Text(Loc.get("Rpm_Cast_Title"))
                .font(.tv(48, .bold))
                .foregroundStyle(Ink.words)
            // One line, with the same height whether it has text or not. The text is the search
            // status, or it is empty.
            Text(speakers.looking ? Loc.get("Rpm_Cast_Searching") : " ")
                .font(.tv(Size.small))
                .foregroundStyle(Ink.dim)
                .padding(.top, 6)
                .padding(.bottom, 24)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 10) {
                    row(name: Loc.get("Atv_Cast_ThisTv"), line: nil, symbol: "appletv", on: playingOn == nil) {
                        Task {
                            await speakers.stop()
                            dismiss()
                        }
                    }
                    ForEach(speakers.found) { speaker in
                        // Shown only for a group, where it helps the user: a group is the one that
                        // works when the speaker next to it refuses.
                        row(name: speaker.name, line: speaker.isGroup ? Loc.get("Rpm_Cast_Group") : nil,
                            symbol: speaker.isGroup ? "hifispeaker.2" : "hifispeaker",
                            on: playingOn?.id == speaker.id) {
                            Task {
                                await speakers.cast(to: speaker)
                                if speakers.trouble == nil { dismiss() }
                            }
                        }
                        .transition(.opacity)
                    }
                    if speakers.found.isEmpty, !speakers.looking {
                        Text(Loc.get("Rpm_Cast_NoneNearby"))
                            .font(.tv(Size.small))
                            .foregroundStyle(Ink.dim)
                            .padding(.horizontal, RowStyle.inset)
                            .padding(.top, 10)
                    }
                }
                .animation(.easeOut(duration: 0.25), value: speakers.found.map(\.id))
                // Room for a focused row to grow inside the list's edges.
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            // Clips the list to its place, so a long list does not scroll over the controls below
            // it.
            .padding(.horizontal, -14)
            .frame(maxHeight: .infinity, alignment: .top)

            if let trouble = speakers.trouble {
                Text(trouble)
                    .font(.tv(Size.small))
                    .foregroundStyle(Ink.failed)
                    .padding(.top, 16)
            }
            if let playingOn {
                volume(on: playingOn)
                    .padding(.top, 16)
            }
            Button(Loc.get("Rpm_Cast_LookAgain"), systemImage: "arrow.clockwise") {
                Task { await speakers.look() }
            }
            .buttonStyle(.glass)
            .disabled(speakers.looking)
            .padding(.top, 20)
        }
        .padding(50)
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .task { await speakers.look() }
    }

    private func row(name: String, line: String?, symbol: String, on: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 24) {
                Image(systemName: symbol)
                    .font(.system(size: 30))
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name)
                        .font(.tv(Size.row, .semibold))
                        .lineLimit(1)
                    if let line {
                        Text(line)
                            .font(.tv(Size.rowLine))
                            .foregroundStyle(Ink.dim)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if on {
                    Image(systemName: "checkmark")
                        .font(.system(size: 26, weight: .semibold))
                }
            }
            .foregroundStyle(Ink.words)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(RowStyle())
    }

    /// The speaker's own volume. The remote's volume keys control the TV, not the speaker.
    private func volume(on speaker: CastDevice) -> some View {
        let player = model.player
        return HStack(spacing: 20) {
            Text(Loc.get("Viz_Volume"))
                .font(.tv(Size.row))
                .foregroundStyle(Ink.words)
            Spacer()
            Button { player.setRoomVolume(step: player.roomVolume - 5) } label: {
                Image(systemName: "speaker.minus.fill")
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Loc.get("Transport_VolumeDown"))
            Text("\(player.roomVolume)")
                .font(.tv(Size.row, .semibold).monospacedDigit())
                .foregroundStyle(Ink.words)
                .frame(width: 80)
            Button { player.setRoomVolume(step: player.roomVolume + 5) } label: {
                Image(systemName: "speaker.plus.fill")
            }
            .buttonStyle(.glass)
            .accessibilityLabel(Loc.get("Transport_VolumeUp"))
        }
        .padding(.horizontal, RowStyle.inset)
        .focusSection()
    }
}
