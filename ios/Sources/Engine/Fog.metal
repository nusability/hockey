#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
using namespace metal;

// Distance fog for RealityKit, which has none (ADR 0005). The formula is Filament's, so both
// platforms fade the world the same way: opacity = max * (1 - exp(-density * max(d - start, 0))),
// d the distance to the camera. RealityKit gives a surface shader no post-lighting hook, so the
// fogged share of the albedo moves into emission: lit albedo * (1 - f) + fog colour * f.
//
// custom_parameter (every fogged material): x = start, y = density, z = max opacity, w = the fog
// colour as sRGB 0xRRGGBB packed into a float (exact below 2^24) — the world's look
// (teams.toml [world.look]), set by Materials.swift. Android's View.FogOptions gets the same numbers.

static float3 srgbToLinear(float3 c)
{
    return select(pow((c + 0.055) / 1.055, 2.4), c / 12.92, c <= 0.04045);
}

static float3 fogColour(float4 p)
{
    uint v = uint(p.w + 0.5);
    return srgbToLinear(float3((v >> 16) & 255u, (v >> 8) & 255u, v & 255u) / 255.0);
}

static float fogAmount(realitykit::surface_parameters params)
{
    float4 p = params.uniforms().custom_parameter();
    float4 view = params.uniforms().world_to_view() * float4(params.geometry().world_position(), 1.0);
    float d = length(view.xyz);
    return p.z * (1.0 - exp(-p.y * max(d - p.x, 0.0)));
}

// The worlds: the palette texture, lit, fogged.
[[visible]]
void fogSurface(realitykit::surface_parameters params)
{
    constexpr sampler nearest(address::clamp_to_edge, filter::nearest);
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    half3 albedo = params.textures().base_color().sample(nearest, uv).rgb;
    albedo *= half3(params.material_constants().base_color_tint());

    float f = fogAmount(params);
    params.surface().set_base_color(albedo * half(1.0 - f));
    params.surface().set_emissive_color(half3(fogColour(params.uniforms().custom_parameter()) * f));
    params.surface().set_roughness(1.0);
    params.surface().set_metallic(0.0);
}

// The match's toys (players, ball, dummies): a flat colour, lit, fogged — like Android's actor.mat.
[[visible]]
void actorSurface(realitykit::surface_parameters params)
{
    half3 albedo = half3(params.material_constants().base_color_tint());
    float f = fogAmount(params);
    params.surface().set_base_color(albedo * half(1.0 - f));
    params.surface().set_emissive_color(half3(fogColour(params.uniforms().custom_parameter()) * f));
    params.surface().set_roughness(0.6);
    params.surface().set_metallic(0.0);
}

// Marks on the pitch (the aim line, the orbit): an unlit colour at the material's opacity, fogged
// like everything else in the world — like Android's overlay.mat.
[[visible]]
void overlaySurface(realitykit::surface_parameters params)
{
    float3 colour = params.material_constants().base_color_tint();
    float f = fogAmount(params);
    params.surface().set_base_color(half3(0));
    params.surface().set_emissive_color(half3(colour * (1.0 - f) + fogColour(params.uniforms().custom_parameter()) * f));
    params.surface().set_specular(0);
    params.surface().set_roughness(1);
    params.surface().set_opacity(half(params.material_constants().opacity_scale()));
}

// The sky dome: the palette's gradient as pure emission (no albedo, no specular), never fogged,
// tinted by the world's look (custom_parameter.xyz, linear) — sampled with the same UV convention as
// fogSurface, so the two can never disagree about which way up the palette is.
[[visible]]
void skySurface(realitykit::surface_parameters params)
{
    constexpr sampler linear(address::clamp_to_edge, filter::linear);
    float2 uv = params.geometry().uv0();
    uv.y = 1.0 - uv.y;
    half3 sky = params.textures().base_color().sample(linear, uv).rgb;
    params.surface().set_emissive_color(sky * half3(params.uniforms().custom_parameter().xyz));
    params.surface().set_base_color(half3(0));
    params.surface().set_specular(0);
    params.surface().set_roughness(1);
}
