import Foundation
import CoreGraphics

/// A photograph, cut for the screen it is going on.
///
/// The work has three steps: **read** the picture (Vision), **choose** the window (shared
/// arithmetic), and **cut** it out. Each step can be tested on its own: the choice without a
/// screen, and the reading without a crop. Only this type needs all three.
///
/// The cut is a redraw, not a `cropping(to:)`. A cropped `CGImage` shares the pixels of its
/// parent, so a thumbnail of a face would keep the whole decoded photograph in memory. The
/// redraw also scales the picture to the size it will be shown at, so it takes a few hundred
/// kilobytes on screen instead of several megabytes.
public enum ArtFrame {
    /// The window of this photograph to show on `scene`'s frame, drawn out at no more than
    /// `widest` pixels across.
    ///
    /// Nil if Vision cannot read the picture or the drawing fails. That is not an error. The
    /// caller then shows the photograph uncropped, and the view fills with it.
    public static func cut(_ photograph: CGImage, for scene: ArtScene, widest: Int) -> CGImage? {
        framed(photograph, for: scene, widest: widest)?.picture
    }

    /// A window, and the reading it was chosen from.
    public struct Framed: Sendable {
        public let picture: CGImage
        public let choice: CropChoice
        public let reading: PhotoReading

        /// The window in the photograph's own pixels. It is used to measure how much the zoom
        /// discards.
        public let window: CropRect
    }

    /// The same cut, with the reading kept.
    ///
    /// For callers that choose between photographs. The score uses the faces, the colour and how
    /// far the window had to zoom. All three are known once the picture is cut, so reading the
    /// photograph again would run Vision twice on the same image.
    public static func framed(_ photograph: CGImage, for scene: ArtScene,
                              widest: Int) -> Framed? {
        // A frame with no size is not a frame. Cutting for one would measure a rectangle against
        // nothing and return a result that looks valid.
        guard scene.isLaidOut, let reading = PhotoVision.read(photograph) else { return nil }

        let choice = SaliencyCrop.choose(
            saliency: reading.saliency,
            width: reading.workWidth, height: reading.workHeight,
            targetAspect: scene.aspect,
            faces: reading.faces, scene: scene)

        let window = PhotoVision.toSource(reading, choice.rect)
        guard let picture = draw(photograph, window, widest: widest) else { return nil }

        return Framed(picture: picture, choice: choice, reading: reading, window: window)
    }

    /// A picture that is already framed on its subject. It is cut for `scene` with no reading:
    /// the largest window of the frame's shape that fits the picture, centred across and kept at
    /// the top.
    ///
    /// Used for fanart.tv's square artist pictures, which are already cut on the person. Reading
    /// them with Vision would only zoom in further on a picture that already fits. The window is
    /// kept at the top because a square in a frame that is wider than it is loses height. Taken
    /// from the middle, it would cut through people's heads. The desktop artist page also keeps
    /// the top.
    ///
    /// Nil if the frame has no size or the drawing fails, as with ``cut(_:for:widest:)``.
    public static func filled(_ photograph: CGImage, for scene: ArtScene, widest: Int) -> CGImage? {
        guard scene.isLaidOut else { return nil }

        let window = topWindow(width: photograph.width, height: photograph.height,
                               aspect: scene.aspect)
        return draw(photograph, window, widest: widest)
    }

    /// Where a face sits on the frame, as a fraction down it. It is measured at the eyes, not at
    /// the middle of Vision's box. The box runs from the forehead to the chin, and the eyes are
    /// what must stay visible.
    static let eyesDown = 0.4

    /// Whether ``filled(_:for:widest:)`` would put the main face where it cannot be seen. That is
    /// when its eyes are above the scene's ``ArtScene/clearTop`` (behind the status bar and the
    /// Dynamic Island), or outside the window.
    ///
    /// The main face is the largest one. A picture with no face has nothing to hide, so it is not
    /// covered. The check catches a square whose whole face would be behind the Dynamic Island.
    ///
    /// - Parameters:
    ///   - faces: the face boxes, in the picture's own pixels (`width` by `height`). See
    ///     ``PhotoVision/faces(_:)``.
    public static func coversFace(_ faces: [FaceBox], width: Int, height: Int,
                                  for scene: ArtScene) -> Bool {
        guard scene.isLaidOut,
              let face = faces.max(by: { $0.width * $0.height < $1.width * $1.height })
        else { return false }

        let window = topWindow(width: width, height: height, aspect: scene.aspect)
        let across = (Double(face.x) + Double(face.width) / 2 - Double(window.x))
            / Double(max(1, window.width))
        let down = (Double(face.y) + Double(face.height) * eyesDown - Double(window.y))
            / Double(max(1, window.height))

        guard (0...1).contains(across), (0...1).contains(down) else { return true }
        return down < scene.clearTop
    }

    /// The largest window of `aspect` (width over height) that fits inside a picture of this size,
    /// centred across and against the top edge.
    static func topWindow(width: Int, height: Int, aspect: Double) -> CropRect {
        let width = max(1, width), height = max(1, height)
        guard aspect > 0 else { return CropRect(x: 0, y: 0, width: width, height: height) }

        if Double(width) / Double(height) > aspect {
            // Wider than the frame: take the full height and trim the sides evenly.
            let across = min(width, max(1, Int((Double(height) * aspect).rounded())))
            return CropRect(x: (width - across) / 2, y: 0, width: across, height: height)
        }

        // Taller than the frame: take the full width and trim the bottom.
        let down = min(height, max(1, Int((Double(width) / aspect).rounded())))
        return CropRect(x: 0, y: 0, width: width, height: down)
    }

    /// The window, copied out at the size it will be drawn. It is never enlarged. A crop narrower
    /// than the screen keeps its own pixel size, and the view scales it up. Scaling here would use
    /// more memory and give the same soft picture.
    private static func draw(_ image: CGImage, _ crop: CropRect, widest: Int) -> CGImage? {
        guard let window = image.cropping(to: CGRect(x: crop.x, y: crop.y,
                                                     width: crop.width, height: crop.height))
        else { return nil }

        let scale = min(1, Double(widest) / Double(max(1, crop.width)))
        let width = max(1, Int((Double(crop.width) * scale).rounded()))
        let height = max(1, Int((Double(crop.height) * scale).rounded()))

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            // No alpha. A backdrop fills the screen and nothing shows through it, and dropping the
            // alpha channel saves a quarter of the memory.
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }

        context.interpolationQuality = .high
        context.draw(window, in: CGRect(x: 0, y: 0, width: width, height: height))

        return context.makeImage()
    }
}
