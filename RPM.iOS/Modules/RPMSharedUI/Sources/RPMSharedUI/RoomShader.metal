#include <metal_stdlib>
using namespace metal;

// The room that the record plays in.
//
// A translation of `RPM.Core/Viz/RoomSource.cs`, the shader source that the other two apps also
// compile: the desktop app as GLSL through OpenGL, and the Uno phone app as SkSL through Skia.
// This app has neither Skia nor GL, so it compiles the same figures as Metal, and SwiftUI adds
// the shader as a colour effect. Three compilers draw one picture, and it stays one picture only
// while the text stays the same: **every figure below comes from that file, and none may be
// changed here alone.** If one changes there, change it here too.
//
// The composition around the room (the dimming under the text, the vignette, the grain) is in
// `RoomProgram.cs`, and the apps are allowed to differ there. This one puts the text along the
// foot, like the Uno phone app, because both are portrait.
//
// It is not shared through a translator as the other two are. SkSL is GLSL with different
// spelling, so a regular expression can convert it, but Metal needs its own header and its own
// attributes. The shader is therefore written out by hand, and the comment above is what keeps it
// in step.

// ── the figures ──

constant int RPM_LOBES = 6;
constant int RPM_LOBES2 = 5;
constant int RPM_LOBES3 = 4;
constant float AIR_RATE = 1.3;
constant float AIR_SOFT = 1.08;

// The height that one lobe of that softness reaches on its own. The third family's ramps are
// all written against this value, so its blur can be changed without changing its brightness.
constant float AIR_PEAK = 1.0 / AIR_SOFT;

// A lobe with no edge: its value never reaches zero, which lets six of them melt into one
// another instead of overlapping like coins. `soft` is how far the falloff is spread. A larger
// value lowers the peak and widens the skirt, which gives a blurrier lobe of the same size and
// not a bigger one.
static float rpmLobe(float2 p, float2 c, float r, float soft)
{
    float2 d = p - c;
    float r2 = r * r;
    return r2 / (dot(d, d) + r2 * soft);
}

// `p` is the plane with the origin in the middle of the screen, scaled by its height, so the
// figures have the same size and shape at any aspect ratio. `t` is in seconds.
static float3 rpmRoomColour(float2 p, float t, float bass, float mid, float air,
                            float3 ground, float3 tint, float3 glow, float3 shade)
{
    // ── the third family, which is drawn first ──
    //
    // The smallest and fastest figures, in the sleeve's third colour only, drawn behind the other
    // two. The room starts here, on the ground and not over it.
    //
    // Behind is the right place. These figures follow the busiest part of the music, and a fast
    // small figure in front of two slow large ones looks scattered on top of the picture. Behind
    // them, the other families break it up and it is seen between them, like the top end of a mix.
    float t3 = t * AIR_RATE;

    float2 w3 = p;
    w3 += 0.11 * float2(sin(p.y * 3.2 + t3 * 0.29), cos(p.x * 2.9 - t3 * 0.25));
    w3 += (0.05 + air * 0.11) * float2(sin(w3.y * 5.1 - t3 * 0.21), cos(w3.x * 4.6 + t3 * 0.23));

    float field3 = 0.0;
    for (int i = 0; i < RPM_LOBES3; i++)
    {
        float fi = float(i);
        float a = t3 * (0.095 + fi * 0.026) + fi * 2.9;
        float2 c = float2(cos(a * 0.94 + fi * 1.9) * 0.70,
                          sin(a * 1.37 + fi * 2.6) * 0.42);
        // Half the size of the second family's, and swelling more, so a hi-hat hit is clearly
        // visible.
        float r = (0.085 + 0.030 * sin(t3 * 0.41 + fi * 3.1)) * (1.0 + air * 0.85);
        // The softest skirt of the three: a figure seen between other things should have no
        // visible edge and should look like a light behind them.
        field3 += rpmLobe(w3, c, r, AIR_SOFT);
    }

    // There is no wash to average here: one colour means nothing to mix between. The two ramps
    // are fractions of AIR_PEAK (the height one lobe reaches), so blurring the family does not
    // also dim it.
    float3 back = mix(ground, shade, smoothstep(0.17 * AIR_PEAK, 1.22 * AIR_PEAK, field3) * 0.70);
    // The glow, which is the purpose of this family. The ramp starts below a single lobe's peak.
    // The other two families only bloom where several lobes overlap, and four small fast figures
    // would almost never do that.
    back += shade * smoothstep(0.65 * AIR_PEAK, 1.73 * AIR_PEAK, field3) * (0.16 + air * 0.62);

    // ── the figures ──
    //
    // Warp the plane twice before measuring anything. The lobes below are round, and the warp is
    // the only reason the picture is not. The second warp is driven by the bass, so the low end
    // does not only swell the shapes, it also stirs them.
    float2 w = p;
    w += 0.20 * float2(sin(p.y * 2.1 + t * 0.19), cos(p.x * 1.8 - t * 0.15));
    w += (0.10 + bass * 0.14) * float2(sin(w.y * 3.9 - t * 0.11), cos(w.x * 3.3 + t * 0.13));

    float field = 0.0;
    float weight = 0.0;
    float3 wash = float3(0.0);
    for (int i = 0; i < RPM_LOBES; i++)
    {
        float fi = float(i);
        // The golden angle spreads their phases so that no two of them ever line up.
        float a = t * (0.047 + fi * 0.0115) + fi * 2.39996;
        float2 c = float2(cos(a + fi * 1.3) * (0.46 + 0.20 * sin(t * 0.031 + fi)),
                          sin(a * 0.83 + fi * 2.1) * 0.32);
        float r = (0.20 + 0.055 * sin(t * 0.21 + fi * 1.7)) * (1.0 + bass * 0.62);

        float g = rpmLobe(w, c, r, 0.42);
        field += g;
        // Weighted by the square of the lobe's strength, not the strength itself. With a linear
        // average, six overlapping lobes give every pixel almost the same mixture and the whole
        // screen becomes one colour. With the square, the nearest lobe owns its neighbourhood and
        // the colours stay separate where they meet.
        float wg = g * g;
        weight += wg;
        wash += mix(tint, glow, fract(fi * 0.41 + 0.15)) * wg;
    }
    wash /= max(weight, 1e-4);

    // Mixed over the third family and not over the ground, because that layer is the ground here.
    float3 col = mix(back, wash, smoothstep(0.30, 1.75, field));
    // Where several lobes overlap, the colour lifts instead of clipping, and the bass lifts it
    // further. This bloom makes the room look lit from inside.
    //
    // The light in the body of the room follows the bass only. A room lit by the whole mix at
    // once flickers, which looks like noise and not like a pulse.
    col += wash * smoothstep(1.60, 3.40, field) * (0.12 + bass * 0.44);

    // ── the second family ──
    //
    // Smaller and faster, in the contrasting colour: figures that cross the room and do not fill
    // it. They follow the middle of the music, so they move quickly while the big lobes swell.
    // Two things at two speeds make a moving picture and not just a moving wash.
    float2 w2 = p;
    w2 += 0.15 * float2(sin(p.y * 2.6 - t * 0.27), cos(p.x * 2.3 + t * 0.23));
    w2 += (0.07 + mid * 0.13) * float2(sin(w2.y * 4.4 + t * 0.19), cos(w2.x * 3.9 - t * 0.21));

    float field2 = 0.0;
    float weight2 = 0.0;
    float3 wash2 = float3(0.0);
    for (int i = 0; i < RPM_LOBES2; i++)
    {
        float fi = float(i);
        float a = t * (0.083 + fi * 0.021) + fi * 1.7;
        float2 c = float2(cos(a * 1.21 + fi * 2.7) * 0.62,
                          sin(a + fi * 0.9) * 0.38);
        float r = (0.145 + 0.045 * sin(t * 0.37 + fi * 2.3)) * (1.0 + mid * 0.55);

        // A wider skirt than the big lobes have. It spreads these figures out, so they do not
        // look like five bright coins moving over the wash.
        float g = rpmLobe(w2, c, r, 0.88);
        // The weighting is gentler than the square used for the primary lobes: these figures
        // should blend into one another and not hold their own area.
        float wg = g * sqrt(g);
        field2 += g;
        weight2 += wg;
        wash2 += mix(shade, glow, fract(fi * 0.53 + 0.40)) * wg;
    }
    wash2 /= max(weight2, 1e-4);

    // A long, low ramp: the edge of the second family must never be visible.
    col = mix(col, wash2, smoothstep(0.20, 1.90, field2) * 0.78);
    col += wash2 * smoothstep(1.30, 3.50, field2) * (0.14 + bass * 0.40);

    return col;
}

// ── the composition ──

// ── the room as a card's background ──
//
// The same figures without the stage's treatment, like `CardRoomArt` on the desktop, where the
// card's entry point is one call and a clamp. The wash, the foot ramp and the vignette belong to a
// screen that has a title, a seek bar and a row of keys over it.
//
// How far either side of the fold the blur reaches, and how far apart its samples spread at the
// fold itself, in points.
constant float kSeamBand = 30.0;
constant float kSeamSpread = 18.0;

// The card room at one height down the view, folded at the card's foot. Below the fold it reads
// its own picture backwards, which forms the reflection.
static float3 rpmCardRoomAt(float x, float yy, float2 size, float time,
                            float bass, float mid, float air,
                            float3 ground, float3 tint, float3 glow, float3 shade, float fold)
{
    float y = (fold > 0.0 && yy > fold) ? 2.0 * fold - yy : yy;
    float2 flipped = float2(x, size.y - y);
    float2 p = (flipped - 0.5 * size) / size.y;
    return rpmRoomColour(p, time, bass, mid, air, ground, tint, glow, shade);
}

// The card room must not use the stage's treatment. `col *= 0.62` and a floor of 0.42 under the
// foot ramp would leave a card at about a quarter of the desktop's brightness. The foot ramp also
// lights only the top of the frame, because `uv.y` counts up from the bottom, so the one bright
// band on a card would lie along its top edge and not in the middle.
//
// The grain stays, and the desktop app does not have it. The desktop draws its card at a tenth of
// the size and magnifies it, which blurs away the banding. This shader draws at the screen's own
// pixels, where 8 bits across a field this soft shows visible bands, and the bands crawl as the
// figures drift.
//
// `fold` is where the card ends and its reflection begins, in the same points that `position`
// uses. Below it the room is the room above it, mirrored, so one pass draws the card and what it
// casts under itself. A second room drawn under the first would be a second shader on a second
// clock: twice the cost of the most expensive thing on the screen, and two rooms that drift apart.
// 0 means a card that casts nothing, which is every room that is not on the home strip.
[[ stitchable ]] half4 rpmCardRoom(float2 position, half4 colour,
                                   float2 size, float time,
                                   float bass, float mid, float air,
                                   float3 ground, float3 tint, float3 glow, float3 shade,
                                   float fold)
{
    float3 col;

    // A blur over the fold. The mirror meets the card in the same colour but turns back on itself
    // there, and that turn looks like a crease. Within the band, a few samples down the column are
    // averaged, and the spread falls to 0 at the band's edges so the band has no visible edge.
    // Only these rows pay for the extra samples.
    float away = fold > 0.0 ? abs(position.y - fold) : 1.0e9;
    if (away < kSeamBand) {
        float spread = kSeamSpread * (1.0 - smoothstep(0.0, kSeamBand, away));
        float3 sum = float3(0.0);
        for (int i = -3; i <= 3; i++) {
            sum += rpmCardRoomAt(position.x, position.y + float(i) * spread / 3.0, size, time,
                                 bass, mid, air, ground, tint, glow, shade, fold);
        }
        col = sum / 7.0;
    } else {
        col = rpmCardRoomAt(position.x, position.y, size, time,
                            bass, mid, air, ground, tint, glow, shade, fold);
    }

    float grain = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    col += grain * (1.6 / 255.0);

    return half4(half3(clamp(col, 0.0, 1.0)), 1.0h);
}

// `foot` is where the text starts, as a fraction of the height from the top. The room is dimmed
// below it. 1 means there is no text anywhere and the whole room is lit.
[[ stitchable ]] half4 rpmRoom(float2 position, half4 colour,
                               float2 size, float time,
                               float bass, float mid, float air,
                               float3 ground, float3 tint, float3 glow, float3 shade,
                               float foot)
{
    // SwiftUI counts y down from the top, but the room is written counting up from the bottom.
    // The flip is done once here and not in the shared figures, which no app may change alone.
    float2 flipped = float2(position.x, size.y - position.y);
    float2 uv = flipped / size;
    float2 p = (flipped - 0.5 * size) / size.y;

    float3 col = rpmRoomColour(p, time, bass, mid, air, ground, tint, glow, shade);

    // The figures are the background, and the important content is drawn over them in white. The
    // whole wash is therefore dimmed, and dimmed more along the foot, where the title, the seek bar
    // and the keys are. It is dimmed and not covered: a grey panel on top would kill the colour,
    // while dimming just moves that part of the room away from the light.
    col *= 0.62;
    // A foot of 1 means a room with no text over it (RoomView.foot), so there is no ramp at all.
    // The ramp formula at 1 would still dim everything except one band. On the Apple TV landscape
    // room, where the text is not along the foot, that left a dark band across the screen.
    if (foot < 1.0) {
        col *= mix(0.42, 1.0, smoothstep(foot - 0.24, foot, uv.y));
    }

    // The corners are darkened, so the middle of the screen is the brightest part.
    float vig = pow(16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y), 0.20);
    col *= 0.42 + 0.58 * vig;

    // A grain of dither. 8 bits across a gradient this wide and this soft show visible bands, and
    // the bands crawl as the figures drift, which is more distracting than the noise.
    float grain = fract(sin(dot(position, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
    col += grain * (1.6 / 255.0);

    return half4(half3(max(col, float3(0.0))), 1.0h);
}
