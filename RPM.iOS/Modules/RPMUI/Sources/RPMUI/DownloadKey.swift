import SwiftUI
import RPMKit
import RPMLibrary

/// The data for the download key on an album page or a playlist page: the album's or the list's
/// state on this phone, and the two actions the person can take.
///
/// The key is nil on a borrowed shelf, and not a key that does nothing. A download is signed as
/// the account's own track, and another person's record is not one.
public struct DownloadKey {
    /// The album's download state, or nil if it has not been downloaded.
    public let standing: AlbumDownloads.Standing?
    public let onDownload: () -> Void
    public let onRemove: () -> Void

    /// Whether the key is on a playlist page. Only the questions before a stop or a removal
    /// differ: they name a playlist and not an album.
    public let isPlaylist: Bool

    /// Where one of the page's songs stands on the phone, by its id: what the mark at the end of
    /// its row is made from (``TrackDownloadMark``). The app passes
    /// ``AlbumDownloads/track(_:)``. Read in the mark's own view, so only the marks are drawn
    /// again while a song arrives, not the whole page.
    public let track: (String) -> TrackDownload

    public init(standing: AlbumDownloads.Standing?,
                onDownload: @escaping () -> Void, onRemove: @escaping () -> Void,
                isPlaylist: Bool = false,
                track: @escaping (String) -> TrackDownload = { _ in .absent }) {
        self.standing = standing
        self.onDownload = onDownload
        self.onRemove = onRemove
        self.isPlaylist = isPlaylist
        self.track = track
    }
}

/// The key itself, the same size as the shuffle and heart keys next to it.
///
/// It has five faces: an arrow to download, a turning arc while the store prepares the chosen
/// bitrate, a ring that fills while downloading, a tick when every track is on the phone, and a
/// warning when some tracks could not be downloaded. Removing asks for confirmation first,
/// because a removed album must be downloaded again to play offline.
struct DownloadButton: View {
    let key: DownloadKey

    /// Its mark alone, with no glass, in a box as tall as the Play key beside it: the record page's
    /// keys beside Play are their marks alone.
    var bare = false

    @State private var asking = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            Haptics.pick()
            switch key.standing {
            case nil, .stuck: key.onDownload()
            case .downloading, .onPhone: asking = true
            }
        } label: {
            face
        }
        .buttonStyle(Bare(bare: bare))
        .frame(width: 56)
        .accessibilityLabel(label)
        .confirmationDialog(question, isPresented: $asking, titleVisibility: .visible) {
            Button(action, role: .destructive) { key.onRemove() }
            Button(Loc.get("Common_Cancel"), role: .cancel) {}
        }
    }

    @ViewBuilder
    private var face: some View {
        switch key.standing {
        case nil:
            Text(Glyph.download).font(RPMFont.icon(17))

        case .downloading(_, _, let fraction, let preparing):
            ZStack {
                Circle()
                    .stroke(RPMInk.white(0x33 / 255), lineWidth: 2.5)

                if preparing {
                    // Nothing is transferring yet, so there is no progress to show. A quarter
                    // arc turns instead, like the system's waiting download. It follows the
                    // clock and is not a repeating animation, so rebuilding the view cannot
                    // leave it running or stop it.
                    TimelineView(.animation(paused: reduceMotion)) { time in
                        let turn = time.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: 1)
                        Circle()
                            .trim(from: 0, to: 0.25)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                            .rotationEffect(.degrees(reduceMotion ? -90 : turn * 360))
                    }
                } else {
                    Circle()
                        .trim(from: 0, to: max(0.03, min(1, fraction)))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                }

                // A stop mark in the middle, like the system's download rings.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white)
                    .frame(width: 6, height: 6)
            }
            .frame(width: 20, height: 20)

        case .onPhone:
            Text(Glyph.downloaded).font(RPMFont.icon(17))

        case .stuck:
            Text(Glyph.stuck).font(RPMFont.icon(17))
                .foregroundStyle(RPMInk.white(0xB3 / 255))
        }
    }

    private var label: String {
        switch key.standing {
        case nil: Loc.get("Rpm_Download_Download")
        case .downloading(let have, let of, _, let preparing):
            preparing ? Loc.get("Rpm_Download_Preparing", have, of)
                      : Loc.get("Rpm_Download_Progress", have, of)
        case .onPhone: Loc.get("Rpm_Download_OnPhone")
        case .stuck: Loc.get("Rpm_Download_Stuck")
        }
    }

    private var question: String {
        if case .downloading = key.standing {
            return key.isPlaylist ? Loc.get("Rpm_Download_StopPlaylistQuestion")
                                  : Loc.get("Rpm_Download_StopQuestion")
        }
        return key.isPlaylist ? Loc.get("Rpm_Download_RemovePlaylistQuestion")
                              : Loc.get("Rpm_Download_RemoveQuestion")
    }

    private var action: String {
        if case .downloading = key.standing { return Loc.get("Rpm_Download_Stop") }
        return Loc.get("Rpm_Download_Remove")
    }
}

/// The download key's face: the ghost glass button, or with ``DownloadButton/bare`` its mark alone in
/// a box as tall as that button.
private struct Bare: ButtonStyle {
    let bare: Bool

    func makeBody(configuration: Configuration) -> some View {
        if bare {
            configuration.label
                .font(RPMFont.icon(17))
                .foregroundStyle(RPMInk.white(0xF0 / 255))
                .frame(width: 56, height: 50)
                .contentShape(Rectangle())
                .opacity(configuration.isPressed ? 0.6 : 1)
        } else {
            RPMGlassButton(.ghost, radius: 14, height: 50).makeBody(configuration: configuration)
        }
    }
}

/// The small mark at the end of a song's row on an album page or a playlist page: what the page's
/// download key cannot say about one song. See ``TrackDownloadMark`` for which mark a row shows.
///
/// It is drawn over the row's own trailing margin and takes no room in the row, so a mark that
/// comes or goes never moves the title or the length. Nothing is drawn where there is no key (a
/// borrowed shelf, the queue, the favourite songs) or no mark.
struct RowDownloadMark: View {
    let key: DownloadKey?
    let rpmId: String

    /// The side of the mark: about the size of the length's figures beside it.
    static let edge: CGFloat = 11

    /// The room the mark is centred in: the row's trailing margin.
    static let room: CGFloat = 20

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // The song's state is read here and not in the row, so a song that moves on draws this
        // mark again and not the row or the page.
        if let key, let mark = TrackDownloadMark.of(page: key.standing, track: key.track(rpmId)) {
            face(mark)
                .frame(width: Self.edge, height: Self.edge)
                .frame(width: Self.room)
                .accessibilityElement()
                .accessibilityLabel(label(mark))
                .accessibilityValue(value(mark))
        }
    }

    @ViewBuilder
    private func face(_ mark: TrackDownloadMark) -> some View {
        switch mark {
        case .waiting:
            Circle().stroke(RPMInk.white(0x55 / 255), lineWidth: 1.2)

        case .preparing:
            // Nothing is transferring, so there is no progress to show. A quarter arc turns, as on
            // the key. It follows the clock and is not a repeating animation, so rebuilding the
            // row cannot leave it running or stop it.
            ZStack {
                Circle().stroke(RPMInk.white(0x33 / 255), lineWidth: 1.5)
                TimelineView(.animation(paused: reduceMotion)) { time in
                    let turn = time.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 1)
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(RPMInk.white(0xB3 / 255),
                                style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .rotationEffect(.degrees(reduceMotion ? -90 : turn * 360))
                }
            }

        case .arriving(let fraction):
            ZStack {
                Circle().stroke(RPMInk.white(0x33 / 255), lineWidth: 1.5)
                Circle()
                    .trim(from: 0, to: max(0.03, min(1, fraction)))
                    .stroke(RPMInk.white(0xB3 / 255),
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: fraction)
            }

        case .done:
            Text(Glyph.downloaded).font(RPMFont.icon(Self.edge))
                .foregroundStyle(RPMInk.white(0x77 / 255))
                .fixedSize()

        case .stuck:
            Text(Glyph.stuck).font(RPMFont.icon(Self.edge))
                .foregroundStyle(RPMInk.white(0xB3 / 255))
                .fixedSize()
        }
    }

    private func label(_ mark: TrackDownloadMark) -> String {
        switch mark {
        case .waiting: Loc.get("Cloud_StateQueued")
        case .preparing: Loc.get("Rpm_Downloads_Preparing")
        case .arriving: Loc.get("CloudChip_StageRestoring")
        case .done: Loc.get("Rpm_Download_OnPhone")
        case .stuck: Loc.get("CloudChip_StageFailedRestore")
        }
    }

    /// How much of a song that is arriving has come, as a percentage in the reader's own format.
    private func value(_ mark: TrackDownloadMark) -> Text {
        guard case .arriving(let fraction) = mark else { return Text(verbatim: "") }
        return Text(min(1, max(0, fraction)), format: .percent.precision(.fractionLength(0)))
    }
}
