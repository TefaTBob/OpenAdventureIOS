// CRT.metal — the monitor look, as a SwiftUI layer effect.
//
// The layer underneath is plain grayscale (white text on black). This shader
// bends it onto a curved tube, colors it with the chosen phosphor, and adds
// bloom, scanlines, static, jitter, flicker, horizontal-sync wobble, a rolling
// glow line and a little chromatic fringing — the same family of effects
// cool-retro-term offers, written from scratch.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float luma(SwiftUI::Layer layer, float2 p, float2 size) {
    p = clamp(p, float2(0.5), size - 0.5);
    return float(layer.sample(p).g);
}

[[ stitchable ]]
half4 crtMonitor(float2 position, SwiftUI::Layer layer,
                 float2 size, float time, half4 phosphor,
                 float brightness, float contrast, float bloom, float curvature,
                 float noise, float jitter, float flicker, float hsync,
                 float glowLine, float scanlines, float chroma,
                 float sourceRows, float ambient)
{
    float2 uv = position / size;

    // --- Tube curvature: barrel-distort around the centre.
    float2 cc = uv - 0.5;
    float k = curvature * 0.28;
    // Bend the same physical amount whatever the screen's shape: on a tall
    // portrait tube, ease the vertical bend so lines bow like on a 4:3 tube.
    float ky = k * min(1.0, (size.x / size.y) / (4.0 / 3.0));
    float r2 = dot(cc, cc) * 4.0;
    float2 cuv = float2(cc.x * (1.0 + k * r2), cc.y * (1.0 + ky * r2)) + 0.5;

    // Outside the bent picture is the dark glass of the tube.
    if (cuv.x < 0.0 || cuv.x > 1.0 || cuv.y < 0.0 || cuv.y > 1.0) {
        return half4(half3(phosphor.rgb) * half(ambient * 0.02), 1.0h);
    }

    // --- Frame jitter: the whole picture twitches a little, 30 times a second.
    float frame = floor(time * 30.0);
    float2 jit = (float2(hash12(float2(frame, 1.7)), hash12(float2(frame, 9.2))) - 0.5)
                 * jitter * float2(0.0035, 0.0025);

    // --- Horizontal sync: gentle wave, with occasional stronger tears.
    float wave = sin(cuv.y * 48.0 + time * 6.0) * 0.6 + sin(cuv.y * 9.0 - time * 2.3) * 0.4;
    float tear = pow(max(0.0, sin(time * 0.83) * sin(time * 0.31 + 1.7)), 8.0);
    float xoff = hsync * wave * (0.0012 + 0.018 * tear);

    float2 suv = cuv + jit + float2(xoff, 0.0);
    float2 p = suv * size;

    // --- Chromatic fringing: sample each channel slightly apart.
    float ca = chroma * 1.6;
    float r = luma(layer, p + float2(ca, 0.0), size);
    float g = luma(layer, p, size);
    float b = luma(layer, p - float2(ca, 0.0), size);

    // --- Bloom: phosphor light spilling into its neighbours.
    float glow = 0.0;
    float radius1 = 1.5 + bloom * 2.0;
    float radius2 = 3.5 + bloom * 5.0;
    for (int i = 0; i < 8; i++) {
        float a = float(i) * 0.785398 + 0.3;
        float2 d = float2(cos(a), sin(a));
        glow += luma(layer, p + d * radius1, size) * 0.6;
        glow += luma(layer, p + d * radius2, size) * 0.4;
    }
    glow /= 8.0;

    float3 tint = float3(phosphor.rgb);
    float3 col = float3(r, g, b) * tint;
    col += tint * glow * bloom * 0.85;

    // --- Contrast & brightness.
    float c = 0.6 + contrast * 0.9;
    col = (col - 0.5) * c + 0.5;
    col *= 0.55 + brightness * 0.9;
    col = max(col, float3(0.0));

    // --- Scanlines, locked to the source image's pixel rows.
    float row = suv.y * sourceRows;
    float line = 0.5 + 0.5 * cos(row * 6.2831853);
    col *= mix(1.0, 0.45 + 0.55 * line, scanlines);

    // --- Rolling glow line drifting down the tube.
    float band = fract(time * 0.11);
    float d = suv.y - band;
    col += tint * exp(-d * d * 900.0) * glowLine * 0.12;

    // --- Ambient phosphor glow: the tube is never truly black.
    col += tint * ambient * 0.035;

    // --- Static.
    float n = hash12(p * 0.73 + float2(frame * 13.1, frame * 7.7));
    col += tint * (n - 0.35) * noise * 0.22;

    // --- Flicker.
    float f = hash12(float2(floor(time * 20.0), 3.1));
    col *= 1.0 - flicker * 0.09 * f;

    // --- Vignette toward the tube edges.
    float2 vv = cuv - 0.5;
    col *= 1.0 - dot(vv, vv) * (0.6 + curvature * 0.8);

    return half4(half3(clamp(col, float3(0.0), float3(1.2))), 1.0h);
}
