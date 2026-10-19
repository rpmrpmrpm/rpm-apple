import SwiftUI
import RPMKit
import RPMAudio

/// The lyrics as they are sung, scrolling so that the sung line stays in the middle.
///
/// This follows the Uno app's `LyricLayer` rules: how far either side of the sung line
/// anything is drawn, the ramp that fades the lines out, and the dots that fill in across
/// a break.
///
/// **It draws a score, not a list of lines.** See ``LyricScore``. The sheet is cut once
/// into stretches and rests, and every opacity changes only when the playhead reaches a
/// new piece. This avoids two problems of computing the visible part of the sheet on every
/// frame from the playhead. First, a break would only exist where the writer marked one,
/// so an unmarked instrumental would remove the words and show nothing in their place.
/// Second, an opacity computed from the playhead changes only four times a second (the
/// rate at which the playhead is read), so every fade would stutter.
///
/// **The layout is not ported from the Uno app.** That layer stacks the lines by hand on a
/// `Canvas`. Each line reports its own height after layout, a coalesced dispatcher hop
/// re-stacks the sheet from those heights, and the opacities are written only when the sung
/// line changes. This causes three display faults: a wrapped line whose height arrives
/// after the stack was built overlaps the line below it, a re-stack during a scroll makes
/// the sheet jump, and a layout change that does not change the line (a rotation or a
/// resize) leaves the old opacities on screen.
///
/// Here SwiftUI lays out the lines, including wrapping, and this view only says which line
/// goes in the middle. Every opacity is derived from the playhead in the pass that draws
/// it, so there is no state that can become stale and nothing to re-stack.
struct LyricView: View {
    let sheet: LyricSheet
    let player: Player

    /// How many lines either side of the sung line are drawn at all. Together with the ramp
    /// in `fade(distance:started:)`, this is the whole fade at the top and bottom of the
    /// sheet.
    ///
    /// **This is the mask.** A veil across the top and bottom would need a fixed colour,
    /// but the lyrics sit on a background whose colour changes every second. Instead, the
    /// fade depends on the distance from the sung line, so the lines become transparent and
    /// the background shows through.
    private static let reach = 3

    /// The gap between lines, as a multiple of the type's own size.
    private static let leading: CGFloat = 0.62

    var body: some View {
        GeometryReader { box in
            let size = min(max(box.size.width * 0.055, 16), 26)

            // Computed here and not kept in state. It is one pass over a sheet of about
            // sixty lines, and a stored copy would have to be kept in step with the
            // current record.
            let score = LyricScore.of(sheet)
            let at = score.index(at: player.position.seconds)

            ScrollViewReader { hand in
                ScrollView {
                    LazyVStack(spacing: size * Self.leading) {
                        ForEach(score.parts) { part in
                            row(part, of: score, at: at, size: size)
                                .id(part.id)
                        }
                    }
                    // Half the height on each side, so the first and the last line can
                    // both be scrolled to the middle.
                    .padding(.vertical, box.size.height / 2)
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.hidden)
                .onChange(of: at) { _, now in
                    withAnimation(.easeOut(duration: 0.45)) {
                        hand.scrollTo(now ?? 0, anchor: .center)
                    }
                }
                .onAppear {
                    // Jump straight to the current position with no animation. The user
                    // has just opened the view and is not following a scroll.
                    hand.scrollTo(at ?? 0, anchor: .center)
                }
                // **The intro.** Nothing is being sung, so no line is lit and the sheet
                // is blank. The overlay shows the record's title and artist and the same
                // dots as a break, filling towards the first line. It switches off once,
                // when the singing starts, instead of fading out under the lyrics.
                .overlay {
                    if at == nil { opening(size: size) }
                }
                .animation(.easeOut(duration: 0.35), value: at == nil)
            }
        }
    }

    /// The screen before the first line: the title and artist, and how much of the intro
    /// is left.
    ///
    /// **Only for the intro.** A break in the middle of a song happens while the user is
    /// already reading, so repeating the title there would be a distraction. Breaks show
    /// the dots alone. The other apps behave the same way.
    private func opening(size: CGFloat) -> some View {
        VStack(spacing: 18) {
            VStack(spacing: 5) {
                Text(player.current?.title ?? "")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(.white)

                Text(player.current?.artist ?? "")
                    .font(.system(size: size * 0.82, weight: .medium))
                    .foregroundStyle(Color(white: 0xEA / 255).opacity(0.66))
            }
            .multilineTextAlignment(.center)
            .lineLimit(3)

            LyricDots(through: countIn)
        }
        .padding(.horizontal, 32)
    }

    /// How far through the intro the record is, from 0 to 1. It is taken from the playhead,
    /// like the dots of a break. After a seek into the middle of a long intro, the dots are
    /// already mostly filled, which is correct.
    private var countIn: Double {
        guard let first = sheet.lines.first?.seconds, first > 0 else { return 1 }
        return min(max(player.position.seconds / first, 0), 1)
    }

    /// One piece of the score: a line of words, or the rest that closes a stretch.
    ///
    /// **Only one stretch of the song is shown at a time.** The reach on either side of the
    /// sung line is a distance, and a distance passes straight through a break. Without the
    /// stretches, while the last line of a verse is sung, the first lines after the solo
    /// would already be on screen and would stay there through the whole break. See
    /// ``LyricScore``, which cuts a sheet into stretches at the breaks that the writer marked
    /// AND at the waits that nobody marked, which are most of them.
    @ViewBuilder
    private func row(_ part: LyricScore.Part, of score: LyricScore,
                     at: Int?, size: CGFloat) -> some View {
        let here = at.map { score.parts[$0] }
        let distance = abs(part.id - (at ?? 0))
        let sung = part.id == at

        // While a rest is playing, only the dots are shown and the earlier words are hidden.
        let resting = here?.piece.isRest == true
        let ours = part.section == here?.section

        switch part.piece {
        case .rest(let from, let until):
            // An empty screen during a break looks like the sheet has stopped, and the
            // user cannot tell a break from a stall. Three dots fill in across the
            // break instead, which also shows how much of it is left.
            LyricDots(through: through(from: from, until: until))
                .opacity(ours ? fade(distance: distance, started: at != nil) : 0)
                .animation(.easeOut(duration: 0.35), value: at)

        case .words(let line):
            Text(line.text)
                // **The same weight on every line, sung or not.** A heavier weight makes
                // the text wider, so a bolder sung line would wrap again and move every
                // line under it. Only the brightness shows which line is sung.
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(sung ? Color.white : Color(white: 0xEA / 255))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .opacity(ours && !resting ? fade(distance: distance, started: at != nil) : 0)
                // Animated when the playhead reaches a new piece, not when this row
                // becomes the sung line. When a new stretch arrives, a dozen rows change
                // from invisible to their own opacity at once, and none of them is the
                // sung line. **Nothing else changes this opacity**, which keeps it
                // smooth. An opacity that also included a fade computed from the playhead
                // would change four times a second, the rate at which the playhead is read.
                .animation(.easeOut(duration: 0.35), value: at)
        }
    }

    /// The opacity ramp by distance from the sung line: 1, 0.42, 0.24, 0.12, then 0.
    ///
    /// **Nothing is shown before the first line.** The intro has its own overlay, and a
    /// faint sheet showing through the title would put two displays on top of each other.
    private func fade(distance: Int, started: Bool) -> Double {
        guard started else { return 0 }

        switch distance {
        case 0: return 1
        case 1: return 0.42
        case 2: return 0.24
        default: return distance <= Self.reach ? 0.12 : 0
        }
    }

    /// How far through a rest the record is, from 0 to 1. It is read from the playhead and
    /// not animated, so that after a seek into the middle of a rest the dots are already
    /// two thirds filled, which is correct.
    ///
    /// A rest with no end (the one after the last line) never fills, because there is
    /// nothing to count towards.
    private func through(from: Double, until: Double) -> Double {
        let run = until - from
        guard run.isFinite, run > 0 else { return 0 }

        return min(max((player.position.seconds - from) / run, 0), 1)
    }
}

/// The three dots of a break, filling in across it.
///
/// Each dot fills over its own third of the break, so the three together look like one bar
/// filling and not three lights switching on.
private struct LyricDots: View {
    let through: Double

    /// The opacity of a dot before its turn. It stays visible: all three dots are shown from
    /// the start, and the fill shows how many have been reached.
    private static let rest: Double = 0.16

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { dot in
                let share = min(max(through * 3 - Double(dot), 0), 1)

                Circle()
                    .fill(Color.white.opacity(Self.rest + (1 - Self.rest) * share))
                    .frame(width: 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
        // **The playhead is read four times a second**, so a fill taken directly from it
        // would change in quarter-second steps and look like three lights switching on, not
        // a bar filling. The animation is linear and as long as the gap between two
        // readings, so what it draws in between matches the real playing position.
        .animation(.linear(duration: 0.25), value: through)
    }
}
