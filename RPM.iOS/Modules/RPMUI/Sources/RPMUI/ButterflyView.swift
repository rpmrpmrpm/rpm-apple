import SwiftUI
import RPMStages

/// The spectrum, mirrored into four parts.
///
/// This look has no camera, no room and no beat: it only draws the spectrum values. So it uses
/// neither the cutting room nor the bloom and tone map that the marched looks use. The desktop
/// does the same, and it is also not a `MarchedStage` there.
struct ButterflyView: View {
    /// The whole spectrum row. It is passed as a float array and not a texture, because that
    /// is what a stitched shader accepts. The shader does the interpolation that a sampler
    /// would otherwise do.
    let spectrum: [Float]

    /// Read so that the drawing is refreshed when it changes.
    let tick: Int

    var body: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(.black)
                .colorEffect(ShaderLibrary.bundle(.module).rpmButterfly(
                    .float2(geo.size), .floatArray(spectrum)))
        }
        .allowsHitTesting(false)
    }
}
