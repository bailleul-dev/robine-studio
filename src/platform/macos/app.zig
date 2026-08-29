const std = @import("std");
const wireframe = @import("robine").ui.wireframe;

const Object = ?*anyopaque;
const Selector = *anyopaque;
const Class = *anyopaque;

const Point = extern struct { x: f64, y: f64 };
const Size = extern struct { width: f64, height: f64 };
const Rect = extern struct { origin: Point, size: Size };
const ClearColor = extern struct { red: f64, green: f64, blue: f64, alpha: f64 };

extern fn objc_getClass(name: [*:0]const u8) Object;
extern fn sel_registerName(name: [*:0]const u8) Selector;
extern fn objc_allocateClassPair(superclass: Class, name: [*:0]const u8, extra_bytes: usize) Object;
extern fn objc_registerClassPair(cls: Class) void;
extern fn class_addMethod(cls: Class, name: Selector, implementation: *const anyopaque, types: [*:0]const u8) bool;
extern fn objc_msgSend() callconv(.c) void;
extern fn MTLCreateSystemDefaultDevice() Object;

pub const Options = struct {
    title: [*:0]const u8,
    width: u32,
    height: u32,
    line_vertices: []const wireframe.Vertex,
    fill_vertices: []const wireframe.Vertex,
};

const RenderState = struct {
    command_queue: Object,
    pipeline: Object,
    line_buffer: Object,
    fill_buffer: Object,
    line_count: usize,
    fill_count: usize,
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
    const pipeline = try createPipeline(device);
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
        .command_queue = command_queue,
        .pipeline = pipeline,
        .line_buffer = line_buffer,
        .fill_buffer = fill_buffer,
        .line_count = options.line_vertices.len,
        .fill_count = options.fill_vertices.len,
    };
    defer render_state = null;

    const frame = Rect{
        .origin = .{ .x = 0, .y = 0 },
        .size = .{ .width = @floatFromInt(options.width), .height = @floatFromInt(options.height) },
    };

    const view_alloc = try send0(Object, try classNamed("MTKView"), "alloc");
    const view = try send2(Object, Rect, Object, view_alloc, "initWithFrame:device:", frame, device);
    try send1(void, usize, view, "setColorPixelFormat:", 80);
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

fn createPipeline(device: Object) !Object {
    const source = try nsString(shader_source);
    const library = try send3(Object, Object, Object, Object, device, "newLibraryWithSource:options:error:", source, null, null);
    const vertex_function = try send1(Object, Object, library, "newFunctionWithName:", try nsString("vertex_main"));
    const fragment_function = try send1(Object, Object, library, "newFunctionWithName:", try nsString("fragment_main"));

    const descriptor_alloc = try send0(Object, try classNamed("MTLRenderPipelineDescriptor"), "alloc");
    const descriptor = try send0(Object, descriptor_alloc, "init");
    try send1(void, Object, descriptor, "setVertexFunction:", vertex_function);
    try send1(void, Object, descriptor, "setFragmentFunction:", fragment_function);

    const attachments = try send0(Object, descriptor, "colorAttachments");
    const color_attachment = try send1(Object, usize, attachments, "objectAtIndexedSubscript:", 0);
    try send1(void, usize, color_attachment, "setPixelFormat:", 80);

    return send2(Object, Object, Object, device, "newRenderPipelineStateWithDescriptor:error:", descriptor, null);
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

fn drawInMTKView(_: Object, _: Selector, view: Object) callconv(.c) void {
    draw(view) catch |err| std.log.err("Metal frame failed: {s}", .{@errorName(err)});
}

fn drawableSizeChanged(_: Object, _: Selector, _: Object, _: Size) callconv(.c) void {}

fn terminateAfterLastWindow(_: Object, _: Selector, _: Object) callconv(.c) i8 {
    return 1;
}

fn draw(view: Object) !void {
    const state = render_state orelse return;
    const descriptor = try send0(Object, view, "currentRenderPassDescriptor");
    if (descriptor == null) return;
    const drawable = try send0(Object, view, "currentDrawable");
    if (drawable == null) return;

    const command_buffer = try send0(Object, state.command_queue, "commandBuffer");
    const encoder = try send1(Object, Object, command_buffer, "renderCommandEncoderWithDescriptor:", descriptor);
    try send1(void, Object, encoder, "setRenderPipelineState:", state.pipeline);
    try send3(void, Object, usize, usize, encoder, "setVertexBuffer:offset:atIndex:", state.fill_buffer, 0, 0);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 3, 0, state.fill_count);
    try send3(void, Object, usize, usize, encoder, "setVertexBuffer:offset:atIndex:", state.line_buffer, 0, 0);
    try send3(void, usize, usize, usize, encoder, "drawPrimitives:vertexStart:vertexCount:", 1, 0, state.line_count);
    try send0(void, encoder, "endEncoding");
    try send1(void, Object, command_buffer, "presentDrawable:", drawable);
    try send0(void, command_buffer, "commit");
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
