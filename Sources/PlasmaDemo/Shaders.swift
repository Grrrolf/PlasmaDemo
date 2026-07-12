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
static float3 plasmaColor(float2 uv, float t, float sceneTime) {
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
    return col * smoothstep(0.0, 2.0, sceneTime);
}

// Classic Amiga-style copper bars: horizontal metallic bars sweeping up and
// down, each with a bright specular core that fades towards the edges.
static float3 copperBars(float3 col, float2 uv, float t, float sceneTime) {
    const int   BAR_COUNT = 6;
    float       halfH     = 0.045 * min(1.0, sceneTime * 0.5);

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
static float3 tunnelColor(float2 uv, float2 res, float t, float sceneTime) {
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
    col *= smoothstep(0.0, 0.5, r);
    return col * smoothstep(0.0, 1.5, sceneTime);
}

// Classic Commodore 64-style raster bars: full-width horizontal bars over a
// black screen, each a single hue shaded in discrete steps (like stacked
// raster lines), sweeping up and down on phase-shifted sine paths.
static float3 rasterBars(float2 uv, float t, float sceneTime) {
    float3 col = float3(0.0);            // black background
    const int   BAR_COUNT = 8;
    float       halfH     = 0.035 * min(1.0, sceneTime * 0.7);

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
static float3 starfield(float2 uv, float2 res, float t, float sceneTime) {
    float3 col = float3(0.0);
    float2 p = (uv * 2.0 - 1.0) * float2(res.x / res.y, 1.0);

    for (int i = 0; i < 4; ++i) {
        float fi = float(i);
        // Each layer has a different offset in depth (z).
        float z = fract(0.25 * fi - t * 0.3);
        float fade = smoothstep(0.0, 0.1, z) * smoothstep(1.0, 0.8, z);
        float scale = mix(20.0, 0.2, z);
        float2 sp = p * scale;
        float2 id = floor(sp);
        float2 fd = fract(sp) - 0.5;
        float h = fract(sin(dot(id, float2(12.9898, 78.233))) * 43758.5453);
        if (h > 0.94) {
            // Stars grow larger as they get closer (smaller z).
            float r = 0.09 * (1.0 - z);
            // Stars start invisible and fade in over 2 seconds.
            col += smoothstep(r, 0.0, length(fd)) * fade * smoothstep(0.0, 2.0, sceneTime);
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
static float3 cubeColor(float2 uv, float2 res, float t, float sceneTime) {
    float2 p = (uv * 2.0 - 1.0) * float2(res.x / res.y, 1.0);
    float3 ro = float3(0, 0, -3);
    float3 rd = normalize(float3(p, 1.5));
    float3 col = starfield(uv, res, t, sceneTime);

    // Cube scales up from nothing.
    float cubeSize = 0.6 * clamp(sceneTime * 0.5, 0.01, 1.0);

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
static float3 bobsColor(float3 background, float2 uv, float2 res, float t, float sceneTime) {
    float3 col = background;
    float aspect = res.x / res.y;
    float2 p = uv;
    p.x *= aspect;

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
    int limit = 1 + int(sceneTime * 30.0);
    if (limit > 1000) limit = 1000;

    // We use a high count to simulate "unlimited" bobs on a snake path.
    // Iterating backwards so the "head" (i=0) is drawn last (on top).
    for (int i = limit - 1; i >= 0; --i) {
        float fi = float(i);
        // Each bob lags behind the previous one to form a trailing snake.
        float t2 = t - fi * 0.035;
        float2 center = float2(0.5 * aspect, 0.42) +
                        float2(sin(t2 * 1.5) * 0.4 * aspect,
                               cos(t2 * 1.1) * 0.33);

        float d = length(p - center);
        float size = 0.035;

        if (d < size) {
            // Cycle through some nice C64 colors (avoiding black/gray)
            int ci = (i % 7) + 2;
            float3 bobCol = pal[ci];

            // Retro shading: hard steps
            float sh = 1.0 - d / size;
            if (sh > 0.8)      bobCol = mix(bobCol, float3(1.0), 0.4); // highlight
            else if (sh < 0.3) bobCol *= 0.5;                          // shadow edge

            col = bobCol;
        }
    }
    return col;
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
    float  t    = u.sceneTime;

    // ---- background: current demo part ------------------------------------
    float3 col;
    if (u.scene < 0.5) {
        col = plasmaColor(uv, t, u.sceneTime);
        // copper bars (behind the scroller)
        col = copperBars(col, uv, t, u.sceneTime);
    } else if (u.scene < 1.5) {
        col = tunnelColor(uv, res, t, u.sceneTime);
    } else if (u.scene < 2.5) {
        col = rasterBars(uv, t, u.sceneTime);
    } else if (u.scene < 3.5) {
        col = cubeColor(uv, res, t, u.sceneTime);
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

        if (isCube) {
            // ---- Part 4 (Cube): Struggling train scroller -----------------
            float trainT = t + 0.5 * sin(t * 2.0);
            scroll = trainT * 0.35 * res.x;
            cy     = res.y * 0.85;                     // lower screen
        } else {
            // ---- Part 1 & 2: Bouncing sine scroller -----------------------
            scroll = t * 0.35 * res.x;
            float waveFreq    = isTunnel ? 0.004 : 0.008;
            float waveSpeed   = isTunnel ? 1.2 : 2.5;
            float bounceSpeed = isTunnel ? 0.8 : 1.6;
            wave   = sin(frag.x * waveFreq - t * waveSpeed) * 0.10 * res.y;
            bounce = abs(sin(t * bounceSpeed)) * 0.25 * res.y;
            cy     = res.y * 0.72 - bounce;
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
        float scroll   = t * (isBobs ? 0.22 : 0.28) * res.x; // scroll speed
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
        float actualBandHalf = bandHalf * bandBuildup;

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
        col = bobsColor(col, uv, res, t, u.sceneTime);
    }

    // ---- part-transition fade ---------------------------------------------
    col *= u.fade;

    return float4(col, 1.0);
}
"""
