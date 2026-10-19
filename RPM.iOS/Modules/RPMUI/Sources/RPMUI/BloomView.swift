import SwiftUI
import MetalKit
import simd
import RPMStages

/// Draws the flower of light (see `Bloom.metal`).
///
/// **This is the only visualiser with its own renderer.** The others are fragment functions
/// that SwiftUI runs in its own pass, which is the cheapest way to draw a picture that depends
/// only on the pixel. This one draws 12,700 instanced quads on a three-dimensional phyllotaxis
/// spiral. That needs a vertex stage, so it uses its own pipeline on an `MTKView`, as the
/// desktop app does.
///
/// Drawing is additive, with no depth buffer and no sorting: light adds up where petals
/// overlap, and addition gives the same result in any order.
struct BloomView: UIViewRepresentable {
    let field: BloomField

    /// Read so that SwiftUI calls `updateUIView`, which draws one frame. The clock belongs to
    /// the stage, so this look does not need a display link of its own.
    let tick: Int

    /// Instance counts: 12,000 petals and 700 motes.
    static let petals = 12_000, motes = 700

    /// The dark navy colour the frame is cleared to.
    private static let ground = MTLClearColor(red: 0.006, green: 0.010, blue: 0.024, alpha: 1)

    func makeCoordinator() -> Renderer { Renderer(field: field) }

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: context.coordinator.device)

        view.delegate = context.coordinator
        view.clearColor = Self.ground
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.isOpaque = true
        view.isUserInteractionEnabled = false

        // **Draws only when asked, not on its own clock.** The stage already runs a display
        // link for the audio tap. A second link here would give two clocks for one picture.
        view.isPaused = true
        view.enableSetNeedsDisplay = false

        return view
    }

    func updateUIView(_ view: MTKView, context: Context) {
        context.coordinator.field = field
        view.draw()
    }

    /// Owns the Metal objects and draws each frame.
    final class Renderer: NSObject, MTKViewDelegate {
        let device: MTLDevice?
        var field: BloomField

        private var queue: MTLCommandQueue?
        private var pipeline: MTLRenderPipelineState?
        private var corners: MTLBuffer?
        private var history: MTLTexture?

        /// The spectrogram in the texture's format: one byte per value, row-major.
        private var rows = [UInt8](repeating: 0, count: BloomField.bands * BloomField.columns)

        private var began = CACurrentMediaTime()
        private var lastFrame: CFTimeInterval = 0

        init(field: BloomField) {
            self.field = field
            device = MTLCreateSystemDefaultDevice()

            super.init()
            build()
        }

        /// Creates everything that is made once. If any step fails, the pipeline stays nil and
        /// the view shows only its clear colour.
        private func build() {
            guard let device,
                  let library = try? device.makeDefaultLibrary(bundle: .module),
                  let vertex = library.makeFunction(name: "rpmBloomVertex"),
                  let fragment = library.makeFunction(name: "rpmBloomFragment")
            else { return }

            queue = device.makeCommandQueue()

            let describe = MTLRenderPipelineDescriptor()
            describe.vertexFunction = vertex
            describe.fragmentFunction = fragment
            describe.colorAttachments[0].pixelFormat = .bgra8Unorm

            // Additive: overlapping petals accumulate into the glow at the heart.
            describe.colorAttachments[0].isBlendingEnabled = true
            describe.colorAttachments[0].rgbBlendOperation = .add
            describe.colorAttachments[0].alphaBlendOperation = .add
            describe.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            describe.colorAttachments[0].destinationRGBBlendFactor = .one
            describe.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            describe.colorAttachments[0].destinationAlphaBlendFactor = .one

            pipeline = try? device.makeRenderPipelineState(descriptor: describe)

            // One quad made of two triangles. Every instance uses it, and the vertex function
            // places and turns it.
            let quad: [SIMD2<Float>] = [
                SIMD2(-1, -1), SIMD2(1, -1), SIMD2(1, 1),
                SIMD2(-1, -1), SIMD2(1, 1), SIMD2(-1, 1),
            ]
            corners = device.makeBuffer(bytes: quad,
                                        length: MemoryLayout<SIMD2<Float>>.stride * quad.count,
                                        options: .storageModeShared)

            let shape = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm, width: BloomField.columns, height: BloomField.bands,
                mipmapped: false)
            shape.usage = .shaderRead
            shape.storageMode = .shared
            history = device.makeTexture(descriptor: shape)
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

        func draw(in view: MTKView) {
            guard let queue, let pipeline, let corners, let history,
                  let target = view.currentRenderPassDescriptor,
                  let drawable = view.currentDrawable,
                  let buffer = queue.makeCommandBuffer(),
                  let pass = buffer.makeRenderCommandEncoder(descriptor: target)
            else { return }

            let now = CACurrentMediaTime() - began
            let since = lastFrame > 0 ? min(0.1, now - lastFrame) : 0
            lastFrame = now

            field.turn(since)
            upload(history)

            let size = view.drawableSize
            var uniforms = look(at: now, width: Float(size.width), height: Float(size.height))

            pass.setRenderPipelineState(pipeline)
            pass.setVertexBuffer(corners, offset: 0, index: 0)
            pass.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            pass.setVertexTexture(history, index: 0)
            pass.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

            pass.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6,
                                instanceCount: BloomView.petals + BloomView.motes)
            pass.endEncoding()

            buffer.present(drawable)
            buffer.commit()
        }

        /// Copies the spectrogram into the texture. One byte per value is enough: the shader
        /// reads one channel, and the result is only drawn, never read back.
        private func upload(_ texture: MTLTexture) {
            let read = field.history
            for i in rows.indices { rows[i] = UInt8(min(255, max(0, read[i] * 255 + 0.5))) }

            rows.withUnsafeBytes { bytes in
                texture.replace(
                    region: MTLRegionMake2D(0, 0, BloomField.columns, BloomField.bands),
                    mipmapLevel: 0, withBytes: bytes.baseAddress!,
                    bytesPerRow: BloomField.columns)
            }
        }

        /// The values passed to the vertex function. The layout must match `BloomUniforms` in
        /// the shader, member for member. Metal does not check this.
        private struct Uniforms {
            var viewProjection: simd_float4x4
            var camera: SIMD3<Float>
            var time: Float
            var swell: Float
            var turn: Float
            var resolution: SIMD2<Float>
        }

        /// The camera orbits the bloom and moves up and down. From above the bloom looks like a
        /// mandala, and from low down it shows the height of the petals.
        private func look(at now: Double, width: Float, height: Float) -> Uniforms {
            let t = Float(now)
            let swell = field.swell

            let orbit = t * 0.043
            // Radians above the plane.
            let pitch = 0.62 + sin(t * 0.037) * 0.34
            let dist = 2.42 - swell * 0.20 + sin(t * 0.021) * 0.22

            let eye = SIMD3<Float>(cos(orbit) * cos(pitch) * dist,
                                   sin(pitch) * dist,
                                   sin(orbit) * cos(pitch) * dist)
            let at = SIMD3<Float>(0, 0.10, 0)

            let view = Self.lookAt(eye: eye, at: at, up: SIMD3<Float>(0, 1, 0))
            let projection = Self.perspective(fov: .pi / 3.4,
                                              aspect: width / max(1, height),
                                              near: 0.05, far: 24)

            return Uniforms(viewProjection: projection * view,
                            camera: eye, time: t, swell: swell, turn: field.turned,
                            resolution: SIMD2(width, height))
        }

        /// A right-handed look-at, in the column-vector convention Metal multiplies in.
        ///
        /// Written here and not copied from the desktop code. The desktop uses `System.Numerics`
        /// (row-vector matrices) and uploads them to a GL uniform that reads column-major,
        /// which transposes them. That transpose has no equivalent here, so only the picture
        /// is matched.
        private static func lookAt(eye: SIMD3<Float>, at: SIMD3<Float>,
                                   up: SIMD3<Float>) -> simd_float4x4 {
            let z = simd_normalize(eye - at)
            let x = simd_normalize(simd_cross(up, z))
            let y = simd_cross(z, x)

            return simd_float4x4(columns: (
                SIMD4(x.x, y.x, z.x, 0),
                SIMD4(x.y, y.y, z.y, 0),
                SIMD4(x.z, y.z, z.z, 0),
                SIMD4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)))
        }

        private static func perspective(fov: Float, aspect: Float,
                                        near: Float, far: Float) -> simd_float4x4 {
            let up = 1 / tan(fov * 0.5)

            return simd_float4x4(columns: (
                SIMD4(up / aspect, 0, 0, 0),
                SIMD4(0, up, 0, 0),
                SIMD4(0, 0, far / (near - far), -1),
                SIMD4(0, 0, near * far / (near - far), 0)))
        }
    }
}
