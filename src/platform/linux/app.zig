const std = @import("std");
const wireframe = @import("robine").ui.wireframe;
const lighting_lab = @import("robine").ui.lighting_lab;
const pedalboard_3d = @import("robine").ui.pedalboard_3d;
const pbr = @import("pbr.zig");

const c = @cImport({
    @cInclude("X11/Xlib.h");
    @cInclude("X11/Xatom.h");
    @cInclude("X11/keysym.h");
    @cInclude("GL/gl.h");
    @cInclude("GL/glx.h");
    @cInclude("time.h");
    @cInclude("unistd.h");
});

pub const ContentMode = enum { wireframe, pedalboard_3d, lighting_lab };

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

const equipment_camera_transition_seconds: f32 = 1.4;

pub fn run(options: Options) !void {
    const display = c.XOpenDisplay(null) orelse return error.X11DisplayUnavailable;
    defer _ = c.XCloseDisplay(display);

    const screen = c.XDefaultScreen(display);
    var preferred_visual_attributes = [_]c_int{
        c.GLX_RGBA,
        c.GLX_DOUBLEBUFFER,
        c.GLX_DEPTH_SIZE,
        24,
        c.GLX_SAMPLE_BUFFERS,
        1,
        c.GLX_SAMPLES,
        4,
        0,
    };
    var fallback_visual_attributes = [_]c_int{
        c.GLX_RGBA,
        c.GLX_DOUBLEBUFFER,
        c.GLX_DEPTH_SIZE,
        24,
        0,
    };
    const visual = c.glXChooseVisual(display, screen, &preferred_visual_attributes) orelse
        c.glXChooseVisual(display, screen, &fallback_visual_attributes) orelse
        return error.OpenGLVisualUnavailable;
    defer _ = c.XFree(visual);

    const root = c.XRootWindow(display, screen);
    const colormap = c.XCreateColormap(display, root, visual.*.visual, c.AllocNone);
    defer _ = c.XFreeColormap(display, colormap);
    var attributes: c.XSetWindowAttributes = std.mem.zeroes(c.XSetWindowAttributes);
    attributes.colormap = colormap;
    attributes.event_mask = c.ExposureMask | c.StructureNotifyMask | c.ButtonPressMask | c.KeyPressMask;
    const window = c.XCreateWindow(
        display,
        root,
        0,
        0,
        options.width,
        options.height,
        0,
        visual.*.depth,
        c.InputOutput,
        visual.*.visual,
        c.CWColormap | c.CWEventMask,
        &attributes,
    );
    if (window == 0) return error.X11WindowCreationFailed;
    defer _ = c.XDestroyWindow(display, window);

    _ = c.XStoreName(display, window, options.title);
    const net_wm_name = c.XInternAtom(display, "_NET_WM_NAME", c.False);
    const utf8_string = c.XInternAtom(display, "UTF8_STRING", c.False);
    const title = std.mem.span(options.title);
    _ = c.XChangeProperty(display, window, net_wm_name, utf8_string, 8, c.PropModeReplace, title.ptr, @intCast(title.len));
    var delete_atom = c.XInternAtom(display, "WM_DELETE_WINDOW", c.False);
    _ = c.XSetWMProtocols(display, window, &delete_atom, 1);
    _ = c.XMapWindow(display, window);

    const context = c.glXCreateContext(display, visual, null, c.True) orelse
        return error.OpenGLContextUnavailable;
    defer c.glXDestroyContext(display, context);
    if (c.glXMakeCurrent(display, window, context) == 0) return error.OpenGLContextActivationFailed;
    defer _ = c.glXMakeCurrent(display, 0, null);

    if (c.glGetString(c.GL_RENDERER)) |renderer| {
        std.log.info("Linux OpenGL renderer: {s}", .{std.mem.span(renderer)});
    }

    var pbr_renderer: ?pbr.Renderer = pbr.Renderer.init() catch |err| fallback: {
        std.log.warn("OpenGL PBR unavailable; using the legacy lighting path: {s}", .{@errorName(err)});
        break :fallback null;
    };
    defer if (pbr_renderer) |*renderer| renderer.deinit();
    if (pbr_renderer != null) {
        var samples: c.GLint = 0;
        c.glGetIntegerv(c.GL_SAMPLES, &samples);
        std.log.info("Linux PBR enabled: GGX, shadows, emissive lights, ACES, textured surfaces, {d}x MSAA", .{samples});
    }

    c.glClearColor(0.025, 0.038, 0.036, 1.0);
    c.glEnable(c.GL_DEPTH_TEST);
    c.glEnable(c.GL_NORMALIZE);
    c.glEnable(c.GL_MULTISAMPLE);

    var width: u32 = options.width;
    var height: u32 = options.height;
    var geometry: Geometry = .{
        .line_vertices = options.line_vertices,
        .fill_vertices = options.fill_vertices,
        .equipment_vertices = options.equipment_vertices,
        .equipment_lights = options.equipment_lights,
        .equipment_revision = options.equipment_revision,
        .equipment_camera = options.equipment_camera,
        .mode = options.mode,
    };
    var camera_transition = CameraTransition{
        .from = options.equipment_camera,
        .to = options.equipment_camera,
        .started_at = monotonicSeconds(),
        .duration = 0,
    };
    var running = true;
    while (running) {
        while (c.XPending(display) > 0) {
            var event: c.XEvent = undefined;
            _ = c.XNextEvent(display, &event);
            switch (event.type) {
                c.ConfigureNotify => {
                    width = @intCast(@max(event.xconfigure.width, 1));
                    height = @intCast(@max(event.xconfigure.height, 1));
                },
                c.ButtonPress => if (event.xbutton.button == c.Button1) {
                    if (options.interaction) |interaction| {
                        const point = [2]f32{
                            @as(f32, @floatFromInt(event.xbutton.x)) / @as(f32, @floatFromInt(width)) * 2.0 - 1.0,
                            1.0 - @as(f32, @floatFromInt(event.xbutton.y)) / @as(f32, @floatFromInt(height)) * 2.0,
                        };
                        const aspect = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height));
                        if (interaction.pointer_down(interaction.context, point, aspect)) {
                            const now = monotonicSeconds();
                            const current_camera = cameraAt(&camera_transition, now);
                            geometry = interaction.geometry(interaction.context);
                            camera_transition = .{
                                .from = current_camera,
                                .to = geometry.equipment_camera,
                                .started_at = now,
                                .duration = if (cameraPoseEqual(current_camera, geometry.equipment_camera))
                                    0
                                else
                                    equipment_camera_transition_seconds,
                            };
                        }
                    }
                },
                c.KeyPress => if (c.XLookupKeysym(&event.xkey, 0) == c.XK_Escape) {
                    running = false;
                },
                c.ClientMessage => if (@as(c.Atom, @intCast(event.xclient.data.l[0])) == delete_atom) {
                    running = false;
                },
                c.DestroyNotify => running = false,
                else => {},
            }
        }

        draw(
            if (pbr_renderer) |*renderer| renderer else null,
            geometry,
            cameraAt(&camera_transition, monotonicSeconds()),
            width,
            height,
        );
        c.glXSwapBuffers(display, window);
        _ = c.usleep(16_000);
    }
}

fn draw(renderer: ?*const pbr.Renderer, geometry: Geometry, camera: pedalboard_3d.CameraPose, width: u32, height: u32) void {
    c.glViewport(0, 0, @intCast(width), @intCast(height));
    c.glClear(c.GL_COLOR_BUFFER_BIT | c.GL_DEPTH_BUFFER_BIT);
    switch (geometry.mode) {
        .wireframe => drawWireframe(geometry),
        .pedalboard_3d => if (renderer) |active_renderer|
            active_renderer.draw(.{
                .vertices = geometry.equipment_vertices,
                .lights = geometry.equipment_lights,
                .camera = camera,
                .key_position = pedalboard_3d.studio_profile.key_position,
                .key_size = pedalboard_3d.studio_profile.key_size,
                .key_intensity = pedalboard_3d.studio_profile.key_intensity,
                .exposure = pedalboard_3d.studio_profile.exposure,
                .environment_strength = pedalboard_3d.studio_profile.environment_strength,
                .fill_radiance = pedalboard_3d.studio_profile.fill_radiance,
            }, width, height)
        else
            drawEquipment(geometry.equipment_vertices, camera, width, height),
        .lighting_lab => drawLightingLab(geometry.equipment_vertices, width, height),
    }
}

fn drawWireframe(geometry: Geometry) void {
    c.glDisable(c.GL_LIGHTING);
    c.glDisable(c.GL_DEPTH_TEST);
    c.glMatrixMode(c.GL_PROJECTION);
    c.glLoadIdentity();
    c.glMatrixMode(c.GL_MODELVIEW);
    c.glLoadIdentity();

    c.glBegin(c.GL_TRIANGLES);
    for (geometry.fill_vertices) |vertex| {
        c.glColor4fv(&vertex.color);
        c.glVertex4fv(&vertex.position);
    }
    c.glEnd();
    c.glLineWidth(1.25);
    c.glBegin(c.GL_LINES);
    for (geometry.line_vertices) |vertex| {
        c.glColor4fv(&vertex.color);
        c.glVertex4fv(&vertex.position);
    }
    c.glEnd();
}

fn drawEquipment(vertices: []const lighting_lab.Vertex, camera: pedalboard_3d.CameraPose, width: u32, height: u32) void {
    const aspect = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(height));
    setCamera(camera, aspect);
    drawLitTriangles(vertices, pedalboard_3d.studio_profile.key_position);
}

fn drawLightingLab(vertices: []const lighting_lab.Vertex, width: u32, height: u32) void {
    const camera: pedalboard_3d.CameraPose = .{
        .camera = .{ 0, 3.35, 5.85 },
        .target = .{ 0, 0.28, 0 },
        .field_of_view_degrees = 46,
    };
    const aspect = @as(f64, @floatFromInt(width)) / @as(f64, @floatFromInt(height));
    setCamera(camera, aspect);
    drawLitTriangles(vertices, .{ 3.8, 3.7, 0.8 });
}

fn setCamera(camera: pedalboard_3d.CameraPose, aspect: f64) void {
    const near: f64 = 0.1;
    const top = near * @tan(@as(f64, camera.field_of_view_degrees) * std.math.pi / 360.0);
    c.glMatrixMode(c.GL_PROJECTION);
    c.glLoadIdentity();
    c.glFrustum(-top * aspect, top * aspect, -top, top, near, 40.0);
    c.glMatrixMode(c.GL_MODELVIEW);
    const view = lookAt(camera.camera, camera.target, .{ 0, 1, 0 });
    c.glLoadMatrixf(&view);
}

fn drawLitTriangles(vertices: []const lighting_lab.Vertex, light_position: [3]f32) void {
    c.glEnable(c.GL_DEPTH_TEST);
    c.glEnable(c.GL_LIGHTING);
    c.glEnable(c.GL_LIGHT0);
    c.glEnable(c.GL_COLOR_MATERIAL);
    c.glColorMaterial(c.GL_FRONT_AND_BACK, c.GL_AMBIENT_AND_DIFFUSE);
    const ambient = [4]f32{ 0.20, 0.24, 0.28, 1.0 };
    const diffuse = [4]f32{ 1.0, 0.93, 0.82, 1.0 };
    const position = [4]f32{ light_position[0], light_position[1], light_position[2], 1.0 };
    c.glLightfv(c.GL_LIGHT0, c.GL_AMBIENT, &ambient);
    c.glLightfv(c.GL_LIGHT0, c.GL_DIFFUSE, &diffuse);
    c.glLightfv(c.GL_LIGHT0, c.GL_POSITION, &position);
    c.glBegin(c.GL_TRIANGLES);
    for (vertices) |vertex| {
        const glow = 1.0 + @min(vertex.material[2], 4.0) * 0.35;
        const color = [4]f32{
            @min(vertex.base_color[0] * glow, 1.0),
            @min(vertex.base_color[1] * glow, 1.0),
            @min(vertex.base_color[2] * glow, 1.0),
            vertex.base_color[3],
        };
        c.glColor4fv(&color);
        c.glNormal3fv(&vertex.normal);
        c.glVertex4fv(&vertex.position);
    }
    c.glEnd();
    c.glDisable(c.GL_LIGHTING);
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

fn monotonicSeconds() f64 {
    var value: c.timespec = undefined;
    if (c.clock_gettime(c.CLOCK_MONOTONIC, &value) != 0) return 0;
    return @as(f64, @floatFromInt(value.tv_sec)) + @as(f64, @floatFromInt(value.tv_nsec)) / 1_000_000_000.0;
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
