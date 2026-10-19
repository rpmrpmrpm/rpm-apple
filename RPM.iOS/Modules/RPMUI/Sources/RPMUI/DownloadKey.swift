import SwiftUI
import RPMKit
import RPMLibrary

/// The data for the download key on an album page: the album's state on this phone, and the two
/// actions the person can take.
///
/// The key is nil on a borrowed shelf, and not a key that does nothing. A download is signed as
/// the account's own track, and another person's record is not one.
public struct DownloadKey {
    /// The album's download state, or nil if it has not been downloaded.
    public let standing: AlbumDownloads.Standing?
    public let onDownload: () -> Void
    public let onRemove: () -> Void

    public init(standing: AlbumDownloads.Standing?,
                onDownload: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.standing = standing
        self.onDownload = onDownload
        self.onRemove = onRemove
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
        .buttonStyle(RPMGlassButton(.ghost, radius: 14, height: 50))
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
        if case .downloading = key.standing { return Loc.get("Rpm_Download_StopQuestion") }
        return Loc.get("Rpm_Download_RemoveQuestion")
    }

    private var action: String {
        if case .downloading = key.standing { return Loc.get("Rpm_Download_Stop") }
        return Loc.get("Rpm_Download_Remove")
    }
}
