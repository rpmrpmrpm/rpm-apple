import SwiftUI
import RPMSharedUI
import RPMKit
import RPMLibrary

/// The albums and playlists downloaded to this phone, and the way to remove them.
///
/// It is shown as a sheet from the Downloads card on ``SettingsPage``, like ``AboutPage``. The
/// profile tab is not inside a `NavigationStack`, because a stack paints its own opaque
/// background over the app's ground.
///
/// One album is removed with a swipe. Several are removed with Select, which shows a tick beside
/// each row and a Remove key under the list. Select all is there because clearing the phone
/// before a trip is the usual reason to open this page. A downloaded playlist is a row like an
/// album, so this page shows everything the downloads take.
public struct DownloadsPage: View {
    /// One row: the record or the playlist, the space it uses on the phone, and its download
    /// state.
    public struct Row: Identifiable {
        /// The record, or the playlist as the book keeps it (``AlbumDownloads/entry(for:)``).
        public let album: CloudAlbum
        public let bytes: Int64
        public let standing: AlbumDownloads.Standing

        /// The playlist this row is, for its picture. Nil for a record, and for a downloaded
        /// playlist that is not among the lists on the screen: that row shows the sleeve of its
        /// first record.
        public let list: PlaylistSet?

        public var id: String { album.key }

        /// Whether the row is a playlist and not a record.
        public var isPlaylist: Bool { DownloadBook.isPlaylistKey(album.key) }

        public init(album: CloudAlbum, bytes: Int64, standing: AlbumDownloads.Standing,
                    list: PlaylistSet? = nil) {
            self.album = album
            self.bytes = bytes
            self.standing = standing
            self.list = list
        }
    }

    private let rows: [Row]
    private let covers: any CoverStore
    private let onRemove: (Set<String>) -> Void
    private let onClose: () -> Void

    /// The space every download takes, for the line at the top (``AlbumDownloads/bytes``). A track
    /// that an album and a playlist share is in both rows' sizes and counted once here. Nil adds
    /// up the rows.
    private let total: Int64?

    @State private var selecting = false
    @State private var picked: Set<String> = []
    @State private var asking = false

    public init(rows: [Row], covers: any CoverStore,
                onRemove: @escaping (Set<String>) -> Void, onClose: @escaping () -> Void,
                total: Int64? = nil) {
        self.rows = rows
        self.covers = covers
        self.onRemove = onRemove
        self.onClose = onClose
        self.total = total
    }

    public var body: some View {
        ZStack {
            RPMInk.ground.ignoresSafeArea()

            if rows.isEmpty {
                empty
            } else {
                list
            }
        }
        .safeAreaInset(edge: .top) { bar }
        .safeAreaInset(edge: .bottom) {
            if selecting { removeBar }
        }
        // The selection may only hold rows that still exist. An album that has finished being
        // removed, or was removed another way, must not be removed again.
        .onChange(of: rows.map(\.id)) { _, now in picked.formIntersection(now) }
        .confirmationDialog(question, isPresented: $asking, titleVisibility: .visible) {
            Button(Loc.get("Rpm_Download_Remove"), role: .destructive) {
                onRemove(picked)
                picked = []
                selecting = false
            }
            Button(Loc.get("Common_Cancel"), role: .cancel) {}
        }
    }

    // ── the bar ──

    private var bar: some View {
        HStack {
            Button(Loc.get("About_Close"), action: onClose)
                .buttonStyle(RPMGlassButton(.ghost, radius: 9, height: 34,
                                            stretches: false, inset: 16, size: 13))

            Spacer()

            Text(Loc.get("Rpm_Downloads_Title")).rpmKicker()

            Spacer()

            Button(selecting ? Loc.get("Rpm_Downloads_Done") : Loc.get("Rpm_Downloads_Select")) {
                selecting.toggle()
                if !selecting { picked = [] }
            }
            .buttonStyle(RPMGlassButton(.ghost, radius: 9, height: 34,
                                        stretches: false, inset: 16, size: 13))
            .disabled(rows.isEmpty)
            .opacity(rows.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // ── the list ──

    private var list: some View {
        List {
            Text(summary)
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0x88 / 255))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .plainRow()

            ForEach(rows) { row in
                Button {
                    guard selecting else { return }
                    Haptics.pick()
                    if picked.contains(row.id) { picked.remove(row.id) } else { picked.insert(row.id) }
                } label: {
                    line(row)
                }
                .buttonStyle(.plain)
                .plainRow()
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onRemove([row.id])
                    } label: {
                        Label(Loc.get("Rpm_Download_Remove"), systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 1)
    }

    private func line(_ row: Row) -> some View {
        HStack(spacing: 12) {
            if selecting {
                Image(systemName: picked.contains(row.id) ? "checkmark.circle.fill" : "circle")
                    .font(RPMFont.display(20))
                    .foregroundStyle(picked.contains(row.id) ? Color.white : RPMInk.white(0x55 / 255))
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            if row.isPlaylist {
                // The list's own picture, as on the playlists tab, else its first record's sleeve.
                PlaylistSleeve(list: row.list?.picture, track: row.album.tracks.first,
                               glyph: Glyph.playlists, edge: 48, mark: 16, covers: covers,
                               framed: FramedList.of(row.list))
            } else {
                RowSleeve(album: row.album, covers: covers)
            }

            VStack(alignment: .leading, spacing: 2) {
                MarkedTitle(row.album.album, explicit: !row.isPlaylist && row.album.isExplicit)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                // A playlist has no artist of its own. Its kind is shown in that place, as on
                // home's quick selection.
                Text(row.isPlaylist ? Loc.get("Home_QuickPlaylist") : row.album.artist)
                    .font(RPMFont.display(12))
                    .foregroundStyle(RPMInk.white(0x88 / 255))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(state(row))
                .font(RPMFont.display(12))
                .foregroundStyle(RPMInk.white(0x77 / 255))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.2), value: selecting)
    }

    private var removeBar: some View {
        HStack(spacing: 10) {
            Button(picked.count == rows.count ? Loc.get("Rpm_Downloads_SelectNone")
                                              : Loc.get("Rpm_Downloads_SelectAll")) {
                picked = picked.count == rows.count ? [] : Set(rows.map(\.id))
            }
            .buttonStyle(RPMGlassButton(.ghost, radius: 12, height: 44))

            Button(Loc.get("Rpm_Downloads_RemoveCount", picked.count)) { asking = true }
                .buttonStyle(RPMGlassButton(.primary, radius: 12, height: 44))
                .disabled(picked.isEmpty)
                .opacity(picked.isEmpty ? 0.4 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    // ── no downloads ──

    private var empty: some View {
        VStack(spacing: 12) {
            Text(Glyph.download)
                .font(RPMFont.icon(34))
                .foregroundStyle(RPMInk.white(0x55 / 255))

            Text(Loc.get("Rpm_Downloads_Empty"))
                .font(RPMFont.display(14))
                .foregroundStyle(RPMInk.white(0xAA / 255))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }

    // ── text ──

    private var summary: String {
        let playlists = rows.filter(\.isPlaylist).count
        return Self.summary(albums: rows.count - playlists, playlists: playlists,
                            bytes: total ?? rows.reduce(Int64(0)) { $0 + $1.bytes })
    }

    /// How many albums and playlists are downloaded, and the space they use. Read on this page
    /// and on the Downloads card on ``SettingsPage``. With no downloads at all it is the card's
    /// "none" line.
    ///
    /// Only albums: the album count. One playlist alone: that it is one playlist. Any other mix:
    /// how many downloads there are.
    static func summary(albums: Int, playlists: Int, bytes: Int64) -> String {
        let size = Self.size(bytes)
        if albums + playlists == 0 { return Loc.get("Rpm_Downloads_None") }
        if playlists == 0 {
            return albums == 1 ? Loc.get("Rpm_Downloads_SummaryOne", size)
                               : Loc.get("Rpm_Downloads_Summary", albums, size)
        }
        if albums == 0 && playlists == 1 { return Loc.get("Rpm_Downloads_SummaryOnePlaylist", size) }
        return Loc.get("Rpm_Downloads_SummaryMixed", albums + playlists, size)
    }

    private var question: String {
        let chosen = rows.filter { picked.contains($0.id) }
        let playlists = chosen.filter(\.isPlaylist).count
        if chosen.count == 1 {
            return playlists == 1 ? Loc.get("Rpm_Download_RemovePlaylistQuestion")
                                  : Loc.get("Rpm_Download_RemoveQuestion")
        }
        return playlists == 0 ? Loc.get("Rpm_Downloads_RemoveQuestion", chosen.count)
                              : Loc.get("Rpm_Downloads_RemoveMixedQuestion", chosen.count)
    }

    private func state(_ row: Row) -> String {
        switch row.standing {
        case .onPhone: Self.size(row.bytes)
        case .downloading(_, _, _, true): Loc.get("Rpm_Downloads_Preparing")
        case .downloading(_, _, let fraction, false): "\(Int((fraction * 100).rounded()))%"
        case .stuck(let have, let of): Loc.get("Rpm_Download_StuckCount", have, of)
        }
    }

    /// A size as every page shows one: kilobytes below a million bytes, else megabytes or
    /// gigabytes, in steps of 1024. The Android app's `bytes` gives the same text.
    public static func size(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = count < 1_000_000 ? [.useKB] : [.useGB, .useMB]
        formatter.countStyle = .binary
        // "0 KB", not the formatter's "Zero KB".
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: count)
    }
}

/// A small cover for a row. It is fetched when the row appears.
private struct RowSleeve: View {
    let album: CloudAlbum
    let covers: any CoverStore

    @State private var cover: Cover?

    private static let edge: CGFloat = 48

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)

        ZStack {
            shape.fill(Color.black.opacity(0x22 / 255))

            if let cover {
                Sleeve(image: cover.image)
                    .clipShape(shape)
            } else {
                Text(Glyph.record)
                    .font(RPMFont.icon(16))
                    .foregroundStyle(RPMInk.white(0x3A / 255))
            }
        }
        .frame(width: Self.edge, height: Self.edge)
        .overlay { shape.strokeBorder(RPMInk.cardBorder, lineWidth: 1) }
        .task(id: album.key) {
            cover = nil
            cover = await covers.cover(for: album, edge: Self.edge)
        }
    }
}
