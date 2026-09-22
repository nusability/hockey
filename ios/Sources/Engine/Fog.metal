#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Distance fog for RealityKit, which has none (ADR 0005). The formula is Filament's, so both
// platforms fade the world the same way: opacity = maxOpacity * (1 - exp(-density * max(d - start, 0))).
// RealityKit gives a surface shader no post-lighting hook, so the fogged share of the albedo moves
// into emission: lit albedo * (1 - f) + fog colour * f.
//
// custom_parameter: xyz = camera position (world), w unused. Constants below mirror the Android
// scene's View.FogOptions; they move to shared/data with the world declarations (SMASH-6).
constant float3 fogColour = float3(1.0, 0.86, 0.62);
constant float fogStart = 45.0;
constant float fogDensity = 0.012;
constant float fogMaxOpacity = 0.8;

[[visible]]
void fogSurface(realitykit::surface_parameters params)
{
    constexpr sampler nearest(address::clamp_to_edge, filter::nearest);
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    half3 albedo = params.textures().base_color().sample(nearest, uv).rgb;
    albedo *= half3(params.material_constants().base_color_tint());

    float3 camera = params.uniforms().custom_parameter().xyz;
    float d = distance(params.geometry().world_position(), camera);
    float f = fogMaxOpacity * (1.0 - exp(-fogDensity * max(d - fogStart, 0.0)));

    params.surface().set_base_color(albedo * half(1.0 - f));
    params.surface().set_emissive_color(half3(fogColour * f));
    params.surface().set_roughness(1.0);
    params.surface().set_metallic(0.0);
}

// The sky dome: the palette's gradient as pure emission (no albedo, no specular), never fogged — sampled with the same UV
// convention as fogSurface, so the two can never disagree about which way up the palette is.
[[visible]]
void skySurface(realitykit::surface_parameters params)
{
    constexpr sampler linear(address::clamp_to_edge, filter::linear);
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    params.surface().set_emissive_color(params.textures().base_color().sample(linear, uv).rgb);
    params.surface().set_base_color(half3(0));
    params.surface().set_specular(0);
    params.surface().set_roughness(1);
}
