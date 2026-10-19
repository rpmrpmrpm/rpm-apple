import SwiftUI
import RPMKit
import RPMAudio

/// Shows the playback position: the bar, the two clocks and the bit rate under them.
///
/// **This is a separate view on purpose.** The position changes four times a second. With
/// `@Observable`, the view that READS a property is the view that is rebuilt when it changes.
/// If the player sheet's own body read the position, every tick would rebuild the whole sheet.
/// A `Menu` that is open while its parent is rebuilt flickers, because the system gets a new
/// menu to draw four times a second. Here the position is read in this body and nowhere else,
/// so a changing clock only rebuilds this strip.
struct PlayerNeedle: View {
    let player: Player

    /// The name of the room the sound is going to, if it is going to one. The name is shown on
    /// this line and not beside the cast key, because the Uno phone app also shows it on this
    /// line and the key is a button, not a label.
    var playingOn: String? = nil

    /// Where the live line is placed when there is no bar above it.
    ///
    /// It is centred in the portrait player, where the column IS the screen and the line takes
    /// the place of the two clocks at the ends of a bar. The stage's column is a third of the
    /// screen width and touches the left edge. A centred line would sit alone in the middle of
    /// that column, so there it is aligned with the text above, like everything else.
    var liveLine: HorizontalAlignment = .center

    /// The position of the finger while it is on the bar, in seconds. It is held here and not in
    /// the sheet, for the reason given in the type's description.
    @State private var scrubbing: Double?

    var body: some View {
        VStack(spacing: 4) {
            seek

            // Elapsed time on the left. Time LEFT on the right, counting down, as other
            // players on the phone show it.
            //
            // **A station has neither.** It is live, so there is no elapsed time to show and
            // nothing to count down. A clock that shows 0:00 under a playing station would
            // look like an error.
            HStack {
                if player.onTheRadio {
                    Text(Loc.get("Radio_OnAir")).tracking(1)
                } else {
                    Text(clock(shown))
                    Spacer()
                    Text(player.duration > .zero
                         ? "-" + clock(player.duration.seconds - shown) : "")
                }
            }
            .font(RPMFont.display(11))
            .foregroundStyle(RPMInk.white(0x88 / 255))
            .frame(maxWidth: .infinity,
                   alignment: player.onTheRadio ? Alignment(horizontal: liveLine, vertical: .center)
                                                : .leading)
            // In its own layer, as the Uno phone player uses a grid here: it must be in the
            // middle of the ROW, not in the middle of the space left between the two clocks.
            .overlay { rate }
        }
    }

    /// The same seek bar as the desktop app: a three-point track, the played part in white, and
    /// a thin white bar as the knob. It uses no accent colour.
    private var seek: some View {
        Group {
            if player.onTheRadio {
                // Nothing to scrub. A live track cannot be moved through, so it gets no bar
                // that the user could drag and see jump back.
                Color.clear.frame(height: 20).padding(.top, 6)
            } else {
                scrubber
            }
        }
        // The status sits over the gap above the right-hand end of the bar, **deliberately
        // outside the layout flow**. Inside the column it would push the seek bar, the clock and
        // the whole transport down when buffering starts and back up when it ends, so the keys
        // would move under the user's thumb.
        .overlay(alignment: .topTrailing) { status }
    }

    /// What is wrong, or what is being waited for. It is one line, and it appears only when
    /// there is something to say. It is not in the column, so it never moves other views.
    @ViewBuilder
    private var status: some View {
        // The same order as the Uno phone app: first what went wrong, then what is being
        // waited for, then where the sound is going. The room has the lowest priority because
        // it is not a problem or a wait.
        if let said = player.trouble
            ?? (player.isBusy ? Loc.get("Rpm_Playback_Buffering") : nil)
            ?? playingOn.map({ Loc.get("Rpm_Cast_Playing", $0) }) {
            Text(said)
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 240, alignment: .trailing)
                .offset(y: -8)
        }
    }

    /// The bit rate that is actually playing.
    ///
    /// It is shown only when the rate is known. The rate is unknown while the stream address is
    /// being signed, and a station has no rate at all. The line stays blank in both cases,
    /// because a wrong number is worse than none: the line is only useful if it can be trusted.
    @ViewBuilder
    private var rate: some View {
        if !player.onTheRadio, let kilobits = player.playingKilobits {
            Text(kilobits == AudioLadder.original ? Loc.get("Rpm_Playback_Original")
                                                 : Loc.get("Rpm_Profile_QualityKbps", kilobits))
                .font(RPMFont.display(11))
                .foregroundStyle(RPMInk.white(0x55 / 255))
        }
    }

    private var scrubber: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let played = width * progress

            ZStack(alignment: .leading) {
                Capsule().fill(RPMInk.white(0x2E / 255)).frame(height: 3)
                Capsule().fill(Color.white).frame(width: played, height: 3)

                Capsule()
                    .fill(Color.white)
                    .frame(width: 2, height: 14)
                    .offset(x: max(0, played - 1))
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { where_ in
                        guard player.duration > .zero, width > 0 else { return }
                        scrubbing = min(1, max(0, where_.location.x / width))
                            * player.duration.seconds
                    }
                    .onEnded { _ in
                        if let scrubbing { player.seek(to: .seconds(scrubbing)) }
                        scrubbing = nil
                    })
        }
        .frame(height: 20)
        .padding(.top, 6)
        .disabled(player.duration <= .zero)
    }

    // ── the numbers ──

    /// The position to show: the finger while it is on the bar, the playing position otherwise.
    private var shown: Double { scrubbing ?? player.position.seconds }

    private var progress: Double {
        guard player.duration > .zero else { return 0 }
        return min(1, max(0, shown / player.duration.seconds))
    }

    private func clock(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }
}
