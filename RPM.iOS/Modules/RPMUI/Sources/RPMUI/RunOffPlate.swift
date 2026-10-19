import SwiftUI
import CoreImage
import CoreGraphics

/// ``RunOff`` drawn once into a bitmap, for a card whose photograph has loaded.
///
/// The live ``RunOff`` draws the photograph twelve times, with nine Gaussian blurs and a dozen
/// masks. Core Animation keeps none of those between frames, so a card on screen would pay for
/// all of them on every frame of a scroll, a pull, or a nearby view that is moving. None of it
/// changes once the photograph is in, so it is drawn here once, off the main thread, and the
/// card shows the result.
///
/// The steps are the live view's, in the same order and at the same radii: the face (the
/// photograph filled, held back by ``HomeFeatureCard/held``, the ``HomeFeatureCard/foot`` wash),
/// the two blurs towards the foot, the face turned over under itself, and the blur over the seam.
/// Blending is done in gamma-encoded sRGB, which is what Core Animation blends in, so the two
/// agree.
struct RunOffPlate: Sendable {
    /// What this bitmap was drawn for. The card shows it only while every field still matches
    /// what the card would draw now. Otherwise it draws the live ``RunOff`` until a new one is
    /// ready.
    struct Ask: Hashable, Sendable {
        /// Which photograph, by identity. A new decode of the same file is a new picture.
        let picture: ObjectIdentifier
        let width: Double
        let plate: Double
        let depth: Double
        let blurFrom: Double
        let reflection: RunOffReflection
        let scale: Double
    }

    let ask: Ask
    let image: CGImage

    /// Draws the plate. Returns nil where Core Image cannot, and the card then keeps the live view.
    static func bake(_ picture: CGImage, for ask: Ask) async -> RunOffPlate? {
        await Task.detached(priority: .userInitiated) {
            draw(picture, for: ask).map { RunOffPlate(ask: ask, image: $0) }
        }.value
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    private static let context = CIContext(options: [
        .workingColorSpace: sRGB,
        .outputColorSpace: sRGB,
        .cacheIntermediates: false,
    ])

    /// Everything below is in pixels, with Core Image's origin at the bottom left. A distance
    /// `y` points down from the top of the plate is at `total - y * scale`.
    private static func draw(_ picture: CGImage, for ask: Ask) -> CGImage? {
        let s = ask.scale
        let width = (ask.width * s).rounded()
        let plate = (ask.plate * s).rounded()
        let depth = (ask.depth * s).rounded()
        let total = plate + depth
        guard width > 0, plate > 0 else { return nil }

        guard let face = face(picture, width: Int(width), height: Int(plate)) else { return nil }
        let sharp = CIImage(cgImage: face)

        // The card as it shows: sharp, then softened towards the foot in two steps.
        func ramp(from: Double, to: Double) -> CIImage {
            fade(fromY: plate * (1 - from), toY: plate * (1 - to))
        }
        var painted = blur(sharp, 10 * s)
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: sharp,
                kCIInputMaskImageKey: ramp(from: ask.blurFrom, to: min(1, ask.blurFrom + 0.3)),
            ])
        painted = blur(sharp, 32 * s)
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: painted,
                kCIInputMaskImageKey: ramp(from: min(0.95, ask.blurFrom + 0.2), to: 1),
            ])
            .cropped(to: sharp.extent)

        // What is turned over under the card. See ``RunOffReflection``.
        let underneath: CIImage
        switch ask.reflection {
        case .asDrawn: underneath = painted
        case .blurred: underneath = blur(sharp, 32 * s)
        }

        // The card at the top of the canvas, and the card turned over about its foot under it.
        let above = painted.transformed(by: CGAffineTransform(translationX: 0, y: depth))
        let turned = underneath
            .transformed(by: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: depth))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: depth))
        let canvas = CGRect(x: 0, y: 0, width: width, height: total)
        let mirrored = above.composited(over: turned).cropped(to: canvas)

        // The blur over the line where the two meet: none above 50 points over the foot, all of it
        // within the middle third of the 100 points round the foot, none below.
        let reach = 50 * s
        let edge = depth
        let rising = fade(fromY: edge + reach, toY: edge + reach / 3)
        let falling = fade(fromY: edge - reach, toY: edge - reach / 3)
        let seam = rising.applyingFilter("CIMinimumCompositing",
                                         parameters: [kCIInputBackgroundImageKey: falling])

        let finished = blur(mirrored, 20 * s)
            .applyingFilter("CIBlendWithAlphaMask", parameters: [
                kCIInputBackgroundImageKey: mirrored,
                kCIInputMaskImageKey: seam,
            ])
            .cropped(to: canvas)

        return context.createCGImage(finished, from: canvas, format: .RGBA8, colorSpace: sRGB)
    }

    /// The photograph filled and centred, held back, and the foot wash over it. This is what the
    /// live view calls `face`.
    private static func face(_ picture: CGImage, width: Int, height: Int) -> CGImage? {
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                 bytesPerRow: 0, space: sRGB,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let w = Double(width), h = Double(height)
        let fill = max(w / Double(picture.width), h / Double(picture.height))
        let drawn = CGSize(width: Double(picture.width) * fill, height: Double(picture.height) * fill)
        cg.interpolationQuality = .high
        cg.draw(picture, in: CGRect(x: (w - drawn.width) / 2, y: (h - drawn.height) / 2,
                                    width: drawn.width, height: drawn.height))

        cg.setFillColor(CGColor(gray: 0, alpha: HomeFeatureCard.held))
        cg.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // ``HomeFeatureCard/foot``'s stops, top to foot.
        let stops: [(location: Double, alpha: Double)] = [(0, 0), (0.4, 0.25), (0.68, 0.7), (1, 0.7)]
        if let gradient = CGGradient(
            colorsSpace: sRGB,
            colors: stops.map { CGColor(srgbRed: 0, green: 0, blue: 0, alpha: $0.alpha) } as CFArray,
            locations: stops.map { CGFloat($0.location) }) {
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: .zero, options: [
                .drawsBeforeStartLocation, .drawsAfterEndLocation,
            ])
        }

        return cg.makeImage()
    }

    /// A blur that keeps its edges opaque, which is what `.blur(radius:opaque: true)` does.
    private static func blur(_ image: CIImage, _ sigma: Double) -> CIImage {
        image.clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: image.extent)
    }

    /// A mask that is clear at `fromY` and opaque at `toY`, held at each end beyond them.
    private static func fade(fromY: Double, toY: Double) -> CIImage {
        CIImage.empty().applyingFilter("CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: 0, y: fromY),
            "inputPoint1": CIVector(x: 0, y: toY),
            "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0),
            "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 1),
        ])
    }
}
