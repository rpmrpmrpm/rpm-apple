import SwiftUI
import UIKit
import RPMKit
import RPMRadio
import RPMArt

/// The covers of the songs stations announce, passed down the view tree. Nil: a station shows its
/// logo only.
private struct SongCoversKey: EnvironmentKey {
    static let defaultValue: SongCovers? = nil
}

extension EnvironmentValues {
    public var songCovers: SongCovers? {
        get { self[SongCoversKey.self] }
        set { self[SongCoversKey.self] = newValue }
    }
}

/// The cover of the song a station announces, for drawing over the station's logo, as the desktop
/// and the Android app do. It draws nothing while the station announces no song with an artist and
/// a title, while it reconnects (the caller passes nil), and for a song with no cover found, so the
/// logo under it shows.
///
/// A new song keeps the last song's cover until its own is loaded, so the picture goes from cover to
/// cover and not through the logo. A song with none gives the logo back.
public struct SongCoverPicture: View {
    private let ask: SongAsk?
    private let edge: CGFloat
    private let onColours: ((SleeveColours?) -> Void)?

    @Environment(\.songCovers) private var covers
    @Environment(\.rpmReach) private var reach
    @State private var shown: UIImage?

    /// - Parameters:
    ///   - ask: the song to show the cover of, from ``StationSaid/coverAsk``.
    ///   - edge: the size the cover is drawn at, in points.
    ///   - onColours: called with the colours of each cover as it is shown, and with nil when the
    ///     logo shows again. The player lights its room and its glass from them.
    public init(_ ask: SongAsk?, edge: CGFloat,
                onColours: ((SleeveColours?) -> Void)? = nil) {
        self.ask = ask
        self.edge = edge
        self.onColours = onColours
    }

    public var body: some View {
        ZStack {
            if let shown {
                Image(uiImage: shown)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: edge, height: edge)
        .clipped()
        .animation(.easeInOut(duration: 0.4), value: shown)
        .task(id: ask) { await follow() }
    }

    private func follow() async {
        guard let ask, let covers else {
            show(nil)
            return
        }
        let address: URL?
        if let known = covers.peek(ask) {
            address = known
        } else {
            address = await covers.cover(ask)
        }
        guard !Task.isCancelled else { return }
        guard let address else {
            show(nil)
            return
        }
        // The picture is loaded before it is shown, so the last song's cover stays until then.
        let picture = SmallPictures.inMemory(address, edge: edge)
        let loaded: UIImage?
        if let picture {
            loaded = picture
        } else {
            loaded = await SmallPictures.of(address, edge: edge, reach: reach)
        }
        guard !Task.isCancelled else { return }
        show(loaded)

        // The colours are read off the main thread, from the small picture already loaded.
        guard let onColours, let image = loaded?.cgImage else { return }
        let colours = await Task.detached(priority: .utility) {
            Thumbnail.colours(of: image)
        }.value
        guard !Task.isCancelled else { return }
        onColours(colours)
    }

    /// Shows `picture`, or the logo for nil, and says so to ``onColours`` when the logo comes back.
    private func show(_ picture: UIImage?) {
        shown = picture
        if picture == nil { onColours?(nil) }
    }
}
