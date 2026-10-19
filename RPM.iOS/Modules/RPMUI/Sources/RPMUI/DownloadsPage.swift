import SwiftUI
import RPMKit
import RPMLibrary

/// The albums downloaded to this phone, and the way to remove them.
///
/// It is shown as a sheet from the Downloads card on ``ProfilePage``, like ``AboutPage``. The
/// profile tab is not inside a `NavigationStack`, because a stack paints its own opaque
/// background over the app's ground.
///
/// One album is removed with a swipe. Several are removed with Select, which shows a tick beside
/// each row and a Remove key under the list. Select all is there because clearing the phone
/// before a trip is the usual reason to open this page.
public struct DownloadsPage: View {
    /// One row: the record, the space it uses on the phone, and its download state.
    public struct Row: Identifiable {
        public let album: CloudAlbum
        public let bytes: Int64
        public let standing: AlbumDownloads.Standing

        public var id: String { album.key }

        public init(album: CloudAlbum, bytes: Int64, standing: AlbumDownloads.Standing) {
            self.album = album
            self.bytes = bytes
            self.standing = standing
        }
    }

    private let rows: [Row]
    private let covers: any CoverStore
    private let onRemove: (Set<String>) -> Void
    private let onClose: () -> Void

    @State private var selecting = false
    @State private var picked: Set<String> = []
    @State private var asking = false

    public init(rows: [Row], covers: any CoverStore,
                onRemove: @escaping (Set<String>) -> Void, onClose: @escaping () -> Void) {
        self.rows = rows
        self.covers = covers
        self.onRemove = onRemove
        self.onClose = onClose
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
                    .font(.system(size: 20))
                    .foregroundStyle(picked.contains(row.id) ? Color.white : RPMInk.white(0x55 / 255))
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }

            RowSleeve(album: row.album, covers: covers)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.album.album)
                    .font(RPMFont.display(15))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(row.album.artist)
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
        let total = rows.reduce(Int64(0)) { $0 + $1.bytes }
        return rows.count == 1
            ? Loc.get("Rpm_Downloads_SummaryOne", Self.size(total))
            : Loc.get("Rpm_Downloads_Summary", rows.count, Self.size(total))
    }

    private var question: String {
        picked.count == 1 ? Loc.get("Rpm_Download_RemoveQuestion")
                          : Loc.get("Rpm_Downloads_RemoveQuestion", picked.count)
    }

    private func state(_ row: Row) -> String {
        switch row.standing {
        case .onPhone: Self.size(row.bytes)
        case .downloading(_, _, _, true): Loc.get("Rpm_Downloads_Preparing")
        case .downloading(_, _, let fraction, false): "\(Int((fraction * 100).rounded()))%"
        case .stuck(let have, let of): Loc.get("Rpm_Download_StuckCount", have, of)
        }
    }

    /// Formats a size in the same way as the profile card.
    public static func size(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = count < 1_000_000 ? [.useKB] : [.useGB, .useMB]
        formatter.countStyle = .binary
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
