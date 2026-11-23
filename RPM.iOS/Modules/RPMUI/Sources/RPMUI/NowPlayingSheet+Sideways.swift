import SwiftUI
import RPMKit
import RPMSharedUI
import RPMStages
import RPMDesign

/// The player on its side, in the Modern style (``LandscapePlayer/modern``).
///
/// **It is the same sheet as the upright player, laid out for landscape**, and every part is the
/// upright player's own: the cover with the spectrum on both sides of it, the lyrics that take the
/// cover's place, the title with the heart, the seek bar, the transport and the glass capsule with
/// the lyrics, queue and menu keys. They behave the same way because they are the same views. Only
/// the layout and the background are here.
///
/// - The left holds the cover, with the spectrum beside it.
/// - The right holds the text and the keys, in one column.
/// - The top right holds the cast key and, to its left, the visualiser key.
/// - Behind all of it is the room, or the look chosen with the visualiser key, darker towards the
///   right so the text can be read.
///
/// **Each is put where the drawing has it, from the screen's size** (``SidewaysLayout``), and the
/// pieces are sized by the screen's height. Nothing is put outside the safe area.
extension NowPlayingSheet {
    var sidewaysLayout: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let laid = SidewaysLayout(
                width: geo.size.width + insets.leading + insets.trailing,
                height: geo.size.height + insets.top + insets.bottom,
                safe: CGRect(x: insets.leading, y: insets.top,
                             width: geo.size.width, height: geo.size.height))
            let s = laid.scale

            ZStack(alignment: .topLeading) {
                // The lyrics take the place of the cover here too, as in the upright player.
                if lyricsUp {
                    LyricView(sheet: lyrics, player: player, karaoke: karaoke, measured: measured)
                        .placed(laid.lyrics, in: laid)
                        .transition(.opacity)
                } else {
                    sidewaysCover(laid)
                        .transition(.opacity)
                }

                wordsShown(scale: s)
                    .placed(laid.words, in: laid)
                // See ``chrome`` for why the bar is a view of its own.
                PlayerNeedle(player: player, playingOn: playingOn, scale: s)
                    .placed(laid.needle, in: laid)
                transport(scale: s)
                    .placed(laid.transport, in: laid)
                below(scale: s)
                    .placed(laid.capsule, in: laid)

                sidewaysKeys(laid)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
        .animation(.easeOut(duration: 0.25), value: lyricsUp)
        // The background is a modifier and not a sibling in a stack, for the reason given on the
        // upright player: a sibling that ignores the safe area would make the whole stack extend
        // under the sensor housing.
        .background { sidewaysGround }
        // Every touch on the player stops at the player, as on the upright player.
        .background {
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
        }
    }

    /// The cover at its place, with the spectrum across its span.
    ///
    /// The spectrum is drawn centred on the cover, in a span made even about it, and cut where the
    /// layout's span stops at the safe area: the cover does not move for that.
    private func sidewaysCover(_ laid: SidewaysLayout) -> some View {
        let reach = laid.spectrumReach
        let run = laid.spectrum

        return ZStack(alignment: .topLeading) {
            // The setting can turn the moving bars off. The room behind the sheet stays.
            if bars {
                spectrum(edge: laid.cover.width)
                    .frame(width: reach.width, height: reach.height)
                    .mask {
                        Rectangle()
                            .frame(width: run.width, height: run.height)
                            .position(x: run.midX - reach.minX, y: run.midY - reach.minY)
                    }
                    .placed(reach, in: laid)
            }

            sleeve(edge: laid.cover.width)
                .coachTarget(.playerCover)
                .placed(laid.cover, in: laid)
        }
    }

    /// The keys for the screen and not for the music, at the top right: the visualiser key, then
    /// the cast key in the corner, where the upright player has it. Without the cast key, the
    /// visualiser key takes the corner.
    @ViewBuilder
    private func sidewaysKeys(_ laid: SidewaysLayout) -> some View {
        visualKey(scale: laid.scale)
            .placed(onSpeakers == nil ? laid.cast : laid.visual, in: laid)

        if onSpeakers != nil {
            speakerKey(scale: laid.scale, margin: 0)
                .placed(laid.cast, in: laid)
        }
    }

    /// The look chosen with the visualiser key, or nil for the room.
    private var sidewaysLook: StageLook? { LandscapeVisual.look(visual) }

    /// Chooses what is drawn behind the player: the room (Lava) or one of the stage's looks.
    ///
    /// A system menu and not the stage's panel: the panel is a full screen of its own, and here
    /// the choice only changes the background of a screen that stays in use.
    private func visualKey(scale s: CGFloat) -> some View {
        Menu {
            Picker(Loc.get("Rpm_Stage_Visualiser"), selection: $visual) {
                Text(Loc.get("Rpm_Stage_Room")).tag(LandscapeVisual.room)

                ForEach(LandscapeVisual.looks) { look in
                    Text(look.name).tag(LandscapeVisual.stored(look))
                }
            }
        } label: {
            // The stage's own visualiser glyph, lit while a look is drawn instead of the room.
            Text(StageLook.ribbon.glyph)
                .font(RPMFont.icon(15 * s))
                .foregroundStyle(sidewaysLook == nil ? RPMInk.white(0xB8 / 255) : .white)
                // The glass that ``RPMGlassKey`` draws, on the label: a menu is not a button and
                // takes no button style.
                .frame(width: 40 * s, height: 40 * s)
                .contentShape(Circle())
                .rpmGlass(Circle())
        }
        .accessibilityLabel(Loc.get("Rpm_Stage_Visualiser"))
        .onChange(of: visual) { _, _ in Haptics.pick() }
    }

    /// The picture behind the player on its side, darker towards the right.
    private var sidewaysGround: some View {
        sidewaysPicture
            .overlay {
                // The text and the keys are on the right half, so the picture is darkened there
                // and left as it is behind the cover.
                LinearGradient(
                    stops: [.init(color: .black.opacity(0), location: 0.35),
                            .init(color: .black.opacity(0.55), location: 1)],
                    startPoint: .leading, endPoint: .trailing)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
    }

    /// The room, or the look chosen in its place.
    ///
    /// **Only one of them is in the tree**, so only one runs. The room stops when a look takes its
    /// place, and a look stops when the room comes back. The room's reader still runs for the
    /// spectrum beside the cover.
    ///
    /// A look rests like the room: it keeps its last frame while the sheet is hidden or the music
    /// has been paused for a moment (``SwiftUI/EnvironmentValues/roomsRest``).
    @ViewBuilder
    private var sidewaysPicture: some View {
        if let look = sidewaysLook {
            StageLookView(look: look, player: player, running: showing && !roomsRest)
        } else if RoomView.works {
            // The whole room is lit: there is no text under the cover on this layout, so it is
            // not dimmed from a foot line. The gradient over it darkens the right instead.
            RoomView(colours: room.colours,
                     sound: room.ramp,
                     foot: 1,
                     running: showing,
                     // The same room as the upright player: the record lights it.
                     breathes: false, zero: .whenShown, seed: "stage")
        } else {
            fallbackGround
        }
    }
}

private extension View {
    /// Puts this view at `frame`, which is on the whole screen, in a view that starts at the safe
    /// area's top leading corner.
    func placed(_ frame: CGRect, in laid: SidewaysLayout) -> some View {
        self.frame(width: frame.width, height: frame.height)
            .position(x: frame.midX - laid.safe.minX, y: frame.midY - laid.safe.minY)
    }
}
