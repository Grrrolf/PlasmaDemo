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
    float  pad;
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
static float3 plasmaColor(float2 uv, float t) {
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
    return col * 0.5 + 0.5;
}

// Classic Amiga-style copper bars: horizontal metallic bars sweeping up and
// down, each with a bright specular core that fades towards the edges.
static float3 copperBars(float3 col, float2 uv, float t) {
    const int   BAR_COUNT = 6;
    const float HALF_H    = 0.045;   // half bar height (fraction of screen)

    for (int i = 0; i < BAR_COUNT; ++i) {
        float fi = float(i);
        // Each bar follows its own phase-shifted sine path.
        float center = 0.5 + 0.38 * sin(t * 1.1 + fi * 0.9);
        float d = abs(uv.y - center);
        if (d < HALF_H) {
            float sh = cos(d / HALF_H * 1.5708);   // 1 at core, 0 at edge
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
static float3 tunnelColor(float2 uv, float2 res, float t) {
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
    return col;
}

// Classic Commodore 64-style raster bars: full-width horizontal bars over a
// black screen, each a single hue shaded in discrete steps (like stacked
// raster lines), sweeping up and down on phase-shifted sine paths.
static float3 rasterBars(float2 uv, float t) {
    float3 col = float3(0.0);            // black background
    const int   BAR_COUNT = 8;
    const float HALF_H    = 0.035;       // half bar height (fraction of screen)

    for (int i = 0; i < BAR_COUNT; ++i) {
        float fi = float(i);
        float center = 0.5 + 0.42 * sin(t * 1.3 + fi * 0.45);
        float d = abs(uv.y - center);
        if (d < HALF_H) {
            float sh = 1.0 - d / HALF_H;               // 1 at core, 0 at edge
            sh = floor(sh * 6.0 + 0.5) / 6.0;          // stepped C64 shading
            // Per-bar hue around the color wheel.
            float3 base = 0.5 + 0.5 * cos(fi * 0.785 + float3(0.0, 2.094, 4.188));
            col = base * sh;                           // opaque: later bars on top
        }
    }
    return col;
}

// Classic multi-layer 2D starfield.
static float3 starfield(float2 uv, float t) {
    float3 col = float3(0.0);
    for (int i = 0; i < 3; ++i) {
        float fi = float(i);
        float2 p = uv * (8.0 + fi * 4.0);
        p.x += t * (0.5 + fi * 0.2);
        float2 ip = floor(p);
        float2 fp = fract(p);
        float h = fract(sin(dot(ip, float2(12.9898, 78.233) + fi)) * 43758.5453);
        if (h > 0.97) {
            col += smoothstep(0.15, 0.0, length(fp - 0.5)) * (0.6 + 0.4 * h);
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
static float3 cubeColor(float2 uv, float2 res, float t) {
    float2 p = (uv * 2.0 - 1.0) * float2(res.x / res.y, 1.0);
    float3 ro = float3(0, 0, -3);
    float3 rd = normalize(float3(p, 1.5));
    float3 col = starfield(uv, t);

    float d = 0, tm = 0;
    for (int i = 0; i < 40; ++i) {
        float3 pos = ro + rd * tm;
        pos = rotateX(pos, t * 0.7);
        pos = rotateY(pos, t * 0.5);
        d = sdBox(pos, float3(0.6));
        if (d < 0.001 || tm > 10.0) break;
        tm += d;
    }

    if (d < 0.001) {
        float3 pos = ro + rd * tm;
        float3 normPos = rotateX(pos, t * 0.7);
        normPos = rotateY(normPos, t * 0.5);
        float3 n = step(0.599, abs(normPos)) * sign(normPos);
        float diff = max(0.0, dot(n, normalize(float3(1, 2, -1))));
        float3 cubeCol = float3(0.2, 0.4, 0.8) * diff + 0.1;
        float edge = step(0.55, max(abs(normPos.x), max(abs(normPos.y), abs(normPos.z))));
        cubeCol += edge * 0.3;
        col = cubeCol;
    }
    return col;
}

// Unlimited Bobs: many colorful spheres moving on sine paths.
static float3 bobsColor(float2 uv, float2 res, float t) {
    float3 col = float3(0.05, 0.02, 0.08); // dark background
    float aspect = res.x / res.y;
    float2 p = uv;
    p.x *= aspect;
    for (int i = 0; i < 40; ++i) {
        float fi = float(i);
        float t2 = t + fi * 0.15;
        float2 center = float2(0.5 * aspect, 0.5) + 0.4 * float2(sin(t2 * 1.1) * aspect, cos(t2 * 1.3));
        float d = length(p - center);
        float size = 0.04 + 0.01 * sin(t * 2.0 + fi);
        if (d < size) {
            float sh = 1.0 - d / size;
            float3 bobCol = 0.5 + 0.5 * cos(fi * 0.5 + t + float3(0, 2, 4));
            col = mix(col, bobCol, sh * 0.8);
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
    float  t    = u.time;

    // ---- background: current demo part ------------------------------------
    float3 col;
    if (u.scene < 0.5) {
        col = plasmaColor(uv, t);
        // copper bars (behind the scroller)
        col = copperBars(col, uv, t);
    } else if (u.scene < 1.5) {
        col = tunnelColor(uv, res, t);
    } else if (u.scene < 2.5) {
        col = rasterBars(uv, t);
    } else if (u.scene < 3.5) {
        col = cubeColor(uv, res, t);
    } else {
        col = bobsColor(uv, res, t);
    }

    if (u.scene < 1.5 || u.scene > 2.5) {
        // ---- bouncing sine scroller ---------------------------------------
        bool isTunnel = u.scene > 0.5 && u.scene < 1.5;
        bool isCube   = u.scene > 2.5 && u.scene < 3.5;
        bool isBobs   = u.scene > 3.5;

        float2 tSize;
        texture2d<float> tTex;

        if (isTunnel) { tSize = u.text3Size; tTex = textTex3; }
        else if (isCube) { tSize = u.text4Size; tTex = textTex4; }
        else if (isBobs) { tSize = u.text5Size; tTex = textTex5; }
        else { tSize = u.textSize; tTex = textTex; }

        float bandPix = 0.20 * res.y;                  // on-screen text height
        float scale   = bandPix / tSize.y;             // screen px per text px
        float scroll  = t * 0.35 * res.x;              // scroll speed (screen px)
        float gap     = res.x;                         // blank gap before repeat
        float period  = tSize.x * scale + gap;
        float xs      = fmod(frag.x + scroll, period); // wrapped x (screen px)
        float xt      = xs / scale;                    // text-space x (px)

        // Per-column sine wave, stationary in screen space with a phase that
        // moves over time: every character rides the wave, smoothly going up
        // and down as it scrolls through it. Plus a big vertical bounce.
        // Tunnel scroller (scene 1) uses a slower, calmer animation.
        float waveFreq   = isTunnel ? 0.004 : 0.008;
        float waveSpeed  = isTunnel ? 1.2 : 2.5;
        float bounceSpeed = isTunnel ? 0.8 : 1.6;

        float wave   = sin(frag.x * waveFreq - t * waveSpeed) * 0.10 * res.y;
        float bounce = abs(sin(t * bounceSpeed)) * 0.25 * res.y;
        float cy     = res.y * 0.72 - bounce + wave;   // scroller center line
        float yt     = ((frag.y - cy) / bandPix + 0.5) * tSize.y;

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
        col = mix(col, textCol, a);
    } else {
        // ---- C64 part: static scroller band between two white lines --------
        // No bounce, no sine wave, no rainbow — a black band framed by two
        // white horizontal lines, with warm white glyphs scrolling through.
        float bandPix  = 0.12 * res.y;                 // on-screen text height
        float scale    = bandPix / u.text2Size.y;      // screen px per text px
        float scroll   = t * 0.28 * res.x;             // scroll speed (screen px)
        float gap      = res.x;                        // blank gap before repeat
        float period   = u.text2Size.x * scale + gap;
        float xs       = fmod(frag.x + scroll, period);
        float xt       = xs / scale;

        float cy       = res.y * 0.5;                  // band center line
        float bandHalf = 0.10 * res.y;                 // half band height
        float lineHalf = max(1.5, 0.004 * res.y);      // half line thickness
        float d        = abs(frag.y - cy);

        if (d < bandHalf) {
            col = float3(0.0);                         // black band background
            float yt  = ((frag.y - cy) / bandPix + 0.5) * u.text2Size.y;
            float2 tuv = float2(xt, yt) / u.text2Size;
            float a = textTex2.sample(smp, tuv).r;
            col = mix(col, float3(1.0, 0.96, 0.78), a); // warm white glyphs
        }
        if (abs(d - bandHalf) < lineHalf) {
            col = float3(1.0);                         // white frame lines
        }
    }

    // ---- part-transition fade ---------------------------------------------
    col *= u.fade;

    return float4(col, 1.0);
}
"""
