import SwiftUI
import RPMKit
import RPMLibrary

/// Lets the user choose where a song goes: the playlist tree, one folder at a time, with an Add
/// button at the bottom.
///
/// Ported from `RPM.Mobile/Presentation/Controls/PlaylistPickSheet.xaml`.
///
/// **Tapping a playlist SELECTS it, and the Add button adds the song.** A tap does not add the
/// song at once. A folder and a playlist look alike in a list of places, and a tap that cannot
/// be undone is wrong for a user who is walking through a tree.
public struct PlaylistPickSheet: View {
    private let track: CloudTrack

    /// **Only this account's own lists. The filtering is done here and not at the call site.**
    ///
    /// The tab shows the shelf that is being viewed, and on another user's shelf these are that
    /// user's playlists. They cannot be changed: a playlist names tracks by id under one
    /// account, the store refuses the PUT, and `PlaylistWriter` answers `notYours` to anything
    /// that reaches it. Offering them would only lead to an error message.
    ///
    /// The initialiser keeps only the lists that belong to this account, so there is no way to
    /// create this sheet with a borrowed list. A caller that filters and a caller that forgets
    /// to filter get the same screen.
    private let playlists: [PlaylistSet]

    /// Whether all the lists that were passed in belong to somebody else. **This is a third kind
    /// of empty state**, and it needs a different message from having no playlists: the user is
    /// looking at a borrowed shelf, and its lists are visible on the screen behind this sheet.
    private let borrowed: Bool

    /// - Parameter whenAlreadyThere: what to do with a song that the list already holds.
    ///   The user is asked and the sheet does not decide: see ``add()``.
    private let onAdd: (PlaylistSet, CloudTrack, PlaylistWriter.AlreadyThere) async -> String?
    private let onClose: () -> Void

    public init(track: CloudTrack, playlists: [PlaylistSet],
                onAdd: @escaping (PlaylistSet, CloudTrack,
                                  PlaylistWriter.AlreadyThere) async -> String?,
                onClose: @escaping () -> Void) {
        self.track = track
        self.playlists = playlists.filter { $0.shelf.isOwn }
        self.borrowed = !playlists.isEmpty && !playlists.contains { $0.shelf.isOwn }
        self.onAdd = onAdd
        self.onClose = onClose
    }

    @State private var at: [String] = []
    @State private var picked: String?
    @State private var busy = false
    @State private var said: String?

    /// The list that Add was pressed for, while the question about it is on the screen.
    ///
    /// **It stores the list itself, not a flag.** The user confirms a second copy in *this*
    /// list, and the text on the screen names that list. With a flag, the button would read
    /// `picked` again when it is pressed, and that could be a different list from the one in
    /// the question.
    @State private var asking: PlaylistSet?

    private var browse: PlaylistBrowse {
        PlaylistBrowse.places(at: at, playlists: playlists)
    }

    public var body: some View {
        ZStack {
            // A tap anywhere outside the panel closes it without adding anything.
            Color.black.opacity(0x99 / 255)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            panel
                .frame(width: 320)
                .rpmGlassCard(radius: 18)
        }
        // **A playlist can hold the same song twice, but nobody does it by accident.**
        // When the song is already in the list, the sheet asks the user. Both answers have an
        // effect: Add again puts a second copy in the list.
        //
        // This uses the system alert and not a custom view, because the question must be
        // answered before anything else can happen, and a panel on a glass card cannot
        // enforce that.
        .alert(Loc.get("Rpm_PlaylistPick_AlreadyIn", asking?.name ?? ""),
               isPresented: questioning, presenting: asking) { set in
            Button(Loc.get("Cloud_Cancel"), role: .cancel) { asking = nil }
            Button(Loc.get("Rpm_PlaylistPick_AddAgain")) {
                asking = nil
                file(into: set, whenAlreadyThere: .addAnother)
            }
        } message: { _ in
            Text(Loc.get("Rpm_PlaylistPick_AlreadyInBody"))
        }
    }

    /// Whether the question is shown. The list being asked about decides this, so there is no
    /// second flag to keep in step with it.
    private var questioning: Binding<Bool> {
        Binding(get: { asking != nil }, set: { up in if !up { asking = nil } })
    }

    private var panel: some View {
        VStack(spacing: 0) {
            header

            Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)

            places

            Rectangle().fill(RPMInk.white(0x1A / 255)).frame(height: 1)

            deed
        }
    }

    // ── the song, and where in the tree it is ──

    /// The song that is being added, shown under the title. The row it came from is no longer
    /// visible when this sheet is shown, and a picker that does not name its song makes the
    /// user remember it.
    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            HStack(alignment: .top, spacing: RPMBackKey.besideTitle) {
                if let back = browse.back {
                    RPMBackKey(label: Loc.get("AddMusic_Back")) { at = back; picked = nil }
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(browse.at.last ?? Loc.get("Playlists_AddToPlaylist"))
                        .font(RPMFont.displayBold(19))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(track.title ?? "").rpmKicker().lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Text("\u{f00d}")
                    .font(RPMFont.icon(15))
                    .foregroundStyle(RPMInk.white(0xB8 / 255))
            }
            .buttonStyle(RPMGlassKey(edge: 40))
            .accessibilityLabel(Loc.get("Cloud_Cancel"))
        }
        .padding(.leading, 18)
        .padding(.trailing, 10)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // ── the tree, one level of it ──

    @ViewBuilder
    private var places: some View {
        let rows = browse.rows

        if rows.isEmpty {
            // Three different empty cases: a shelf whose lists all belong to somebody else,
            // a folder that the user opened that holds only folders further down, and an
            // account with no playlists at all.
            Text(borrowed ? Loc.get("Rpm_PlaylistPick_Borrowed")
                 : browse.at.isEmpty ? Loc.get("Rpm_PlaylistPick_Empty")
                 : Loc.get("Rpm_PlaylistPick_EmptyFolder"))
                .rpmKicker()
                .multilineTextAlignment(.center)
                .padding(18)
                .frame(maxWidth: .infinity)
        } else {
            ShortScroll(rows: rows.count, each: 48, upTo: 300) {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        Button { tap(row) } label: { line(row) }
                            .buttonStyle(RowPress())
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func tap(_ row: PlaylistRow) {
        said = nil

        if case .folder(let folder) = row.kind {
            Haptics.pick()
            at = folder.path
            picked = nil
        } else {
            Haptics.tick()
            picked = picked == row.id ? nil : row.id
        }
    }

    private func line(_ row: PlaylistRow) -> some View {
        HStack(spacing: 14) {
            Text(row.isFolder ? Glyph.folder : Glyph.record)
                .font(RPMFont.icon(15))
                .foregroundStyle(RPMInk.white(0xB3 / 255))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(row.name)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(detail(row))
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // A chevron on a folder, because tapping it opens it. A tick on the playlist that
            // the song will be added to. **Never both**: a row shows one or the other.
            if row.isFolder {
                Text(Glyph.into)
                    .font(RPMFont.icon(12))
                    .foregroundStyle(RPMInk.white(0x77 / 255))
            } else if picked == row.id {
                Text("\u{f00c}")
                    .font(RPMFont.icon(14))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }

    private func detail(_ row: PlaylistRow) -> String {
        row.isFolder
            ? (row.playlists == 1 ? Loc.get("Stats_PlaylistsOne")
                                  : Loc.get("Stats_Playlists", row.playlists))
            : PlaylistWords.holding(row.tracks.count, row.duration, missing: row.missing)
    }

    // ── adding the song ──

    private var deed: some View {
        VStack(spacing: 10) {
            if let said {
                Text(said).rpmKicker().frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Button(Loc.get("Cloud_Cancel"), action: onClose)
                    .buttonStyle(RPMGlassButton(.ghost, radius: 10, height: 42, size: 14))

                Button(action: add) {
                    if busy {
                        ProgressView().tint(.white).scaleEffect(0.8)
                    } else {
                        Text(Loc.get("Rpm_PlaylistPick_Add"))
                    }
                }
                .buttonStyle(RPMGlassButton(.primary, radius: 10, height: 42, size: 14))
                .disabled(chosen == nil || busy)
                .opacity(chosen == nil || busy ? 0.45 : 1)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    private var chosen: PlaylistSet? {
        guard let picked else { return nil }
        return playlists.first { $0.id == picked }
    }

    private func add() {
        guard let chosen, !busy else { return }

        // The song is already in the list: ask, and add nothing until the user answers.
        // The count uses the copy stored on this phone, which is what the user sees. The
        // write reads the store again. If the list gained the song on another device a moment
        // ago, the question appears one add later.
        guard chosen.copies(of: track) == 0 else { asking = chosen; return }

        file(into: chosen, whenAlreadyThere: .leaveIt)
    }

    /// Adds the song. The caller **states** what to do about a copy that is already there. The
    /// sheet does not reuse an earlier decision.
    private func file(into set: PlaylistSet, whenAlreadyThere: PlaylistWriter.AlreadyThere) {
        guard !busy else { return }

        busy = true
        said = nil

        Task {
            let trouble = await onAdd(set, track, whenAlreadyThere)
            busy = false

            guard let trouble else { onClose(); return }
            said = trouble
        }
    }
}
