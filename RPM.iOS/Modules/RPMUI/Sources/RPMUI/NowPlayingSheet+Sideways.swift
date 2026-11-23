import SwiftUI
import RPMKit
import RPMSharedUI
import RPMStages

/// The player on its side, in the Modern style (``LandscapePlayer/modern``).
///
/// **It is the same sheet as the upright player, laid out for landscape**, and every part is the
/// upright player's own: the cover with the spectrum on both sides of it, the lyrics that take the
/// cover's place, the title with the heart, the seek bar, the transport and the glass capsule with
/// the lyrics, queue and menu keys. They behave the same way because they are the same views. Only
/// the layout and the background are here.
///
/// - The left half holds the cover, centred, with the spectrum in the margins beside it.
/// - The right half holds the text and the keys, centred as one block.
/// - The top right holds the cast key and, to its left, the visualiser key.
/// - Behind all of it is the room, or the look chosen with the visualiser key, darker towards the
///   right so the text can be read.
extension NowPlayingSheet {
    /// The widest the column of text and keys grows, on a phone with a lot of room on its side.
    private static let sidewaysColumn: CGFloat = 460

    var sidewaysLayout: some View {
        HStack(spacing: 0) {
            // The lyrics take the place of the cover here too, as in the upright player.
            ZStack {
                if lyricsUp {
                    LyricView(sheet: lyrics, player: player, karaoke: karaoke, measured: measured)
                } else {
                    cover
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            chrome
                .frame(maxWidth: Self.sidewaysColumn)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.25), value: lyricsUp)
        .overlay(alignment: .topTrailing) { sidewaysKeys }
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

    /// The keys for the screen and not for the music, at the top right: the visualiser key, then
    /// the cast key in the corner, where the upright player has it.
    private var sidewaysKeys: some View {
        HStack(spacing: 10) {
            visualKey
                // The cast key brings its own margin. Without it, this key takes the corner.
                .padding(.trailing, onSpeakers == nil ? 12 : 0)

            speakerKey
        }
        .padding(.top, 8)
    }

    /// The look chosen with the visualiser key, or nil for the room.
    private var sidewaysLook: StageLook? { LandscapeVisual.look(visual) }

    /// Chooses what is drawn behind the player: the room (Lava) or one of the stage's looks.
    ///
    /// A system menu and not the stage's panel: the panel is a full screen of its own, and here
    /// the choice only changes the background of a screen that stays in use.
    private var visualKey: some View {
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
                .font(RPMFont.icon(15))
                .foregroundStyle(sidewaysLook == nil ? RPMInk.white(0xB8 / 255) : .white)
                // The glass that ``RPMGlassKey`` draws, on the label: a menu is not a button and
                // takes no button style.
                .frame(width: 40, height: 40)
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
