#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The marched visualisers and the finishing pass they share.
//
// Ported from `RPM.Desktop/Presentation/Viz/Controls/*Stage.cs` and `MarchPass.cs`. The
// desktop app draws these with OpenGL: an off-screen buffer at a fraction of the surface
// size, then a bloom and tone map onto the screen. The Uno phone app does not draw them at
// all.
//
// **Two passes, one march.** SwiftUI puts each fragment function in its own render pass, one
// pass per modifier. So the march is a `colorEffect` and the finish is a `layerEffect` that
// samples the output of the march. The desktop app runs the same two passes. Drawing the
// picture twice and blurring one copy for the bloom would march every ray twice, and the
// march is the whole cost.
//
// Every figure below matches the desktop app. What the record does to them comes from
// `VizDirector`, which works it out on the Swift side and passes it in as uniforms.

constant float TAU = 6.28318530718;

static float2x2 rot(float a)
{
    float c = cos(a), s = sin(a);
    return float2x2(float2(c, s), float2(-s, c));
}

// ── the finish, shared by every marcher ──

// Undoes the range compression that the marcher applied when it wrote its output. The value
// is clamped away from 1, where the inverse goes to infinity.
static half3 expand(half3 c)
{
    return c / max(1.0h - c, 0.004h);
}

/// Bloom and tone map. The taps form a ring and not a box: eight taps in a ring look like a
/// halo, while a three-by-three box looks like a cross, and light around hot metal looks like
/// a halo. There are two rings, near and far, so the halo has a bright core and a wider
/// spread.
///
/// The offsets are in POINTS and not in texels of a half-resolution buffer, which is what the
/// desktop app uses. The desktop buffer is half of a large window, but a phone point is
/// already three pixels, so the spread written below is the one that looks right here.
[[ stitchable ]] half4 rpmBloom(float2 position, SwiftUI::Layer layer,
                                float2 size, float bloom, float saturate)
{
    float2 uv = position / size;

    half3 col = expand(layer.sample(position).rgb);

    half3 halo = half3(0.0h);
    for (int i = 0; i < 8; i++)
    {
        float a = TAU * (float(i) + 0.5) / 8.0;
        float2 dir = float2(cos(a), sin(a));

        halo += expand(layer.sample(position + dir * 2.5).rgb) * 0.65h;
        halo += expand(layer.sample(position + dir * 7.0).rgb) * 0.35h;
    }
    col += halo * half(bloom) * 0.045h;

    // Tone map, then restore the colour. A tone map is a curve toward white, and it removes
    // colour as it goes: bright areas become pale, so a picture can be correctly exposed and
    // still look washed out. Saturating afterwards restores the colour that the curve
    // removed.
    col = 1.0h - exp(-col * 0.95h);
    half grey = dot(col, half3(0.2126h, 0.7152h, 0.0722h));
    col = clamp(mix(half3(grey), col, half(saturate)), 0.0h, 1.0h);

    col *= half(0.55 + 0.45 * pow(16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y), 0.22));

    return half4(pow(max(col, 0.0h), half3(1.0h / 2.2h)), 1.0h);
}

// ── the lattice ──

// A grid, turned inside out and driven by the record.
//
// Two changes are made to the space before anything is drawn in it. First it is rotated in
// four dimensions and not three, in the planes that involve the fourth axis. This rotation
// has no three-dimensional equivalent, and it changes what the slice through the space
// CONTAINS and not only where it points. Second it is turned inside out about the origin:
// every point is moved to k·p, where k falls with distance. Far points are brought close and
// packed together, and close points are thrown outward. This inversion is why an endless flat
// grid looks like the inside of a cut stone.
//
// What is drawn is then very simple: the wires along the cell's four axes and a bead where
// they meet. All the shape on screen comes from the two transformations.

// `swell` is returned as the amount by which the inversion magnified this point. It is large
// near the middle of the screen. It is used for the colour, and the distance must be divided
// by it to remain a distance.
static float latticeGrid(float3 p, float4 slice, float4 room,
                         thread float &swell, thread float3 &cellId, thread float3 &offset)
{
    float size = room.x, wire = room.y, bead = room.z, pull = room.w;

    float4 q = float4(p, slice.x);

    // Rotated in the three planes that involve the fourth axis. The camera could not produce
    // any of these rotations.
    q.xw = q.xw * rot(slice.y);
    q.yw = q.yw * rot(slice.z);
    q.zw = q.zw * rot(slice.w);

    // Turned inside out. Every point is moved to k times itself, with k falling as the square
    // of the distance from the origin, so the whole infinite grid is pulled into a ball
    // around the origin.
    //
    // Both ends of k are clamped, and this is required. An inversion has a singularity at the
    // origin: a ray that passes near it is magnified without limit. That shrinks the lattice
    // the ray walks through to nothing, which shrinks its own step to nothing, so the ray
    // stops, one cell fills the screen and the picture is a coloured blob. The clamp is the
    // difference between an inversion and a hang.
    swell = clamp(pull / max(dot(q, q), 0.6), 0.15, 6.0);
    q *= swell;

    // Travelling: the grid is moved past the camera and the camera does not move through the
    // grid, because after an inversion there is no "through" to fly.
    q -= slice.x * 0.35;

    float4 cell = q / size;
    float4 home = round(cell);
    cellId = home.xyz;

    float4 away = (cell - home) * size;
    offset = away.xyz;
    float4 a = abs(away);

    // The wires along the cell's four axes. A wire along x is measured by how far the point
    // is from it in the other three axes. In four dimensions there are four wires, and a
    // slice catches only the cross-section of the fourth, which is the cell that swells and
    // closes.
    float wires = min(min(length(a.yzw), length(a.xzw)), min(length(a.xyw), length(a.xyz))) - wire;
    float knot = length(a) - bead;

    // Divided by the magnification. Otherwise the marcher would step by a distance that is
    // not a true distance and walk straight through the grid it is looking for.
    return min(wires, knot) / swell;
}

// A cell's own colour. It is hashed from the identity of the cell, so a cell keeps its colour
// as it moves and the picture is a lattice of coloured lights, not a rainbow smeared over
// depth.
static float3 latticeColour(float3 id, float swell, float sheen, float palette)
{
    float h = fract(sin(dot(id, float3(12.989, 78.233, 37.719))) * 43758.5453);

    float3 phase = palette < 0.5 ? float3(0.15, 0.45, 0.75)
                 : palette < 1.5 ? float3(0.95, 0.30, 0.60)
                 : palette < 2.5 ? float3(0.40, 0.70, 0.15)
                                 : float3(0.05, 0.35, 0.65);

    // The magnification goes into the hue as well as the brightness: cells brought in from
    // far away have a different colour from cells that were always close. This is the only
    // depth cue in a picture with no shading and no fog. The viewing angle also goes in,
    // which makes the colour iridescent and not only coloured: a wire changes hue along its
    // length as the viewpoint moves over it, like oil on water, because the colour depends on
    // where the viewer stands.
    float shift = h * 0.35 + 0.12 * log2(max(swell, 0.05)) + 0.28 * sheen;

    // Pushed away from grey: a cosine ramp at half amplitude never leaves the middle of the
    // colour space, and pastel wires would look dull.
    return clamp(0.5 + 0.72 * cos(TAU * (shift + phase)), 0.0, 1.0);
}

[[ stitchable ]] half4 rpmLattice(float2 position, half4 colour,
                                  float2 size, float3 camera, float4 slice, float4 room,
                                  float3 beat, float3 bands, float palette, float steps)
{
    // SwiftUI counts y down from the top, and the picture is written counting up from the
    // bottom.
    float2 frag = float2(position.x, size.y - position.y);
    float2 uv = (frag - 0.5 * size) / size.y;

    float beats = beat.x, drop = beat.z;
    int allowed = int(steps);

    float3 ro = float3(0.0, 0.0, -3.0);
    float3 rd = normalize(float3(uv, camera.y));
    rd.xy = rd.xy * rot(camera.x * 0.5);

    float dither = fract(sin(dot(frag, float2(11.317, 57.909)) + beats) * 39181.3717);

    float t = dither * 0.2;
    float3 col = float3(0.0);

    for (int i = 0; i < 96; i++)
    {
        if (i >= allowed) break;

        float swell;
        float3 id, offset;
        float d = latticeGrid(ro + rd * t, slice, room, swell, id, offset);
        float sheen = dot(normalize(offset + 1e-5), rd);

        // A floor in WORLD units, not in the field's units. Near the centre of the inversion
        // the field reports distances that are true but too small to be useful, and a ray
        // that steps by them never arrives anywhere. The floor keeps the march moving through
        // the middle.
        float stride = max(abs(d), 0.02) * 0.75;

        // Gathered and never stopped: this is a lattice of light, and a ray that stopped at
        // the first wire would show only one wire. The light is attenuated with distance as
        // it is gathered. Without that, every ray would bring back the whole depth of the
        // lattice, the picture would have no dark areas, and on a screen this size it would
        // look flat and not vivid.
        col += latticeColour(id, swell, sheen, palette)
             * (stride * (0.026 / (0.004 + d * d)))
             * (1.0 + 0.5 * drop) * exp(-t * 0.055);

        t += stride;
    }

    float level = 0.35 + 1.15 * (bands.x * 0.4 + bands.y * 0.3 + bands.z * 0.3);
    col *= level * 1.05;

    return half4(half3(col / (1.0 + col)), 1.0h);
}

// ── shared shapes ──

// GLSL's `mod`, which is not Metal's `fmod`: `mod` uses the floor and `fmod` truncates, so
// they differ for every negative input. The folds and the cells along a flight both wrap
// coordinates that go negative, so this is the difference between a tunnel and a tunnel with
// a seam down one side.
static float glslMod(float x, float y)
{
    return x - y * floor(x / y);
}

// Folds the plane into `count` identical wedges about the origin. Everything drawn after a
// fold is drawn that many times, and folds combine: two folds with different counts and a
// rotation between them give a count that is neither of the two, and a figure that repeats
// neither.
static float2 wedge(float2 p, float count)
{
    float sector = TAU / count;
    float a = glslMod(atan2(p.y, p.x) + 0.5 * sector, sector) - 0.5 * sector;

    return float2(cos(a), sin(a)) * length(p);
}

static float boxDistance(float3 p, float3 b)
{
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

// A regular prism: fold the plane into `sides` wedges, and one straight cut across the wedge
// then gives all `sides` faces at once. Three sides give a triangle, six give a hexagon, and
// a large number is indistinguishable from a cylinder.
static float prism(float3 p, float sides, float across, float deep)
{
    float sector = TAU / sides;
    float a = glslMod(atan2(p.y, p.x) + 0.5 * sector, sector) - 0.5 * sector;
    float face = cos(a) * length(p.xy) - across;

    return max(face, abs(p.z) - deep);
}

// The eight-sided solid, the one shape here with no faces parallel to anything.
static float octa(float3 p, float s)
{
    return (abs(p.x) + abs(p.y) + abs(p.z) - s) * 0.57735;
}

// The three axis-aligned bars through a cell, as one distance.
static float cutout(float3 p, float r)
{
    float3 q = abs(p);
    return min(max(q.x, q.y), min(max(q.y, q.z), max(q.x, q.z))) - r;
}

// ── the kaleidoscope ──

// Filigree, seen from inside.
//
// Space is folded around the axis, rotated, folded again at a finer count, and then cut into
// cells along the flight. These are three folds in a row, so a single bar with a cross cut
// out of it becomes a tunnel of tracery too fine to count. The camera is not outside looking
// at an ornament. It is inside the ornament, and the ornament closes over it.
//
// Nothing is shaded. Rays are stepped by the distance to the metal on whichever side they
// are, so they pass through it and continue, and what comes back is light gathered along the
// way. This makes it look like glass and mist and not like a solid: there are no faces here,
// only how close the ray came and how often.

// The solid that the mirrors show. There are four solids, one per section. A section changes
// into the next through the distances themselves and not by dissolving between two pictures:
// a bar grows three faces, then six, then it is a diamond.
static float seed(float3 p, float which, float girth, float arm)
{
    if (which < 0.5) return boxDistance(p, float3(girth * 1.5, arm * 0.22, girth * 1.5));
    if (which < 1.5) return prism(p, 3.0, girth * 2.0, arm * 0.22);
    if (which < 2.5) return prism(p, 6.0, girth * 1.8, arm * 0.24);

    return octa(p, girth * 2.6);
}

static float filigree(float3 p, float3 room1, float3 room2, float3 shape)
{
    float folds = room1.x, arm = room1.y, twist = room1.z;
    float ring = room2.x, girth = room2.y, bite = room2.z;

    // First fold, about the axis, in a space that is already twisting like a corkscrew. The
    // roll of the shot is NOT applied here: rolling the world and not the camera spins the
    // room around the viewer on every cut, which is a lurch and not a cut. The roll belongs
    // on the ray.
    p.xy = p.xy * rot(p.z * twist);
    p.xy = wedge(p.xy, folds);
    p.x -= arm;

    // Rotate again by a different amount, and fold at twice the count. This is where the
    // tracery comes from: the second fold folds something that is already folded, so the
    // figure is multiplied and not repeated.
    p.xy = p.xy * rot(p.z * twist * 0.6);
    p.xy = wedge(p.xy, folds * 2.0);
    p.x -= arm * 0.42;

    // Mirror the pair, which halves everything again and puts a seam down the middle.
    p.xy = abs(p.xy) - float2(arm * 0.16);

    // Cells along the flight, and long ones. Measured over the volume that a ray actually
    // crosses, cells at the room's own spacing would leave a twelfth of the space within a
    // twentieth of a unit of metal. That is effectively no free space: every ray would pass
    // through tracery for its whole length, every ray would gather the same light, and the
    // picture would be an even fog whatever the exposure.
    p.z = glslMod(p.z + 1.1 * ring, 2.2 * ring) - 1.1 * ring;

    // The section's solid, with a cross cut out of it. What remains is edges, and edges are
    // all that survives this many folds: a solid would close the tunnel.
    float solid = mix(seed(p, shape.y, girth, arm), seed(p, shape.x, girth, arm), shape.z);

    return max(solid, -cutout(p, girth * 0.85 * bite));
}

[[ stitchable ]] half4 rpmKaleidoscope(float2 position, half4 colour,
                                       float2 size, float travel, float3 camera,
                                       float3 room1, float3 room2, float3 beat, float3 shape,
                                       float palette, float3 bands, float steps)
{
    float2 frag = float2(position.x, size.y - position.y);
    float2 uv = (frag - 0.5 * size) / size.y;

    float beats = beat.x, glitch = beat.y, drop = beat.z;
    int allowed = int(steps);

    // The break. For a fraction of a beat after the room changes, the picture is quantised
    // into blocks and the rows are pulled sideways, like a video signal when something
    // upstream of it changes. It is the only cut this visualiser makes: everything else
    // crossfades, so without it a change of room would go unnoticed.
    if (glitch > 0.0)
    {
        float blocks = mix(140.0, 26.0, glitch);
        uv = floor(uv * blocks) / blocks;
        float band = floor(uv.y * 22.0);
        uv.x += (fract(sin(band * 91.7 + floor(beats)) * 4713.31) - 0.5) * glitch * 0.35;
    }

    float3 ro = float3(sin(beats * 0.11) * camera.z * 0.5, cos(beats * 0.08) * camera.z * 0.5, travel);
    float3 rd = normalize(float3(uv, camera.y));
    rd.xy = rd.xy * rot(camera.x * 0.5 + sin(beats * 0.05) * camera.z * 0.2);

    float dither = fract(sin(dot(frag, float2(21.577, 43.191)) + beats) * 24634.6345);

    float t = dither * 0.3;
    float core = 0.0;   // the tight layer: the edges themselves
    float haze = 0.0;   // the loose one: the air they are standing in

    for (int i = 0; i < 96; i++)
    {
        if (i >= allowed) break;

        // Whichever side of the metal the ray is on, it steps by its distance from the metal,
        // so it passes through and keeps gathering.
        //
        // The floor on the step decides how far down the tunnel the picture reaches, and it
        // matters. This field is folded three times, so close to the tracery it reports
        // distances of a few thousandths, and a ray that steps by those spends every step it
        // has in the first few units.
        float d = max(abs(filigree(ro + rd * t, room1, room2, shape)), 0.006);

        // Counted per STEP and not per unit of distance travelled, and this is the whole
        // look. The step is the distance to the metal, so a ray in open space crosses it in a
        // few long strides and gathers almost nothing, while a ray threading the tracery
        // takes dozens of tiny steps and lights up.
        //
        // The falloff is steep. The tracery continues as far as a ray can travel, so with a
        // gentle falloff every pixel would be the sum of sixty units of it, and the median of
        // the picture would be as bright as its highlights.
        float air = exp(-t * 0.11);

        // A tight kernel and a loose one. The tight one must be TIGHT: with a wide epsilon,
        // every ray that passes anywhere near the tracery scores almost as well as one that
        // threads it, and the result is an even wash with no blacks and no highlights.
        core += (0.0022 / (0.0022 + d * d)) * air;
        haze += (0.004 / (0.260 + d * d)) * air;

        t += d * 0.6;
        // Out of the tracery and into open space: nothing more to gather.
        if (t > 70.0) break;
    }

    // The wash: cream at the centre, indigo at the corners. It is laid down first and the
    // gathered light is added on top, which gives the picture depth and not a black
    // background. Each section has its own pair of colours, one for what the tracery is made
    // of and one for the air behind it, so a phrase changes the colour of the room at the
    // same moment as the shape in it.
    float fall = clamp(length(uv) * 1.20, 0.0, 1.0);

    float3 lit  = palette < 0.5 ? float3(1.00, 0.76, 0.30)    // sand
                : palette < 1.5 ? float3(1.00, 0.42, 0.60)    // rose
                : palette < 2.5 ? float3(0.35, 1.00, 0.68)    // jade
                                : float3(0.45, 0.76, 1.00);   // ice
    float3 dark = palette < 0.5 ? float3(0.09, 0.07, 0.16)
                : palette < 1.5 ? float3(0.14, 0.05, 0.12)
                : palette < 2.5 ? float3(0.04, 0.12, 0.11)
                                : float3(0.05, 0.08, 0.18);

    float3 wash = mix(lit * 0.9, dark, fall);

    float level = 0.35 + 1.25 * (bands.x * 0.35 + bands.y * 0.45 + bands.z * 0.20);

    // No per-beat swell: this visualiser flies at a constant speed and changes by crossfading
    // its room. The beat is in the shape of the tracery and not in a light that is turned up
    // and down over it.
    float strike = 0.85 + 0.5 * drop;

    // The tracery keeps its own colour whatever the music is doing, and the air band only
    // moves it toward white. Mixing a long way toward a COMPLEMENTARY colour may seem
    // reasonable but it is not: two opposite hues in equal parts make grey, and the picture
    // would turn grey.
    float3 metal = mix(lit, float3(1.0), clamp(bands.z * 0.7, 0.0, 0.30));

    // The floor must be much lower than it seems it needs to be: this is linear light and the
    // finish gamma-encodes it, which lifts 0.01 to about 0.14. A wash of 0.012 is not a hint
    // of colour in the dark, it is a grey card behind the whole picture.
    float3 col = wash * (0.0025 + 0.004 * haze * level)
               + metal * core * 0.045 * level * strike;

    return half4(half3(col / (1.0 + col)), 1.0h);
}

// ── the tunnel ──

// A tunnel of folded light, flown to the beat. There is no image in it: the metal is
// generated at the point where the ray lands on it, so it never repeats and never blurs
// however close the camera gets.

// A number from 0 to 1 per slab. The input is an integer, so a slab keeps its own angle and
// its own lamp for as long as it is on screen and does not shimmer as the camera moves.
static float slabHash(float n, float salt)
{
    return fract(sin(n * 41.317 + salt * 7.913) * 24634.6345);
}

// Value noise. This is where the tunnel's surface comes from.
static float valueNoise(float3 p)
{
    float3 cell = floor(p), f = fract(p);
    // Smooth, so the lattice of the noise does not show.
    f = f * f * (3.0 - 2.0 * f);

    // The eight corners of the cell, hashed and blended.
    float n = 0.0;
    for (int i = 0; i < 8; i++)
    {
        float3 corner = float3(float(i & 1), float((i >> 1) & 1), float((i >> 2) & 1));
        float h = fract(sin(dot(cell + corner, float3(127.1, 311.7, 74.7))) * 43758.5453);
        float3 w = mix(1.0 - f, f, corner);
        n += h * w.x * w.y * w.z;
    }

    return n;
}

// Two octaves, not three. The third octave carries a seventh of the amplitude and a third of
// the cost of the whole function. The function is called five times per pixel and is the most
// expensive part of the visualiser, and a third octave would add detail below the size of a
// pixel.
static float grain(float3 p)
{
    return 0.65 * valueNoise(p) + 0.35 * valueNoise(p * 2.07);
}

// The tunnel, and how bright the nearest thing to p is. It returns the distance, and `lamp`
// is 0 for machinery and 1 for something lit, which the shading uses to find where the light
// is.
//
// Nothing here ever closes the bore. The camera flies down the middle of it at speed, and a
// slab across the way would not be a dramatic moment: it would be one grey frame and then
// another.
static float tunnelRoom(float3 p, float3 room1, float3 room2, float beats, thread float &lamp)
{
    float bore = room1.y * 2.4;          // the tunnel's radius
    float pitch = room2.x * 2.6;         // how far apart the ribs are
    float thick = room2.y * 4.0;
    float r = max(length(p.xy), 1e-4);
    float ang = atan2(p.y, p.x);

    // The wall, from inside.
    float tube = bore - r;

    // One cell per rib, and the cell's own number decides what is in it.
    float id = floor(p.z / pitch + 0.5);
    float qz = p.z - id * pitch;

    // A rib standing proud of the wall.
    float rib = max(bore * 0.82 - r, abs(qz) - thick * (0.6 + slabHash(id, 2.0)));

    // The machinery on the wall. The whole surface is cut into a fine grid of cells around
    // and along the tunnel, and each cell is a block standing out from the wall by its own
    // amount. So the tunnel is not a smooth pipe with things attached to it: it is built from
    // parts all the way down, which makes it look like machinery and not like a drain.
    float around = 26.0;
    float sector = TAU / around;
    float run = pitch * 0.25;

    float column = floor((ang + 3.14159265) / sector);
    float row = floor(p.z / run + 0.5);
    float hash = slabHash(column * 7.0 + row * 13.0, 9.0);
    float tall = slabHash(column * 3.0 + row * 29.0, 17.0);

    // Local coordinates inside one block: across the wall, and along the tunnel.
    float across = (glslMod(ang + 3.14159265 + 0.5 * sector, sector) - 0.5 * sector) * r;
    float along = p.z - row * run;

    // How far in from the wall the face of this block sits. A few blocks are recesses, which
    // stops such a regular grid from looking like a pattern.
    float stand = bore * (0.045 + 0.16 * hash * tall);
    float face = bore - stand;

    float3 slot = float3(max(face - r, r - bore),
                         abs(across) - sector * r * (0.30 + 0.14 * tall),
                         abs(along) - run * (0.26 + 0.16 * hash));
    float block = max(slot.x, max(slot.y, slot.z));

    // Conduits: every so often a block is a lamp, and the lit ones are the only objects here
    // with a colour of their own.
    float lit = step(0.93, hash);

    // The ring let into the wall between the ribs.
    float strip = max(abs(r - bore * 0.93) - thick * 0.30, abs(qz - pitch * 0.5) - thick * 0.55);
    float ringLit = step(0.42, slabHash(id, 3.0));

    // A fin swinging out from the wall, well clear of the middle, so there is an edge to
    // catch the light as the camera passes.
    float3 q = p;
    q.z = qz;
    q.xy = q.xy * rot(slabHash(id, 1.0) * TAU + beats * 0.02 * (slabHash(id, 5.0) - 0.5));
    float3 fin = abs(q - float3(bore * 0.62, 0.0, 0.0)) - float3(bore * 0.30, thick * 1.6, thick * 0.9);
    float blade = length(max(fin, 0.0)) + min(max(fin.x, max(fin.y, fin.z)), 0.0);

    float d = min(min(tube, rib), min(min(strip, blade), block));

    // Lit only where the lit thing is the nearest thing. On the machinery next to it, this
    // reads 0, which keeps the metal dark and the conduits bright.
    lamp = max(ringLit * (1.0 - smoothstep(0.0, thick * 0.5, strip - d)),
               lit * (1.0 - smoothstep(0.0, thick * 0.4, block - d)));

    return d;
}

static float tunnelDistance(float3 p, float3 room1, float3 room2, float beats)
{
    float ignored;
    return tunnelRoom(p, room1, room2, beats, ignored);
}

// The surface normal, from four samples around the point and not six. It costs half as much
// as the textbook central difference and looks no worse on a wall this dull.
static float3 tunnelNormal(float3 p, float3 room1, float3 room2, float beats)
{
    float2 e = float2(0.0025, -0.0025);

    return normalize(e.xyy * tunnelDistance(p + e.xyy, room1, room2, beats)
                   + e.yyx * tunnelDistance(p + e.yyx, room1, room2, beats)
                   + e.yxy * tunnelDistance(p + e.yxy, room1, room2, beats)
                   + e.xxx * tunnelDistance(p + e.xxx, room1, room2, beats));
}

// The strips' colour for this section, and the band that drives them. The bass lights what is
// near and the treble lights what is far, so a kick arrives and a hi-hat recedes.
static float3 lampColour(float depth, float palette, float3 bands)
{
    // Two of the four sections are lit in the colour of a machine room: sickly green, which
    // is also the only colour that shows on metal this dark. The other two are the cold blue
    // and the hot magenta that a tunnel like this usually has.
    float3 cold = palette < 1.5 ? float3(0.12, 0.85, 0.30)
                : palette < 2.5 ? float3(0.20, 0.62, 1.00)
                                : float3(0.95, 0.35, 0.55);

    // The hot end is not white. A lamp that goes white when it is loud has no colour left at
    // the moment it fills the screen.
    float3 hot  = palette < 1.5 ? float3(0.45, 1.00, 0.35)
                : palette < 2.5 ? float3(0.50, 0.85, 1.00)
                                : float3(1.00, 0.50, 0.35);

    float close = exp(-depth * 0.06);
    float band = mix(bands.z, bands.x, close);

    return mix(cold, hot, clamp(band * 1.6, 0.0, 1.0)) * (0.25 + 2.6 * band);
}

// Marches until something is hit. Returns the distance travelled, or a negative number when
// the ray left the tunnel without hitting anything.
static float tunnelTravel(float3 ro, float3 rd, int steps, float from,
                          float3 room1, float3 room2, float beats)
{
    float t = from;

    for (int i = 0; i < 96; i++)
    {
        if (i >= steps) break;

        float d = tunnelDistance(ro + rd * t, room1, room2, beats);
        if (d < 0.0025) return t;
        if (t > 90.0) break;

        t += d * 0.85;
    }

    return -1.0;
}

[[ stitchable ]] half4 rpmTunnel(float2 position, half4 colour,
                                 float2 size, float travelled, float3 camera,
                                 float3 room1, float3 room2, float3 beat, float3 bands,
                                 float palette, float steps)
{
    float2 frag = float2(position.x, size.y - position.y);
    float2 uv = (frag - 0.5 * size) / size.y;

    float beats = beat.x, drop = beat.z;
    int allowed = int(steps);

    // Cheap motion blur: the frame is one sample per pixel, so the travel is jittered per
    // pixel by up to a fraction of a beat. A path tracer gets blur from forty samples at
    // forty slightly different instants; this gets it from one sample at a scattered instant.
    float smear = fract(sin(dot(frag.yx, float2(31.71, 19.37)) + beats) * 17631.417);

    float3 ro = float3(sin(beats * 0.13) * camera.z, cos(beats * 0.09) * camera.z,
                       travelled + smear * 0.35);
    float3 rd = normalize(float3(uv, camera.y));
    rd.xy = rd.xy * rot(camera.x * 0.4 + sin(beats * 0.07) * camera.z * 0.25);

    // Scattering the first step per pixel stands in for motion blur and for the grain that a
    // path tracer gets for free. Without it the step size shows as rings around the vanishing
    // point, and every edge in here is hard.
    float dither = fract(sin(dot(frag, float2(12.9898, 78.233)) + beats) * 43758.5453);

    float3 col = float3(0.0);
    float t = tunnelTravel(ro, rd, allowed, 0.02 + dither * 0.12, room1, room2, beats);

    if (t > 0.0)
    {
        float3 p = ro + rd * t;
        float lamp;
        tunnelRoom(p, room1, room2, beats, lamp);
        float3 n = tunnelNormal(p, room1, room2, beats);

        // The metal, generated where the ray hit it. It has four layers, none of them an
        // image: the cast of the alloy itself, panel seams cut into it, dirt that runs along
        // the length of the tunnel and not around it, and a bolt at the corner of every
        // panel.
        //
        // How much of this is computed depends on how far away the wall is. Detail beyond
        // about 30 units is smaller than a pixel, so computing it would cost a fifth of the
        // frame for a texture nobody can see. The relief is dropped first, then the cast.
        float detail = 1.0 - smoothstep(14.0, 30.0, t);

        float3 skin = p * 2.7;
        float alloyCast = detail > 0.02 ? grain(skin) : 0.5;
        // Stretched: it runs along the wall and does not form spots.
        float dirt = grain(float3(p.xy * 0.9, p.z * 0.16));
        float seam = max(abs(fract(p.z * 3.1) - 0.5), abs(fract(atan2(p.y, p.x) * 5.7) - 0.5));
        float bolt = length(fract(float2(p.z * 3.1, atan2(p.y, p.x) * 5.7)) - 0.5);

        // Relief. The same noise displaces the normal, so the surface has direction as well
        // as colour. Without this, a texture on a curved wall looks like paint and not like
        // metal.
        if (detail > 0.25)
        {
            float e = 0.02;
            float3 bump = float3(grain(skin + float3(e, 0.0, 0.0)) - alloyCast,
                                 grain(skin + float3(0.0, e, 0.0)) - alloyCast,
                                 grain(skin + float3(0.0, 0.0, e)) - alloyCast) / e;
            n = normalize(n - (bump - n * dot(bump, n)) * 0.06 * detail);
        }

        float sky = 0.5 + 0.5 * dot(n, normalize(float3(0.2, 0.7, -0.6)));

        float3 alloy = mix(float3(0.020, 0.026, 0.022), float3(0.048, 0.052, 0.040), alloyCast);
        // Stains down the length.
        alloy *= 0.55 + 0.75 * mix(0.5, dirt, detail);
        // The seams are cut, so they are dark, and a bolt at each corner.
        alloy *= 1.0 - 0.55 * smoothstep(0.40, 0.49, seam);
        alloy *= 1.0 - 0.35 * smoothstep(0.10, 0.05, bolt);

        float3 wall = alloy * (0.3 + 1.1 * sky);
        float3 light = lampColour(t, palette, bands) * lamp;

        // One bounce. A strip reflected in the wall is most of what makes a tunnel like this
        // look like concrete and not paper. One bounce is enough because the only thing worth
        // reflecting is a lamp, and only from a wall that the camera is near. A reflection
        // thirty units down the tunnel is a few dim pixels, and finding it would cost a
        // second march.
        float3 rr = reflect(rd, n);
        float t2 = t < 26.0
            ? tunnelTravel(p + n * 0.02, rr, allowed / 3, 0.02, room1, room2, beats)
            : -1.0;

        if (t2 > 0.0)
        {
            float3 p2 = p + n * 0.02 + rr * t2;
            float lamp2;
            tunnelRoom(p2, room1, room2, beats, lamp2);
            light += lampColour(t + t2, palette, bands) * lamp2 * 0.85 * exp(-t2 * 0.08);
        }

        col = wall + light;

        // No per-beat swell. This one is cut and not pulsed: the camera holds a shot for two
        // bars and changes on a beat, which is where its rhythm is.
        col *= 0.9 + 0.5 * drop;
        // The far end fades to nothing, which is where the tunnel ends.
        col *= exp(-t * 0.035);
    }

    // Range-compressed on the way out and expanded by the finish. With eight bits, a bloomed
    // picture would clip everything the bloom is made of.
    return half4(half3(col / (1.0 + col)), 1.0h);
}

// ── the butterfly ──

// The spectrum, mirrored into four. Bass is in the middle and treble runs out to the edges.
// The level of each band draws a dark line with light opening away from it, so loud bands
// glow wide and quiet ones close to a seam.
//
// Not a marcher: this one has no camera, no room and no beat. It draws the spectrum reading
// directly.
//
// The desktop app passes the row to the shader as a 512-wide texture and lets the sampler
// interpolate. Here it is a float array, so the interpolation is written out. It is linear
// across the row on purpose: 512 texels stretched over the width would show steps, and the
// spectrum between two bins is a reading and not an invention.

// The ramp is written in gamma-encoded light, so it is encoded before it is returned. Mixing
// in linear light and leaving it there makes the middle of the ramp much too bright.
static float3 butterflyTint(float y)
{
    float3 middle = float3(170.0, 170.0, 210.0) / 255.0;   // pale lavender, through the centre
    float3 edge   = float3( 51.0, 153.0, 255.0) / 255.0;   // full blue, at the top and bottom

    return pow(mix(middle, edge, y), float3(1.0 / 2.2));
}

// **The count is required.** SwiftUI passes a float array as a pointer AND its length, so a
// function that declares only the pointer does not match the arguments it receives, and the
// result is not a wrong picture but a black screen.
[[ stitchable ]] half4 rpmButterfly(float2 position, half4 colour,
                                    float2 size, device const float *spectrum, int count)
{
    if (count < 2) return half4(0.0h, 0.0h, 0.0h, 1.0h);

    // Folded twice: 0 at the centre of the frame and 1 at either edge, on both axes. One
    // quadrant is drawn and the frame shows it four times, mirrored.
    float2 uv = abs((float2(position.x, size.y - position.y) / size - 0.5) * 2.0);

    // Squared, so the width is spent on the bottom of the spectrum where the music is, and
    // not half of it on a top end that is nearly always empty.
    float band = uv.x * uv.x;

    float at = clamp(band, 0.0, 1.0) * float(count - 1);
    int lo = int(at);
    int hi = min(lo + 1, count - 1);
    float level = mix(spectrum[lo], spectrum[hi], at - float(lo));

    // Distance from the level this band is sounding at, scaled by that level. The level line
    // is the dark edge, the light grows away from it, and a band with nothing in it is black.
    return half4(half3(abs(uv.y - level) * level * butterflyTint(uv.y)), 1.0h);
}
