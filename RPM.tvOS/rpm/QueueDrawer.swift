import SwiftUI
import RPMKit
import RPMLibrary
import RPMAudio

/// The queue drawer. The desktop app has the same drawer. It is a glass panel down the left side of
/// the player, 0.36 of the screen width. The queue is in it, and the playing row is lit and focused
/// when the drawer opens. Selecting a row plays it. Press and hold shows Play, Play next, Move and
/// Remove from queue. Move lifts the row. Up and Down move it one place, and select places it. Back
/// puts it back where it started. Back closes a move first, then the drawer. Right closes the
/// drawer.
///
/// Every edit first asks the player whether the row is still at that index. An edit from elsewhere,
/// such as a track ending or a song queued next from a page, can change the queue. The check stops
/// an edit from acting on the wrong row.
struct QueueDrawer: View {
    @Environment(TVModel.self) private var model
    @Environment(Screens.self) private var screens
    let close: () -> Void

    /// How far the rows are inset from the drawer's edges.
    private static let listInset: CGFloat = 18

    @State private var moving: Row?
    @State private var movingAt = 0
    @State private var movedFrom = 0
    @FocusState private var focused: String?

    /// One row of the queue: the track, and which copy of it this is. A row keeps its identity when
    /// a move carries it past other tracks. A track queued twice is two rows.
    struct Row: Identifiable, Equatable {
        let id: String
        let track: CloudTrack
    }

    private var rows: [Row] {
        var copies: [String: Int] = [:]
        return model.player.queue.map { track in
            let copy = (copies[track.rpmId] ?? 0) + 1
            copies[track.rpmId] = copy
            return Row(id: "\(track.rpmId)#\(copy)", track: track)
        }
    }

    var body: some View {
        let rows = rows
        let playing = model.player.index
        let albums = Dictionary(model.session.albums.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(Loc.get("Viz_BrowseQueue"))
                        .font(.tv(Size.heading, .semibold))
                        .foregroundStyle(Ink.words)
                    // How many tracks are still to come. The phone's queue shows the same count.
                    Text(toCome)
                        .font(.tv(Size.small))
                        .foregroundStyle(Ink.dim)
                    Spacer()
                    // Shuffles the tracks that have not been played yet. It is one press, not a
                    // mode. The button is hidden when shuffling would change nothing.
                    if model.player.canShuffleWhatIsComing {
                        Button {
                            withAnimation { model.player.shuffleWhatIsComing() }
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 20))
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel(Loc.get("Rpm_Queue_Shuffle"))
                    }
                }
                // Drawn over the rows' content, not over their lit background.
                .padding(.horizontal, Self.listInset + RowStyle.inset)

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 4) {
                            // Shows the rows from where this listening session began, as the
                            // phone's queue does. Tracks above that point were never played.
                            ForEach(Array(rows.enumerated()).filter { $0.offset >= model.player.earliest }, id: \.element.id) { at, row in
                                line(row, at: at, playing: at == playing, played: playing.map { at < $0 } ?? false,
                                     album: albums[AlbumGrouping.key(for: row.track)])
                                    .id(row.id)
                            }
                        }
                        .padding(.horizontal, Self.listInset)
                        .padding(.vertical, 12)
                    }
                    .onAppear {
                        if let playing, rows.indices.contains(playing) {
                            proxy.scrollTo(rows[playing].id, anchor: .center)
                            focused = rows[playing].id
                        } else {
                            // The first row shown is where the session began.
                            let first = model.player.earliest
                            focused = rows.indices.contains(first) ? rows[first].id : rows.first?.id
                        }
                    }
                }
            }
            .padding(.top, 50)
            .frame(width: 1920 * 0.36)
            .frame(maxHeight: .infinity)
            .glassEffect(.regular, in: Rectangle())
            .overlay(alignment: .trailing) {
                Rectangle().fill(Color.white.opacity(0x26 / 255)).frame(width: 1)
            }
            Spacer()
        }
        .ignoresSafeArea()
        .focusSection()
        // Back puts a carried row back. Otherwise it closes the drawer (`Screens.backInPlayer`).
        .onChange(of: screens.playerBackAsked) { _, _ in
            if let row = moving { putBack(row) } else { close() }
        }
        .onChange(of: model.player.queue.count) { _, _ in
            // If the queue changes length during a move, something other than this drawer changed
            // it. The move then ends where it is.
            moving = nil
        }
    }

    /// The "to come" count, such as "3 to come".
    private var toCome: String {
        let left = max(0, model.player.queue.count - ((model.player.index ?? -1) + 1))
        return left == 1 ? Loc.get("Rpm_Queue_ToComeOne") : Loc.get("Rpm_Queue_ToCome", String(left))
    }

    private func line(_ row: Row, at: Int, playing: Bool, played: Bool, album: CloudAlbum?) -> some View {
        let isMoving = moving?.id == row.id
        return Button {
            if moving != nil {
                moving = nil
            } else if holds(at, row) {
                model.jump(to: at)
            }
        } label: {
            HStack(spacing: 18) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white.opacity(isMoving ? 1 : 0.42))
                Sleeve(album: album, edge: 56, corner: 5)
                Text(row.track.title ?? "")
                    .font(.tv(26, playing ? .semibold : .regular))
                    .foregroundStyle(Ink.words)
                    .lineLimit(1)
                Spacer(minLength: 10)
                if row.track.duration > .zero {
                    Text(clock(row.track.duration.seconds))
                        .font(.tv(22).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            // Played rows are dimmed, as on the phone.
            .opacity(isMoving ? 0.86 : (playing ? 1 : (played ? 0.4 : 0.7)))
            .background {
                if playing { RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0x1F / 255)).padding(-10) }
            }
        }
        .buttonStyle(RowStyle())
        .focused($focused, equals: row.id)
        .onMoveCommand { direction in
            switch direction {
            case .up where moving?.id == row.id: step(row, by: -1)
            case .down where moving?.id == row.id: step(row, by: 1)
            case .right where moving == nil: close()
            default: break
            }
        }
        .contextMenu {
            if moving == nil { menu(row, at: at) }
        }
    }

    @ViewBuilder
    private func menu(_ row: Row, at: Int) -> some View {
        let current = model.player.index ?? -1
        Button(Loc.get("AlbumMenu_Play"), systemImage: "play.fill") {
            if holds(at, row) { model.jump(to: at) }
        }
        if at != current, at != current + 1 {
            Button(Loc.get("Viz_QueuePlayNext"), systemImage: "text.line.first.and.arrowtriangle.forward") {
                let now = model.player.index ?? -1
                guard holds(at, row), at != now, at != now + 1 else { return }
                // If the track comes from above the playing row, the playing row moves up one
                // place.
                model.player.move(from: at, to: at < now ? now : now + 1)
            }
        }
        if model.player.queue.count > 1 {
            Button(Loc.get("Viz_QueueMove"), systemImage: "arrow.up.arrow.down") {
                guard holds(at, row) else { return }
                moving = row
                movingAt = at
                movedFrom = at
                focused = row.id
            }
        }
        Button(Loc.get("Viz_QueueRemove"), systemImage: "minus.circle", role: .destructive) {
            guard holds(at, row) else { return }
            let next = rows.indices.contains(at + 1) ? rows[at + 1].id : (at > 0 ? rows[at - 1].id : nil)
            model.player.remove([at])
            // The removed row cannot take the focus. The row that moves into its place takes it.
            focused = next
        }
    }

    /// Whether the player still holds `row` at `at`. Every edit asks this at the moment of the key.
    private func holds(_ at: Int, _ row: Row) -> Bool {
        rows.indices.contains(at) && rows[at].id == row.id
    }

    private func step(_ row: Row, by: Int) {
        guard holds(movingAt, row) else { moving = nil; return }
        let to = movingAt + by
        guard model.player.queue.indices.contains(to) else { return }
        model.player.move(from: movingAt, to: to)
        movingAt = to
        focused = row.id
    }

    private func putBack(_ row: Row) {
        if movingAt != movedFrom, holds(movingAt, row), movedFrom < model.player.queue.count {
            model.player.move(from: movingAt, to: movedFrom)
        }
        moving = nil
        focused = row.id
    }
}
