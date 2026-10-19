import SwiftUI
import RPMStages

/// The code shared by all the marched visualisers. Only the shader differs.
///
/// Same structure as `RPM.Desktop/Presentation/Viz/Controls/MarchedStage.cs`.
///
/// **The timing comes from the music, not from a clock.** The camera holds a shot for two
/// bars and cuts on a beat, the room changes on the eight-bar phrase, and the flight moves
/// forward on each beat and eases into the next. All of this is ``VizDirector``'s, worked
/// out from the playing position. It is derived and never accumulated, so after a seek the
/// picture is the one that position would always have had.
///
/// **Two passes, one march.** The picture is a `colorEffect` and the finish is a
/// `layerEffect` over it: bloom, tone map, saturate, vignette. The desktop app uses the
/// same pair. Drawing the picture twice and blurring one copy for the bloom would march
/// every ray twice, and the march is the whole cost.
struct MarchedView: View {
    /// The shader's name in the bundle's library, and the function that builds its arguments.
    let march: String
    let uniforms: (VizShot, CGSize) -> [Shader.Argument]

    /// How much halo the finish adds around what the march drew, and how far it restores
    /// the colour after the tone map. A saturate of 1 leaves the colour as the tone curve
    /// made it, which on a bright picture is paler than what was drawn.
    let bloom: Float
    let saturate: Float

    /// `tick` is read so that the view redraws when it changes. `seconds` is the playing
    /// position.
    let tick: Int
    let seconds: Double

    /// The most steps a ray may take. The desktop app's governor lowers this before it
    /// lowers the resolution: fewer steps only shortens the view distance (the far end fades
    /// out), while a coarser buffer makes the whole picture worse.
    static let steps: Float = 64

    /// How far the halo reaches, in points. The finish must be told this, or SwiftUI clips
    /// the layer that the shader samples.
    private static let reach = CGSize(width: 8, height: 8)

    var body: some View {
        GeometryReader { geo in
            let shot = VizDirector.shot(.free(seconds))

            Rectangle()
                .fill(.black)
                .colorEffect(marching(shot, geo.size))
                .layerEffect(ShaderLibrary.bundle(.module).rpmBloom(
                    .float2(geo.size), .float(bloom), .float(saturate)),
                             maxSampleOffset: Self.reach)
        }
        .allowsHitTesting(false)
    }

    /// The march shader with its arguments filled in. The arguments are assigned as an
    /// array because a shader function takes them variadically, while a look supplies a list.
    private func marching(_ shot: VizShot, _ size: CGSize) -> Shader {
        var shader = ShaderLibrary.bundle(.module)[dynamicMember: march]()
        shader.arguments = uniforms(shot, size)

        return shader
    }
}
