//
//  Shaders.swift
//  PlasmaDemo
//
//  Metal shader source, compiled at runtime so the demo needs no build-time
//  .metal file processing.
//

let shaderSource = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float  time;
    float  fade;         // global brightness, 1 = normal, 0 = black
    float2 resolution;   // drawable size in pixels
    float2 textSize;     // scrolltext texture size in pixels
    float2 text2Size;    // C64-part scrolltext texture size in pixels
    float2 text3Size;    // tunnel-part scrolltext texture size in pixels
    float2 text4Size;    // cube-part scrolltext texture size in pixels
    float2 text5Size;    // bobs-part scrolltext texture size in pixels
    float  scene;        // 0=plasma, 1=tunnel, 2=raster, 3=cube, 4=bobs
    float  sceneTime;    // time since scene start
};

struct VertexOut {
    float4 position [[position]];
};

// Fullscreen triangle, no vertex buffer needed.
vertex VertexOut fullscreenVertex(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VertexOut out;
    out.position = float4(pos[vid], 0.0, 1.0);
    return out;
}

// Classic old-school plasma: sum of sines plus a moving radial term.
static float3 plasmaColor(float2 uv, float t, float sceneTime, float fade) {
    float2 p = uv * 2.0 - 1.0;
    float v = 0.0;
    v += sin(p.x * 6.0 + t);
    v += sin((p.y * 6.0 + t) * 0.5);
    v += sin((p.x + p.y) * 6.0 + t) * 0.5;
    float2 c = p + float2(0.5 * sin(t / 3.0), 0.5 * cos(t / 2.0));
    v += sin(sqrt(50.0 * dot(c, c) + 1.0) + t);
    v *= 0.5;

    float3 col = float3(sin(v * 3.14159),
                        sin(v * 3.14159 + 2.094),
                        sin(v * 3.14159 + 4.188));
    col = col * 0.5 + 0.5;
    return col * smoothstep(0.0, 2.0, sceneTime) * fade;
}

// Classic Amiga-style copper bars: horizontal metallic bars sweeping up and
// down, each with a bright specular core that fades towards the edges.
static float3 copperBars(float3 col, float2 uv, float t, float sceneTime, float fade) {
    const int   BAR_COUNT = 6;
    float       halfH     = 0.045 * min(1.0, sceneTime * 0.5) * fade;

    for (int i = 0; i < BAR_COUNT; ++i) {
        float fi = float(i);
        // Each bar follows its own phase-shifted sine path.
        float center = 0.5 + 0.38 * sin(t * 1.1 + fi * 0.9);
        float d = abs(uv.y - center);
        if (d < halfH) {
            float sh = cos(d / halfH * 1.5708);   // 1 at core, 0 at edge
            // Per-bar hue around the color wheel (red, gold, green, blue...).
            float3 base   = 0.5 + 0.5 * cos(fi * 1.047 + float3(0.0, 2.094, 4.188));
            float3 barCol = base * (sh * sh)                    // shaded body
                          + float3(1.0) * pow(sh, 8.0) * 0.6;   // specular core
            col = mix(col, barCol, 0.85 * sh);
        }
    }
    return col;
}

// Classic demoscene tunnel: polar-mapped checkerboard flying towards the
// viewer, with a drifting center, slow rotation and a dark far end.
static float3 tunnelColor(float2 uv, float2 res, float t, float sceneTime, float fade) {
    float2 p = uv * 2.0 - 1.0;
    p.x *= res.x / res.y;                       // keep the tunnel round
    p += float2(0.35 * sin(t * 0.5),            // wandering tunnel center
                0.25 * cos(t * 0.4));

    float r   = length(p);
    float ang = atan2(p.y, p.x);
    float tu  = ang / 6.28318 + t * 0.06;       // slow twist
    float tv  = 0.35 / max(r, 0.02) + t * 0.9;  // fly forward

    // Checkerboard walls.
    float checker = fmod(step(0.5, fract(tu * 8.0))
                       + step(0.5, fract(tv * 0.5)), 2.0);

    // Depth-cycled palette, dimmed in the dark squares.
    float3 base = 0.5 + 0.5 * cos(tv * 0.7 + t * 0.3 + float3(0.0, 2.094, 4.188));
    float3 col  = base * (0.35 + 0.65 * checker);

    // Fade to black towards the far end of the tunnel.
    // Hole collapses during transition.
    float hole = 0.5 * fade;
    col *= smoothstep(0.0, hole, r);
    return col * smoothstep(0.0, 1.5, sceneTime) * fade;
}

// Classic Commodore 64-style raster bars: full-width horizontal bars over a
// black screen, each a single hue shaded in discrete steps (like stacked
// raster lines), sweeping up and down on phase-shifted sine paths.
static float3 rasterBars(float2 uv, float t, float sceneTime, float fade) {
    float3 col = float3(0.0);            // black background
    const int   BAR_COUNT = 8;
    float       halfH     = 0.035 * min(1.0, sceneTime * 0.7) * fade;

    for (int i = 0; i < BAR_COUNT; ++i) {
        float fi = float(i);
        float center = 0.5 + 0.42 * sin(t * 1.3 + fi * 0.45);
        float d = abs(uv.y - center);
        if (d < halfH) {
            float sh = 1.0 - d / halfH;                // 1 at core, 0 at edge
            sh = floor(sh * 6.0 + 0.5) / 6.0;          // stepped C64 shading
            // Per-bar hue around the color wheel.
            float3 base = 0.5 + 0.5 * cos(fi * 0.785 + float3(0.0, 2.094, 4.188));
            col = base * sh;                           // opaque: later bars on top
        }
    }
    return col;
}

// Classic 3D "flying" starfield: stars originate from the center and grow
// as they move towards the viewer.
static float3 starfield(float2 uv, float2 res, float t, float sceneTime, float fade) {
    float3 col = float3(0.0);
    float2 p = (uv * 2.0 - 1.0) * float2(res.x / res.y, 1.0);

    for (int i = 0; i < 4; ++i) {
        float fi = float(i);
        // Each layer has a different offset in depth (z).
        float z = fract(0.25 * fi - t * 0.3);
        float starFade = smoothstep(0.0, 0.1, z) * smoothstep(1.0, 0.8, z);
        float scale = mix(20.0, 0.2, z);
        float2 sp = p * scale;
        float2 id = floor(sp);
        float2 fd = fract(sp) - 0.5;
        float h = fract(sin(dot(id, float2(12.9898, 78.233))) * 43758.5453);
        if (h > 0.94) {
            // Stars grow larger as they get closer (smaller z).
            float r = 0.09 * (1.0 - z);
            // Stars start invisible and fade in over 2 seconds. Fade out during transition.
            col += smoothstep(r, 0.0, length(fd)) * starFade * smoothstep(0.0, 2.0, sceneTime) * fade;
        }
    }
    return col;
}

// 3D Box SDF.
static float sdBox(float3 p, float3 b) {
    float3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

static float3 rotateX(float3 p, float a) {
    float s = sin(a), c = cos(a);
    return float3(p.x, c * p.y - s * p.z, s * p.y + c * p.z);
}

static float3 rotateY(float3 p, float a) {
    float s = sin(a), c = cos(a);
    return float3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

// Raymarching a rotating 3D cube.
static float3 cubeColor(float2 uv, float2 res, float t, float sceneTime, float fade) {
    float2 p = (uv * 2.0 - 1.0) * float2(res.x / res.y, 1.0);
    float3 ro = float3(0, 0, -3);
    float3 rd = normalize(float3(p, 1.5));
    float3 col = starfield(uv, res, t, sceneTime, fade);

    // Cube scales up from nothing and scales down during transition.
    float cubeSize = 0.6 * clamp(sceneTime * 0.5, 0.01, 1.0) * fade;

    float d = 0, tm = 0;
    for (int i = 0; i < 40; ++i) {
        float3 pos = ro + rd * tm;
        pos = rotateX(pos, t * 0.7);
        pos = rotateY(pos, t * 0.5);
        d = sdBox(pos, float3(cubeSize));
        if (d < 0.001 || tm > 10.0) break;
        tm += d;
    }

    if (d < 0.001) {
        float3 pos = ro + rd * tm;
        float3 normPos = rotateX(pos, t * 0.7);
        normPos = rotateY(normPos, t * 0.5);
        float3 n = step(cubeSize - 0.001, abs(normPos)) * sign(normPos);

        // Lighting: rotate light into local space to match the local normal.
        float3 l = normalize(float3(1.0, 2.0, -1.0));
        l = rotateX(l, t * 0.7);
        l = rotateY(l, t * 0.5);
        float diff = max(0.0, dot(n, l));

        // Rubik's style colors: fixed color per side.
        float3 baseCol;
        if      (n.x > 0.5)  baseCol = float3(0.8, 0.0, 0.0); // Red
        else if (n.x < -0.5) baseCol = float3(1.0, 0.5, 0.0); // Orange
        else if (n.y > 0.5)  baseCol = float3(0.9, 0.9, 0.9); // White
        else if (n.y < -0.5) baseCol = float3(1.0, 1.0, 0.0); // Yellow
        else if (n.z > 0.5)  baseCol = float3(0.0, 0.2, 0.8); // Blue
        else                 baseCol = float3(0.0, 0.7, 0.0); // Green

        float3 cubeCol = baseCol * (diff * 0.7 + 0.3);

        // 3x3 Sticker grid.
        float2 faceUV = (n.x != 0) ? normPos.yz : ((n.y != 0) ? normPos.xz : normPos.xy);
        float2 grid = fract((faceUV + cubeSize) * (1.5 / cubeSize));
        float sticker = step(0.1, grid.x) * step(grid.x, 0.9) * step(0.1, grid.y) * step(grid.y, 0.9);

        // Darken the gaps between stickers and the cube edges.
        float edge = step(cubeSize * 0.95, max(abs(faceUV.x), abs(faceUV.y)));
        sticker *= (1.0 - edge);

        col = mix(float3(0.05), cubeCol, sticker);
    }
    return col;
}

// Unlimited Bobs: many colorful spheres moving on sine paths.
// The number of bobs grows one by one based on sceneTime.
//
// Optimized for fullscreen/Retina: instead of testing every bob for every
// pixel (O(pixels x bobs), which crawled at 5K), we march the snake path
// head-first in coarse steps of STEP bobs using an enlarged radius, and
// only refine to exact per-bob tests when the pixel is near the path.
// Since the head (i=0) is drawn on top, the first hit in ascending index
// order is the visible bob, so we can return immediately. Trig inside the
// coarse loop is replaced by an incremental 2D rotation, and pixels
// outside the snake's bounding box bail out at once.
static float3 bobsColor(float3 background, float2 uv, float2 res, float t, float sceneTime, float fade) {
    float aspect = res.x / res.y;
    float2 p = uv;
    p.x *= aspect;

    // Path constants (tunables): center, amplitudes, frequencies, lag, radius.
    const float2 base  = float2(0.5 * aspect, 0.42); // snake path center
    const float  ampX  = 0.4 * aspect;               // horizontal amplitude
    const float  ampY  = 0.33;                       // vertical amplitude
    const float  frqX  = 1.5;                        // horizontal frequency
    const float  frqY  = 1.1;                        // vertical frequency
    const float  lag   = 0.035;                      // time lag between bobs
    const float  size  = 0.035;                      // bob radius

    // Cheap bounding-box rejection: no bob can ever reach outside this.
    if (abs(p.x - base.x) > ampX + size || abs(p.y - base.y) > ampY + size) {
        return background;
    }

    // C64-ish palette (classic Commodore colors)
    float3 pal[16] = {
        float3(0.00, 0.00, 0.00), // 0: Black
        float3(1.00, 1.00, 1.00), // 1: White
        float3(0.53, 0.20, 0.13), // 2: Red
        float3(0.47, 0.73, 0.73), // 3: Cyan
        float3(0.53, 0.27, 0.60), // 4: Purple
        float3(0.33, 0.67, 0.27), // 5: Green
        float3(0.20, 0.13, 0.53), // 6: Blue
        float3(0.73, 0.80, 0.47), // 7: Yellow
        float3(0.53, 0.33, 0.00), // 8: Orange
        float3(0.33, 0.20, 0.00), // 9: Brown
        float3(0.80, 0.47, 0.47), // 10: Light Red
        float3(0.20, 0.20, 0.20), // 11: Dark Gray
        float3(0.47, 0.47, 0.47), // 12: Medium Gray
        float3(0.67, 1.00, 0.67), // 13: Light Green
        float3(0.67, 0.67, 1.00), // 14: Light Blue
        float3(0.80, 0.80, 0.80)  // 15: Light Gray
    };

    // Number of bobs to show: grows by 30 per second, starting with 1.
    // Shortens during transition as fade goes to 0.
    int limit = 1 + int(sceneTime * 30.0 * fade);
    if (limit > 1000) limit = 1000;

    // Coarse marching: one path sample covers the STEP bobs around it.
    const int STEP = 8;
    // Upper bound on the distance between neighbouring bobs (path speed * lag),
    // so a coarse sample plus this pad is guaranteed to enclose its window.
    float spacing  = lag * length(float2(ampX * frqX, ampY * frqY));
    float coarseR  = size + spacing * float(STEP / 2);
    float coarseR2 = coarseR * coarseR;
    float size2    = size * size;

    // Incremental rotation state for the two path phases at the head (i=0);
    // each coarse step rotates them back by STEP * lag worth of phase.
    float2 sc1 = float2(sin(t * frqX), cos(t * frqX));
    float2 sc2 = float2(sin(t * frqY), cos(t * frqY));
    float2 r1  = float2(sin(float(STEP) * lag * frqX), cos(float(STEP) * lag * frqX));
    float2 r2  = float2(sin(float(STEP) * lag * frqY), cos(float(STEP) * lag * frqY));

    // March one coarse sample past `limit` so the tail bobs that fall
    // after the last full window are still covered.
    for (int i = 0; i < limit + STEP / 2; i += STEP) {
        float2 center = base + float2(ampX * sc1.x, ampY * sc2.y);
        float2 dv = p - center;
        if (dot(dv, dv) < coarseR2) {
            // Refine: exact test for the bobs in this coarse window,
            // in ascending order so the first hit is the topmost bob.
            int jBeg = max(i - STEP / 2, 0);
            int jEnd = min(i + STEP / 2, limit);
            for (int j = jBeg; j < jEnd; ++j) {
                // Each bob lags behind the previous one to form a trailing snake.
                float t2 = t - float(j) * lag;
                float2 c = base + float2(sin(t2 * frqX) * ampX,
                                         cos(t2 * frqY) * ampY);
                float2 dj = p - c;
                float d2 = dot(dj, dj);
                if (d2 < size2) {
                    // Cycle through some nice C64 colors (avoiding black/gray)
                    int ci = (j % 7) + 2;
                    float3 bobCol = pal[ci];

                    // Retro shading: hard steps
                    float sh = 1.0 - sqrt(d2) / size;
                    if (sh > 0.8)      bobCol = mix(bobCol, float3(1.0), 0.4); // highlight
                    else if (sh < 0.3) bobCol *= 0.5;                          // shadow edge

                    return bobCol;
                }
            }
        }
        // Rotate both phases back by one coarse step (angle subtraction).
        sc1 = float2(sc1.x * r1.y - sc1.y * r1.x, sc1.y * r1.y + sc1.x * r1.x);
        sc2 = float2(sc2.x * r2.y - sc2.y * r2.x, sc2.y * r2.y + sc2.x * r2.x);
    }
    return background;
}

fragment float4 plasmaFragment(VertexOut in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]],
                               texture2d<float> textTex [[texture(0)]],
                               texture2d<float> textTex2 [[texture(1)]],
                               texture2d<float> textTex3 [[texture(2)]],
                               texture2d<float> textTex4 [[texture(3)]],
                               texture2d<float> textTex5 [[texture(4)]]) {
    constexpr sampler smp(mag_filter::linear,
                          min_filter::linear,
                          address::clamp_to_zero);

    float2 res  = u.resolution;
    float2 frag = in.position.xy;      // pixel coords, origin top-left
    float2 uv   = frag / res;

    // ---- artful transitions: coordinate-based (Bit-Crush, Raster Wipe) ----
    if (u.fade < 0.999) {
        if (u.scene > 2.5 && u.scene < 3.5) {
            // Scene 3 (Cube): Bit-Crush / Resolution Downsample
            float size = mix(40.0, 1.0, pow(u.fade, 0.4));
            frag = floor(frag / size) * size + size * 0.5;
        } else if (u.scene > 1.5 && u.scene < 2.5) {
            // Scene 2 (Raster Bars): Horizontal Raster Wipe
            float slice = floor(uv.y * 40.0);
            float shift = (1.0 - u.fade) * 1.2 * res.x * (fract(sin(slice * 437.12) * 98.43) - 0.5);
            frag.x += shift;
        }
    }

    // Refresh UV after potential frag modification
    uv = frag / res;
    float  t = u.sceneTime;

    // ---- background: current demo part ------------------------------------
    float3 col;
    if (u.scene < 0.5) {
        col = plasmaColor(uv, t, u.sceneTime, u.fade);
        // copper bars (behind the scroller)
        col = copperBars(col, uv, t, u.sceneTime, u.fade);
    } else if (u.scene < 1.5) {
        col = tunnelColor(uv, res, t, u.sceneTime, u.fade);
    } else if (u.scene < 2.5) {
        col = rasterBars(uv, t, u.sceneTime, u.fade);
    } else if (u.scene < 3.5) {
        col = cubeColor(uv, res, t, u.sceneTime, u.fade);
    } else {
        col = float3(0.0, 0.0, 0.0);
    }

    if (u.scene < 1.5 || (u.scene > 2.5 && u.scene < 3.5)) {
        // ---- scrollers (Plasma, Tunnel, Cube) -----------------------------
        bool isTunnel = u.scene > 0.5 && u.scene < 1.5;
        bool isCube   = u.scene > 2.5 && u.scene < 3.5;

        float2 tSize;
        texture2d<float> tTex;
        if (isTunnel)      { tSize = u.text3Size; tTex = textTex3; }
        else if (isCube)   { tSize = u.text4Size; tTex = textTex4; }
        else               { tSize = u.textSize;  tTex = textTex;  }

        float bandPix = 0.20 * res.y;                  // on-screen text height
        float scale   = bandPix / tSize.y;             // screen px per text px
        float gap     = res.x;                         // blank gap before repeat
        float period  = tSize.x * scale + gap;

        float scroll, cy, wave = 0.0, bounce = 0.0;

        // Sink scroller during transition
        float sink = (1.0 - u.fade) * 0.25 * res.y;

        if (isCube) {
            // ---- Part 4 (Cube): Struggling train scroller -----------------
            float trainT = t + 0.5 * sin(t * 2.0);
            scroll = trainT * 0.56 * res.y;            // res.y-based, aspect-independent (was 0.35 * res.x)
            cy     = res.y * 0.85 + sink;              // lower screen
        } else {
            // ---- Part 1 & 2: Bouncing sine scroller -----------------------
            // Speeds and wavelength are normalized to res.y (screen height, the
            // basis of the text size) instead of res.x. Using res.x tied the
            // scroll speed and wave frequency to the pixel width, so going
            // fullscreen (more pixels / wider aspect) made the wave steepen and
            // the characters bob much faster, ruining legibility. Now the
            // scroller reads the same at any resolution or aspect; the values
            // below are chosen to be identical to the old ones at the default
            // 1.6 window aspect.
            scroll = t * 0.56 * res.y;                 // was 0.35 * res.x
            float waveFreq    = isTunnel ? 4.8 : 9.6;  // wave cycles factor (per res.y); was 0.004 / 0.008 per pixel
            float waveSpeed   = isTunnel ? 1.2 : 2.5;
            float bounceSpeed = isTunnel ? 0.8 : 1.6;
            wave   = sin(frag.x / res.y * waveFreq - t * waveSpeed) * 0.10 * res.y;
            bounce = abs(sin(t * bounceSpeed)) * 0.25 * res.y;
            cy     = res.y * 0.72 - bounce + sink;
        }

        float xs = fmod(frag.x + scroll, period);
        float xt = xs / scale;
        float yt = ((frag.y - (cy + wave)) / scale + (tSize.y * 0.5));

        float2 tuv = float2(xt, yt) / tSize;

        // Cheap drop shadow.
        float2 shOff = float2(5.0, 5.0) / scale;
        float2 suv   = (float2(xt, yt) - shOff) / tSize;
        float  sh    = tTex.sample(smp, suv).r;
        col = mix(col, float3(0.0), sh * 0.55);

        // Rainbow-cycled glyphs.
        float a = tTex.sample(smp, tuv).r;
        float hue = 6.28318 * (tuv.x * 2.0 + t * 0.25);
        float3 textCol = 0.5 + 0.5 * cos(hue + float3(0.0, 2.094, 4.188));
        textCol = mix(textCol, float3(1.0), 0.25);     // brighten a bit

        // Scroller fades in smoothly.
        float textAlpha = smoothstep(0.0, 0.5, u.sceneTime);
        col = mix(col, textCol, a * textAlpha);
    } else {
        // ---- C64 and Bobs parts: Band Scroller -----------------------------
        bool isBobs = u.scene > 3.5;
        float2 tSize   = isBobs ? u.text5Size : u.text2Size;
        texture2d<float> tTex = isBobs ? textTex5 : textTex2;

        float bandPix  = (isBobs ? 0.15 : 0.12) * res.y;  // on-screen text height
        float scale    = bandPix / tSize.y;               // screen px per text px
        float scroll   = t * (isBobs ? 0.352 : 0.448) * res.y; // scroll speed (res.y-based, aspect-independent; was 0.22/0.28 * res.x)
        float gap      = res.x;                           // blank gap before repeat
        float period   = tSize.x * scale + gap;
        float xs       = fmod(frag.x + scroll, period);
        float xt       = xs / scale;

        float cy       = res.y * (isBobs ? 0.88 : 0.5);   // band center line
        float bandHalf = (isBobs ? 0.08 : 0.10) * res.y;  // half band height
        float lineHalf = max(1.5, 0.004 * res.y);         // half line thickness
        float d        = abs(frag.y - cy);

        // Band and text build-up.
        float bandBuildup = smoothstep(0.0, 0.8, u.sceneTime);
        float actualBandHalf = bandHalf * bandBuildup * u.fade;

        if (d < actualBandHalf) {
            col = float3(0.0);                            // black band background
            float yt  = ((frag.y - cy) / bandPix + 0.5) * tSize.y;
            float2 tuv = float2(xt, yt) / tSize;
            float a = tTex.sample(smp, tuv).r;
            // Bobs get a light blue-ish tint, C64 gets warm white.
            float3 glyphCol = isBobs ? float3(0.7, 0.9, 1.0) : float3(1.0, 0.96, 0.78);
            col = mix(col, glyphCol, a * smoothstep(0.5, 1.0, u.sceneTime));
        }
        if (abs(d - actualBandHalf) < lineHalf && bandBuildup > 0.1) {
            col = float3(1.0);                            // white frame lines
        }
    }

    if (u.scene > 3.5) {
        col = bobsColor(col, uv, res, t, u.sceneTime, u.fade);
    }

    // ---- part-transition fade ---------------------------------------------
    if (u.fade < 0.999) {
        if (u.scene < 0.5) {
            // Scene 0 (Plasma): Organic Melting
            float m = (sin(uv.x * 7.0 + t) + sin(uv.y * 5.0 - t * 0.5) +
                       sin((uv.x + uv.y) * 4.0) + sin(uv.x * 10.0 - uv.y * 3.0)) * 0.125 + 0.5;
            if (m > u.fade) col = float3(0.0);
        } else if (u.scene < 1.5) {
            // Scene 1 (Tunnel): Radial Iris Wipe
            float d = length((uv - 0.5) * float2(res.x / res.y, 1.0));
            if (d > u.fade * 1.2) col = float3(0.0);
        } else if (u.scene < 2.5) {
            // Scene 2 (Raster Bars): Horizontal Raster Wipe (coord-based)
            col *= u.fade;
        } else if (u.scene < 3.5) {
            // Scene 3 (Cube): Bit-Crush (coord-based)
            col *= u.fade;
        } else {
            // Scene 4 (Bobs): Dithered Dissolve
            int2 p = int2(in.position.xy) % 4;
            float bayer[16] = { 0.0,    0.5,    0.125,  0.625,
                                0.75,   0.25,   0.875,  0.375,
                                0.1875, 0.6875, 0.0625, 0.5625,
                                0.9375, 0.4375, 0.8125, 0.3125 };
            if (bayer[p.y * 4 + p.x] > u.fade) col = float3(0.0);
        }
    }

    return float4(col, 1.0);
}
"""
