import CoreImage
import UIKit
import WidgetKit
import RPMKit

/// Writes what is playing into the App Group folder for the home screen widget (``WidgetCard``,
/// ``WidgetShelf``), and asks for the widget to be drawn again.
///
/// It is fed by `RemoteControl.onCard`, so the widget shows what the lock screen shows. When the
/// lock screen's card is taken down, the widget keeps the last song and shows it paused.
///
/// Only a change is written: the same song, play state and cover again writes nothing. The
/// pictures are written only when the cover changes. The writes are done one after the other,
/// away from the main thread, so a later song is never overwritten by an earlier one.
@MainActor
final class WidgetFeed {
    /// What was written last. The cover is known by the identity of its image.
    private struct Shown: Equatable {
        let title: String
        let artist: String
        let playing: Bool
        let cover: ObjectIdentifier?
    }

    private var shown: Shown?
    private var writing: Task<Void, Never>?

    /// The longest side of the cover written for the widget, in pixels.
    nonisolated private static let coverSide: CGFloat = 600

    func show(title: String?, artist: String?, playing: Bool, artwork: UIImage?) {
        guard WidgetShelf.folder != nil else { return }

        let now: Shown
        if let title {
            now = Shown(title: title, artist: artist ?? "", playing: playing,
                        cover: artwork.map(ObjectIdentifier.init))
        } else {
            // The card was taken down: the last song stays, paused.
            guard let last = shown else { return }
            now = Shown(title: last.title, artist: last.artist, playing: false, cover: last.cover)
        }
        guard now != shown else { return }

        let coverChanged = now.cover != shown?.cover
        shown = now

        let card = WidgetCard(title: now.title, artist: now.artist, playing: now.playing,
                              previous: Loc.get("Transport_Previous"),
                              playPause: Loc.get("Transport_PlayPause"),
                              next: Loc.get("Transport_Next"))
        // Made small here, where the image may be read. The blur is done away from the main
        // thread, from these bytes.
        let cover = coverChanged ? artwork.flatMap(Self.smallJPEG) : nil

        let before = writing
        writing = Task.detached(priority: .utility) {
            await before?.value
            Self.store(card, cover: cover, coverChanged: coverChanged)
            await MainActor.run {
                WidgetCenter.shared.reloadTimelines(ofKind: WidgetCard.kind)
            }
        }
    }

    /// The picture as a JPEG, no larger than ``coverSide`` on its longer side.
    nonisolated private static func smallJPEG(_ picture: UIImage) -> Data? {
        let longest = max(picture.size.width, picture.size.height)
        guard longest > 0 else { return nil }

        let scale = min(1, coverSide / longest)
        let size = CGSize(width: (picture.size.width * scale).rounded(),
                          height: (picture.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            picture.draw(in: CGRect(origin: .zero, size: size))
        }
        return small.jpegData(compressionQuality: 0.85)
    }

    /// Writes the pictures (when the cover changed) and then the card. The card is written last,
    /// so the widget never reads a card whose pictures are not there yet.
    nonisolated private static func store(_ card: WidgetCard, cover: Data?, coverChanged: Bool) {
        guard let folder = WidgetShelf.folder, let cardFile = WidgetShelf.cardFile,
              let coverFile = WidgetShelf.coverFile, let backdropFile = WidgetShelf.backdropFile
        else { return }

        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)

        if coverChanged {
            if let cover {
                try? cover.write(to: coverFile, options: .atomic)
                if let soft = blurred(cover) {
                    try? soft.write(to: backdropFile, options: .atomic)
                } else {
                    try? files.removeItem(at: backdropFile)
                }
            } else {
                // A song with no cover (yet): no old cover stays under its name.
                try? files.removeItem(at: coverFile)
                try? files.removeItem(at: backdropFile)
            }
        }

        if let data = try? JSONEncoder().encode(card) {
            try? data.write(to: cardFile, options: .atomic)
        }
    }

    /// The cover, blurred strongly, for the widget's ground. The edges are carried out before the
    /// blur, so the picture does not fade to clear at its sides.
    nonisolated private static func blurred(_ jpeg: Data) -> Data? {
        guard let image = CIImage(data: jpeg) else { return nil }

        let soft = image.clampedToExtent()
            .applyingGaussianBlur(sigma: 22)
            .cropped(to: image.extent)
        guard let drawn = CIContext().createCGImage(soft, from: image.extent) else { return nil }
        return UIImage(cgImage: drawn).jpegData(compressionQuality: 0.8)
    }
}
