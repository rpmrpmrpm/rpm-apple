import Foundation
import CoreGraphics
import CoreML
import CoreVideo
import os.log
import Vision

/// One photograph, read: a saliency map and the faces, both in the same working space,
/// plus the size of the picture they were measured against.
public struct PhotoReading: Sendable {
    /// One score per pixel of the working space, row by row. This is what ``SaliencyCrop/choose`` takes.
    public let saliency: [Double]
    public let workWidth: Int, workHeight: Int

    /// Every face found, in the working space's pixels. An empty list is a real answer: no face was found.
    public let faces: [FaceBox]

    /// The picture the reading was taken from, so a crop can be scaled back onto it.
    public let sourceWidth: Int, sourceHeight: Int

    /// A small RGBA copy, for the colour and contrast that the chooser reads. It comes from the same decode,
    /// so a photograph is read once and answers both questions.
    public let thumbnail: [UInt8]
    public let thumbWidth: Int, thumbHeight: Int
}

/// The faces in a picture, in a working space with the picture's own shape. See ``PhotoVision/faces(_:)``.
public struct FaceReading: Sendable {
    public let faces: [FaceBox]
    public let width: Int, height: Int
}

/// The two measurements that the art system uses: what the photograph is about, and where the faces are.
/// Both are taken from Vision.
///
/// This is a port in shape of `RPM.Mobile/Services/PhotoVision.cs`.
///
/// The desktop app ships two ONNX models for this: u2netp for saliency and ultraface for faces. Together they
/// are 5.6 MB and need a native runtime. iOS has both measurements built in, on the Neural Engine. Nothing has
/// to be shipped or loaded at launch. The models are different, but they give the same two numbers. The
/// arithmetic that turns them into a crop is shared code, tested separately, in ``SaliencyCrop``.
///
/// Vision's saliency map is coarse: 68 squares across. It is expanded into a working space that is big enough
/// to hold the face boxes at full precision. The faces decide the framing. Quantising them to 68 cells would
/// throw away most of what makes the crop useful.
public enum PhotoVision {
    /// The long edge of the space the crop is computed in. It is big enough for a face box to land on the right
    /// pixel, and small enough that the saliency map stays at about a megabyte.
    public static let workLongEdge = 512

    /// The long edge of the thumbnail that the look is read from. It is 96 pixels, the same size the desktop's
    /// preselector uses. Both platforms then judge a photograph's colour and contrast the same way.
    public static let thumbLongEdge = 96

    /// Below this confidence, Vision has found a shape that might be a face. A crop placed on a maybe is worse
    /// than one placed on the saliency map.
    private static let minFaceConfidence: Float = 0.4

    /// Reads a photograph. Nil for anything Vision refuses. The caller then shows the picture uncropped.
    public static func read(_ image: CGImage) -> PhotoReading? {
        let sourceWidth = image.width, sourceHeight = image.height
        guard sourceWidth > 0, sourceHeight > 0 else { return nil }

        let saliencyRequest = VNGenerateAttentionBasedSaliencyImageRequest()
        let faceRequest = VNDetectFaceRectanglesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])

        // **The faces are requested on their own, before the saliency.** If they are performed together, a refused
        // saliency request also cancels the face request. A refused saliency is not rare. The simulators have no
        // model for it ("Failed to create espresso context"). The faces alone decide most framings.
        do {
            try perform([faceRequest], on: handler)
        } catch {
            // A photograph that Vision will not read is shown uncropped. This is logged when the stage diagnostics
            // are on, because "the crop did nothing" and "the crop chose the middle" look the same otherwise.
            say("refused a \(sourceWidth)x\(sourceHeight) photograph: \(error)")
            return nil
        }
        let saliencyRead = (try? perform([saliencyRequest], on: handler)) != nil

        let scale = min(1, Double(workLongEdge) / Double(max(sourceWidth, sourceHeight)))
        let workWidth = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let workHeight = max(1, Int((Double(sourceHeight) * scale).rounded()))

        let faces = found(faceRequest, workWidth: workWidth, workHeight: workHeight)

        let saliency: [Double]
        if saliencyRead, let read = map(saliencyRequest, workWidth: workWidth, workHeight: workHeight) {
            saliency = read
        } else if !faces.isEmpty {
            // There is no saliency map, but there are faces. Use a flat map, so the faces alone place the crop.
            say("no saliency map for a \(sourceWidth)x\(sourceHeight) photograph; cut on its faces")
            saliency = [Double](repeating: 1, count: workWidth * workHeight)
        } else {
            say("no saliency map and no face in a \(sourceWidth)x\(sourceHeight) photograph")
            return nil
        }

        let (thumb, thumbWidth, thumbHeight) = small(image)

        return PhotoReading(saliency: saliency,
                            workWidth: workWidth, workHeight: workHeight,
                            faces: faces,
                            sourceWidth: sourceWidth, sourceHeight: sourceHeight,
                            thumbnail: thumb, thumbWidth: thumbWidth, thumbHeight: thumbHeight)
    }

    /// The faces in a photograph and nothing else. There is no saliency map and no thumbnail. This is for a
    /// picture whose cut is not chosen from a reading, such as the squares (see ``ArtFrame/filled(_:for:widest:)``).
    /// Here the only question is where the face is.
    ///
    /// Nil if Vision refuses the picture. That means "not known", not "no face".
    public static func faces(_ image: CGImage) -> FaceReading? {
        guard image.width > 0, image.height > 0 else { return nil }

        let request = VNDetectFaceRectanglesRequest()
        do {
            try perform([request], on: VNImageRequestHandler(cgImage: image, options: [:]))
        } catch {
            say("refused a \(image.width)x\(image.height) picture for faces: \(error)")
            return nil
        }

        let scale = min(1, Double(workLongEdge) / Double(max(image.width, image.height)))
        let workWidth = max(1, Int((Double(image.width) * scale).rounded()))
        let workHeight = max(1, Int((Double(image.height) * scale).rounded()))

        return FaceReading(faces: found(request, workWidth: workWidth, workHeight: workHeight),
                           width: workWidth, height: workHeight)
    }

    /// A small RGBA copy. An empty copy is a real answer. The look is then scored as unmeasured, not as bad. The
    /// difference is between "nobody could read this" and "this is a black photograph".
    private static func small(_ image: CGImage) -> ([UInt8], Int, Int) {
        let scale = min(1, Double(thumbLongEdge) / Double(max(image.width, image.height)))
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))

        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }

            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }

        return drawn ? (pixels, width, height) : ([], 0, 0)
    }

    private static let diag = ProcessInfo.processInfo.environment["RPM_STAGE_DIAG"] != nil
    private static let log = Logger(subsystem: "com.rpm.player", category: "art")

    private static func say(_ what: String) {
        guard diag else { return }

        log.notice("\(what, privacy: .public)")
    }

    /// Rescales a crop from the working space onto the photograph's own pixels. The working space is a uniform
    /// scale of the photograph, so one factor applies to both axes.
    public static func toSource(_ reading: PhotoReading, _ crop: CropRect) -> CropRect {
        let scale = Double(reading.sourceWidth) / Double(max(1, reading.workWidth))

        let x = min(max(Int((Double(crop.x) * scale).rounded()), 0), max(0, reading.sourceWidth - 1))
        let y = min(max(Int((Double(crop.y) * scale).rounded()), 0), max(0, reading.sourceHeight - 1))
        let width = min(max(Int((Double(crop.width) * scale).rounded()), 1), reading.sourceWidth - x)
        let height = min(max(Int((Double(crop.height) * scale).rounded()), 1), reading.sourceHeight - y)

        return CropRect(x: x, y: y, width: width, height: height)
    }

    // ── Vision, unpacked ──

    /// Runs the requests on the device's default compute unit, and on the CPU if that fails. Some devices have no
    /// inference context for it. The simulators do not, and neither does an Apple TV without a Neural Engine.
    /// They report "Could not create inference context" and cancel the request. The CPU then reads the same faces,
    /// more slowly.
    private static func perform(_ requests: [VNRequest], on handler: VNImageRequestHandler) throws {
        do {
            try handler.perform(requests)
        } catch {
            let cpu = MLComputeDevice.allComputeDevices.first { device in
                if case .cpu = device { true } else { false }
            }
            guard let cpu else { throw error }
            for request in requests { request.setComputeDevice(cpu, for: .main) }
            try handler.perform(requests)
        }
    }

    /// Vision returns saliency as a small one-channel float buffer. It is expanded to the working space by
    /// nearest neighbour. Interpolating a 68-cell map adds no information, and the crop reads it as regions,
    /// not as a gradient.
    private static func map(_ request: VNGenerateAttentionBasedSaliencyImageRequest,
                            workWidth: Int, workHeight: Int) -> [Double]? {
        guard let observation = request.results?.first as? VNSaliencyImageObservation
        else { return nil }

        let buffer = observation.pixelBuffer
        let mapWidth = CVPixelBufferGetWidth(buffer)
        let mapHeight = CVPixelBufferGetHeight(buffer)
        guard mapWidth > 0, mapHeight > 0 else { return nil }

        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let stride = CVPixelBufferGetBytesPerRow(buffer)

        var small = [Double](repeating: 0, count: mapWidth * mapHeight)
        for y in 0..<mapHeight {
            let row = (base + y * stride).assumingMemoryBound(to: Float.self)
            for x in 0..<mapWidth {
                small[y * mapWidth + x] = Double(max(0, row[x]))
            }
        }

        var expanded = [Double](repeating: 0, count: workWidth * workHeight)
        for y in 0..<workHeight {
            let from = min(mapHeight - 1, y * mapHeight / workHeight) * mapWidth
            let into = y * workWidth
            for x in 0..<workWidth {
                expanded[into + x] = small[from + min(mapWidth - 1, x * mapWidth / workWidth)]
            }
        }

        return expanded
    }

    /// Vision's boxes use normalised coordinates with the origin at the bottom left. The crop's boxes use pixels
    /// with the origin at the top left. ``FaceBox/fromNormalizedBottomLeft`` does that conversion, and it is
    /// tested there, not here.
    private static func found(_ request: VNDetectFaceRectanglesRequest,
                              workWidth: Int, workHeight: Int) -> [FaceBox] {
        guard let results = request.results else { return [] }

        return results.compactMap { observation in
            guard observation.confidence >= minFaceConfidence else { return nil }

            let box = observation.boundingBox
            let face = FaceBox.fromNormalizedBottomLeft(
                x: box.origin.x, y: box.origin.y,
                width: box.size.width, height: box.size.height,
                pixelWidth: workWidth, pixelHeight: workHeight)

            return face.width > 0 && face.height > 0 ? face : nil
        }
    }
}
