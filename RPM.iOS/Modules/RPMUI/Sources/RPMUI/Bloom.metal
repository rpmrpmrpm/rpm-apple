#include <metal_stdlib>
using namespace metal;

// A flower of light that is also a picture of the music.
//
// Ported from `RPM.Desktop/Presentation/Viz/Controls/BloomStage.cs`.
//
// The petals sit on a phyllotaxis spiral: petal i is at the golden angle times i, at radius
// pow(i/N, 0.62). This is the packing of a sunflower head. No two petals line up into a spoke,
// and the density is even from the heart to the rim.
//
// Each petal shows a polar spectrogram. ANGLE is frequency, from bass to treble once around
// the wheel. RADIUS is time: the heart of the flower is the present and the rim is about two
// and a half seconds ago. A beat opens at the centre and travels outward as a ring, a held
// note draws a spiral arm, and the last few seconds are all on screen at once.
//
// This is the only visualiser with a vertex stage. The others are fragment functions that
// SwiftUI runs in its own pass. This one draws 12,700 instanced quads, which a per-pixel
// function cannot do, so it uses its own pipeline on an `MTKView` (see `BloomView`).
//
// Drawing is additive: there is no depth buffer and no sorting. Light adds up where petals
// overlap, which gives the heart its glow.

constant int RPM_PETALS = 12000;
constant float RPM_BLOOM_RADIUS = 1.62;
constant float RPM_GOLDEN = 2.39996323;

struct BloomUniforms {
    float4x4 viewProjection;
    float3 camera;
    float time;
    float swell;
    float turn;
    float2 resolution;
};

struct Petal {
    float4 position [[position]];
    float2 corner;
    float3 colour;
    float energy;
    /// Where on the flower this petal sits: 0 at the heart, 1 at the rim.
    float radius;
};

static float hash1(float n)
{
    return fract(sin(n * 12.9898) * 43758.5453);
}

vertex Petal rpmBloomVertex(uint vertexId [[vertex_id]],
                            uint instance [[instance_id]],
                            constant float2 *corners [[buffer(0)]],
                            constant BloomUniforms &u [[buffer(1)]],
                            texture2d<float> history [[texture(0)]])
{
    constexpr sampler wheel(filter::linear, address::clamp_to_edge);

    float2 corner = corners[vertexId];
    float i = float(instance);

    Petal out;
    out.corner = corner;

    // The last instances are motes, not petals. They drift up and around the bloom like
    // pollen and react to the top end of the music. They fill the dark space around the
    // flower.
    if (instance >= uint(RPM_PETALS))
    {
        float m = float(instance - uint(RPM_PETALS));
        float ha = hash1(m * 1.13), hb = hash1(m * 2.71), hc = hash1(m * 5.37);
        float ma = ha * 6.2831853 + u.time * (0.02 + hb * 0.05);
        float mr = RPM_BLOOM_RADIUS * (0.35 + hb * 1.25);
        // Rises, then starts again from the bottom.
        float rise = fract(hc + u.time * (0.010 + ha * 0.022));
        float my = -0.25 + rise * 1.55;

        float3 centre = float3(cos(ma) * mr, my, sin(ma) * mr);
        float spark = history.sample(wheel, float2(0.04, 0.72 + hb * 0.26)).r;
        float twinkle = 0.45 + 0.55 * sin(u.time * (1.1 + hc * 2.2) + m);
        float e = (0.22 + spark * 0.85) * twinkle
                * smoothstep(0.0, 0.12, rise) * (1.0 - smoothstep(0.72, 1.0, rise));

        float msize = 0.0060 + hc * 0.0070;
        float3 viewDir = normalize(u.camera - centre);
        float3 mr1 = normalize(cross(viewDir, float3(0.0, 1.0, 0.0)));
        float3 mr2 = normalize(cross(viewDir, mr1));
        float3 world = centre + mr1 * (corner.x * msize) + mr2 * (corner.y * msize);

        out.colour = mix(float3(0.55, 0.88, 1.0), float3(1.0), spark * 0.6);
        out.energy = e;
        out.radius = 1.0;
        out.position = u.viewProjection * float4(world, 1.0);

        return out;
    }

    // 0 at the heart, 1 at the rim. `pow(f, 0.62)` is used instead of a square root because it
    // puts slightly more petals near the heart. The centre then forms a bright core instead
    // of thinning out where the petals meet.
    float f = (i + 0.5) / float(RPM_PETALS);
    float rf = pow(f, 0.62);

    // Phyllotaxis plus a differential turn: the heart turns a little faster than the rim, so
    // the arms curl into a slow swirl instead of a rigid wheel. A small jitter is added to the
    // angle and radius, because exact phyllotaxis looks like a regular comb.
    float jitter = hash1(i * 1.7);
    float ang = i * RPM_GOLDEN + u.turn * (1.35 - 0.55 * rf) + (jitter - 0.5) * 0.045;
    float r = RPM_BLOOM_RADIUS * (0.055 + 0.945 * rf) * (1.0 + (hash1(i * 3.1) - 0.5) * 0.035);

    // The petal's own value from the music: its angle gives the band, its radius gives the age.
    float band = fract(ang / 6.2831853);
    float age = clamp(rf, 0.0, 1.0);
    float e = history.sample(wheel, float2(age, band)).r;

    // Soft knee. Additive petals accumulate, so a linear value turns white as soon as several
    // loud bands overlap. This curve keeps rising but never reaches 1.
    e = e / (0.55 + e);

    // Older rings fade out, so the flower has a soft edge.
    e *= 1.0 - smoothstep(0.55, 1.0, rf);

    // The heart always glows, so silence leaves a faint centre instead of a hole. It follows
    // the swell.
    e = max(e, exp(-rf * 6.0) * (0.16 + u.swell * 0.30));
    out.energy = e;

    // Height above the plane: a shallow dome that follows the swell, plus the petal's energy.
    float dome = (1.0 - rf * rf) * (0.10 + u.swell * 0.18);
    float y = dome + e * (0.20 + u.swell * 0.16) + (hash1(i) - 0.5) * 0.010;

    float3 centre = float3(cos(ang) * r, y, sin(ang) * r);

    // Petals are stretched along their own radius and grow with energy. A loud band gives
    // long strokes of light and a quiet band gives small specks. The innermost petals are
    // larger with a soft halo, so the centre of the spiral is filled with light and not dark.
    float size = (0.0105 + 0.0075 * rf) * (0.55 + e * 2.0 + u.swell * 0.25)
               * (1.0 + 1.9 * exp(-rf * 7.0));
    float longAxis = size * (1.45 + e * 2.3);
    float shortAxis = size * 0.55;

    // The radial direction in world space, made perpendicular to the view so the stretch looks
    // radial on screen from any angle.
    float3 radial = float3(cos(ang), 0.0, sin(ang));
    float3 viewDir = normalize(u.camera - centre);
    radial = normalize(radial - viewDir * dot(radial, viewDir));
    float3 across = normalize(cross(viewDir, radial));

    // The stroke bends as it goes outward: straight rays at the heart, arcs at the rim. This
    // follows the spiral arms of a real flower and stops the disc looking like a comb of
    // spokes.
    float lean = 0.26 + smoothstep(0.02, 0.95, rf) * 0.62;
    float3 along = normalize(mix(radial, across, lean));
    float3 side = normalize(cross(viewDir, along));

    float3 world = centre + along * (corner.x * longAxis) + side * (corner.y * shortAxis);

    // Colour by band: the app's azure, then cyan, then near white at the top end. The loudest
    // petals move toward white whatever their band.
    float3 low = float3(0.05, 0.17, 0.95);
    float3 middle = float3(0.02, 0.78, 1.00);
    float3 high = float3(0.86, 0.97, 1.00);

    float3 col = band < 0.5 ? mix(low, middle, band * 2.0) : mix(middle, high, (band - 0.5) * 2.0);
    col = mix(col, float3(1.0), clamp(e * e * 0.35, 0.0, 0.40));

    out.colour = col;
    out.radius = rf;
    out.position = u.viewProjection * float4(world, 1.0);

    return out;
}

fragment float4 rpmBloomFragment(Petal in [[stage_in]],
                                 constant BloomUniforms &u [[buffer(1)]])
{
    // A soft grain of light: a bright core inside a wide, weak halo. The halo joins
    // neighbouring petals into arms of light instead of separate dots.
    float d = dot(in.corner, in.corner);
    float core = exp(-d * 8.0);
    float halo = exp(-d * 2.0) * 0.45;

    // Each petal is faint on purpose. With 12,000 of them the light comes from ACCUMULATION,
    // which gives soft gradients and avoids flat, clipped white. The heart gets more light
    // than the rim, so the flower has a bright centre and fades into the dark.
    float heart = 1.0 + 0.85 * exp(-in.radius * 4.0);
    float a = (core + halo) * (0.045 + in.energy * 0.42) * heart;

    float3 col = in.colour * (0.55 + in.energy * 0.95)
               + float3(0.50, 0.85, 1.0) * core * in.energy * 0.25;
    // The centre is nearly white.
    col = mix(col, float3(0.72, 0.93, 1.0), exp(-in.radius * 6.0) * 0.45);

    // Vignette: the corners of the frame stay dark.
    float2 uv = in.position.xy / u.resolution;
    a *= uv.x * (1.0 - uv.x) * uv.y * (1.0 - uv.y) * 26.0 * 0.6 + 0.34;

    return float4(col * a, a);
}
