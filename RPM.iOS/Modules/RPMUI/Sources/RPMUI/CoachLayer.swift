import SwiftUI
import RPMKit
import RPMDesign

/// The first-run hints, over the app and the player: the player's tour while the player is up, the
/// app's tour otherwise, and the closing card after the app's tour. See ``CoachMark``.
///
/// Put it over the whole app with `overlayPreferenceValue(CoachTargetFrames.self)`, so it reads where
/// every part it can point at stands. It takes no touches while it shows nothing. While a hint shows,
/// the whole screen takes the touches, so only the hint's own keys answer, as the desktop's hints
/// with a Next link block the window.
public struct CoachLayer: View {
    private let frames: [CoachTarget: CGRect]
    private let playerUp: Bool
    private let allowed: Bool

    /// - Parameters:
    ///   - frames: where the parts stand, in the screen's coordinates.
    ///   - playerUp: whether the player is up. Its hints wait until it has risen.
    ///   - allowed: whether hints may show now. False while the welcome, the wait mark, the opening
    ///     screen, the stage or a picker is up, and over another account's collection.
    public init(frames: [CoachTarget: CGRect], playerUp: Bool, allowed: Bool) {
        self.frames = frames
        self.playerUp = playerUp
        self.allowed = allowed
    }

    private var firstRun: FirstRun { FirstRun.shared }

    /// Whether the player has risen far enough for its parts to be pointed at.
    @State private var playerSettled = false

    /// Whether a hint of the app's tour showed in this run of the app. The closing card follows
    /// only such a run, as on the desktop.
    @State private var touredNow = false

    /// How long the player takes to rise before its hints point at its parts.
    private static let playerRises: Duration = .milliseconds(700)

    /// The tour that may show now, or nil.
    private var tour: [CoachMark]? {
        guard allowed, firstRun.welcomed else { return nil }
        if playerUp { return playerSettled ? CoachMark.playerTour : nil }
        return CoachMark.appTour
    }

    /// The hint to show now, or nil.
    private var due: CoachMark? {
        guard let tour else { return nil }
        let key = firstRun.seen.due(in: tour.map(\.rawValue)) { name in
            CoachMark(rawValue: name).map { frames[$0.target] != nil } ?? false
        }
        return key.flatMap { CoachMark(rawValue: $0) }
    }

    /// Whether the closing card shows: after the app's tour, in a run where one of its hints showed.
    private var finale: Bool {
        allowed && firstRun.welcomed && !playerUp && due == nil && touredNow
            && !firstRun.seen.has(CoachMark.done)
    }

    public var body: some View {
        let hint = self.due
        let closing = self.finale

        GeometryReader { space in
            // The parts are measured in the screen's coordinates; this layer may start lower.
            let origin = space.frame(in: .global).origin

            ZStack {
                if let hint, let frame = frames[hint.target] {
                    CoachHint(mark: hint,
                              target: frame.offsetBy(dx: -origin.x, dy: -origin.y),
                              onNext: { withAnimation(.easeOut(duration: 0.2)) { firstRun.see(hint.rawValue) } },
                              onClose: {
                                  // The close key ends the tour it belongs to.
                                  let tour = CoachMark.playerTour.contains(hint) ? CoachMark.playerTour
                                                                                : CoachMark.appTour
                                  withAnimation(.easeOut(duration: 0.2)) { firstRun.see(tour.map(\.rawValue)) }
                              })
                        // A new hint is a new view, so each one fades in while the dim stays.
                        .id(hint)
                } else if closing {
                    CoachFinale {
                        withAnimation(.easeOut(duration: 0.25)) { firstRun.see(CoachMark.done) }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: space.size.width, height: space.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(hint != nil || closing)
        .task(id: playerUp) {
            playerSettled = false
            guard playerUp else { return }
            try? await Task.sleep(for: Self.playerRises)
            guard !Task.isCancelled else { return }
            playerSettled = true
        }
        .onChange(of: due, initial: true) { _, now in
            if let now, CoachMark.appTour.contains(now) { touredNow = true }
        }
    }
}

/// One hint over everything, pointing at `target`: the dim with the part cut out, the ring round the
/// cut, the arrow, and the bubble with its close key and its Next link.
struct CoachHint: View {
    let mark: CoachMark

    /// The part, in this view's coordinates.
    let target: CGRect

    /// Answers the hint and moves on.
    let onNext: () -> Void

    /// Answers the hint and ends its tour.
    let onClose: () -> Void

    /// Whether the marks have faded in (`CoachmarkPainter`'s 300 ms on the marks layer).
    @State private var shown = false

    var body: some View {
        GeometryReader { space in
            let screen = space.size
            let hole = target.insetBy(dx: -CoachLook.pad, dy: -CoachLook.pad)
            let width = min(CoachLook.bubbleWidth, screen.width - CoachLook.edge * 2)

            // Over the part when it is in the lower half of the screen, under it otherwise.
            let above = target.midY > screen.height / 2
            let left = min(max(target.midX - width / 2, CoachLook.edge),
                           max(CoachLook.edge, screen.width - CoachLook.edge - width))

            // Where the bubble ends towards the part, which is where the arrow leaves it.
            let foot = above ? hole.minY - CoachLook.reach : hole.maxY + CoachLook.reach
            let arrow = CoachArrow(
                from: CGPoint(x: min(max(target.midX, left + 24), left + width - 24), y: foot),
                to: CGPoint(x: target.midX, y: above ? hole.minY - 5 : hole.maxY + 5),
                flip: above)

            ZStack(alignment: .topLeading) {
                // The dim, with the part cut out of it.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: screen))
                    path.addRect(hole)
                }
                .fill(CoachLook.dim, style: FillStyle(eoFill: true))

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: CoachLook.ringRadius, style: .continuous)
                        .stroke(CoachLook.accent, lineWidth: CoachLook.ringWidth)
                        .frame(width: hole.width, height: hole.height)
                        .offset(x: hole.minX, y: hole.minY)

                    arrow.line
                        .stroke(CoachLook.accent,
                                style: StrokeStyle(lineWidth: CoachLook.arrowWidth, lineCap: .round))
                    arrow.tip.fill(CoachLook.accent)

                    // The bubble's foot is fixed and its height follows its words, so it is laid out
                    // in the room between the part and the edge, against the part's side.
                    bubble
                        .frame(width: width)
                        .frame(width: width, height: max(0, above ? foot : screen.height - foot),
                               alignment: above ? .bottom : .top)
                        .offset(x: left, y: above ? 0 : foot)
                }
                .opacity(shown ? 1 : 0)
            }
            .frame(width: screen.width, height: screen.height, alignment: .topLeading)
        }
        // Every touch stops here: only the hint's own keys answer.
        .contentShape(Rectangle())
        .onTapGesture {}
        .onAppear {
            withAnimation(.easeOut(duration: CoachLook.fade)) { shown = true }
        }
    }

    private var bubble: some View {
        VStack(alignment: .trailing, spacing: 8) {
            Text(Loc.get(mark.words))
                .font(RPMFont.display(13.5))
                .lineSpacing(4)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 15)
                .padding(.vertical, 11)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CoachLook.panel)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(CoachLook.accent, lineWidth: 1.5)
                }
                // The round close key on the bubble's top left corner.
                .overlay(alignment: .topLeading) { closeKey.offset(x: -18, y: -18) }

            Button(action: onNext) {
                HStack(spacing: 7) {
                    Text(Loc.get("Coach_Next"))
                        .font(RPMFont.text(14, weight: .semibold))
                    Text(Glyph.into)
                        .font(RPMFont.icon(10))
                }
                .foregroundStyle(CoachLook.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// The disc is 24 points across, in a 36-point square that takes the touch.
    private var closeKey: some View {
        Button(action: onClose) {
            Text(Glyph.close)
                .font(RPMFont.icon(11))
                .foregroundStyle(CoachLook.accent)
                .frame(width: 24, height: 24)
                .background { Circle().fill(CoachLook.disc) }
                .overlay { Circle().strokeBorder(CoachLook.accent, lineWidth: 1.5) }
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Loc.get("Coach_Dismiss"))
    }
}

/// The card that ends the app's tour, centred over the dimmed screen: "And that's the tour!", a line,
/// and the key that hands the app over (`CoachmarkPainter`'s finale card).
struct CoachFinale: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            CoachLook.dim

            VStack(spacing: 14) {
                Text(Loc.get("Coach_DoneTitle"))
                    .font(RPMFont.displayBold(30))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text(Loc.get("Coach_Phone_DoneBody"))
                    .font(RPMFont.display(14))
                    .lineSpacing(5)
                    .foregroundStyle(RPMInk.white(0xC4 / 255))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button(Loc.get("Coach_DoneButton"), action: onDone)
                    .buttonStyle(RPMGlassButton(.ghost, stretches: false, inset: 28))
                    .padding(.top, 10)
            }
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 26)
            .frame(maxWidth: 460)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CoachLook.panel)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(CoachLook.accent, lineWidth: 1.5)
            }
            .padding(.horizontal, 16)
        }
        // Every touch stops here: only the card's key answers.
        .contentShape(Rectangle())
        .onTapGesture {}
    }
}
