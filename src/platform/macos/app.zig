const std = @import("std");
const wireframe = @import("robine").ui.wireframe;
const lighting_lab = @import("robine").ui.lighting_lab;

const Object = ?*anyopaque;
const Selector = *anyopaque;
const Class = *anyopaque;

const Point = extern struct { x: f64, y: f64 };
const Size = extern struct { width: f64, height: f64 };
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
    mode: ContentMode = .wireframe,
    interaction: ?Interaction = null,
};

pub const Geometry = struct {
    line_vertices: []const wireframe.Vertex,
    fill_vertices: []const wireframe.Vertex,
    mode: ContentMode = .wireframe,
};

pub const Interaction = struct {
    context: *anyopaque,
    pointer_down: *const fn (context: *anyopaque, point: [2]f32) bool,
    geometry: *const fn (context: *anyopaque) Geometry,
};

const RenderState = struct {
    device: Object,
    command_queue: Object,
    pipeline: Object,
    line_buffer: Object,
    fill_buffer: Object,
    line_count: usize,
    fill_count: usize,
    mode: ContentMode,
    lighting_lab: LightingLabRenderState,
    interaction: ?Interaction,
};

const LightingLabRenderState = struct {
    pipeline: Object,
    shadow_pipeline: Object,
    depth_state: Object,
    vertex_buffer: Object,
    vertex_count: usize,
    shadow_texture: Object,
};

const PbrUniforms = extern struct {
    view_projection: [16]f32,
    light_view_projection: [16]f32,
    camera_position: [4]f32,
    light_position: [4]f32,
    light_axis: [4]f32,
    strip_size_exposure: [4]f32,
    time: f32,
    padding: [3]f32 = .{ 0, 0, 0 },
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
    \\    float time;
    \\    float3 padding;
    \\};
    \\
    \\struct PbrRasterData {
    \\    float4 position [[position]];
    \\    float3 world_position;
    \\    float3 normal;
    \\    float3 base_color;
    \\    float2 material;
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
    \\    out.material = source_vertex.material.xy;
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
    \\        float3 radiance = float3(1.0, 0.78, 0.54) * max(edge, 0.15) * 34.0 /
    \\            (distance_squared * float(sample_count));
    \\        direct += (diffuse + specular) * radiance * ndotl;
    \\    }
    \\    float3 reflection = reflect(-v, n);
    \\    float horizon = clamp(reflection.y * 0.5 + 0.5, 0.0, 1.0);
    \\    float3 environment = mix(float3(0.006, 0.010, 0.014), float3(0.10, 0.16, 0.18), horizon);
    \\    float3 to_strip = normalize(uniforms.light_position.xyz - in.world_position);
    \\    float strip_reflection = pow(max(dot(reflection, to_strip), 0.0), mix(180.0, 12.0, roughness));
    \\    environment += float3(1.0, 0.72, 0.46) * strip_reflection * 2.8;
    \\    float3 fixed_strip_direction = normalize(float3(-0.72, 0.40, 0.56));
    \\    float fixed_strip = pow(max(dot(reflection, fixed_strip_direction), 0.0), mix(120.0, 10.0, roughness));
    \\    environment += float3(0.30, 0.58, 0.70) * fixed_strip * 1.6;
    \\    float3 ambient_fresnel = fresnel_schlick(max(dot(n, v), 0.0), f0);
    \\    float3 ambient = environment * (ambient_fresnel + in.base_color * (1.0 - metallic) * 0.22) *
    \\        uniforms.strip_size_exposure.w;
    \\    float3 color = ambient + direct * mix(0.42, 1.0, visibility);
    \\    color = aces_tonemap(color * uniforms.strip_size_exposure.z);
    \\    color = pow(color, float3(1.0 / 2.2));
    \\    return float4(color, 1.0);
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
    const library = try createLibrary(device);
    const pipeline = try createWireframePipeline(device, library);
    const lab_render_state = try createLightingLabRenderState(device, library);
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
    render_state = .{
        .device = device,
        .command_queue = command_queue,
        .pipeline = pipeline,
        .line_buffer = line_buffer,
        .fill_buffer = fill_buffer,
        .line_count = options.line_vertices.len,
        .fill_count = options.fill_vertices.len,
        .mode = options.mode,
        .lighting_lab = lab_render_state,
        .interaction = options.interaction,
    };
    defer render_state = null;

    const frame = Rect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = @floatFromInt(options.width), .height = @floatFromInt(options.height) },
    };

    const view_class = try makeViewClass();
    const view_alloc = try send0(Object, view_class, "alloc");
    const view = try send2(Object, Rect, Object, view_alloc, "initWithFrame:device:", frame, device);
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

fn createLibrary(device: Object) !Object {
    var compile_error: Object = null;
    const Function = *const fn (Object, Selector, Object, Object, *Object) callconv(.c) Object;
    const function: Function = @ptrCast(&objc_msgSend);
    const library = function(device, sel_registerName("newLibraryWithSource:options:error:"), try nsString(shader_source), null, &compile_error);
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

fn createWireframePipeline(device: Object, library: Object) !Object {
    const vertex_function = try send1(Object, Object, library, "newFunctionWithName:", try nsString("vertex_main"));
    const fragment_function = try send1(Object, Object, library, "newFunctionWithName:", try nsString("fragment_main"));

    const descriptor_alloc = try send0(Object, try classNamed("MTLRenderPipelineDescriptor"), "alloc");
    const descriptor = try send0(Object, descriptor_alloc, "init");
    try send1(void, Object, descriptor, "setVertexFunction:", vertex_function);
    try send1(void, Object, descriptor, "setFragmentFunction:", fragment_function);

    const attachments = try send0(Object, descriptor, "colorAttachments");
    const color_attachment = try send1(Object, usize, attachments, "objectAtIndexedSubscript:", 0);
    try send1(void, usize, color_attachment, "setPixelFormat:", 80);
    try send1(void, usize, descriptor, "setDepthAttachmentPixelFormat:", 252);

    return send2(Object, Object, Object, device, "newRenderPipelineStateWithDescriptor:error:", descriptor, null);
}

fn createLightingLabRenderState(device: Object, library: Object) !LightingLabRenderState {
    const pbr_vertex = try send1(Object, Object, library, "newFunctionWithName:", try nsString("pbr_vertex"));
    const pbr_fragment = try send1(Object, Object, library, "newFunctionWithName:", try nsString("pbr_fragment"));
    const pbr_descriptor = try send0(Object, try send0(Object, try classNamed("MTLRenderPipelineDescriptor"), "alloc"), "init");
    try send1(void, Object, pbr_descriptor, "setVertexFunction:", pbr_vertex);
    try send1(void, Object, pbr_descriptor, "setFragmentFunction:", pbr_fragment);
    const pbr_attachments = try send0(Object, pbr_descriptor, "colorAttachments");
    const pbr_color = try send1(Object, usize, pbr_attachments, "objectAtIndexedSubscript:", 0);
    try send1(void, usize, pbr_color, "setPixelFormat:", 80);
    try send1(void, usize, pbr_descriptor, "setDepthAttachmentPixelFormat:", 252);
    const pbr_pipeline = try send2(Object, Object, Object, device, "newRenderPipelineStateWithDescriptor:error:", pbr_descriptor, null);

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
        .shadow_pipeline = shadow_pipeline,
        .depth_state = depth_state,
        .vertex_buffer = vertex_buffer,
        .vertex_count = mesh.items().len,
        .shadow_texture = try createShadowTexture(device),
    };
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
        if (!interaction.pointer_down(interaction.context, point)) return;
        try replaceGeometry(state, interaction.geometry(interaction.context));
    }
}

fn replaceGeometry(state: *RenderState, geometry: Geometry) !void {
    const new_line_buffer = try createVertexBuffer(state.device, geometry.line_vertices);
    errdefer send0(void, new_line_buffer, "release") catch {};
    const new_fill_buffer = try createVertexBuffer(state.device, geometry.fill_vertices);

    try send0(void, state.line_buffer, "release");
    try send0(void, state.fill_buffer, "release");
    state.line_buffer = new_line_buffer;
    state.fill_buffer = new_fill_buffer;
    state.line_count = geometry.line_vertices.len;
    state.fill_count = geometry.fill_vertices.len;
    state.mode = geometry.mode;
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

fn draw(view: Object) !void {
    const state = render_state orelse return;
    const descriptor = try send0(Object, view, "currentRenderPassDescriptor");
    if (descriptor == null) return;
    const drawable = try send0(Object, view, "currentDrawable");
    if (drawable == null) return;

    const command_buffer = try send0(Object, state.command_queue, "commandBuffer");
    const drawable_size = try send0(Size, view, "drawableSize");
    const lab_viewport = Viewport{
        .origin_x = drawable_size.width * 0.01,
        .origin_y = drawable_size.height * 0.15,
        .width = drawable_size.width * 0.74,
        .height = drawable_size.height * 0.77,
        .z_near = 0,
        .z_far = 1,
    };
    const uniforms = lightingUniforms(@floatCast(lab_viewport.width / lab_viewport.height));

    if (state.mode == .lighting_lab) try drawShadowPass(command_buffer, &state, &uniforms);

    const encoder = try send1(Object, Object, command_buffer, "renderCommandEncoderWithDescriptor:", descriptor);
    try send1(void, Object, encoder, "setRenderPipelineState:", state.pipeline);
    try send3(void, Object, usize, usize, encoder, "setVertexBuffer:offset:atIndex:", state.fill_buffer, 0, 0);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 3, 0, state.fill_count);

    if (state.mode == .lighting_lab) try drawLightingLabPass(encoder, &state, &uniforms, lab_viewport);

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

fn drawShadowPass(command_buffer: Object, state: *const RenderState, uniforms: *const PbrUniforms) !void {
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
    try send3(void, Object, usize, usize, encoder, "setVertexBuffer:offset:atIndex:", state.lighting_lab.vertex_buffer, 0, 0);
    try send3(void, *const anyopaque, usize, usize, encoder, "setVertexBytes:length:atIndex:", @ptrCast(uniforms), @sizeOf(PbrUniforms), 1);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 3, 0, state.lighting_lab.vertex_count);
    try send0(void, encoder, "endEncoding");
}

fn drawLightingLabPass(encoder: Object, state: *const RenderState, uniforms: *const PbrUniforms, viewport: Viewport) !void {
    try send1(void, Object, encoder, "setRenderPipelineState:", state.lighting_lab.pipeline);
    try send1(void, Object, encoder, "setDepthStencilState:", state.lighting_lab.depth_state);
    try send1(void, Viewport, encoder, "setViewport:", viewport);
    try send3(void, Object, usize, usize, encoder, "setVertexBuffer:offset:atIndex:", state.lighting_lab.vertex_buffer, 0, 0);
    try send3(void, *const anyopaque, usize, usize, encoder, "setVertexBytes:length:atIndex:", @ptrCast(uniforms), @sizeOf(PbrUniforms), 1);
    try send3(void, *const anyopaque, usize, usize, encoder, "setFragmentBytes:length:atIndex:", @ptrCast(uniforms), @sizeOf(PbrUniforms), 1);
    try send2(void, Object, usize, encoder, "setFragmentTexture:atIndex:", state.lighting_lab.shadow_texture, 0);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 3, 0, state.lighting_lab.vertex_count);
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
        .light_axis = .{ 0, 1, 0, 0 },
        .strip_size_exposure = .{
            lighting_lab.studio_profile.strip_width,
            lighting_lab.studio_profile.strip_height,
            lighting_lab.studio_profile.exposure,
            lighting_lab.studio_profile.environment_strength,
        },
        .time = time,
    };
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
