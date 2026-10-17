#include <metal_stdlib>
using namespace metal;

// Rounded box with the largest possible radius: a horizontal or vertical capsule.
static float capsuleDistance(float2 p, float4 rect) {
    float2 halfSize = max(rect.zw * 0.5, float2(0.5));
    float radius = min(halfSize.x, halfSize.y);
    float2 q = abs(p - rect.xy) - (halfSize - radius);
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
}

static float smoothUnion(float a, float b) {
    constexpr float k = 24.0;
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

static float zoneLight(float2 p, float4 focus, float3 gaps, int zone) {
    float gap = gaps[zone - 1];
    float reach = 2.0 * (gap + 68.0);
    float width = focus.w + max(0.0, focus.z - focus.w) * 0.45;
    float2 radius = max(float2(width + reach, focus.w + reach) * 0.5, float2(1.0));
    float r = length((p - focus.xy) / radius);
    // Empty zones take no ring: the innermost ring (gaps.x, the rest gap) starts at the focus,
    // every other one after the nearest ring inside it.
    float previous = gaps.x;
    for (int i = 0; i < 3; i++) {
        if (gaps[i] < gap - 0.5) { previous = max(previous, gaps[i]); }
    }
    float inner = gap <= gaps.x + 0.5 ? 0.12 : (focus.w * 0.5 + previous + 36.0) / radius.y;
    float peak = inner + (1.0 - inner) * 0.5;
    return smoothstep(inner, peak, r) * (1.0 - smoothstep(peak, 1.0, r));
}

[[ stitchable ]] half4 atmosphere(float2 position, float4 focus, float3 zones, float3 gaps,
                                 float4 source, float4 target,
                                 float pairIntensity, float proximity, float pairVisibility) {
    float2 p = position;
    bool hasPair = source.z > 0.0 && source.w > 0.0 && target.z > 0.0 && target.w > 0.0;
    if (hasPair && pairIntensity > 0.0) {
        float2 midpoint = (source.xy + target.xy) * 0.5;
        float influence = 1.0 - smoothstep(0.0, 160.0, length(p - midpoint));
        float2 direction = midpoint - focus.xy;
        p -= 8.0 * influence * proximity * pairVisibility * direction / max(40.0, length(direction));
    }

    float transmission = 1.0;
    if (focus.z > 0.0 && focus.w > 0.0) {
        for (int i = 0; i < 3; ++i) {
            if (zones[i] > 0.0)
                transmission *= 1.0 - zones[i] * zoneLight(p, focus, gaps, i + 1);
        }
    }
    if (hasPair && pairIntensity > 0.0) {
        float distance = smoothUnion(capsuleDistance(position, source), capsuleDistance(position, target));
        float outside = max(0.0, distance) / 28.0;
        float glow = exp(-outside * outside);
        // Distant tap-prepared pairs keep native selection feedback; no luminous bridge
        // crosses the canvas. Contact and deep overlap progressively reveal this light.
        transmission *= 1.0 - glow * pairIntensity * smoothstep(0.0, 1.0, proximity);
    }
    float alpha = clamp(1.0 - transmission, 0.0, 0.18);
    return half4(half3(alpha), half(alpha)); // Premultiplied white, in the destination color space.
}
