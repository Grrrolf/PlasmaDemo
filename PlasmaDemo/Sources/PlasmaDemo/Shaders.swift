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
    float  scene;        // 0 = plasma part, 1 = tunnel part
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

fragment float4 plasmaFragment(VertexOut in [[stage_in]],
                               constant Uniforms &u [[buffer(0)]],
                               texture2d<float> textTex [[texture(0)]]) {
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
    } else {
        col = tunnelColor(uv, res, t);
    }

    // ---- bouncing sine scroller -------------------------------------------
    float bandPix = 0.20 * res.y;                  // on-screen text height
    float scale   = bandPix / u.textSize.y;        // screen px per text px
    float scroll  = t * 0.35 * res.x;              // scroll speed (screen px)
    float gap     = res.x;                         // blank gap before repeat
    float period  = u.textSize.x * scale + gap;
    float xs      = fmod(frag.x + scroll, period); // wrapped x (screen px)
    float xt      = xs / scale;                    // text-space x (px)

    // Per-column sine wave, stationary in screen space with a phase that
    // moves over time: every character rides the wave, smoothly going up
    // and down as it scrolls through it. Plus a big vertical bounce.
    float wave   = sin(frag.x * 0.008 - t * 2.5) * 0.10 * res.y;
    float bounce = abs(sin(t * 1.6)) * 0.25 * res.y;
    float cy     = res.y * 0.72 - bounce + wave;   // scroller center line
    float yt     = ((frag.y - cy) / bandPix + 0.5) * u.textSize.y;

    float2 tuv = float2(xt, yt) / u.textSize;

    // Cheap drop shadow.
    float2 shOff = float2(5.0, 5.0) / scale;
    float2 suv   = (float2(xt, yt) - shOff) / u.textSize;
    float  sh    = textTex.sample(smp, suv).r;
    col = mix(col, float3(0.0), sh * 0.55);

    // Rainbow-cycled glyphs.
    float a = textTex.sample(smp, tuv).r;
    float hue = 6.28318 * (tuv.x * 2.0 + t * 0.25);
    float3 textCol = 0.5 + 0.5 * cos(hue + float3(0.0, 2.094, 4.188));
    textCol = mix(textCol, float3(1.0), 0.25);     // brighten a bit
    col = mix(col, textCol, a);

    // ---- part-transition fade ---------------------------------------------
    col *= u.fade;

    return float4(col, 1.0);
}
"""
