#include <metal_stdlib>
using namespace metal;

/// Barrel lens: samples are pulled toward the center (magnifying the middle
/// of the line), easing out to identity at the edges and as `strength` → 0.
/// Displacement per axis is bounded by half-size * strength, so Swift sets
/// maxSampleOffset exactly and no sample ever leaves the layer.
[[ stitchable ]] float2 fisheye(float2 position, float2 size, float strength, float power) {
    if (strength <= 0.0 || size.x <= 0.0 || size.y <= 0.0) { return position; }
    float2 lensCenter = size * 0.5;
    float2 offset = position - lensCenter;
    float radius = clamp(length(offset / lensCenter), 0.0, 1.0);
    float pull = strength * pow(1.0 - radius, power);
    return lensCenter + offset * (1.0 - pull);
}