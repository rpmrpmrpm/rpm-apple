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
///
/// **Words a sheet puts in round brackets are a second voice**, shown as on the desktop and the
/// Android phone (``LyricVoices``): on a smaller row under their line while it is sung, folded
/// away after. A line bracketed from end to end has no row of its own. It comes in under the line
/// before it while it is sung and folds away when it is done, and the lyrics move on as if it were
/// not there (``LyricScore/Aside``). A row opens and folds as on the Android phone (``Fold``).
///
/// **The view wakes at each moment something changes**: when the next piece takes over, and when a
/// backing line comes in or goes. Between two readings of the player it would otherwise wait for
/// the next reading, up to a quarter of a second late. See ``awaitMoment(_:from:)``.
struct LyricView: View {
    let sheet: LyricSheet
    let player: Player

    /// Whether the sung line lights letter by letter as it is sung. See ``SweptLine``.
    let karaoke: Bool

    /// The words of this song as the cloud measured them from the recording. A line that has
    /// them is lit by them, and every other line by its time shared between its words. See
    /// ``KaraokeLines``.
    let measured: [MeasuredLine]

    /// The last position read from the player, and when it was read. The player reads the engine
    /// four times a second, which is too coarse for a light moving through a word, so the sung
    /// line works out the time in between from this. See ``LyricTime``.
    @State private var reading = Reading(seconds: 0, at: .distantPast)

    struct Reading {
        let seconds: Double
        let at: Date
    }

    /// The steady time the karaoke words follow, one for each record. The line hand-over and the
    /// letter sweep both read it, so the light does not step back when a reading of the player
    /// does. See ``KaraokeClock``.
    @State private var clock = KaraokeClock()

    /// The piece the last scroll went to. A late second scroll goes only to the piece that is still
    /// the sung one.
    @State private var aimed: Int?

    /// Counts the wakes at the moments something changes. A change draws the view again. See
    /// ``awaitMoment(_:from:)``.
    @State private var beat = 0

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

    /// The gap between a line and the second voice under it, as a multiple of the type's own size.
    private static let voiceGap: CGFloat = 0.2

    /// The time for the karaoke words, worked out from the player's readings. See ``LyricTime``.
    private var time: LyricTime {
        LyricTime(reading: reading, position: player.position.seconds, playing: player.isPlaying,
                  clock: clock)
    }

    var body: some View {
        GeometryReader { box in
            let size = min(max(box.size.width * 0.055, 16), 26)

            // Computed here and not kept in state. It is one pass over a sheet of about
            // sixty lines, and a stored copy would have to be kept in step with the
            // current record. A line bracketed from end to end goes with the line before it.
            let score = LyricScore.of(sheet, asides: true)
            let heard = karaoke ? KaraokeLines.heard(score, measured: measured) : []
            // The steady time, read once for this pass. It moves the lines and shows the backing
            // lines, with karaoke or without, as on the Android phone.
            let now = time.seconds(at: .now)
            // With karaoke, a line stays up while its last measured word is still sung, and takes
            // over as its measured words start. Every line is sung for a moment.
            let handovers = KaraokeLines.handovers(score, heard: heard)
            let at = handovers.piece(at: now)
            // When each backing line shows, by piece.
            let voices = score.parts.map { part in
                part.asides.map { KaraokeLines.voice($0, measured: karaoke ? measured : []) }
            }
            let wake = Wake(seconds: Self.nextMoment(after: now, handovers: handovers, voices: voices),
                            playing: player.isPlaying, beat: beat)

            ScrollViewReader { hand in
                ScrollView {
                    // **Not lazy.** A lazy stack does not move the rows under a row whose height
                    // changes with it: they jump when the change ends. A second voice that folds
                    // must move the lines under it on every frame. A song is a few dozen lines,
                    // so laying them all out costs little.
                    VStack(spacing: size * Self.leading) {
                        ForEach(score.parts) { part in
                            row(part, of: score, at: at, size: size, heard: heard,
                                voices: voices[part.id], now: now)
                                .id(part.id)
                        }
                    }
                    // Half the height on each side, so the first and the last line can
                    // both be scrolled to the middle.
                    .padding(.vertical, box.size.height / 2)
                    .padding(.horizontal, 24)
                }
                .scrollIndicators(.hidden)
                // **The lyrics follow the song and cannot be dragged.** Only the seek bar moves
                // the song. `scrollTo` still scrolls a disabled scroll view.
                .scrollDisabled(true)
                .onChange(of: at) { _, now in
                    aimed = now
                    withAnimation(LyricMotion.ease(LyricMotion.scroll)) {
                        hand.scrollTo(now ?? 0, anchor: .center)
                    }
                    // The second voices that open and fold away at this moment move the line while
                    // it scrolls, and a scroll goes to where the line was when it started. Once
                    // the folds are done, the scroll is aimed at the line again, to arrive when the
                    // first scroll would have, if it is still the sung line.
                    Task {
                        try? await Task.sleep(for: .seconds(LyricMotion.fold + 0.01))
                        guard aimed == now else { return }
                        withAnimation(.easeOut(duration: LyricMotion.scroll - LyricMotion.fold - 0.01)) {
                            hand.scrollTo(now ?? 0, anchor: .center)
                        }
                    }
                }
                .task(id: wake) { await awaitMoment(wake, from: now) }
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
        .onAppear { reading = Reading(seconds: player.position.seconds, at: .now) }
        .onChange(of: player.position) { _, now in
            reading = Reading(seconds: now.seconds, at: .now)
        }
        // A new clock for each record, so nothing of the last record's time carries over.
        .onChange(of: player.current?.rpmId) { _, _ in clock = KaraokeClock() }
    }

    /// The next moment the view must wake at (``awaitMoment(_:from:)``), in seconds of the record,
    /// nil when there is none; whether the record plays; and how many wakes there have been.
    private struct Wake: Equatable {
        let seconds: Double?
        let playing: Bool
        let beat: Int
    }

    /// The first moment after `seconds` at which something on screen changes: the next piece takes
    /// over, or a backing line comes in or goes. Nil when nothing changes any more.
    private static func nextMoment(after seconds: Double, handovers: KaraokeLines.Handovers,
                                   voices: [[KaraokeLines.Voice]]) -> Double? {
        var next = handovers.next(after: seconds)
        for asides in voices {
            for voice in asides {
                let moment = seconds < voice.from ? voice.from : voice.until
                guard moment > seconds, moment.isFinite else { continue }
                next = min(next ?? moment, moment)
            }
        }
        return next
    }

    /// Waits until the moment `wake` names and draws the view again, so the sung line and the
    /// backing lines change at their moment and not at the next reading of the player. `now` is the
    /// time the view was drawn at. The Android phone waits for each moment in the same way.
    ///
    /// The steady clock can still be a little short of the moment when the view is drawn again.
    /// Each wake is counted in `beat`, which is part of the task's identity, so the view then waits
    /// again for what is left.
    private func awaitMoment(_ wake: Wake, from now: Double) async {
        guard wake.playing, let moment = wake.seconds else { return }
        try? await Task.sleep(for: .seconds(max(moment - now, 0.016)))
        guard !Task.isCancelled else { return }
        beat &+= 1
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
                     at: Int?, size: CGFloat, heard: [[WordSpan]?],
                     voices: [KaraokeLines.Voice], now: Double) -> some View {
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
                .animation(LyricMotion.ease(LyricMotion.line), value: at)

        case .words(let line):
            // Its measured words where they fit the line, else its time shared between its words
            // by length. The bracketed words come out of the line onto a row of their own.
            let spans = KaraokeLines.spans(of: part, in: score, heard: heard)
            let split = LyricVoices.split(line.text, spans: spans)

            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    verse(line.text, split: split, spans: spans, sung: sung)

                    // The second voice is read with its line: it shows only while the line is
                    // sung, at the line's own strength, and folds away when the line is done.
                    if let voice = split?.voice {
                        Fold(open: sung, gap: size * Self.voiceGap) {
                            secondVoice(voice, light: spans, sung: sung, size: size)
                        }
                    }
                }
                    .opacity(ours && !resting ? fade(distance: distance, started: at != nil) : 0)
                    // Animated when the playhead reaches a new piece, not when this row
                    // becomes the sung line. When a new stretch arrives, a dozen rows change
                    // from invisible to their own opacity at once, and none of them is the
                    // sung line. **Nothing else changes this opacity**, which keeps it
                    // smooth. An opacity that also included a fade computed from the playhead
                    // would change four times a second, the rate at which the playhead is read.
                    // The second voice fades with it, and with its fold.
                    .animation(LyricMotion.ease(LyricMotion.line), value: at)

                // The backing lines that go with this line pop in under it while they are sung,
                // and fold away after. They are at full strength, as the sung line is.
                ForEach(Array(part.asides.enumerated()), id: \.offset) { place, aside in
                    if place < voices.count {
                        backing(aside, voice: voices[place], now: now, size: size)
                    }
                }
            }
                // **The same weight on every line, sung or not.** A heavier weight makes
                // the text wider, so a bolder sung line would wrap again and move every
                // line under it. Only the brightness shows which line is sung.
                .font(.system(size: size, weight: .semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// The verse of a line: the whole line, or the line without its bracketed words where it has
    /// a second voice. The sung line lights letter by letter with karaoke.
    ///
    /// The plain line and the karaoke line change in one step, as on the Android phone. A
    /// cross-fade showed both at once, and while a fold above moved the line the two copies were
    /// drawn apart, so the line looked doubled.
    @ViewBuilder
    private func verse(_ text: String, split: LyricVoices.Split?, spans: [WordSpan],
                       sung: Bool) -> some View {
        Group {
            if sung && karaoke {
                if let verse = split?.verse {
                    SweptLine(text: verse.text, spans: verse.spans, time: time,
                              light: spans, letters: verse.letters)
                } else {
                    SweptLine(text: text, spans: spans, time: time)
                }
            } else {
                Text(split?.verse.text ?? text)
                    .foregroundStyle(sung ? Color.white : Color(white: 0xEA / 255))
            }
        }
        .transition(.identity)
    }

    /// The second voice of a line, on its smaller row: lit letter by letter as part of the whole
    /// line (`light`) while the line is sung with karaoke, else in the line's colour.
    ///
    /// The two ways of drawing it change in one step when the line is done, as on the Android
    /// phone. Without `.transition(.identity)` they would cross-fade during the fold.
    @ViewBuilder
    private func secondVoice(_ voice: LyricVoices.Row, light: [WordSpan], sung: Bool,
                             size: CGFloat) -> some View {
        Group {
            if sung && karaoke {
                SweptLine(text: voice.text, spans: voice.spans, time: time,
                          light: light, letters: voice.letters)
                    .transition(.identity)
            } else {
                Text(voice.text)
                    .foregroundStyle(sung ? Color.white : Color(white: 0xEA / 255))
                    .transition(.identity)
            }
        }
        .font(.system(size: size * LyricVoices.scale, weight: .semibold))
    }

    /// A backing line (``LyricScore/Aside``) under the line it goes with: shown while it is sung
    /// (``KaraokeLines/voice(_:measured:)``), lit word by word with karaoke, and folded away when
    /// it is done. It has no row of its own, so the lyrics move on as if it were not there.
    private func backing(_ aside: LyricScore.Aside, voice: KaraokeLines.Voice, now: Double,
                         size: CGFloat) -> some View {
        // The words as the row shows them: the line without the brackets round it.
        let row = LyricVoices.unbracketed(aside.line.text, spans: voice.spans)
        return Fold(open: voice.shows(at: now), gap: size * Self.voiceGap) {
            Group {
                if karaoke {
                    SweptLine(text: row.text, spans: row.spans, time: time,
                              light: voice.spans, letters: row.letters)
                } else {
                    Text(row.text).foregroundStyle(Color.white)
                }
            }
            .font(.system(size: size * LyricVoices.scale, weight: .semibold))
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

/// The time the karaoke words are lit by: the player's last reading carried forward, made steady by
/// a ``KaraokeClock``.
///
/// The reading is carried forward no further than ``ahead`` past it, so a reading that is late does
/// not run the light past the voice. A reading older than a second (or none yet, as the view opens)
/// is not used: the player's position is, so the first frame already shows the right line.
struct LyricTime {
    let reading: LyricView.Reading
    let position: Double
    let playing: Bool
    let clock: KaraokeClock

    /// How far past the player's last reading the time may run, in seconds: a little more than
    /// the time between two readings.
    static let ahead = 0.3

    func seconds(at date: Date) -> Double {
        let age = date.timeIntervalSince(reading.at)
        let reported = playing && age >= 0 && age < 1 ? reading.seconds + min(age, Self.ahead) : position
        return clock.seconds(reported: reported, advancing: playing,
                             at: date.timeIntervalSinceReferenceDate)
    }
}

extension KaraokeLines.Voice {
    /// Whether the backing line is shown at `seconds`.
    func shows(at seconds: Double) -> Bool { seconds >= from && seconds < until }
}

/// The timings and the curve of the lyric view's movements, the same as the Android phone's.
private enum LyricMotion {
    /// How long a second voice takes to open or fold away, in seconds. Quicker than the scroll: it
    /// is a thing finishing, and a slow fold would look like the lyrics were still deciding.
    static let fold = 0.25

    /// How long a line takes to fade to its new opacity, in seconds.
    static let line = 0.35

    /// How long the scroll to the next line takes, in seconds.
    static let scroll = 0.45

    /// Compose's `FastOutSlowInEasing`, a cubic Bezier curve with the control points (0.4, 0) and
    /// (0.2, 1), over `duration` seconds. The Android phone eases the folds, the line fades and the
    /// scroll on it.
    static func ease(_ duration: Double) -> Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: duration)
    }
}

/// A row that opens under a line and folds away again, as on the Android phone. While `open` it
/// takes its full height and shows; otherwise it takes none and is not drawn. Between the two it
/// eases over ``LyricMotion/fold``, its height and its opacity together (``FoldLayout``), so the
/// lines under it move with it and do not jump. The row is cut at the bottom while it opens, so it
/// is uncovered from the top down.
private struct Fold<Content: View>: View {
    let open: Bool
    let gap: CGFloat
    let content: () -> Content

    /// How far the row is open, from 0 (closed) to 1 (open). Its height and its opacity both
    /// follow it.
    ///
    /// **It is moved with its own `withAnimation`** when `open` changes, and not with an
    /// `.animation(_:value:)` modifier. The change of `open` arrives in whatever transaction
    /// redrew the lyrics (a wake, a player reading), and a modifier on a row was not applied:
    /// the row lost its opacity and its height in one frame. An explicit animation of this view's
    /// own state always eases.
    @State private var amount: CGFloat

    /// Whether the content is kept. It stays while the row folds away and is dropped once the
    /// fold is done, so a closed row holds no karaoke line that is drawn again on every frame.
    @State private var kept: Bool

    /// Counts the folds, so that only the last one to finish drops the content.
    @State private var folds = 0

    init(open: Bool, gap: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.open = open
        self.gap = gap
        self.content = content
        _amount = State(initialValue: open ? 1 : 0)
        _kept = State(initialValue: open)
    }

    var body: some View {
        FoldLayout(amount: amount) {
            if kept {
                content()
                    .padding(.top, gap)
                    .frame(maxWidth: .infinity)
                    .opacity(Double(amount))
            }
        }
        .clipped()
        .onChange(of: open) { _, now in
            folds += 1
            let fold = folds
            // The content is there before the row opens, so it is uncovered as the row grows.
            if now { kept = true }
            withAnimation(LyricMotion.ease(LyricMotion.fold)) {
                amount = now ? 1 : 0
            } completion: {
                guard folds == fold, !now else { return }
                kept = false
            }
        }
    }
}

/// Lays its one child out at its full height from the top, and takes `amount` of that height: 0
/// when closed, 1 when open. The lines under it follow its height on every frame of the animation.
/// The child is not made smaller; the ``Fold`` clips what does not fit.
private struct FoldLayout: Layout {
    var amount: CGFloat

    /// `nonisolated` because `Animatable` is. See `SpectrumRunView.animatableData`.
    nonisolated var animatableData: CGFloat {
        get { amount }
        set { amount = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let full = subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
            ?? .zero
        // An infinite width must not be returned to the parent as a size.
        let width = proposal.width.map { $0.isFinite ? $0 : full.width } ?? full.width
        return CGSize(width: width, height: full.height * amount)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        guard let child = subviews.first else { return }
        let full = child.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
        child.place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                    proposal: ProposedViewSize(width: bounds.width, height: full.height))
    }
}

/// The sung line for karaoke: a soft edge of light moves through each word as it is sung, letter
/// by letter, from ``KaraokeLight/rest`` up to white. See ``KaraokeLight``.
///
/// Only this line is redrawn every frame. Each frame reads the steady time (``LyricTime``).
///
/// The letters are lit as the letters of `light`, the words of the whole line, and `letters` says
/// which of those each letter of `spans` is (nil when `spans` are the whole line). So a line cut
/// into its verse and its second voice (``LyricVoices/split(_:spans:)``) is lit as one line: the
/// light goes from one row to the other as the words do.
private struct SweptLine: View {
    let text: String
    let spans: [WordSpan]
    let time: LyricTime
    var light: [WordSpan]? = nil
    var letters: [Int]? = nil

    var body: some View {
        TimelineView(.animation(paused: !time.playing)) { context in
            Text(lit(at: time.seconds(at: context.date)))
        }
    }

    /// The line with each letter at its strength. The space between two words takes the strength
    /// of the letter before it, so the light does not jump back down between words.
    private func lit(at now: Double) -> AttributedString {
        // The sung line does not fade after its last word: it stays lit until the next line takes
        // over. See ``KaraokeLight/light(_:now:fades:)``.
        let whole = KaraokeLight.light(light ?? spans, now: now, fades: false)
        let strengths = letters.map { places in
            places.map { whole.indices.contains($0) ? whole[$0] : KaraokeLight.rest }
        } ?? whole
        let characters = Array(text)

        var strength = Array(repeating: KaraokeLight.rest, count: characters.count)
        var letter = 0
        var last = KaraokeLight.rest
        var at = 0
        for span in spans {
            while at < min(span.start, characters.count) { strength[at] = last; at += 1 }
            for offset in 0..<span.length where span.start + offset < characters.count {
                last = letter < strengths.count ? strengths[letter] : KaraokeLight.rest
                strength[span.start + offset] = last
                letter += 1
            }
            at = min(span.start + span.length, characters.count)
        }
        while at < characters.count { strength[at] = last; at += 1 }

        // One run for each stretch of letters at the same strength, rounded to a hundredth, so a
        // line that is not changing gives the same text every frame.
        var out = AttributedString()
        var start = 0
        while start < characters.count {
            let level = (strength[start] * 100).rounded() / 100
            var end = start + 1
            while end < characters.count, (strength[end] * 100).rounded() / 100 == level { end += 1 }
            var run = AttributedString(String(characters[start..<end]))
            run.foregroundColor = Color.white.opacity(level)
            out.append(run)
            start = end
        }
        return out
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
