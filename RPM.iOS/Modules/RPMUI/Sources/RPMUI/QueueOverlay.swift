import SwiftUI
import RPMKit
import RPMAudio
import RPMDesign

/// The queue, drawn over the player instead of pushed as a new page.
///
/// The Uno app has the same screen in `RPM.Mobile/Presentation/Controls/QueueOverlay.xaml`. The
/// queue is part of what is already on the screen. Opening it as a page would feel like leaving
/// the player, so the panel rises from the bottom over the sheet, on the same glass as the bar,
/// and the sleeve stays behind it.
///
/// It stops below the top on purpose: the record above the panel shows that this is still the
/// player, and a tap on that gap closes the list.
public struct QueueOverlay: View {
    private let player: Player

    /// Whether the drawer is up, and how far down it has been pulled. The player itself uses the
    /// same value. See ``ScreenPull``.
    @Binding private var pull: ScreenPull

    public init(player: Player, pull: Binding<ScreenPull>) {
        self.player = player
        self._pull = pull
    }

    /// How tall the panel is, and so the size a pull is measured against. The scrim behind the
    /// panel fades with the pull, so the frame and the darkness use one number and always agree.
    fileprivate static let height: CGFloat = 520

    public var body: some View {
        // **The `if` is here, directly over the two views that carry a transition.** A
        // transition runs for the view that an `if` inserts or removes. If the `if` is in the
        // player, one level up, nothing animates the removal: a tap on the grip fades the drawer
        // out in place instead of sliding it down. A drag hides this, because the panel is
        // already low when it goes. The player's own `if` and `.belowWindow` are paired in the
        // same way.
        ZStack(alignment: .bottom) {
            if pull.up {
                // Tap the sleeve above the panel to close it. This also stops a tap from
                // reaching the transport controls underneath while the list is up.
                Color.black.opacity(0x59 / 255)
                    .ignoresSafeArea()
                    // The dark fades with the list. A scrim that stays black behind a panel that
                    // is already half off the bottom looks like two things moving separately,
                    // and the finger is only on the panel.
                    .opacity(1 - pull.share(of: Self.height))
                    .onTapGesture { pull.putAway() }
                    .transition(.opacity)

                QueuePanel(player: player, pull: $pull)
                    .pulledDown(pull)
                    .transition(.belowWindow)
            }
        }
        .animation(.spring(duration: 0.32), value: pull.up)
    }
}

/// The drawer itself: the grip, the heading and the list. It is inserted again on each raise, so
/// rearranging is off every time the list comes up.
private struct QueuePanel: View {
    let player: Player
    @Binding var pull: ScreenPull

    /// Rearranging. On this platform it is a mode, not a handle on every row: the framework's own
    /// reorder keeps its standard behaviour, and the same key as on the Now playing page turns it
    /// on.
    @State private var rearranging = false

    /// The queue as this sitting has it: from where the listening began, with the needle's
    /// position. The rows can then show which tracks were played, and a drag cannot move a row
    /// into the past. See ``QueueRows``.
    private var look: QueueLook {
        .sitting(from: player.earliest, playing: player.index)
    }

    private var shown: [QueueRow] { QueueRows.of(player.queue, look) }

    var body: some View {
        VStack(spacing: 0) {
            grip

            if player.queue.isEmpty {
                // A station, or a queue of one: nothing is coming, and a short message is
                // clearer than an empty list.
                Text(Loc.get("Rpm_Queue_Empty"))
                    .font(RPMFont.display(13))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                rows
            }
        }
        // Below the top: the record above the panel shows that this is still the player.
        .frame(maxWidth: .infinity, maxHeight: QueueOverlay.height)
        .background {
            // Rounded at the top only: the panel comes up from the bottom edge of the screen and
            // is not a card floating on it.
            let plate = UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18,
                                               style: .continuous)

            RPMFrost()
                .clipShape(plate)
                .overlay { plate.fill(RPMInk.glassWash) }
                .overlay {
                    UnevenRoundedRectangle(topLeadingRadius: 18, topTrailingRadius: 18,
                                           style: .continuous)
                        .strokeBorder(RPMInk.glassEdge, lineWidth: 1)
                }
                // The glass runs under the home indicator and the content stops above it. A
                // bottom-aligned panel that respects the inset would leave a strip of scrim
                // below it.
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The grip. It has the same gesture as the player's own grip: pull it down and the list goes
    /// back down. The whole strip takes the drag, not only the bar drawn in it.
    private var grip: some View {
        VStack(spacing: 10) {
            Grabber()

            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Loc.get("Viz_Queue"))
                        .font(RPMFont.displayBold(18))
                        .foregroundStyle(.white)

                    Text(count).rpmKicker()
                }
                Spacer(minLength: 0)

                // The two keys are a pair, closer than the list's own spacing: they are one
                // group of controls on one heading, and eight points between them would look
                // like two separate keys that happen to be near each other.
                HStack(spacing: 0) {
                    // Another order for what has not been played yet. **One press, not a
                    // mode**: this app has no shuffle state (the key on a record starts it
                    // shuffled), so a toggle here would be the only one, with nothing to
                    // compare it to on any other screen.
                    //
                    // It is hidden when it could change nothing: on the last record of a
                    // queue, or in a queue of one.
                    if player.canShuffleWhatIsComing {
                        Button {
                            Haptics.commit()
                            withAnimation { player.shuffleWhatIsComing() }
                        } label: {
                            Text(Glyph.shuffle)
                                .font(RPMFont.icon(15))
                                .foregroundStyle(RPMInk.white(0xB8 / 255))
                                .frame(width: 38, height: 38)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Loc.get("Rpm_Queue_Shuffle"))
                    }

                    // Only while there is something to rearrange. The key is here and not on the
                    // rows, for the reason the Now playing page gives: the framework shows its
                    // grips when you say you are rearranging, and keeping its gesture handling
                    // is better than a hand-made drag inside a scrolling list.
                    if player.queue.count > 1 {
                        Button {
                            Haptics.pick()
                            withAnimation { rearranging.toggle() }
                        } label: {
                            // A tick to leave the mode, not a play mark: a play glyph here
                            // would look like "play this", which it does not do.
                            //
                            // **The glyph and nothing else.** A round dark background under it
                            // would be a second plate on a panel that is already glass, and the
                            // key would look like a button stuck on the list instead of part
                            // of its heading.
                            Text(rearranging ? "\u{f00c}" : Glyph.grip)
                                .font(RPMFont.icon(15))
                                .foregroundStyle(RPMInk.white(0xB8 / 255))
                                .frame(width: 38, height: 38)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // **Over the times, not beside them.** The key is 38 points of touch
                        // target around 15 points of glyph. If its box lined up with the 18
                        // points that the rows are padded by, the glyph itself would sit well
                        // inside the column that the durations run down. This offset is half the
                        // difference between the glyph and a time, so the two are centred on
                        // each other.
                        .padding(.trailing, -6)
                        .accessibilityLabel(rearranging ? Loc.get("CloudChip_StageDone")
                                                        : Loc.get("Rpm_Queue_Rearrange"))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) {
            Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)
        }
        // Pull it down to put the list away, or tap it: the same
        // ``SwiftUI/View/pullGrip(_:)`` that the player's own grip uses.
        .pullGrip($pull)
    }

    private var count: String {
        let left = max(0, player.queue.count - ((player.index ?? -1) + 1))
        return left == 1 ? Loc.get("Rpm_Queue_ToComeOne") : Loc.get("Rpm_Queue_ToCome", left)
    }

    // ── the list ──

    private var rows: some View {
        List {
            // **Identity, position and place on the screen are three different things**, and
            // ``QueueRows`` keeps them apart. The row carries an id that survives a drag, and
            // `at`, its position in the player's own queue, which is what every action here
            // receives.
            ForEach(shown) { row in
                Button { Task { await player.jump(to: row.at) } } label: {
                    self.row(row)
                }
                .buttonStyle(RowPress())
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                // Rows that were already played cannot be rearranged, and neither can the
                // record in the speaker: the running order can only change after the needle.
                .moveDisabled(row.state != .coming)
                // Swipe right to move the song up to just after the one playing, left to
                // remove it. The Uno app has the same two actions on the row's edges; here they
                // are the framework's own.
                //
                // **The leading edge is left off where the key would do nothing, not given an
                // empty group.** That means not on the one playing and not on the one already
                // next: a key that promises something and does nothing is wrong, and an empty
                // `swipeActions` is worse than no key, because the edge is still claimed and the
                // row pulls open against nothing.
                .modifier(MoveUpNext(
                    at: row.at, playing: player.index,
                    move: { player.move(from: row.at, to: (player.index ?? -1) + 1) }))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Haptics.commit()
                        player.remove([row.at])
                    } label: {
                        Label(Loc.get("Details_RemoveArt"), systemImage: "trash")
                    }
                }
            }
            .onMove { from, to in
                guard let plan = QueueRows.drop(shown, look, from: from, to: to,
                                                count: player.queue.count) else { return }
                Haptics.tick()
                player.move(from: plan.from, to: plan.to)
            }
        }
        .environment(\.editMode, .constant(rearranging ? .active : .inactive))
        .listStyle(.plain)
        // The rows are laid out at this list's width, not at the cell's width, so a swipe
        // moves them instead of squeezing them. See ``View/rowsKeepTheirWidth()``.
        .rowsKeepTheirWidth()
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .environment(\.defaultMinListRowHeight, 54)
    }

    private func row(_ row: QueueRow) -> some View {
        let track = row.track

        return HStack(spacing: 12) {
            // The playing mark sits in the list's own left margin, so every title starts at the
            // same x position whether it is the one playing or not.
            Rectangle()
                .fill(row.state == .playing ? Color.white : .clear)
                .frame(width: 3, height: 26)
                .clipShape(Capsule())
                .padding(.leading, 7)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.title ?? "")
                    .font(RPMFont.display(15))
                    // Played tracks are dimmer than the ones coming: the list reads from the
                    // needle downwards.
                    .foregroundStyle(row.state == .played ? RPMInk.white(0x77 / 255) : .white)
                    .lineLimit(1)

                Text(track.artist ?? "")
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(AlbumPage.length(track.duration))
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0x66 / 255))
        }
        .padding(.trailing, 18)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
        .keepsItsWidth()
    }
}

/// The leading swipe on a queue row, shown only on the rows it can move.
///
/// ``PlaylistPage`` has the same pair of actions in its `QueueRowKeys`, for the same queue drawn
/// by the other list.
private struct MoveUpNext: ViewModifier {
    let at: Int
    let playing: Int?
    let move: () -> Void

    private var canMoveUp: Bool { at != playing && at != (playing ?? -1) + 1 }

    @ViewBuilder
    func body(content: Content) -> some View {
        if canMoveUp {
            content.swipeActions(edge: .leading) {
                Button {
                    Haptics.commit()
                    move()
                } label: {
                    Label(Loc.get("AlbumMenu_PlayNext"),
                          systemImage: "text.line.first.and.arrowtriangle.forward")
                }
                .tint(RPMInk.white(0x33 / 255))
            }
        } else {
            content
        }
    }
}
