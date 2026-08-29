const std = @import("std");
const wireframe = @import("robine").ui.wireframe;
const lighting_lab = @import("robine").ui.lighting_lab;
const pedalboard_3d = @import("robine").ui.pedalboard_3d;

const Object = ?*anyopaque;
const Selector = *anyopaque;
const Class = *anyopaque;

const Point = extern struct { x: f64, y: f64 };
const Size = extern struct { width: f64, height: f64 };
const GridSize = extern struct { width: usize, height: usize, depth: usize };
const Rect = extern struct { origin: Point, size: Size };
const ClearColor = extern struct { red: f64, green: f64, blue: f64, alpha: f64 };
const Viewport = extern struct {
    origin_x: f64,
    origin_y: f64,
    width: f64,
    height: f64,
    z_near: f64,
    z_far: f64,
};

pub const ContentMode = enum {
    wireframe,
    pedalboard_3d,
    lighting_lab,
};

extern fn objc_getClass(name: [*:0]const u8) Object;
extern fn sel_registerName(name: [*:0]const u8) Selector;
extern fn objc_allocateClassPair(superclass: Class, name: [*:0]const u8, extra_bytes: usize) Object;
extern fn objc_registerClassPair(cls: Class) void;
extern fn class_addMethod(cls: Class, name: Selector, implementation: *const anyopaque, types: [*:0]const u8) bool;
extern fn objc_msgSend() callconv(.c) void;
extern fn MTLCreateSystemDefaultDevice() Object;
extern fn CACurrentMediaTime() f64;

pub const Options = struct {
    title: [*:0]const u8,
    width: u32,
    height: u32,
    line_vertices: []const wireframe.Vertex,
    fill_vertices: []const wireframe.Vertex,
    equipment_vertices: []const lighting_lab.Vertex = &.{},
    equipment_lights: []const pedalboard_3d.EmissiveLight = &.{},
    equipment_revision: u64 = 0,
    equipment_camera: pedalboard_3d.CameraPose = pedalboard_3d.rig_camera,
    mode: ContentMode = .wireframe,
    interaction: ?Interaction = null,
};

pub const Geometry = struct {
    line_vertices: []const wireframe.Vertex,
    fill_vertices: []const wireframe.Vertex,
    equipment_vertices: []const lighting_lab.Vertex = &.{},
    equipment_lights: []const pedalboard_3d.EmissiveLight = &.{},
    equipment_revision: u64 = 0,
    equipment_camera: pedalboard_3d.CameraPose = pedalboard_3d.rig_camera,
    mode: ContentMode = .wireframe,
};

pub const Interaction = struct {
    context: *anyopaque,
    pointer_down: *const fn (context: *anyopaque, point: [2]f32, window_aspect: f32) bool,
    geometry: *const fn (context: *anyopaque) Geometry,
};

const CameraTransition = struct {
    from: pedalboard_3d.CameraPose,
    to: pedalboard_3d.CameraPose,
    started_at: f64,
    duration: f32,
};

const RenderState = struct {
    device: Object,
    command_queue: Object,
    pipeline: Object,
    line_buffer: Object,
    fill_buffer: Object,
    line_count: usize,
    fill_count: usize,
    equipment_buffer: Object,
    equipment_count: usize,
    equipment_source_ptr: usize,
    equipment_revision: u64,
    equipment_lights: []const pedalboard_3d.EmissiveLight,
    mode: ContentMode,
    lighting_lab: LightingLabRenderState,
    ray_tracing: ?RayTracingRenderState,
    interaction: ?Interaction,
    camera_transition: CameraTransition,
};

const RayTracingRenderState = struct {
    compute_pipeline: Object,
    composite_pipeline: Object,
    acceleration_structure: Object,
    accumulation_texture: Object = null,
    texture_width: usize = 0,
    texture_height: usize = 0,
    sample_count: u32 = 0,
    sequence_index: u32 = 0,
    camera_was_moving: bool = false,
};

const AccelerationStructureSizes = extern struct {
    acceleration_structure_size: usize,
    build_scratch_buffer_size: usize,
    refit_scratch_buffer_size: usize,
};

const RayUniforms = extern struct {
    camera_fov: [4]f32,
    forward_aspect: [4]f32,
    right_min_distance: [4]f32,
    up_max_distance: [4]f32,
    sample_dimensions: [4]u32,
};

const progressive_ao_sample_limit: u32 = 24;

const LightingLabRenderState = struct {
    pipeline: Object,
    comparison_pipeline: Object,
    shadow_pipeline: Object,
    depth_state: Object,
    vertex_buffer: Object,
    vertex_count: usize,
    shadow_texture: Object,
};

const GpuEmissiveLight = extern struct {
    position_radius: [4]f32 = .{ 0, 0, 0, 0 },
    color_intensity: [4]f32 = .{ 0, 0, 0, 0 },
    direction_cone: [4]f32 = .{ 0, 0, 0, -1 },
};

const PbrUniforms = extern struct {
    view_projection: [16]f32,
    light_view_projection: [16]f32,
    camera_position: [4]f32,
    light_position: [4]f32,
    light_axis: [4]f32,
    strip_size_exposure: [4]f32,
    time_fill: [4]f32 = .{ 0, 0, 0, 0 },
    emissive_lights: [pedalboard_3d.Mesh.max_emissive_lights]GpuEmissiveLight =
        [_]GpuEmissiveLight{.{}} ** pedalboard_3d.Mesh.max_emissive_lights,
    emissive_light_count: u32 = 0,
    emissive_padding: [3]u32 = .{ 0, 0, 0 },
};

var render_state: ?RenderState = null;
var retained_delegate: Object = null;

const shader_source =
    \\#include <metal_stdlib>
    \\using namespace metal;
    \\
    \\struct Vertex {
    \\    float4 position;
    \\    float4 color;
    \\};
    \\
    \\struct RasterData {
    \\    float4 position [[position]];
    \\    float4 color;
    \\};
    \\
    \\vertex RasterData vertex_main(
    \\    uint vertex_id [[vertex_id]],
    \\    const device Vertex* vertices [[buffer(0)]]) {
    \\    RasterData out;
    \\    out.position = vertices[vertex_id].position;
    \\    out.color = vertices[vertex_id].color;
    \\    return out;
    \\}
    \\
    \\fragment float4 fragment_main(RasterData in [[stage_in]]) {
    \\    return in.color;
    \\}
    \\
    \\struct PbrVertex {
    \\    float4 position;
    \\    float4 normal;
    \\    float4 base_color;
    \\    float4 material;
    \\};
    \\
    \\struct PbrUniforms {
    \\    float4x4 view_projection;
    \\    float4x4 light_view_projection;
    \\    float4 camera_position;
    \\    float4 light_position;
    \\    float4 light_axis;
    \\    float4 strip_size_exposure;
    \\    float4 time_fill;
    \\    struct EmissiveLight {
    \\        float4 position_radius;
    \\        float4 color_intensity;
    \\        float4 direction_cone;
    \\    } emissive_lights[16];
    \\    uint emissive_light_count;
    \\    uint3 emissive_padding;
    \\};
    \\
    \\struct PbrRasterData {
    \\    float4 position [[position]];
    \\    float3 world_position;
    \\    float3 normal;
    \\    float3 base_color;
    \\    float3 material;
    \\    float4 shadow_position;
    \\};
    \\
    \\vertex PbrRasterData pbr_vertex(
    \\    uint vertex_id [[vertex_id]],
    \\    const device PbrVertex* vertices [[buffer(0)]],
    \\    constant PbrUniforms& uniforms [[buffer(1)]]) {
    \\    PbrVertex source_vertex = vertices[vertex_id];
    \\    PbrRasterData out;
    \\    out.position = uniforms.view_projection * source_vertex.position;
    \\    out.world_position = source_vertex.position.xyz;
    \\    out.normal = normalize(source_vertex.normal.xyz);
    \\    out.base_color = source_vertex.base_color.rgb;
    \\    out.material = source_vertex.material.xyz;
    \\    out.shadow_position = uniforms.light_view_projection * source_vertex.position;
    \\    return out;
    \\}
    \\
    \\vertex float4 shadow_vertex(
    \\    uint vertex_id [[vertex_id]],
    \\    const device PbrVertex* vertices [[buffer(0)]],
    \\    constant PbrUniforms& uniforms [[buffer(1)]]) {
    \\    return uniforms.light_view_projection * vertices[vertex_id].position;
    \\}
    \\
    \\float distribution_ggx(float3 n, float3 h, float roughness) {
    \\    float a = roughness * roughness;
    \\    float a2 = a * a;
    \\    float ndoth = max(dot(n, h), 0.0);
    \\    float denominator = ndoth * ndoth * (a2 - 1.0) + 1.0;
    \\    return a2 / max(M_PI_F * denominator * denominator, 0.0001);
    \\}
    \\
    \\float geometry_schlick_ggx(float ndotv, float roughness) {
    \\    float r = roughness + 1.0;
    \\    float k = (r * r) * 0.125;
    \\    return ndotv / max(ndotv * (1.0 - k) + k, 0.0001);
    \\}
    \\
    \\float geometry_smith(float3 n, float3 v, float3 l, float roughness) {
    \\    return geometry_schlick_ggx(max(dot(n, v), 0.0), roughness) *
    \\           geometry_schlick_ggx(max(dot(n, l), 0.0), roughness);
    \\}
    \\
    \\float3 fresnel_schlick(float cosine, float3 f0) {
    \\    return f0 + (1.0 - f0) * pow(clamp(1.0 - cosine, 0.0, 1.0), 5.0);
    \\}
    \\
    \\float shadow_visibility(float4 shadow_position, depth2d<float> shadow_map) {
    \\    float3 projected = shadow_position.xyz / max(shadow_position.w, 0.0001);
    \\    float2 uv = float2(projected.x * 0.5 + 0.5, 0.5 - projected.y * 0.5);
    \\    if (any(uv < 0.0) || any(uv > 1.0) || projected.z <= 0.0 || projected.z >= 1.0) return 1.0;
    \\    constexpr sampler shadow_sampler(coord::normalized, address::clamp_to_edge,
    \\        filter::linear, compare_func::less_equal);
    \\    float visibility = 0.0;
    \\    float2 texel = float2(2.2 / 1024.0);
    \\    for (int y = -1; y <= 1; ++y) {
    \\        for (int x = -1; x <= 1; ++x) {
    \\            visibility += shadow_map.sample_compare(shadow_sampler, uv + float2(x, y) * texel,
    \\                projected.z - 0.003);
    \\        }
    \\    }
    \\    return visibility / 9.0;
    \\}
    \\
    \\float3 aces_tonemap(float3 color) {
    \\    const float a = 2.51;
    \\    const float b = 0.03;
    \\    const float c = 2.43;
    \\    const float d = 0.59;
    \\    const float e = 0.14;
    \\    return clamp((color * (a * color + b)) / (color * (c * color + d) + e), 0.0, 1.0);
    \\}
    \\
    \\fragment float4 pbr_fragment(
    \\    PbrRasterData in [[stage_in]],
    \\    constant PbrUniforms& uniforms [[buffer(1)]],
    \\    depth2d<float> shadow_map [[texture(0)]]) {
    \\    float3 n = normalize(in.normal);
    \\    float3 v = normalize(uniforms.camera_position.xyz - in.world_position);
    \\    float roughness = clamp(in.material.x, 0.045, 1.0);
    \\    float metallic = clamp(in.material.y, 0.0, 1.0);
    \\    float emissive_strength = max(in.material.z, 0.0);
    \\    float3 f0 = mix(float3(0.04), in.base_color, metallic);
    \\    float3 direct = float3(0.0);
    \\    float visibility = shadow_visibility(in.shadow_position, shadow_map);
    \\    const int sample_count = 9;
    \\    for (int sample_index = 0; sample_index < sample_count; ++sample_index) {
    \\        float t = float(sample_index) / float(sample_count - 1) - 0.5;
    \\        float3 sample_position = uniforms.light_position.xyz + uniforms.light_axis.xyz *
    \\            t * uniforms.strip_size_exposure.y;
    \\        float3 difference = sample_position - in.world_position;
    \\        float distance_squared = max(dot(difference, difference), 0.2);
    \\        float3 l = normalize(difference);
    \\        float3 h = normalize(v + l);
    \\        float ndotl = max(dot(n, l), 0.0);
    \\        float ndotv = max(dot(n, v), 0.0);
    \\        float distribution = distribution_ggx(n, h, roughness);
    \\        float geometry = geometry_smith(n, v, l, roughness);
    \\        float3 fresnel = fresnel_schlick(max(dot(h, v), 0.0), f0);
    \\        float3 specular = distribution * geometry * fresnel /
    \\            max(4.0 * ndotv * ndotl, 0.001);
    \\        float3 diffuse = (1.0 - fresnel) * (1.0 - metallic) * in.base_color / M_PI_F;
    \\        float edge = 1.0 - abs(t) * 1.35;
    \\        float3 radiance = float3(1.0, 0.78, 0.54) * max(edge, 0.15) * uniforms.light_axis.w /
    \\            (distance_squared * float(sample_count));
    \\        direct += (diffuse + specular) * radiance * ndotl;
    \\    }
    \\    float3 fill_l = normalize(float3(0.78, 0.52, -0.36));
    \\    float3 fill_h = normalize(v + fill_l);
    \\    float fill_ndotl = max(dot(n, fill_l), 0.0);
    \\    float fill_ndotv = max(dot(n, v), 0.0);
    \\    float fill_distribution = distribution_ggx(n, fill_h, roughness);
    \\    float fill_geometry = geometry_smith(n, v, fill_l, roughness);
    \\    float3 fill_fresnel = fresnel_schlick(max(dot(fill_h, v), 0.0), f0);
    \\    float3 fill_specular = fill_distribution * fill_geometry * fill_fresnel /
    \\        max(4.0 * fill_ndotv * fill_ndotl, 0.001);
    \\    float3 fill_diffuse = (1.0 - fill_fresnel) * (1.0 - metallic) * in.base_color / M_PI_F;
    \\    direct += (fill_diffuse + fill_specular) * uniforms.time_fill.yzw * fill_ndotl;
    \\    float3 indicator_light = float3(0.0);
    \\    for (uint light_index = 0; light_index < min(uniforms.emissive_light_count, 16u); ++light_index) {
    \\        float3 difference = uniforms.emissive_lights[light_index].position_radius.xyz - in.world_position;
    \\        float radius = uniforms.emissive_lights[light_index].position_radius.w;
    \\        float distance_squared = max(dot(difference, difference), 0.006);
    \\        float distance_to_light = sqrt(distance_squared);
    \\        float3 led_l = difference / max(distance_to_light, 0.001);
    \\        float falloff = clamp(1.0 - distance_to_light / max(radius, 0.001), 0.0, 1.0);
    \\        falloff = falloff * falloff / max(distance_squared, 0.045);
    \\        float cone_cosine = uniforms.emissive_lights[light_index].direction_cone.w;
    \\        if (cone_cosine > -0.5) {
    \\            float3 cone_direction = normalize(uniforms.emissive_lights[light_index].direction_cone.xyz);
    \\            float cone_alignment = dot(-led_l, cone_direction);
    \\            falloff *= smoothstep(cone_cosine, min(cone_cosine + 0.18, 0.98), cone_alignment);
    \\        }
    \\        float led_ndotl = max(dot(n, led_l), 0.0);
    \\        float3 led_h = normalize(v + led_l);
    \\        float3 led_fresnel = fresnel_schlick(max(dot(led_h, v), 0.0), f0);
    \\        float led_distribution = distribution_ggx(n, led_h, roughness);
    \\        float led_geometry = geometry_smith(n, v, led_l, roughness);
    \\        float3 led_specular = led_distribution * led_geometry * led_fresnel /
    \\            max(4.0 * max(dot(n, v), 0.0) * led_ndotl, 0.001);
    \\        float3 led_diffuse = (1.0 - led_fresnel) * (1.0 - metallic) * in.base_color / M_PI_F;
    \\        float local_scale = cone_cosine > -0.5 ? 0.42 : 0.055;
    \\        float3 led_radiance = uniforms.emissive_lights[light_index].color_intensity.rgb *
    \\            uniforms.emissive_lights[light_index].color_intensity.w * falloff * local_scale;
    \\        indicator_light += (led_diffuse + led_specular) * led_radiance * led_ndotl;
    \\    }
    \\    float3 reflection = reflect(-v, n);
    \\    float horizon = clamp(reflection.y * 0.5 + 0.5, 0.0, 1.0);
    \\    float3 environment = mix(float3(0.010, 0.007, 0.004), float3(0.14, 0.095, 0.055), horizon);
    \\    float3 to_strip = normalize(uniforms.light_position.xyz - in.world_position);
    \\    float key_reflection_roughness = clamp(roughness + uniforms.strip_size_exposure.x * 0.035, 0.0, 1.0);
    \\    float strip_reflection = pow(max(dot(reflection, to_strip), 0.0), mix(150.0, 8.0, key_reflection_roughness));
    \\    environment += float3(1.0, 0.72, 0.46) * strip_reflection * 3.2;
    \\    float3 fixed_strip_direction = normalize(float3(0.22, 0.91, -0.35));
    \\    float fixed_strip_roughness = clamp(roughness + 0.20, 0.0, 1.0);
    \\    float fixed_strip = pow(max(dot(reflection, fixed_strip_direction), 0.0), mix(110.0, 7.0, fixed_strip_roughness));
    \\    environment += float3(0.42, 0.32, 0.22) * fixed_strip * 1.35;
    \\    float3 ambient_fresnel = fresnel_schlick(max(dot(n, v), 0.0), f0);
    \\    float3 ambient = environment * (ambient_fresnel + in.base_color * (1.0 - metallic) * 0.22) *
    \\        uniforms.strip_size_exposure.w;
    \\    float clearcoat_strength = pow(1.0 - roughness, 3.0);
    \\    float clearcoat_fresnel = fresnel_schlick(max(dot(n, v), 0.0), float3(0.04)).r;
    \\    ambient += float3(0.52, 0.78, 0.96) * fixed_strip * clearcoat_strength *
    \\        (0.55 + clearcoat_fresnel * 3.0);
    \\    float polished_visibility = metallic * pow(1.0 - roughness, 6.0);
    \\    float polished_warm = pow(max(dot(reflection, normalize(float3(-0.48, 0.82, 0.31))), 0.0), 16.0);
    \\    float polished_cool = pow(max(dot(reflection, normalize(float3(0.24, 0.91, -0.34))), 0.0), 12.0);
    \\    ambient += (float3(1.0, 0.72, 0.46) * polished_warm +
    \\        float3(0.70, 0.52, 0.34) * polished_cool) * polished_visibility * 0.62;
    \\    float3 emitted = in.base_color * emissive_strength;
    \\    float3 color = ambient + direct * mix(0.42, 1.0, visibility) + indicator_light + emitted;
    \\    color = aces_tonemap(color * uniforms.strip_size_exposure.z);
    \\    color = pow(color, float3(1.0 / 2.2));
    \\    return float4(color, 1.0);
    \\}
    \\
    \\struct LayerRasterData {
    \\    float4 position [[position]];
    \\    float2 uv;
    \\};
    \\
    \\vertex LayerRasterData layer_vertex(uint vertex_id [[vertex_id]]) {
    \\    const float2 positions[6] = {
    \\        float2(-1.0, -1.0), float2(1.0, -1.0), float2(1.0, 1.0),
    \\        float2(-1.0, -1.0), float2(1.0, 1.0), float2(-1.0, 1.0)
    \\    };
    \\    const float2 coordinates[6] = {
    \\        float2(0.0, 1.0), float2(1.0, 1.0), float2(1.0, 0.0),
    \\        float2(0.0, 1.0), float2(1.0, 0.0), float2(0.0, 0.0)
    \\    };
    \\    LayerRasterData out;
    \\    out.position = float4(positions[vertex_id], 0.0, 1.0);
    \\    out.uv = coordinates[vertex_id];
    \\    return out;
    \\}
    \\
    \\float layer_height(float2 point) {
    \\    float radius = length(point);
    \\    float collar = 0.16 * (1.0 - smoothstep(0.330, 0.350, radius));
    \\    float body = 0.82 * (1.0 - smoothstep(0.265, 0.315, radius));
    \\    return max(collar, body);
    \\}
    \\
    \\float3 shade_layer_material(
    \\    float3 base_color,
    \\    float roughness,
    \\    float metallic,
    \\    float3 normal,
    \\    float3 view_direction,
    \\    float3 light_direction,
    \\    float visibility,
    \\    constant PbrUniforms& uniforms) {
    \\    float3 half_direction = normalize(view_direction + light_direction);
    \\    float ndotl = max(dot(normal, light_direction), 0.0);
    \\    float ndotv = max(dot(normal, view_direction), 0.0);
    \\    float3 f0 = mix(float3(0.04), base_color, metallic);
    \\    float distribution = distribution_ggx(normal, half_direction, roughness);
    \\    float geometry = geometry_smith(normal, view_direction, light_direction, roughness);
    \\    float3 fresnel = fresnel_schlick(max(dot(half_direction, view_direction), 0.0), f0);
    \\    float3 specular = distribution * geometry * fresnel / max(4.0 * ndotv * ndotl, 0.001);
    \\    float3 diffuse = (1.0 - fresnel) * (1.0 - metallic) * base_color / M_PI_F;
    \\    float3 direct = (diffuse + specular) * float3(1.0, 0.78, 0.54) * 3.8 * ndotl * visibility;
    \\    float3 reflection = reflect(-view_direction, normal);
    \\    float horizon = clamp(reflection.y * 0.5 + 0.5, 0.0, 1.0);
    \\    float3 environment = mix(float3(0.006, 0.010, 0.014), float3(0.10, 0.16, 0.18), horizon);
    \\    float moving_strip = pow(max(dot(reflection, light_direction), 0.0), mix(180.0, 12.0, roughness));
    \\    environment += float3(1.0, 0.72, 0.46) * moving_strip * 2.8;
    \\    float fixed_strip = pow(max(dot(reflection, normalize(float3(-0.72, 0.40, 0.56))), 0.0),
    \\        mix(120.0, 10.0, roughness));
    \\    environment += float3(0.30, 0.58, 0.70) * fixed_strip * 1.6;
    \\    float3 ambient_fresnel = fresnel_schlick(max(dot(normal, view_direction), 0.0), f0);
    \\    float3 ambient = environment * (ambient_fresnel + base_color * (1.0 - metallic) * 0.22) *
    \\        uniforms.strip_size_exposure.w;
    \\    return ambient + direct;
    \\}
    \\
    \\fragment float4 layer_fragment(
    \\    LayerRasterData in [[stage_in]],
    \\    constant PbrUniforms& uniforms [[buffer(1)]]) {
    \\    const float viewport_aspect = 0.625;
    \\    float2 point = float2((in.uv.x - 0.5) * 2.0 * viewport_aspect, (0.5 - in.uv.y) * 2.0);
    \\    float radius = length(point);
    \\    float height = layer_height(point);
    \\    const float epsilon = 0.003;
    \\    float height_dx = layer_height(point + float2(epsilon, 0.0)) -
    \\        layer_height(point - float2(epsilon, 0.0));
    \\    float height_dy = layer_height(point + float2(0.0, epsilon)) -
    \\        layer_height(point - float2(0.0, epsilon));
    \\    float3 normal = radius < 0.350 ? normalize(float3(-height_dx * 4.0, -height_dy * 4.0, epsilon * 2.0)) :
    \\        float3(0.0, 0.0, 1.0);
    \\    float3 base_color = float3(0.050, 0.075, 0.068);
    \\    float roughness = 0.31;
    \\    float metallic = 0.42;
    \\    if (radius < 0.315) {
    \\        base_color = float3(0.070, 0.088, 0.084);
    \\        roughness = 0.14;
    \\        metallic = 0.96;
    \\    } else if (radius < 0.350) {
    \\        base_color = float3(0.32, 0.35, 0.34);
    \\        roughness = 0.19;
    \\        metallic = 1.0;
    \\    }
    \\    bool indicator = abs(point.x) < 0.026 && point.y > 0.205 && point.y < 0.405;
    \\    if (indicator) {
    \\        base_color = float3(0.95, 0.42, 0.055);
    \\        roughness = 0.25;
    \\        metallic = 0.35;
    \\        normal = float3(0.0, 0.0, 1.0);
    \\    }
    \\    float3 mapped_light = float3(uniforms.light_position.x, -uniforms.light_position.z,
    \\        uniforms.light_position.y);
    \\    float3 light_direction = normalize(mapped_light - float3(point * 3.0, height));
    \\    float3 mapped_camera = float3(uniforms.camera_position.x, -uniforms.camera_position.z,
    \\        uniforms.camera_position.y);
    \\    float3 view_direction = normalize(mapped_camera - float3(point * 3.0, height));
    \\    float visibility = 1.0;
    \\    if (radius >= 0.350) {
    \\        float front_light = max(light_direction.z, 0.18);
    \\        float2 shadow_offset = -light_direction.xy / front_light * 0.16;
    \\        float shadow_distance = length(point - shadow_offset) - 0.350;
    \\        float softness = 0.045 + 0.035 * (1.0 - front_light);
    \\        visibility = mix(0.38, 1.0, smoothstep(-softness, softness, shadow_distance));
    \\    }
    \\    float3 color = shade_layer_material(base_color, roughness, metallic, normal,
    \\        view_direction, light_direction, visibility, uniforms);
    \\    color = aces_tonemap(color * uniforms.strip_size_exposure.z);
    \\    color = pow(color, float3(1.0 / 2.2));
    \\    return float4(color, 1.0);
    \\}
;

const ray_tracing_shader_source =
    \\#include <metal_stdlib>
    \\#include <metal_raytracing>
    \\using namespace metal;
    \\using namespace metal::raytracing;
    \\
    \\struct PbrVertex {
    \\    float4 position;
    \\    float4 normal;
    \\    float4 base_color;
    \\    float4 material;
    \\};
    \\
    \\struct RayUniforms {
    \\    float4 camera_fov;
    \\    float4 forward_aspect;
    \\    float4 right_min_distance;
    \\    float4 up_max_distance;
    \\    uint4 sample_dimensions;
    \\};
    \\
    \\uint hash_uint(uint value) {
    \\    value ^= value >> 16;
    \\    value *= 0x7feb352du;
    \\    value ^= value >> 15;
    \\    value *= 0x846ca68bu;
    \\    return value ^ (value >> 16);
    \\}
    \\
    \\float random_float(thread uint &state) {
    \\    state = hash_uint(state);
    \\    return float(state) * (1.0 / 4294967296.0);
    \\}
    \\
    \\float3 cosine_hemisphere(float3 normal, thread uint &state) {
    \\    float r1 = random_float(state);
    \\    float r2 = random_float(state);
    \\    float radius = sqrt(r1);
    \\    float phi = 6.28318530718 * r2;
    \\    float3 local = float3(radius * cos(phi), radius * sin(phi), sqrt(max(0.0, 1.0 - r1)));
    \\    float3 helper = abs(normal.y) < 0.95 ? float3(0.0, 1.0, 0.0) : float3(1.0, 0.0, 0.0);
    \\    float3 tangent = normalize(cross(helper, normal));
    \\    float3 bitangent = cross(normal, tangent);
    \\    return normalize(tangent * local.x + bitangent * local.y + normal * local.z);
    \\}
    \\
    \\kernel void progressive_ao(
    \\    const device PbrVertex *vertices [[buffer(0)]],
    \\    primitive_acceleration_structure scene [[buffer(1)]],
    \\    constant RayUniforms &uniforms [[buffer(2)]],
    \\    texture2d<float, access::read_write> accumulation [[texture(0)]],
    \\    uint2 gid [[thread_position_in_grid]]) {
    \\    uint2 dimensions = uniforms.sample_dimensions.yz;
    \\    if (gid.x >= dimensions.x || gid.y >= dimensions.y) return;
    \\    uint seed = gid.x + gid.y * dimensions.x + uniforms.sample_dimensions.w * 0x9e3779b9u;
    \\    float2 uv = (float2(gid) + 0.5) / float2(dimensions);
    \\    float2 screen = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    \\    float tan_half_fov = uniforms.camera_fov.w;
    \\    float3 direction = normalize(uniforms.forward_aspect.xyz +
    \\        uniforms.right_min_distance.xyz * (screen.x * uniforms.forward_aspect.w * tan_half_fov) +
    \\        uniforms.up_max_distance.xyz * (screen.y * tan_half_fov));
    \\    ray primary_ray;
    \\    primary_ray.origin = uniforms.camera_fov.xyz;
    \\    primary_ray.direction = direction;
    \\    primary_ray.min_distance = uniforms.right_min_distance.w;
    \\    primary_ray.max_distance = 40.0;
    \\    intersector<triangle_data> primary_intersector;
    \\    auto hit = primary_intersector.intersect(primary_ray, scene);
    \\    float visibility = 1.0;
    \\    if (hit.type != intersection_type::none) {
    \\        uint vertex_index = hit.primitive_id * 3;
    \\        float2 bary = hit.triangle_barycentric_coord;
    \\        float3 normal = normalize(vertices[vertex_index].normal.xyz * (1.0 - bary.x - bary.y) +
    \\            vertices[vertex_index + 1].normal.xyz * bary.x + vertices[vertex_index + 2].normal.xyz * bary.y);
    \\        if (dot(normal, direction) > 0.0) normal = -normal;
    \\        float3 hit_position = primary_ray.origin + primary_ray.direction * hit.distance;
    \\        visibility = 0.0;
    \\        intersector<triangle_data> ao_intersector;
    \\        ao_intersector.accept_any_intersection(true);
    \\        for (uint ray_index = 0; ray_index < 4; ++ray_index) {
    \\            ray ao_ray;
    \\            ao_ray.origin = hit_position + normal * 0.006;
    \\            ao_ray.direction = cosine_hemisphere(normal, seed);
    \\            ao_ray.min_distance = 0.004;
    \\            ao_ray.max_distance = uniforms.up_max_distance.w;
    \\            auto ao_hit = ao_intersector.intersect(ao_ray, scene);
    \\            float ray_visibility = 1.0;
    \\            if (ao_hit.type != intersection_type::none) {
    \\                float normalized_distance = saturate(ao_hit.distance / ao_ray.max_distance);
    \\                ray_visibility = smoothstep(0.08, 0.92, normalized_distance);
    \\            }
    \\            visibility += ray_visibility * 0.25;
    \\        }
    \\    }
    \\    uint sample_index = uniforms.sample_dimensions.x;
    \\    float previous = sample_index == 0 ? visibility : accumulation.read(gid).r;
    \\    float averaged = (previous * float(sample_index) + visibility) / float(sample_index + 1);
    \\    accumulation.write(float4(averaged), gid);
    \\}
    \\
    \\struct CompositeRasterData {
    \\    float4 position [[position]];
    \\    float2 uv;
    \\};
    \\
    \\vertex CompositeRasterData ao_composite_vertex(uint vertex_id [[vertex_id]]) {
    \\    const float2 positions[6] = {
    \\        float2(-1.0, -1.0), float2(1.0, -1.0), float2(-1.0, 1.0),
    \\        float2(-1.0, 1.0), float2(1.0, -1.0), float2(1.0, 1.0)
    \\    };
    \\    float2 position = positions[vertex_id];
    \\    CompositeRasterData out;
    \\    out.position = float4(position, 0.0, 1.0);
    \\    out.uv = float2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
    \\    return out;
    \\}
    \\
    \\fragment float4 ao_composite_fragment(
    \\    CompositeRasterData in [[stage_in]],
    \\    texture2d<float> accumulation [[texture(0)]]) {
    \\    constexpr sampler linear_sampler(coord::normalized, address::clamp_to_edge, filter::linear);
    \\    float2 texel = 1.0 / float2(accumulation.get_width(), accumulation.get_height());
    \\    float visibility = accumulation.sample(linear_sampler, in.uv).r * 0.25;
    \\    visibility += accumulation.sample(linear_sampler, in.uv + float2(texel.x, 0.0)).r * 0.125;
    \\    visibility += accumulation.sample(linear_sampler, in.uv - float2(texel.x, 0.0)).r * 0.125;
    \\    visibility += accumulation.sample(linear_sampler, in.uv + float2(0.0, texel.y)).r * 0.125;
    \\    visibility += accumulation.sample(linear_sampler, in.uv - float2(0.0, texel.y)).r * 0.125;
    \\    visibility += accumulation.sample(linear_sampler, in.uv + texel).r * 0.0625;
    \\    visibility += accumulation.sample(linear_sampler, in.uv - texel).r * 0.0625;
    \\    visibility += accumulation.sample(linear_sampler, in.uv + float2(texel.x, -texel.y)).r * 0.0625;
    \\    visibility += accumulation.sample(linear_sampler, in.uv + float2(-texel.x, texel.y)).r * 0.0625;
    \\    float opacity = saturate((1.0 - visibility) * 0.34);
    \\    return float4(0.018, 0.022, 0.020, opacity);
    \\}
;

pub fn run(options: Options) !void {
    const pool = try send0(Object, try classNamed("NSAutoreleasePool"), "new");
    defer send0(void, pool, "drain") catch {};

    const application = try send0(Object, try classNamed("NSApplication"), "sharedApplication");
    _ = try send1(i8, isize, application, "setActivationPolicy:", 0);

    const delegate_class = try makeDelegateClass();
    const delegate_alloc = try send0(Object, delegate_class, "alloc");
    retained_delegate = try send0(Object, delegate_alloc, "init");
    try send1(void, Object, application, "setDelegate:", retained_delegate);

    const device = MTLCreateSystemDefaultDevice() orelse return error.MetalUnavailable;
    const sample_count = try preferredSampleCount(device);
    const library = try createLibrary(device);
    const pipeline = try createWireframePipeline(device, library, sample_count);
    const lab_render_state = try createLightingLabRenderState(device, library, sample_count);
    const command_queue = try send0(Object, device, "newCommandQueue");
    const line_buffer = try send3(
        Object,
        *const anyopaque,
        usize,
        usize,
        device,
        "newBufferWithBytes:length:options:",
        @ptrCast(options.line_vertices.ptr),
        options.line_vertices.len * @sizeOf(wireframe.Vertex),
        0,
    );
    const fill_buffer = try send3(
        Object,
        *const anyopaque,
        usize,
        usize,
        device,
        "newBufferWithBytes:length:options:",
        @ptrCast(options.fill_vertices.ptr),
        options.fill_vertices.len * @sizeOf(wireframe.Vertex),
        0,
    );
    const equipment_buffer = try send3(
        Object,
        *const anyopaque,
        usize,
        usize,
        device,
        "newBufferWithBytes:length:options:",
        @ptrCast(options.equipment_vertices.ptr),
        options.equipment_vertices.len * @sizeOf(lighting_lab.Vertex),
        0,
    );
    const ray_tracing_state = if (options.mode == .pedalboard_3d and try supportsRayTracing(device))
        createRayTracingRenderState(
            device,
            command_queue,
            equipment_buffer,
            options.equipment_vertices.len,
            sample_count,
        ) catch |err| fallback: {
            std.log.warn("Progressive ray-traced AO unavailable, using raster fallback: {s}", .{@errorName(err)});
            break :fallback null;
        }
    else
        null;
    render_state = .{
        .device = device,
        .command_queue = command_queue,
        .pipeline = pipeline,
        .line_buffer = line_buffer,
        .fill_buffer = fill_buffer,
        .line_count = options.line_vertices.len,
        .fill_count = options.fill_vertices.len,
        .equipment_buffer = equipment_buffer,
        .equipment_count = options.equipment_vertices.len,
        .equipment_source_ptr = @intFromPtr(options.equipment_vertices.ptr),
        .equipment_revision = options.equipment_revision,
        .equipment_lights = options.equipment_lights,
        .mode = options.mode,
        .lighting_lab = lab_render_state,
        .ray_tracing = ray_tracing_state,
        .interaction = options.interaction,
        .camera_transition = .{
            .from = options.equipment_camera,
            .to = options.equipment_camera,
            .started_at = CACurrentMediaTime(),
            .duration = 0,
        },
    };
    defer render_state = null;

    const frame = Rect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = @floatFromInt(options.width), .height = @floatFromInt(options.height) },
    };

    const view_class = try makeViewClass();
    const view_alloc = try send0(Object, view_class, "alloc");
    const view = try send2(Object, Rect, Object, view_alloc, "initWithFrame:device:", frame, device);
    try send1(void, usize, view, "setSampleCount:", sample_count);
    try send1(void, usize, view, "setColorPixelFormat:", 80);
    try send1(void, usize, view, "setDepthStencilPixelFormat:", 252);
    try send1(void, ClearColor, view, "setClearColor:", .{
        .red = 0.025,
        .green = 0.038,
        .blue = 0.036,
        .alpha = 1.0,
    });
    try send1(void, isize, view, "setPreferredFramesPerSecond:", 60);
    try send1(void, bool, view, "setPaused:", false);
    try send1(void, bool, view, "setEnableSetNeedsDisplay:", false);
    try send1(void, usize, view, "setAutoresizingMask:", 2 | 16);
    try send1(void, Object, view, "setDelegate:", retained_delegate);

    const window_alloc = try send0(Object, try classNamed("NSWindow"), "alloc");
    const style_mask: usize = 1 | 2 | 4 | 8;
    const window = try send4(Object, Rect, usize, usize, bool, window_alloc, "initWithContentRect:styleMask:backing:defer:", frame, style_mask, 2, false);
    try send1(void, Object, window, "setTitle:", try nsString(options.title));
    try send1(void, Size, window, "setContentAspectRatio:", .{
        .width = @floatFromInt(options.width),
        .height = @floatFromInt(options.height),
    });
    try send1(void, Size, window, "setContentMinSize:", .{
        .width = @as(f64, @floatFromInt(options.width)) * 0.625,
        .height = @as(f64, @floatFromInt(options.height)) * 0.625,
    });
    try send1(void, bool, window, "setReleasedWhenClosed:", false);
    try send1(void, Object, window, "setContentView:", view);
    try send0(void, window, "center");
    try send1(void, Object, window, "makeKeyAndOrderFront:", null);
    try send1(void, bool, application, "activateIgnoringOtherApps:", true);
    try send0(void, application, "run");
}

fn supportsRayTracing(device: Object) !bool {
    const selector = sel_registerName("supportsRaytracing");
    if (!try send1(bool, Selector, device, "respondsToSelector:", selector)) return false;
    return send0(bool, device, "supportsRaytracing");
}

fn createLibrary(device: Object) !Object {
    return createLibraryFromSource(device, shader_source);
}

fn createLibraryFromSource(device: Object, source: [*:0]const u8) !Object {
    var compile_error: Object = null;
    const Function = *const fn (Object, Selector, Object, Object, *Object) callconv(.c) Object;
    const function: Function = @ptrCast(&objc_msgSend);
    const library = function(device, sel_registerName("newLibraryWithSource:options:error:"), try nsString(source), null, &compile_error);
    if (library != null) return library;
    if (compile_error) |error_object| {
        const description = send0(Object, error_object, "localizedDescription") catch null;
        if (description) |description_object| {
            const message = send0([*:0]const u8, description_object, "UTF8String") catch return error.MetalShaderCompilationFailed;
            std.log.err("Metal shader compilation failed: {s}", .{message});
        }
    }
    return error.MetalShaderCompilationFailed;
}

fn createWireframePipeline(device: Object, library: Object, sample_count: usize) !Object {
    const vertex_function = try send1(Object, Object, library, "newFunctionWithName:", try nsString("vertex_main"));
    const fragment_function = try send1(Object, Object, library, "newFunctionWithName:", try nsString("fragment_main"));

    const descriptor_alloc = try send0(Object, try classNamed("MTLRenderPipelineDescriptor"), "alloc");
    const descriptor = try send0(Object, descriptor_alloc, "init");
    try send1(void, usize, descriptor, "setRasterSampleCount:", sample_count);
    try send1(void, Object, descriptor, "setVertexFunction:", vertex_function);
    try send1(void, Object, descriptor, "setFragmentFunction:", fragment_function);

    const attachments = try send0(Object, descriptor, "colorAttachments");
    const color_attachment = try send1(Object, usize, attachments, "objectAtIndexedSubscript:", 0);
    try send1(void, usize, color_attachment, "setPixelFormat:", 80);
    try send1(void, usize, descriptor, "setDepthAttachmentPixelFormat:", 252);

    return send2(Object, Object, Object, device, "newRenderPipelineStateWithDescriptor:error:", descriptor, null);
}

fn createLightingLabRenderState(device: Object, library: Object, sample_count: usize) !LightingLabRenderState {
    const pbr_vertex = try send1(Object, Object, library, "newFunctionWithName:", try nsString("pbr_vertex"));
    const pbr_fragment = try send1(Object, Object, library, "newFunctionWithName:", try nsString("pbr_fragment"));
    const pbr_descriptor = try send0(Object, try send0(Object, try classNamed("MTLRenderPipelineDescriptor"), "alloc"), "init");
    try send1(void, usize, pbr_descriptor, "setRasterSampleCount:", sample_count);
    try send1(void, Object, pbr_descriptor, "setVertexFunction:", pbr_vertex);
    try send1(void, Object, pbr_descriptor, "setFragmentFunction:", pbr_fragment);
    const pbr_attachments = try send0(Object, pbr_descriptor, "colorAttachments");
    const pbr_color = try send1(Object, usize, pbr_attachments, "objectAtIndexedSubscript:", 0);
    try send1(void, usize, pbr_color, "setPixelFormat:", 80);
    try send1(void, usize, pbr_descriptor, "setDepthAttachmentPixelFormat:", 252);
    const pbr_pipeline = try send2(Object, Object, Object, device, "newRenderPipelineStateWithDescriptor:error:", pbr_descriptor, null);

    const layer_vertex = try send1(Object, Object, library, "newFunctionWithName:", try nsString("layer_vertex"));
    const layer_fragment = try send1(Object, Object, library, "newFunctionWithName:", try nsString("layer_fragment"));
    const layer_descriptor = try send0(Object, try send0(Object, try classNamed("MTLRenderPipelineDescriptor"), "alloc"), "init");
    try send1(void, usize, layer_descriptor, "setRasterSampleCount:", sample_count);
    try send1(void, Object, layer_descriptor, "setVertexFunction:", layer_vertex);
    try send1(void, Object, layer_descriptor, "setFragmentFunction:", layer_fragment);
    const layer_attachments = try send0(Object, layer_descriptor, "colorAttachments");
    const layer_color = try send1(Object, usize, layer_attachments, "objectAtIndexedSubscript:", 0);
    try send1(void, usize, layer_color, "setPixelFormat:", 80);
    try send1(void, usize, layer_descriptor, "setDepthAttachmentPixelFormat:", 252);
    const layer_pipeline = try send2(Object, Object, Object, device, "newRenderPipelineStateWithDescriptor:error:", layer_descriptor, null);

    const shadow_vertex = try send1(Object, Object, library, "newFunctionWithName:", try nsString("shadow_vertex"));
    const shadow_descriptor = try send0(Object, try send0(Object, try classNamed("MTLRenderPipelineDescriptor"), "alloc"), "init");
    try send1(void, Object, shadow_descriptor, "setVertexFunction:", shadow_vertex);
    try send1(void, usize, shadow_descriptor, "setDepthAttachmentPixelFormat:", 252);
    const shadow_pipeline = try send2(Object, Object, Object, device, "newRenderPipelineStateWithDescriptor:error:", shadow_descriptor, null);

    const depth_descriptor = try send0(Object, try send0(Object, try classNamed("MTLDepthStencilDescriptor"), "alloc"), "init");
    try send1(void, usize, depth_descriptor, "setDepthCompareFunction:", 1);
    try send1(void, bool, depth_descriptor, "setDepthWriteEnabled:", true);
    const depth_state = try send1(Object, Object, device, "newDepthStencilStateWithDescriptor:", depth_descriptor);

    var mesh = lighting_lab.Mesh{};
    try lighting_lab.build(&mesh);
    const vertex_buffer = try send3(
        Object,
        *const anyopaque,
        usize,
        usize,
        device,
        "newBufferWithBytes:length:options:",
        @ptrCast(mesh.items().ptr),
        mesh.items().len * @sizeOf(lighting_lab.Vertex),
        0,
    );

    return .{
        .pipeline = pbr_pipeline,
        .comparison_pipeline = layer_pipeline,
        .shadow_pipeline = shadow_pipeline,
        .depth_state = depth_state,
        .vertex_buffer = vertex_buffer,
        .vertex_count = mesh.items().len,
        .shadow_texture = try createShadowTexture(device),
    };
}

fn createRayTracingRenderState(
    device: Object,
    command_queue: Object,
    equipment_buffer: Object,
    equipment_count: usize,
    sample_count: usize,
) !RayTracingRenderState {
    if (equipment_count < 3) return error.RayTracingGeometryMissing;
    const library = try createLibraryFromSource(device, ray_tracing_shader_source);
    const compute_function = try send1(Object, Object, library, "newFunctionWithName:", try nsString("progressive_ao"));
    const compute_pipeline = try send2(Object, Object, Object, device, "newComputePipelineStateWithFunction:error:", compute_function, null);

    const vertex_function = try send1(Object, Object, library, "newFunctionWithName:", try nsString("ao_composite_vertex"));
    const fragment_function = try send1(Object, Object, library, "newFunctionWithName:", try nsString("ao_composite_fragment"));
    const pipeline_descriptor = try send0(Object, try send0(Object, try classNamed("MTLRenderPipelineDescriptor"), "alloc"), "init");
    try send1(void, usize, pipeline_descriptor, "setRasterSampleCount:", sample_count);
    try send1(void, Object, pipeline_descriptor, "setVertexFunction:", vertex_function);
    try send1(void, Object, pipeline_descriptor, "setFragmentFunction:", fragment_function);
    const attachments = try send0(Object, pipeline_descriptor, "colorAttachments");
    const color_attachment = try send1(Object, usize, attachments, "objectAtIndexedSubscript:", 0);
    try send1(void, usize, color_attachment, "setPixelFormat:", 80);
    try send1(void, bool, color_attachment, "setBlendingEnabled:", true);
    try send1(void, usize, color_attachment, "setSourceRGBBlendFactor:", 4);
    try send1(void, usize, color_attachment, "setDestinationRGBBlendFactor:", 5);
    try send1(void, usize, pipeline_descriptor, "setDepthAttachmentPixelFormat:", 252);
    const composite_pipeline = try send2(Object, Object, Object, device, "newRenderPipelineStateWithDescriptor:error:", pipeline_descriptor, null);

    return .{
        .compute_pipeline = compute_pipeline,
        .composite_pipeline = composite_pipeline,
        .acceleration_structure = try buildAccelerationStructure(device, command_queue, equipment_buffer, equipment_count),
    };
}

fn buildAccelerationStructure(device: Object, command_queue: Object, vertex_buffer: Object, vertex_count: usize) !Object {
    const geometry_descriptor = try send0(Object, try classNamed("MTLAccelerationStructureTriangleGeometryDescriptor"), "descriptor");
    try send1(void, Object, geometry_descriptor, "setVertexBuffer:", vertex_buffer);
    try send1(void, usize, geometry_descriptor, "setVertexBufferOffset:", 0);
    try send1(void, usize, geometry_descriptor, "setVertexStride:", @sizeOf(lighting_lab.Vertex));
    try send1(void, usize, geometry_descriptor, "setTriangleCount:", vertex_count / 3);
    try send1(void, bool, geometry_descriptor, "setOpaque:", true);

    const geometry_descriptors = try send1(Object, Object, try classNamed("NSArray"), "arrayWithObject:", geometry_descriptor);
    const acceleration_descriptor = try send0(Object, try classNamed("MTLPrimitiveAccelerationStructureDescriptor"), "descriptor");
    try send1(void, Object, acceleration_descriptor, "setGeometryDescriptors:", geometry_descriptors);
    const sizes = try send1(AccelerationStructureSizes, Object, device, "accelerationStructureSizesWithDescriptor:", acceleration_descriptor);
    const acceleration_structure = try send1(Object, usize, device, "newAccelerationStructureWithSize:", sizes.acceleration_structure_size);
    const scratch_buffer = try send2(Object, usize, usize, device, "newBufferWithLength:options:", sizes.build_scratch_buffer_size, 2 << 4);

    const command_buffer = try send0(Object, command_queue, "commandBuffer");
    const encoder = try send0(Object, command_buffer, "accelerationStructureCommandEncoder");
    try send4(void, Object, Object, Object, usize, encoder, "buildAccelerationStructure:descriptor:scratchBuffer:scratchBufferOffset:", acceleration_structure, acceleration_descriptor, scratch_buffer, 0);
    try send0(void, encoder, "endEncoding");
    try send0(void, command_buffer, "commit");
    try send0(void, command_buffer, "waitUntilCompleted");
    try send0(void, scratch_buffer, "release");
    return acceleration_structure;
}

fn preferredSampleCount(device: Object) !usize {
    if (try send1(bool, usize, device, "supportsTextureSampleCount:", 4)) return 4;
    if (try send1(bool, usize, device, "supportsTextureSampleCount:", 2)) return 2;
    return 1;
}

fn createShadowTexture(device: Object) !Object {
    const descriptor = try send4(Object, usize, usize, usize, bool, try classNamed("MTLTextureDescriptor"), "texture2DDescriptorWithPixelFormat:width:height:mipmapped:", 252, 1024, 1024, false);
    try send1(void, usize, descriptor, "setUsage:", 1 | 4);
    try send1(void, usize, descriptor, "setStorageMode:", 2);
    return send1(Object, Object, device, "newTextureWithDescriptor:", descriptor);
}

fn makeDelegateClass() !Object {
    if (objc_getClass("RobineStudioDelegate")) |existing| return existing;

    const super_object = objc_getClass("NSObject") orelse return error.ObjectiveCClassMissing;
    const subclass_object = objc_allocateClassPair(@ptrCast(super_object), "RobineStudioDelegate", 0) orelse return error.ObjectiveCClassCreationFailed;
    const subclass: Class = @ptrCast(subclass_object);

    if (!class_addMethod(subclass, sel_registerName("drawInMTKView:"), @ptrCast(&drawInMTKView), "v@:@"))
        return error.ObjectiveCMethodCreationFailed;
    if (!class_addMethod(subclass, sel_registerName("mtkView:drawableSizeWillChange:"), @ptrCast(&drawableSizeChanged), "v@:@{CGSize=dd}"))
        return error.ObjectiveCMethodCreationFailed;
    if (!class_addMethod(subclass, sel_registerName("applicationShouldTerminateAfterLastWindowClosed:"), @ptrCast(&terminateAfterLastWindow), "c@:@"))
        return error.ObjectiveCMethodCreationFailed;

    objc_registerClassPair(subclass);
    return subclass_object;
}

fn makeViewClass() !Object {
    if (objc_getClass("RobineStudioView")) |existing| return existing;

    const super_object = objc_getClass("MTKView") orelse return error.ObjectiveCClassMissing;
    const subclass_object = objc_allocateClassPair(@ptrCast(super_object), "RobineStudioView", 0) orelse return error.ObjectiveCClassCreationFailed;
    const subclass: Class = @ptrCast(subclass_object);

    if (!class_addMethod(subclass, sel_registerName("mouseDown:"), @ptrCast(&mouseDown), "v@:@"))
        return error.ObjectiveCMethodCreationFailed;

    objc_registerClassPair(subclass);
    return subclass_object;
}

fn drawInMTKView(_: Object, _: Selector, view: Object) callconv(.c) void {
    draw(view) catch |err| std.log.err("Metal frame failed: {s}", .{@errorName(err)});
}

fn drawableSizeChanged(_: Object, _: Selector, _: Object, _: Size) callconv(.c) void {}

fn terminateAfterLastWindow(_: Object, _: Selector, _: Object) callconv(.c) i8 {
    return 1;
}

fn mouseDown(view: Object, _: Selector, event: Object) callconv(.c) void {
    handlePointerDown(view, event) catch |err| std.log.err("Pointer interaction failed: {s}", .{@errorName(err)});
}

fn handlePointerDown(view: Object, event: Object) !void {
    if (render_state) |*state| {
        const interaction = state.interaction orelse return;
        const window_point = try send0(Point, event, "locationInWindow");
        const local_point = try send2(Point, Point, Object, view, "convertPoint:fromView:", window_point, null);
        const bounds = try send0(Rect, view, "bounds");
        if (bounds.size.width <= 0 or bounds.size.height <= 0) return;
        const point = [2]f32{
            @floatCast(local_point.x / bounds.size.width * 2.0 - 1.0),
            @floatCast(local_point.y / bounds.size.height * 2.0 - 1.0),
        };
        const window_aspect: f32 = @floatCast(bounds.size.width / bounds.size.height);
        if (!interaction.pointer_down(interaction.context, point, window_aspect)) return;
        try replaceGeometry(state, interaction.geometry(interaction.context));
    }
}

fn replaceGeometry(state: *RenderState, geometry: Geometry) !void {
    const new_line_buffer = try createVertexBuffer(state.device, geometry.line_vertices);
    errdefer send0(void, new_line_buffer, "release") catch {};
    const new_fill_buffer = try createVertexBuffer(state.device, geometry.fill_vertices);
    errdefer send0(void, new_fill_buffer, "release") catch {};
    const equipment_source_ptr = @intFromPtr(geometry.equipment_vertices.ptr);
    const equipment_changed = equipment_source_ptr != state.equipment_source_ptr or
        geometry.equipment_vertices.len != state.equipment_count or
        geometry.equipment_revision != state.equipment_revision;
    var new_equipment_buffer = state.equipment_buffer;
    var new_acceleration_structure: Object = null;
    if (equipment_changed) {
        new_equipment_buffer = try createEquipmentVertexBuffer(state.device, geometry.equipment_vertices);
        errdefer send0(void, new_equipment_buffer, "release") catch {};
        if (state.ray_tracing != null) {
            new_acceleration_structure = try buildAccelerationStructure(
                state.device,
                state.command_queue,
                new_equipment_buffer,
                geometry.equipment_vertices.len,
            );
        }
    }

    try send0(void, state.line_buffer, "release");
    try send0(void, state.fill_buffer, "release");
    if (equipment_changed) try send0(void, state.equipment_buffer, "release");
    state.line_buffer = new_line_buffer;
    state.fill_buffer = new_fill_buffer;
    state.equipment_buffer = new_equipment_buffer;
    state.line_count = geometry.line_vertices.len;
    state.fill_count = geometry.fill_vertices.len;
    state.equipment_count = geometry.equipment_vertices.len;
    state.equipment_source_ptr = equipment_source_ptr;
    state.equipment_revision = geometry.equipment_revision;
    state.equipment_lights = geometry.equipment_lights;
    state.mode = geometry.mode;
    const current_camera = cameraAt(&state.camera_transition, CACurrentMediaTime());
    state.camera_transition = .{
        .from = current_camera,
        .to = geometry.equipment_camera,
        .started_at = CACurrentMediaTime(),
        .duration = if (cameraPoseEqual(current_camera, geometry.equipment_camera)) 0 else 2.8,
    };
    if (state.ray_tracing) |*ray_tracing| {
        if (new_acceleration_structure != null) {
            try send0(void, ray_tracing.acceleration_structure, "release");
            ray_tracing.acceleration_structure = new_acceleration_structure;
        }
        ray_tracing.sample_count = 0;
        ray_tracing.camera_was_moving = false;
    }
}

fn createVertexBuffer(device: Object, vertices: []const wireframe.Vertex) !Object {
    return send3(
        Object,
        *const anyopaque,
        usize,
        usize,
        device,
        "newBufferWithBytes:length:options:",
        @ptrCast(vertices.ptr),
        vertices.len * @sizeOf(wireframe.Vertex),
        0,
    );
}

fn createEquipmentVertexBuffer(device: Object, vertices: []const lighting_lab.Vertex) !Object {
    return send3(
        Object,
        *const anyopaque,
        usize,
        usize,
        device,
        "newBufferWithBytes:length:options:",
        @ptrCast(vertices.ptr),
        vertices.len * @sizeOf(lighting_lab.Vertex),
        0,
    );
}

fn draw(view: Object) !void {
    if (render_state) |*state| try drawState(view, state);
}

fn drawState(view: Object, state: *RenderState) !void {
    const descriptor = try send0(Object, view, "currentRenderPassDescriptor");
    if (descriptor == null) return;
    const drawable = try send0(Object, view, "currentDrawable");
    if (drawable == null) return;

    const command_buffer = try send0(Object, state.command_queue, "commandBuffer");
    const drawable_size = try send0(Size, view, "drawableSize");
    const comparison_gap = drawable_size.width * 0.012;
    const comparison_width = (drawable_size.width * 0.98 - comparison_gap) * 0.5;
    const three_d_viewport = Viewport{
        .origin_x = drawable_size.width * 0.01,
        .origin_y = drawable_size.height * 0.15,
        .width = comparison_width,
        .height = drawable_size.height * 0.77,
        .z_near = 0,
        .z_far = 1,
    };
    const layer_viewport = Viewport{
        .origin_x = three_d_viewport.origin_x + comparison_width + comparison_gap,
        .origin_y = three_d_viewport.origin_y,
        .width = comparison_width,
        .height = three_d_viewport.height,
        .z_near = 0,
        .z_far = 1,
    };
    const pedalboard_viewport = Viewport{
        .origin_x = drawable_size.width * 0.01,
        .origin_y = drawable_size.height * 0.08,
        .width = drawable_size.width * 0.98,
        .height = drawable_size.height * 0.80,
        .z_near = 0,
        .z_far = 1,
    };
    const lab_uniforms = lightingUniforms(@floatCast(three_d_viewport.width / three_d_viewport.height));
    const now = CACurrentMediaTime();
    const pedalboard_camera = cameraAt(&state.camera_transition, now);
    const pedalboard_uniforms = pedalboardUniforms(
        @floatCast(pedalboard_viewport.width / pedalboard_viewport.height),
        state.equipment_lights,
        pedalboard_camera,
    );

    switch (state.mode) {
        .wireframe => {},
        .lighting_lab => try drawShadowPass(
            command_buffer,
            state,
            &lab_uniforms,
            state.lighting_lab.vertex_buffer,
            state.lighting_lab.vertex_count,
        ),
        .pedalboard_3d => try drawShadowPass(
            command_buffer,
            state,
            &pedalboard_uniforms,
            state.equipment_buffer,
            state.equipment_count,
        ),
    }

    if (state.mode == .pedalboard_3d) {
        try encodeContinuousAo(command_buffer, state, pedalboard_camera, pedalboard_viewport, now);
    }

    const encoder = try send1(Object, Object, command_buffer, "renderCommandEncoderWithDescriptor:", descriptor);
    try send1(void, Object, encoder, "setRenderPipelineState:", state.pipeline);
    try send3(void, Object, usize, usize, encoder, "setVertexBuffer:offset:atIndex:", state.fill_buffer, 0, 0);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 3, 0, state.fill_count);

    switch (state.mode) {
        .wireframe => {},
        .lighting_lab => {
            try drawPbrPass(
                encoder,
                state,
                &lab_uniforms,
                three_d_viewport,
                state.lighting_lab.vertex_buffer,
                state.lighting_lab.vertex_count,
            );
            try drawLightingComparisonPass(encoder, state, &lab_uniforms, layer_viewport);
        },
        .pedalboard_3d => {
            try drawPbrPass(
                encoder,
                state,
                &pedalboard_uniforms,
                pedalboard_viewport,
                state.equipment_buffer,
                state.equipment_count,
            );
            try drawProgressiveAoComposite(encoder, state, pedalboard_viewport);
        },
    }

    try send1(void, Object, encoder, "setDepthStencilState:", null);
    try send1(void, Viewport, encoder, "setViewport:", .{
        .origin_x = 0,
        .origin_y = 0,
        .width = drawable_size.width,
        .height = drawable_size.height,
        .z_near = 0,
        .z_far = 1,
    });
    try send3(void, Object, usize, usize, encoder, "setVertexBuffer:offset:atIndex:", state.line_buffer, 0, 0);
    try send1(void, Object, encoder, "setRenderPipelineState:", state.pipeline);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 1, 0, state.line_count);
    try send0(void, encoder, "endEncoding");
    try send1(void, Object, command_buffer, "presentDrawable:", drawable);
    try send0(void, command_buffer, "commit");
}

fn encodeContinuousAo(
    command_buffer: Object,
    state: *RenderState,
    camera: pedalboard_3d.CameraPose,
    viewport: Viewport,
    now: f64,
) !void {
    const ray_tracing = if (state.ray_tracing) |*value| value else return;
    const transition_end = state.camera_transition.started_at + state.camera_transition.duration;
    const camera_is_moving = now < transition_end;
    if (camera_is_moving or ray_tracing.camera_was_moving) {
        ray_tracing.sample_count = 0;
    }
    ray_tracing.camera_was_moving = camera_is_moving;

    const texture_width: usize = @max(1, @as(usize, @intFromFloat(@floor(viewport.width * 0.5))));
    const texture_height: usize = @max(1, @as(usize, @intFromFloat(@floor(viewport.height * 0.5))));
    if (ray_tracing.accumulation_texture == null or
        ray_tracing.texture_width != texture_width or ray_tracing.texture_height != texture_height)
    {
        if (ray_tracing.accumulation_texture != null) try send0(void, ray_tracing.accumulation_texture, "release");
        const texture_descriptor = try send4(Object, usize, usize, usize, bool, try classNamed("MTLTextureDescriptor"), "texture2DDescriptorWithPixelFormat:width:height:mipmapped:", 55, texture_width, texture_height, false);
        try send1(void, usize, texture_descriptor, "setUsage:", 1 | 2);
        try send1(void, usize, texture_descriptor, "setStorageMode:", 2);
        ray_tracing.accumulation_texture = try send1(Object, Object, state.device, "newTextureWithDescriptor:", texture_descriptor);
        ray_tracing.texture_width = texture_width;
        ray_tracing.texture_height = texture_height;
        ray_tracing.sample_count = 0;
    }

    const uniforms = rayUniforms(
        camera,
        @floatCast(viewport.width / viewport.height),
        @min(ray_tracing.sample_count, progressive_ao_sample_limit - 1),
        ray_tracing.sequence_index,
        texture_width,
        texture_height,
    );
    const encoder = try send0(Object, command_buffer, "computeCommandEncoder");
    try send1(void, Object, encoder, "setComputePipelineState:", ray_tracing.compute_pipeline);
    try send3(void, Object, usize, usize, encoder, "setBuffer:offset:atIndex:", state.equipment_buffer, 0, 0);
    try send2(void, Object, usize, encoder, "setAccelerationStructure:atBufferIndex:", ray_tracing.acceleration_structure, 1);
    try send3(void, *const anyopaque, usize, usize, encoder, "setBytes:length:atIndex:", @ptrCast(&uniforms), @sizeOf(RayUniforms), 2);
    try send2(void, Object, usize, encoder, "setTexture:atIndex:", ray_tracing.accumulation_texture, 0);
    try send2(void, GridSize, GridSize, encoder, "dispatchThreads:threadsPerThreadgroup:", .{
        .width = texture_width,
        .height = texture_height,
        .depth = 1,
    }, .{ .width = 8, .height = 8, .depth = 1 });
    try send0(void, encoder, "endEncoding");
    ray_tracing.sample_count = @min(ray_tracing.sample_count + 1, progressive_ao_sample_limit);
    ray_tracing.sequence_index +%= 1;
}

fn rayUniforms(
    camera: pedalboard_3d.CameraPose,
    aspect: f32,
    sample_index: u32,
    sequence_index: u32,
    width: usize,
    height: usize,
) RayUniforms {
    const forward = normalized(.{
        camera.target[0] - camera.camera[0],
        camera.target[1] - camera.camera[1],
        camera.target[2] - camera.camera[2],
    });
    const right = normalized(cross(forward, .{ 0, 1, 0 }));
    const up = cross(right, forward);
    return .{
        .camera_fov = .{
            camera.camera[0],
            camera.camera[1],
            camera.camera[2],
            @tan(camera.field_of_view_degrees * std.math.pi / 360.0),
        },
        .forward_aspect = .{ forward[0], forward[1], forward[2], aspect },
        .right_min_distance = .{ right[0], right[1], right[2], 0.04 },
        .up_max_distance = .{ up[0], up[1], up[2], 1.35 },
        .sample_dimensions = .{ sample_index, @intCast(width), @intCast(height), sequence_index },
    };
}

fn drawProgressiveAoComposite(encoder: Object, state: *const RenderState, viewport: Viewport) !void {
    const ray_tracing = state.ray_tracing orelse return;
    if (ray_tracing.sample_count == 0 or ray_tracing.accumulation_texture == null) return;
    try send1(void, Object, encoder, "setDepthStencilState:", null);
    try send1(void, Object, encoder, "setRenderPipelineState:", ray_tracing.composite_pipeline);
    try send1(void, Viewport, encoder, "setViewport:", viewport);
    try send2(void, Object, usize, encoder, "setFragmentTexture:atIndex:", ray_tracing.accumulation_texture, 0);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 3, 0, 6);
}

fn drawShadowPass(
    command_buffer: Object,
    state: *const RenderState,
    uniforms: *const PbrUniforms,
    vertex_buffer: Object,
    vertex_count: usize,
) !void {
    const descriptor = try send0(Object, try classNamed("MTLRenderPassDescriptor"), "renderPassDescriptor");
    const depth_attachment = try send0(Object, descriptor, "depthAttachment");
    try send1(void, Object, depth_attachment, "setTexture:", state.lighting_lab.shadow_texture);
    try send1(void, usize, depth_attachment, "setLoadAction:", 2);
    try send1(void, usize, depth_attachment, "setStoreAction:", 1);
    try send1(void, f64, depth_attachment, "setClearDepth:", 1.0);

    const encoder = try send1(Object, Object, command_buffer, "renderCommandEncoderWithDescriptor:", descriptor);
    try send1(void, Object, encoder, "setRenderPipelineState:", state.lighting_lab.shadow_pipeline);
    try send1(void, Object, encoder, "setDepthStencilState:", state.lighting_lab.depth_state);
    try send1(void, Viewport, encoder, "setViewport:", .{
        .origin_x = 0,
        .origin_y = 0,
        .width = 1024,
        .height = 1024,
        .z_near = 0,
        .z_far = 1,
    });
    try send3(void, Object, usize, usize, encoder, "setVertexBuffer:offset:atIndex:", vertex_buffer, 0, 0);
    try send3(void, *const anyopaque, usize, usize, encoder, "setVertexBytes:length:atIndex:", @ptrCast(uniforms), @sizeOf(PbrUniforms), 1);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 3, 0, vertex_count);
    try send0(void, encoder, "endEncoding");
}

fn drawPbrPass(
    encoder: Object,
    state: *const RenderState,
    uniforms: *const PbrUniforms,
    viewport: Viewport,
    vertex_buffer: Object,
    vertex_count: usize,
) !void {
    try send1(void, Object, encoder, "setRenderPipelineState:", state.lighting_lab.pipeline);
    try send1(void, Object, encoder, "setDepthStencilState:", state.lighting_lab.depth_state);
    try send1(void, Viewport, encoder, "setViewport:", viewport);
    try send3(void, Object, usize, usize, encoder, "setVertexBuffer:offset:atIndex:", vertex_buffer, 0, 0);
    try send3(void, *const anyopaque, usize, usize, encoder, "setVertexBytes:length:atIndex:", @ptrCast(uniforms), @sizeOf(PbrUniforms), 1);
    try send3(void, *const anyopaque, usize, usize, encoder, "setFragmentBytes:length:atIndex:", @ptrCast(uniforms), @sizeOf(PbrUniforms), 1);
    try send2(void, Object, usize, encoder, "setFragmentTexture:atIndex:", state.lighting_lab.shadow_texture, 0);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 3, 0, vertex_count);
}

fn drawLightingComparisonPass(encoder: Object, state: *const RenderState, uniforms: *const PbrUniforms, viewport: Viewport) !void {
    try send1(void, Object, encoder, "setDepthStencilState:", null);
    try send1(void, Object, encoder, "setRenderPipelineState:", state.lighting_lab.comparison_pipeline);
    try send1(void, Viewport, encoder, "setViewport:", viewport);
    try send3(void, *const anyopaque, usize, usize, encoder, "setFragmentBytes:length:atIndex:", @ptrCast(uniforms), @sizeOf(PbrUniforms), 1);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 3, 0, 6);
}

fn lightingUniforms(aspect: f32) PbrUniforms {
    const time: f32 = @floatCast(@mod(CACurrentMediaTime(), 120.0));
    const orbit = time * std.math.tau / lighting_lab.studio_profile.orbit_seconds;
    const camera = [3]f32{ 0, 3.35, 5.85 };
    const target = [3]f32{ 0, 0.28, 0 };
    const light = [3]f32{ @cos(orbit) * 3.8, 3.7, @sin(orbit) * 3.8 + 0.8 };
    const view = lookAt(camera, target, .{ 0, 1, 0 });
    const projection = perspective(46.0 * std.math.pi / 180.0, aspect, 0.1, 30.0);
    const light_view = lookAt(light, target, .{ 0, 1, 0 });
    const light_projection = perspective(72.0 * std.math.pi / 180.0, 1.0, 0.2, 20.0);
    return .{
        .view_projection = multiplyMatrices(projection, view),
        .light_view_projection = multiplyMatrices(light_projection, light_view),
        .camera_position = .{ camera[0], camera[1], camera[2], 1 },
        .light_position = .{ light[0], light[1], light[2], 1 },
        .light_axis = .{ 0, 1, 0, lighting_lab.studio_profile.key_intensity },
        .strip_size_exposure = .{
            lighting_lab.studio_profile.strip_width,
            lighting_lab.studio_profile.strip_height,
            lighting_lab.studio_profile.exposure,
            lighting_lab.studio_profile.environment_strength,
        },
        .time_fill = .{ time, 0, 0, 0 },
    };
}

fn pedalboardUniforms(aspect: f32, lights: []const pedalboard_3d.EmissiveLight, camera_pose: pedalboard_3d.CameraPose) PbrUniforms {
    const profile = pedalboard_3d.studio_profile;
    const camera = camera_pose.camera;
    const target = camera_pose.target;
    const light = profile.key_position;
    const view = lookAt(camera, target, .{ 0, 1, 0 });
    const projection = perspective(camera_pose.field_of_view_degrees * std.math.pi / 180.0, aspect, 0.1, 40.0);
    const light_view = lookAt(light, target, .{ 0, 1, 0 });
    const light_projection = perspective(84.0 * std.math.pi / 180.0, 1.0, 0.2, 30.0);
    var uniforms = PbrUniforms{
        .view_projection = multiplyMatrices(projection, view),
        .light_view_projection = multiplyMatrices(light_projection, light_view),
        .camera_position = .{ camera[0], camera[1], camera[2], 1 },
        .light_position = .{ light[0], light[1], light[2], 1 },
        .light_axis = .{ 0, 1, 0, profile.key_intensity },
        .strip_size_exposure = .{
            profile.key_size[0],
            profile.key_size[1],
            profile.exposure,
            profile.environment_strength,
        },
        .time_fill = .{ 0, profile.fill_radiance[0], profile.fill_radiance[1], profile.fill_radiance[2] },
    };
    const light_count = @min(lights.len, pedalboard_3d.Mesh.max_emissive_lights);
    for (lights[0..light_count], 0..) |emissive_light, index| {
        uniforms.emissive_lights[index] = .{
            .position_radius = .{ emissive_light.position[0], emissive_light.position[1], emissive_light.position[2], emissive_light.radius },
            .color_intensity = .{ emissive_light.color[0], emissive_light.color[1], emissive_light.color[2], emissive_light.intensity },
            .direction_cone = .{ emissive_light.direction[0], emissive_light.direction[1], emissive_light.direction[2], emissive_light.cone_cosine },
        };
    }
    uniforms.emissive_light_count = @intCast(light_count);
    return uniforms;
}

fn cameraAt(transition: *const CameraTransition, now: f64) pedalboard_3d.CameraPose {
    if (transition.duration <= 0) return transition.to;
    const elapsed: f32 = @floatCast(now - transition.started_at);
    const linear = std.math.clamp(elapsed / transition.duration, 0, 1);
    const eased = linear * linear * linear * (linear * (linear * 6.0 - 15.0) + 10.0);
    return .{
        .camera = interpolate3(transition.from.camera, transition.to.camera, eased),
        .target = interpolate3(transition.from.target, transition.to.target, eased),
        .field_of_view_degrees = transition.from.field_of_view_degrees +
            (transition.to.field_of_view_degrees - transition.from.field_of_view_degrees) * eased,
    };
}

fn interpolate3(from: [3]f32, to: [3]f32, amount: f32) [3]f32 {
    return .{
        from[0] + (to[0] - from[0]) * amount,
        from[1] + (to[1] - from[1]) * amount,
        from[2] + (to[2] - from[2]) * amount,
    };
}

fn cameraPoseEqual(a: pedalboard_3d.CameraPose, b: pedalboard_3d.CameraPose) bool {
    const epsilon: f32 = 0.0001;
    for (a.camera, b.camera) |a_value, b_value| {
        if (@abs(a_value - b_value) > epsilon) return false;
    }
    for (a.target, b.target) |a_value, b_value| {
        if (@abs(a_value - b_value) > epsilon) return false;
    }
    return @abs(a.field_of_view_degrees - b.field_of_view_degrees) <= epsilon;
}

fn perspective(field_of_view: f32, aspect: f32, near: f32, far: f32) [16]f32 {
    const scale = 1.0 / @tan(field_of_view * 0.5);
    var result = [_]f32{0} ** 16;
    result[0] = scale / aspect;
    result[5] = scale;
    result[10] = far / (near - far);
    result[11] = -1;
    result[14] = far * near / (near - far);
    return result;
}

fn lookAt(eye: [3]f32, target: [3]f32, up: [3]f32) [16]f32 {
    const z = normalized(.{ eye[0] - target[0], eye[1] - target[1], eye[2] - target[2] });
    const x = normalized(cross(up, z));
    const y = cross(z, x);
    return .{
        x[0],         y[0],         z[0],         0,
        x[1],         y[1],         z[1],         0,
        x[2],         y[2],         z[2],         0,
        -dot(x, eye), -dot(y, eye), -dot(z, eye), 1,
    };
}

fn multiplyMatrices(a: [16]f32, b: [16]f32) [16]f32 {
    var result: [16]f32 = undefined;
    for (0..4) |column| {
        for (0..4) |row| {
            var value: f32 = 0;
            for (0..4) |index| value += a[index * 4 + row] * b[column * 4 + index];
            result[column * 4 + row] = value;
        }
    }
    return result;
}

fn normalized(value: [3]f32) [3]f32 {
    const length = @sqrt(dot(value, value));
    return .{ value[0] / length, value[1] / length, value[2] / length };
}

fn cross(a: [3]f32, b: [3]f32) [3]f32 {
    return .{ a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0] };
}

fn dot(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

fn classNamed(name: [*:0]const u8) !Object {
    return objc_getClass(name) orelse error.ObjectiveCClassMissing;
}

fn nsString(value: [*:0]const u8) !Object {
    return send1(Object, [*:0]const u8, try classNamed("NSString"), "stringWithUTF8String:", value);
}

fn send0(comptime Return: type, receiver: Object, selector_name: [*:0]const u8) !Return {
    const Function = *const fn (Object, Selector) callconv(.c) Return;
    const function: Function = @ptrCast(&objc_msgSend);
    const result = function(receiver, sel_registerName(selector_name));
    return requireResult(Return, result);
}

fn send1(comptime Return: type, comptime A: type, receiver: Object, selector_name: [*:0]const u8, a: A) !Return {
    const Function = *const fn (Object, Selector, A) callconv(.c) Return;
    const function: Function = @ptrCast(&objc_msgSend);
    const result = function(receiver, sel_registerName(selector_name), a);
    return requireResult(Return, result);
}

fn send2(comptime Return: type, comptime A: type, comptime B: type, receiver: Object, selector_name: [*:0]const u8, a: A, b: B) !Return {
    const Function = *const fn (Object, Selector, A, B) callconv(.c) Return;
    const function: Function = @ptrCast(&objc_msgSend);
    const result = function(receiver, sel_registerName(selector_name), a, b);
    return requireResult(Return, result);
}

fn send3(comptime Return: type, comptime A: type, comptime B: type, comptime C: type, receiver: Object, selector_name: [*:0]const u8, a: A, b: B, c: C) !Return {
    const Function = *const fn (Object, Selector, A, B, C) callconv(.c) Return;
    const function: Function = @ptrCast(&objc_msgSend);
    const result = function(receiver, sel_registerName(selector_name), a, b, c);
    return requireResult(Return, result);
}

fn send4(comptime Return: type, comptime A: type, comptime B: type, comptime C: type, comptime D: type, receiver: Object, selector_name: [*:0]const u8, a: A, b: B, c: C, d: D) !Return {
    const Function = *const fn (Object, Selector, A, B, C, D) callconv(.c) Return;
    const function: Function = @ptrCast(&objc_msgSend);
    const result = function(receiver, sel_registerName(selector_name), a, b, c, d);
    return requireResult(Return, result);
}

fn requireResult(comptime Return: type, result: Return) !Return {
    if (Return == Object and result == null) return error.ObjectiveCMessageReturnedNil;
    return result;
}
