const std = @import("std");
const demo = @import("../model/demo.zig");

pub const Color = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32 = 1,
};

pub const Vertex = extern struct {
    position: [4]f32,
    color: [4]f32,
};

pub const ViewState = enum {
    rig,
    amplifier,
    lighting_lab,
};

pub const Action = enum {
    show_rig,
    show_amplifier,
    show_lighting_lab,
};

pub const HitRegion = struct {
    left: f32,
    bottom: f32,
    right: f32,
    top: f32,
    action: Action,

    fn contains(self: HitRegion, point: [2]f32) bool {
        return point[0] >= self.left and point[0] <= self.right and point[1] >= self.bottom and point[1] <= self.top;
    }
};

pub const Scene = struct {
    pub const max_line_vertices = 12_000;
    pub const max_fill_vertices = 12_000;
    pub const max_hit_regions = 32;

    line_vertices: [max_line_vertices]Vertex = undefined,
    line_len: usize = 0,
    fill_vertices: [max_fill_vertices]Vertex = undefined,
    fill_len: usize = 0,
    hit_regions: [max_hit_regions]HitRegion = undefined,
    hit_len: usize = 0,

    pub fn lines(self: *const Scene) []const Vertex {
        return self.line_vertices[0..self.line_len];
    }

    pub fn fills(self: *const Scene) []const Vertex {
        return self.fill_vertices[0..self.fill_len];
    }

    pub fn hits(self: *const Scene) []const HitRegion {
        return self.hit_regions[0..self.hit_len];
    }

    pub fn actionAt(self: *const Scene, point: [2]f32) ?Action {
        var index = self.hit_len;
        while (index > 0) {
            index -= 1;
            if (self.hit_regions[index].contains(point)) return self.hit_regions[index].action;
        }
        return null;
    }

    fn line(self: *Scene, from: [2]f32, to: [2]f32, color: Color) !void {
        if (self.line_len + 2 > self.line_vertices.len) return error.SceneCapacityExceeded;
        self.line_vertices[self.line_len] = vertex(from, color);
        self.line_vertices[self.line_len + 1] = vertex(to, color);
        self.line_len += 2;
    }

    fn rectangle(self: *Scene, bounds: Bounds, color: Color) !void {
        try self.line(.{ bounds.left, bounds.bottom }, .{ bounds.right(), bounds.bottom }, color);
        try self.line(.{ bounds.right(), bounds.bottom }, .{ bounds.right(), bounds.top() }, color);
        try self.line(.{ bounds.right(), bounds.top() }, .{ bounds.left, bounds.top() }, color);
        try self.line(.{ bounds.left, bounds.top() }, .{ bounds.left, bounds.bottom }, color);
    }

    fn fillRectangle(self: *Scene, bounds: Bounds, color: Color) !void {
        try self.triangle(
            .{ bounds.left, bounds.bottom },
            .{ bounds.right(), bounds.bottom },
            .{ bounds.right(), bounds.top() },
            color,
        );
        try self.triangle(
            .{ bounds.left, bounds.bottom },
            .{ bounds.right(), bounds.top() },
            .{ bounds.left, bounds.top() },
            color,
        );
    }

    fn gradientRectangle(self: *Scene, bounds: Bounds, bottom_color: Color, top_color: Color) !void {
        if (self.fill_len + 6 > self.fill_vertices.len) return error.SceneCapacityExceeded;
        const bottom_left = vertex(.{ bounds.left, bounds.bottom }, bottom_color);
        const bottom_right = vertex(.{ bounds.right(), bounds.bottom }, bottom_color);
        const top_left = vertex(.{ bounds.left, bounds.top() }, top_color);
        const top_right = vertex(.{ bounds.right(), bounds.top() }, top_color);
        self.fill_vertices[self.fill_len] = bottom_left;
        self.fill_vertices[self.fill_len + 1] = bottom_right;
        self.fill_vertices[self.fill_len + 2] = top_right;
        self.fill_vertices[self.fill_len + 3] = bottom_left;
        self.fill_vertices[self.fill_len + 4] = top_right;
        self.fill_vertices[self.fill_len + 5] = top_left;
        self.fill_len += 6;
    }

    fn fillRoundedRectangle(self: *Scene, bounds: Bounds, requested_radius: f32, color: Color) !void {
        const radius = @min(requested_radius, @min(bounds.width, bounds.height) * 0.5);
        if (radius <= 0.0001) return self.fillRectangle(bounds, color);
        try self.fillRectangle(.{
            .left = bounds.left + radius,
            .bottom = bounds.bottom,
            .width = bounds.width - radius * 2.0,
            .height = bounds.height,
        }, color);
        try self.fillRectangle(.{
            .left = bounds.left,
            .bottom = bounds.bottom + radius,
            .width = bounds.width,
            .height = bounds.height - radius * 2.0,
        }, color);
        const corners = [_]struct { center: [2]f32, start: f32 }{
            .{ .center = .{ bounds.left + radius, bounds.bottom + radius }, .start = std.math.pi },
            .{ .center = .{ bounds.right() - radius, bounds.bottom + radius }, .start = -std.math.pi * 0.5 },
            .{ .center = .{ bounds.right() - radius, bounds.top() - radius }, .start = 0 },
            .{ .center = .{ bounds.left + radius, bounds.top() - radius }, .start = std.math.pi * 0.5 },
        };
        for (corners) |corner| {
            for (0..6) |index| {
                const a = corner.start + @as(f32, @floatFromInt(index)) * std.math.pi * 0.5 / 6.0;
                const b = corner.start + @as(f32, @floatFromInt(index + 1)) * std.math.pi * 0.5 / 6.0;
                try self.triangle(corner.center, pointOnCircle(corner.center, radius, a), pointOnCircle(corner.center, radius, b), color);
            }
        }
    }

    fn roundedRectangle(self: *Scene, bounds: Bounds, requested_radius: f32, color: Color) !void {
        const radius = @min(requested_radius, @min(bounds.width, bounds.height) * 0.5);
        if (radius <= 0.0001) return self.rectangle(bounds, color);
        try self.line(.{ bounds.left + radius, bounds.bottom }, .{ bounds.right() - radius, bounds.bottom }, color);
        try self.line(.{ bounds.right(), bounds.bottom + radius }, .{ bounds.right(), bounds.top() - radius }, color);
        try self.line(.{ bounds.right() - radius, bounds.top() }, .{ bounds.left + radius, bounds.top() }, color);
        try self.line(.{ bounds.left, bounds.top() - radius }, .{ bounds.left, bounds.bottom + radius }, color);
        const corners = [_]struct { center: [2]f32, start: f32 }{
            .{ .center = .{ bounds.left + radius, bounds.bottom + radius }, .start = std.math.pi },
            .{ .center = .{ bounds.right() - radius, bounds.bottom + radius }, .start = -std.math.pi * 0.5 },
            .{ .center = .{ bounds.right() - radius, bounds.top() - radius }, .start = 0 },
            .{ .center = .{ bounds.left + radius, bounds.top() - radius }, .start = std.math.pi * 0.5 },
        };
        for (corners) |corner| {
            for (0..6) |index| {
                const a = corner.start + @as(f32, @floatFromInt(index)) * std.math.pi * 0.5 / 6.0;
                const b = corner.start + @as(f32, @floatFromInt(index + 1)) * std.math.pi * 0.5 / 6.0;
                try self.line(pointOnCircle(corner.center, radius, a), pointOnCircle(corner.center, radius, b), color);
            }
        }
    }

    fn triangle(self: *Scene, a: [2]f32, b: [2]f32, c: [2]f32, color: Color) !void {
        if (self.fill_len + 3 > self.fill_vertices.len) return error.SceneCapacityExceeded;
        self.fill_vertices[self.fill_len] = vertex(a, color);
        self.fill_vertices[self.fill_len + 1] = vertex(b, color);
        self.fill_vertices[self.fill_len + 2] = vertex(c, color);
        self.fill_len += 3;
    }

    fn circle(self: *Scene, center: [2]f32, radius: f32, color: Color) !void {
        const segment_count = 32;
        var index: usize = 0;
        while (index < segment_count) : (index += 1) {
            const start_angle = tau * @as(f32, @floatFromInt(index)) / segment_count;
            const end_angle = tau * @as(f32, @floatFromInt(index + 1)) / segment_count;
            try self.line(pointOnCircle(center, radius, start_angle), pointOnCircle(center, radius, end_angle), color);
        }
    }

    fn fillCircle(self: *Scene, center: [2]f32, radius: f32, color: Color) !void {
        const segment_count = 32;
        var index: usize = 0;
        while (index < segment_count) : (index += 1) {
            const start_angle = tau * @as(f32, @floatFromInt(index)) / segment_count;
            const end_angle = tau * @as(f32, @floatFromInt(index + 1)) / segment_count;
            try self.triangle(center, pointOnCircle(center, radius, start_angle), pointOnCircle(center, radius, end_angle), color);
        }
    }

    fn addHitRegion(self: *Scene, bounds: Bounds, action: Action) !void {
        if (self.hit_len >= self.hit_regions.len) return error.SceneCapacityExceeded;
        self.hit_regions[self.hit_len] = .{
            .left = bounds.left,
            .bottom = bounds.bottom,
            .right = bounds.right(),
            .top = bounds.top(),
            .action = action,
        };
        self.hit_len += 1;
    }
};

const tau: f32 = 2.0 * std.math.pi;

const Bounds = struct {
    left: f32,
    bottom: f32,
    width: f32,
    height: f32,

    fn right(self: Bounds) f32 {
        return self.left + self.width;
    }

    fn top(self: Bounds) f32 {
        return self.bottom + self.height;
    }

    fn center(self: Bounds) [2]f32 {
        return .{ self.left + self.width * 0.5, self.bottom + self.height * 0.5 };
    }

    fn inset(self: Bounds, amount: f32) Bounds {
        return .{
            .left = self.left + amount,
            .bottom = self.bottom + amount,
            .width = self.width - amount * 2.0,
            .height = self.height - amount * 2.0,
        };
    }
};

const Layout = struct {
    toolbar: Bounds = .{ .left = -0.98, .bottom = 0.84, .width = 1.96, .height = 0.14 },
    board: Bounds = .{ .left = -0.98, .bottom = -0.76, .width = 1.96, .height = 1.60 },
    slot_bar: Bounds = .{ .left = -0.98, .bottom = -0.84, .width = 1.96, .height = 0.08 },
    transport: Bounds = .{ .left = -0.98, .bottom = -0.98, .width = 1.96, .height = 0.14 },
};

const palette = struct {
    const background = Color{ .r = 0.010, .g = 0.014, .b = 0.014 };
    const chrome = Color{ .r = 0.030, .g = 0.037, .b = 0.036 };
    const chrome_top = Color{ .r = 0.060, .g = 0.070, .b = 0.067 };
    const chrome_light = Color{ .r = 0.082, .g = 0.096, .b = 0.092 };
    const surface = Color{ .r = 0.020, .g = 0.027, .b = 0.026 };
    const surface_active = Color{ .r = 0.105, .g = 0.072, .b = 0.025 };
    const board_a = Color{ .r = 0.040, .g = 0.033, .b = 0.025 };
    const board_b = Color{ .r = 0.053, .g = 0.041, .b = 0.029 };
    const faint = Color{ .r = 0.105, .g = 0.132, .b = 0.128 };
    const mid = Color{ .r = 0.27, .g = 0.35, .b = 0.33 };
    const bright = Color{ .r = 0.70, .g = 0.84, .b = 0.79 };
    const amber = Color{ .r = 1.0, .g = 0.56, .b = 0.08 };
    const amber_soft = Color{ .r = 0.52, .g = 0.25, .b = 0.035 };
    const cable = Color{ .r = 1.0, .g = 0.57, .b = 0.08 };
    const blue = Color{ .r = 0.08, .g = 0.55, .b = 1.0 };
    const green = Color{ .r = 0.20, .g = 0.94, .b = 0.50 };
};

pub fn project(scene: *Scene, rig: *const demo.Rig) !void {
    try projectView(scene, rig, .rig);
}

pub fn projectView(scene: *Scene, rig: *const demo.Rig, view: ViewState) !void {
    try projectStudioView(scene, rig, view, false);
}

pub fn projectStudioView(scene: *Scene, rig: *const demo.Rig, view: ViewState, amplifier_focused: bool) !void {
    scene.* = Scene{};
    const layout = Layout{};

    try scene.fillRectangle(.{ .left = -1, .bottom = -1, .width = 2, .height = 2 }, palette.background);
    try drawToolbar(scene, layout.toolbar, view, amplifier_focused);
    switch (view) {
        .rig => {
            const pedal_bounds = try layoutPedalBounds(layout.board, rig);
            try drawPedalboard3dFrame(scene, layout.board);
            if (amplifier_focused)
                try drawFocusedAmplifierStrip(scene, layout.slot_bar, rig)
            else
                try drawSlotBar(scene, layout.slot_bar, pedal_bounds[0..rig.pedals.len], rig.pedals);
        },
        .amplifier => {
            try drawAmplifierView(scene, layout.board, rig);
            try drawAmplifierViewBar(scene, layout.slot_bar);
        },
        .lighting_lab => {
            try drawLightingLabFrame(scene);
        },
    }
    try drawTransport(scene, layout.transport);
}

pub fn activate(scene: *const Scene, state: *ViewState, point: [2]f32) bool {
    const action = scene.actionAt(point) orelse return false;
    const next: ViewState = switch (action) {
        .show_rig => .rig,
        .show_amplifier => .amplifier,
        .show_lighting_lab => .lighting_lab,
    };
    if (next == state.*) return false;
    state.* = next;
    return true;
}

fn drawToolbar(scene: *Scene, bounds: Bounds, view: ViewState, amplifier_focused: bool) !void {
    try scene.gradientRectangle(bounds, palette.chrome, palette.chrome_top);
    try scene.fillRectangle(.{ .left = bounds.left, .bottom = bounds.bottom, .width = bounds.width, .height = 0.008 }, palette.background);
    try scene.line(.{ bounds.left, bounds.bottom + 0.008 }, .{ bounds.right(), bounds.bottom + 0.008 }, palette.faint);

    const control_height = bounds.height - 0.044;
    const control_bottom = bounds.bottom + 0.026;
    const preset = Bounds{ .left = bounds.left + 0.018, .bottom = control_bottom, .width = 0.118, .height = control_height };
    try scene.fillRoundedRectangle(preset, 0.018, palette.surface);
    try scene.roundedRectangle(preset, 0.018, palette.faint);
    try scene.fillCircle(.{ preset.left + 0.019, preset.center()[1] }, 0.005, palette.amber);
    try drawDigit(scene, .{ preset.left + 0.038, preset.bottom + 0.020 }, 0.017, 0.043, 0, palette.amber);
    try drawDigit(scene, .{ preset.left + 0.062, preset.bottom + 0.020 }, 0.017, 0.043, 0, palette.amber);
    try drawDigit(scene, .{ preset.left + 0.086, preset.bottom + 0.020 }, 0.017, 0.043, 1, palette.amber);

    const navigation = Bounds{ .left = preset.right() + 0.012, .bottom = control_bottom, .width = 0.078, .height = control_height };
    try scene.fillRoundedRectangle(navigation, 0.018, palette.surface);
    try scene.roundedRectangle(navigation, 0.018, palette.faint);
    try scene.line(.{ navigation.center()[0], navigation.bottom + 0.014 }, .{ navigation.center()[0], navigation.top() - 0.014 }, palette.faint);
    try drawChevron(scene, .{ navigation.left + 0.020, navigation.center()[1] }, 0.012, false, palette.mid);
    try drawChevron(scene, .{ navigation.right() - 0.020, navigation.center()[1] }, 0.012, true, palette.bright);

    const title_bar = Bounds{ .left = navigation.right() + 0.012, .bottom = control_bottom, .width = 0.285, .height = control_height };
    try scene.fillRoundedRectangle(title_bar, 0.018, palette.surface);
    try scene.roundedRectangle(title_bar, 0.018, palette.faint);
    const favorite = [2]f32{ title_bar.right() - 0.026, title_bar.center()[1] };
    try scene.circle(favorite, 0.008, palette.amber_soft);
    try drawWave(scene, .{ .left = title_bar.left + 0.022, .bottom = title_bar.bottom + 0.024, .width = title_bar.width - 0.068, .height = title_bar.height - 0.048 }, palette.mid);

    const logo_center = [2]f32{ bounds.center()[0], bounds.bottom + bounds.height * 0.53 };
    try scene.line(.{ logo_center[0] - 0.112, logo_center[1] }, .{ logo_center[0] - 0.036, logo_center[1] }, palette.faint);
    try scene.line(.{ logo_center[0] + 0.036, logo_center[1] }, .{ logo_center[0] + 0.112, logo_center[1] }, palette.faint);
    try scene.circle(.{ logo_center[0] - 0.010, logo_center[1] }, 0.020, palette.bright);
    try scene.circle(.{ logo_center[0] + 0.010, logo_center[1] }, 0.020, palette.amber_soft);
    try scene.fillCircle(logo_center, 0.005, palette.amber);

    const mode_switch = Bounds{ .left = bounds.right() - 0.300, .bottom = control_bottom, .width = 0.210, .height = control_height };
    try scene.fillRoundedRectangle(mode_switch, 0.020, palette.surface);
    try scene.roundedRectangle(mode_switch, 0.020, palette.faint);
    const cell_width = mode_switch.width / 3.0;
    const active_mode: usize = switch (view) {
        .rig => if (amplifier_focused) 1 else 0,
        .amplifier => 1,
        .lighting_lab => 2,
    };
    for (0..3) |index| {
        const cell = Bounds{
            .left = mode_switch.left + @as(f32, @floatFromInt(index)) * cell_width,
            .bottom = mode_switch.bottom,
            .width = cell_width,
            .height = mode_switch.height,
        };
        if (index == active_mode) {
            try scene.fillRoundedRectangle(cell.inset(0.007), 0.015, palette.surface_active);
        }
        const icon_color = if (index == active_mode) palette.amber else palette.mid;
        if (index == 0)
            try drawRigIcon(scene, cell.center(), icon_color)
        else if (index == 1)
            try drawAmpIcon(scene, cell.center(), icon_color)
        else
            try drawCubeIcon(scene, cell.center(), icon_color);
        try scene.addHitRegion(cell, switch (index) {
            0 => .show_rig,
            1 => .show_amplifier,
            else => .show_lighting_lab,
        });
        if (index > 0) try scene.line(.{ cell.left, cell.bottom + 0.018 }, .{ cell.left, cell.top() - 0.018 }, palette.faint);
    }

    const menu = Bounds{ .left = bounds.right() - 0.072, .bottom = control_bottom, .width = 0.054, .height = control_height };
    try scene.fillRoundedRectangle(menu, 0.018, palette.surface);
    try scene.roundedRectangle(menu, 0.018, palette.faint);
    for (0..3) |index| {
        const y = menu.center()[1] + (@as(f32, @floatFromInt(index)) - 1.0) * 0.014;
        try scene.line(.{ menu.left + 0.015, y }, .{ menu.right() - 0.015, y }, if (index == 1) palette.bright else palette.mid);
    }
}

fn drawChevron(scene: *Scene, center: [2]f32, size: f32, right: bool, color: Color) !void {
    const direction: f32 = if (right) 1 else -1;
    const tip = [2]f32{ center[0] + size * direction, center[1] };
    const back_x = center[0] - size * 0.55 * direction;
    try scene.line(.{ back_x, center[1] - size }, tip, color);
    try scene.line(tip, .{ back_x, center[1] + size }, color);
}

fn drawRigIcon(scene: *Scene, center: [2]f32, color: Color) !void {
    const left = Bounds{ .left = center[0] - 0.023, .bottom = center[1] - 0.018, .width = 0.018, .height = 0.034 };
    const right = Bounds{ .left = center[0] + 0.005, .bottom = center[1] - 0.014, .width = 0.018, .height = 0.028 };
    try scene.roundedRectangle(left, 0.004, color);
    try scene.roundedRectangle(right, 0.004, color);
    try scene.circle(.{ left.center()[0], left.bottom + 0.008 }, 0.003, color);
    try scene.circle(.{ right.center()[0], right.bottom + 0.007 }, 0.003, color);
    try scene.line(.{ left.right(), center[1] + 0.005 }, .{ right.left, center[1] + 0.005 }, color);
}

fn drawAmpIcon(scene: *Scene, center: [2]f32, color: Color) !void {
    const shell = Bounds{ .left = center[0] - 0.025, .bottom = center[1] - 0.018, .width = 0.050, .height = 0.036 };
    try scene.roundedRectangle(shell, 0.006, color);
    try scene.line(.{ shell.left + 0.006, shell.top() - 0.010 }, .{ shell.right() - 0.006, shell.top() - 0.010 }, color);
    try scene.circle(.{ center[0], center[1] - 0.005 }, 0.009, color);
}

fn drawCubeIcon(scene: *Scene, center: [2]f32, color: Color) !void {
    const top = [2]f32{ center[0], center[1] + 0.021 };
    const left = [2]f32{ center[0] - 0.021, center[1] + 0.009 };
    const right = [2]f32{ center[0] + 0.021, center[1] + 0.009 };
    const bottom = [2]f32{ center[0], center[1] - 0.021 };
    try scene.line(top, left, color);
    try scene.line(top, right, color);
    try scene.line(left, bottom, color);
    try scene.line(right, bottom, color);
    try scene.line(top, bottom, color);
}

fn drawPedalboard(scene: *Scene, bounds: Bounds, rig: *const demo.Rig) ![8]Bounds {
    const pedals = rig.pedals;
    if (pedals.len > 8) return error.TooManyPedalsForWireframe;
    try scene.fillRectangle(bounds, palette.board_a);
    try scene.rectangle(bounds, palette.faint);

    const plank_count = 11;
    var plank: usize = 0;
    while (plank < plank_count) : (plank += 1) {
        const width = bounds.width / plank_count;
        const plank_bounds = Bounds{
            .left = bounds.left + @as(f32, @floatFromInt(plank)) * width,
            .bottom = bounds.bottom,
            .width = width,
            .height = bounds.height,
        };
        if (plank % 2 == 1) try scene.fillRectangle(plank_bounds, palette.board_b);
        try scene.line(.{ plank_bounds.left, bounds.bottom }, .{ plank_bounds.left, bounds.top() }, palette.faint);
        try scene.line(.{ plank_bounds.left + width * 0.25, bounds.bottom }, .{ plank_bounds.left + width * 0.18, bounds.top() }, palette.board_b);
    }

    const result = try layoutPedalBounds(bounds, rig);
    for (rig.pedals, 0..) |pedal, index| {
        const pedal_bounds = result[index];
        if (pedal.presentation == .open)
            try drawOpenPedal(scene, pedal_bounds, &pedal, index, rig.connections)
        else
            try drawClosedPedal(scene, pedal_bounds, &pedal, index, rig.connections);
    }
    return result;
}

fn drawPedalboard3dFrame(scene: *Scene, bounds: Bounds) !void {
    try scene.fillRectangle(bounds, Color{ .r = 0.008, .g = 0.012, .b = 0.012 });
    try scene.rectangle(bounds, palette.faint);
    try scene.line(.{ bounds.left + 0.02, bounds.top() - 0.025 }, .{ bounds.right() - 0.02, bounds.top() - 0.025 }, palette.chrome_light);
}

fn layoutPedalBounds(bounds: Bounds, rig: *const demo.Rig) ![8]Bounds {
    const pedals = rig.pedals;
    if (pedals.len > 8) return error.TooManyPedalsForWireframe;
    var weights: [8]f32 = undefined;
    var total_weight: f32 = 0;
    for (pedals, 0..) |pedal, index| {
        weights[index] = pedal.enclosure.footprint_units;
        total_weight += weights[index];
    }

    const gap: f32 = 0.026;
    const margin: f32 = 0.025;
    const available = bounds.width - margin * 2.0 - gap * @as(f32, @floatFromInt(pedals.len - 1));
    var cursor = bounds.right() - margin;
    var result: [8]Bounds = undefined;
    for (pedals, 0..) |_, index| {
        const width = available * weights[index] / total_weight;
        const pedal_bounds = Bounds{
            .left = cursor - width,
            .bottom = bounds.bottom + 0.115,
            .width = width,
            .height = bounds.height - 0.22,
        };
        result[index] = pedal_bounds;
        cursor -= width + gap;
    }
    return result;
}

fn drawClosedPedal(scene: *Scene, bounds: Bounds, pedal: *const demo.Pedal, pedal_index: usize, connections: []const demo.Connection) !void {
    const accent = accentColor(pedal.accent);
    const body = darken(accent, 0.16);
    try scene.fillRectangle(bounds, body);
    try scene.rectangle(bounds, accent);
    try scene.rectangle(bounds.inset(0.010), darken(accent, 0.42));

    const top_zone = Bounds{ .left = bounds.left + 0.010, .bottom = bounds.top() - bounds.height * 0.44, .width = bounds.width - 0.020, .height = bounds.height * 0.40 };
    const columns = if (pedal.controls.len <= 2) pedal.controls.len else @min(pedal.controls.len, 4);
    for (pedal.controls, 0..) |control, index| {
        const row: usize = if (index < columns) 0 else 1;
        const column = index % columns;
        const x = top_zone.left + top_zone.width * (@as(f32, @floatFromInt(column)) + 0.5) / @as(f32, @floatFromInt(columns));
        const y = top_zone.top() - 0.075 - @as(f32, @floatFromInt(row)) * 0.115;
        const radius = @min(0.040, bounds.width / @as(f32, @floatFromInt(columns)) * 0.30);
        try drawKnob(scene, .{ x, y }, radius, control.normalized_value, accent);
    }

    const logo = Bounds{ .left = bounds.left + bounds.width * 0.23, .bottom = bounds.bottom + bounds.height * 0.34, .width = bounds.width * 0.54, .height = 0.055 };
    try scene.rectangle(logo, accent);
    try drawWave(scene, logo.inset(0.010), accent);

    const switch_count = @max(@as(usize, 1), pedal.footswitch_count);
    for (0..switch_count) |index| {
        const x = bounds.left + bounds.width * (@as(f32, @floatFromInt(index)) + 1.0) / @as(f32, @floatFromInt(switch_count + 1));
        try drawFootswitch(scene, .{ x, bounds.bottom + 0.075 }, accent);
    }

    try scene.fillCircle(.{ bounds.left + bounds.width * 0.5, bounds.bottom + 0.18 }, 0.011, palette.green);
    try drawJacks(scene, bounds, pedal, pedal_index, connections);
}

fn drawOpenPedal(scene: *Scene, bounds: Bounds, pedal: *const demo.Pedal, pedal_index: usize, connections: []const demo.Connection) !void {
    const accent = accentColor(pedal.accent);
    try scene.fillRectangle(bounds, palette.surface);
    try scene.rectangle(bounds, accent);
    try scene.rectangle(bounds.inset(0.011), palette.mid);

    const pcb = Bounds{ .left = bounds.left + 0.025, .bottom = bounds.bottom + 0.17, .width = bounds.width - 0.050, .height = bounds.height - 0.23 };
    try scene.fillRectangle(pcb, Color{ .r = 0.025, .g = 0.11, .b = 0.075 });
    try scene.rectangle(pcb, palette.green);

    for (pedal.controls, 0..) |control, index| {
        const x = pcb.left + pcb.width * (@as(f32, @floatFromInt(index)) + 0.5) / @as(f32, @floatFromInt(pedal.controls.len));
        try drawKnob(scene, .{ x, pcb.top() - 0.065 }, 0.034, control.normalized_value, accent);
    }

    var row: usize = 0;
    while (row < 4) : (row += 1) {
        var column: usize = 0;
        while (column < 3) : (column += 1) {
            const component = Bounds{
                .left = pcb.left + 0.020 + @as(f32, @floatFromInt(column)) * (pcb.width - 0.055) / 2.0,
                .bottom = pcb.bottom + 0.11 + @as(f32, @floatFromInt(row)) * 0.050,
                .width = if ((row + column) % 2 == 0) 0.045 else 0.030,
                .height = 0.015,
            };
            try scene.fillRectangle(component, if ((row + column) % 2 == 0) palette.cable else palette.blue);
            try scene.rectangle(component, palette.bright);
        }
    }

    const chip = Bounds{ .left = pcb.left + pcb.width * 0.36, .bottom = pcb.bottom + 0.05, .width = pcb.width * 0.28, .height = 0.055 };
    try scene.fillRectangle(chip, palette.chrome);
    try scene.rectangle(chip, accent);
    var pin: usize = 0;
    while (pin < 5) : (pin += 1) {
        const x = chip.left + 0.008 + @as(f32, @floatFromInt(pin)) * (chip.width - 0.016) / 4.0;
        try scene.line(.{ x, chip.bottom - 0.008 }, .{ x, chip.bottom }, palette.bright);
        try scene.line(.{ x, chip.top() }, .{ x, chip.top() + 0.008 }, palette.bright);
    }

    const battery = Bounds{ .left = bounds.left + bounds.width * 0.27, .bottom = bounds.bottom + 0.025, .width = bounds.width * 0.46, .height = 0.105 };
    try scene.fillRectangle(battery, palette.chrome_light);
    try scene.rectangle(battery, accent);
    try scene.line(.{ battery.left + battery.width * 0.33, battery.bottom }, .{ battery.left + battery.width * 0.33, battery.top() }, palette.faint);
    try scene.line(.{ battery.left + battery.width * 0.66, battery.bottom }, .{ battery.left + battery.width * 0.66, battery.top() }, palette.faint);

    try scene.line(.{ pcb.left, pcb.bottom + 0.03 }, .{ battery.left, battery.top() - 0.02 }, palette.cable);
    try scene.line(.{ pcb.right(), pcb.bottom + 0.04 }, .{ battery.right(), battery.top() - 0.04 }, palette.blue);
    try drawJacks(scene, bounds, pedal, pedal_index, connections);
}

const PortProjection = struct {
    socket: [2]f32,
    cable_anchor: [2]f32,
    outward: [2]f32,
};

fn drawJacks(scene: *Scene, bounds: Bounds, pedal: *const demo.Pedal, pedal_index: usize, connections: []const demo.Connection) !void {
    for (pedal.ports) |port| {
        try drawJack(scene, projectPort(bounds, port), isPortConnected(connections, pedal_index, port.role));
    }
}

fn drawJack(scene: *Scene, projection: PortProjection, plugged: bool) !void {
    try scene.fillCircle(projection.socket, 0.018, palette.chrome_light);
    try scene.circle(projection.socket, 0.020, palette.bright);
    try scene.fillCircle(projection.socket, 0.010, palette.background);
    try scene.circle(projection.socket, 0.010, palette.mid);

    if (!plugged) return;

    const perpendicular = [2]f32{ -projection.outward[1], projection.outward[0] };
    const base = addScaled(projection.socket, projection.outward, 0.008);
    const tip = addScaled(projection.socket, projection.outward, 0.035);
    const half_width: f32 = 0.010;
    const plug = [_][2]f32{
        addScaled(base, perpendicular, half_width),
        addScaled(tip, perpendicular, half_width),
        addScaled(tip, perpendicular, -half_width),
        addScaled(base, perpendicular, -half_width),
    };
    try scene.triangle(plug[0], plug[1], plug[2], palette.chrome);
    try scene.triangle(plug[0], plug[2], plug[3], palette.chrome);
    try scene.line(plug[0], plug[1], palette.bright);
    try scene.line(plug[1], plug[2], palette.cable);
    try scene.line(plug[2], plug[3], palette.bright);
}

fn projectPort(bounds: Bounds, port: demo.PedalPort) PortProjection {
    const along = switch (port.slot) {
        .start => @as(f32, 0.76),
        .center => @as(f32, 0.50),
        .end => @as(f32, 0.24),
    };
    const socket: [2]f32 = switch (port.surface) {
        .left_side => .{ bounds.left, bounds.bottom + bounds.height * along },
        .right_side => .{ bounds.right(), bounds.bottom + bounds.height * along },
        .top => .{ bounds.left + bounds.width * (1.0 - along), bounds.top() },
    };
    const outward: [2]f32 = switch (port.surface) {
        .left_side => .{ -1, 0 },
        .right_side => .{ 1, 0 },
        .top => .{ 0, 1 },
    };
    return .{
        .socket = socket,
        .cable_anchor = addScaled(socket, outward, 0.040),
        .outward = outward,
    };
}

fn addScaled(point: [2]f32, direction: [2]f32, scale: f32) [2]f32 {
    return .{ point[0] + direction[0] * scale, point[1] + direction[1] * scale };
}

fn isPortConnected(connections: []const demo.Connection, pedal_index: usize, role: demo.PortRole) bool {
    for (connections) |connection| {
        if (endpointMatchesPort(connection.from, pedal_index, role) or endpointMatchesPort(connection.to, pedal_index, role)) return true;
    }
    return false;
}

fn endpointMatchesPort(endpoint: demo.Endpoint, pedal_index: usize, role: demo.PortRole) bool {
    return switch (endpoint) {
        .pedal_input => |index| role == .input and index == pedal_index,
        .pedal_output => |index| role == .output and index == pedal_index,
        else => false,
    };
}

fn drawKnob(scene: *Scene, center: [2]f32, radius: f32, value: f32, accent: Color) !void {
    try scene.fillCircle(center, radius, palette.chrome);
    try scene.circle(center, radius, accent);
    try scene.circle(center, radius * 0.78, palette.faint);
    const angle = (-0.75 + value * 1.5) * std.math.pi;
    try scene.line(center, pointOnCircle(center, radius * 0.68, angle), accent);
}

fn drawFootswitch(scene: *Scene, center: [2]f32, accent: Color) !void {
    try scene.fillCircle(center, 0.035, palette.chrome_light);
    try scene.circle(center, 0.035, accent);
    try scene.circle(center, 0.022, palette.mid);
}

fn drawSlotBar(scene: *Scene, bounds: Bounds, pedal_bounds: []const Bounds, pedals: []const demo.Pedal) !void {
    try scene.gradientRectangle(bounds, palette.chrome, palette.chrome_top);
    try scene.fillRectangle(.{ .left = bounds.left, .bottom = bounds.top() - 0.006, .width = bounds.width, .height = 0.006 }, palette.background);
    for (pedal_bounds, pedals, 0..) |pedal_bound, pedal, index| {
        const slot = Bounds{
            .left = pedal_bound.left + 0.006,
            .bottom = bounds.bottom + 0.009,
            .width = pedal_bound.width - 0.012,
            .height = bounds.height - 0.018,
        };
        const accent = accentColor(pedal.accent);
        try scene.fillRoundedRectangle(slot, 0.012, if (index == 1) palette.surface_active else palette.surface);
        try scene.roundedRectangle(slot, 0.012, if (index == 1) palette.amber_soft else palette.faint);
        try scene.fillRectangle(.{
            .left = slot.left + 0.014,
            .bottom = slot.bottom + 0.004,
            .width = slot.width - 0.028,
            .height = 0.004,
        }, if (index == 1) palette.amber else darken(accent, 0.58));

        const power = [2]f32{ slot.left + 0.024, slot.center()[1] };
        try scene.fillCircle(power, 0.010, palette.chrome_light);
        try scene.circle(power, 0.010, if (index == 1) palette.amber else accent);
        try scene.circle(power, 0.005, palette.background);
        try scene.line(power, .{ power[0], power[1] + 0.010 }, if (index == 1) palette.amber else accent);

        const control_count = @min(pedal.controls.len, 4);
        const controls_width: f32 = @as(f32, @floatFromInt(control_count)) * 0.018;
        const controls_left = slot.center()[0] - controls_width * 0.5;
        for (0..control_count) |control_index| {
            const center = [2]f32{
                controls_left + @as(f32, @floatFromInt(control_index)) * 0.018 + 0.009,
                slot.center()[1],
            };
            try scene.fillCircle(center, 0.005, palette.chrome_light);
            try scene.circle(center, 0.005, if (index == 1) palette.bright else accent);
        }
        const menu_center = [2]f32{ slot.right() - 0.020, slot.center()[1] };
        try scene.line(.{ menu_center[0] - 0.006, menu_center[1] + 0.003 }, .{ menu_center[0], menu_center[1] - 0.004 }, palette.mid);
        try scene.line(.{ menu_center[0], menu_center[1] - 0.004 }, .{ menu_center[0] + 0.006, menu_center[1] + 0.003 }, palette.mid);
    }
}

fn drawFocusedAmplifierStrip(scene: *Scene, bounds: Bounds, rig: *const demo.Rig) !void {
    try scene.gradientRectangle(bounds, palette.chrome, palette.chrome_top);
    try scene.fillRectangle(.{ .left = bounds.left, .bottom = bounds.top() - 0.006, .width = bounds.width, .height = 0.006 }, palette.background);

    const back = Bounds{ .left = bounds.left + 0.012, .bottom = bounds.bottom + 0.009, .width = 0.080, .height = bounds.height - 0.018 };
    try scene.fillRoundedRectangle(back, 0.014, palette.surface_active);
    try scene.roundedRectangle(back, 0.014, palette.amber_soft);
    try drawChevron(scene, .{ back.center()[0] - 0.004, back.center()[1] }, 0.009, false, palette.amber);
    try scene.addHitRegion(back, .show_rig);

    const identity = Bounds{ .left = back.right() + 0.012, .bottom = back.bottom, .width = 0.175, .height = back.height };
    try scene.fillRoundedRectangle(identity, 0.014, palette.surface);
    try scene.roundedRectangle(identity, 0.014, palette.faint);
    try drawAmpIcon(scene, .{ identity.left + 0.034, identity.center()[1] }, palette.amber);
    try scene.line(.{ identity.left + 0.064, identity.center()[1] }, .{ identity.right() - 0.018, identity.center()[1] }, palette.mid);

    const control_area = Bounds{ .left = identity.right() + 0.012, .bottom = back.bottom, .width = 0.65, .height = back.height };
    try scene.fillRoundedRectangle(control_area, 0.014, palette.surface);
    try scene.roundedRectangle(control_area, 0.014, palette.faint);
    const control_count = @max(@as(usize, 1), rig.amplifier.controls.len);
    for (rig.amplifier.controls, 0..) |control, index| {
        const x = control_area.left + control_area.width * (@as(f32, @floatFromInt(index)) + 0.5) / @as(f32, @floatFromInt(control_count));
        const center = [2]f32{ x, control_area.center()[1] };
        try scene.fillCircle(center, 0.012, palette.chrome_light);
        try scene.circle(center, 0.012, if (index == 0) palette.amber else palette.mid);
        const angle = (-0.72 + control.normalized_value * 1.44) * std.math.pi;
        try scene.line(center, pointOnCircle(center, 0.009, angle), palette.bright);
    }

    const status = Bounds{ .left = control_area.right() + 0.012, .bottom = back.bottom, .width = bounds.right() - control_area.right() - 0.024, .height = back.height };
    try scene.fillRoundedRectangle(status, 0.014, palette.surface);
    try scene.roundedRectangle(status, 0.014, palette.faint);
    const power = [2]f32{ status.left + 0.035, status.center()[1] };
    try scene.fillCircle(power, 0.010, palette.amber_soft);
    try scene.circle(power, 0.010, palette.amber);
    try scene.line(power, .{ power[0], power[1] + 0.011 }, palette.bright);
    const input = [2]f32{ status.right() - 0.035, status.center()[1] };
    try scene.fillCircle(input, 0.011, palette.chrome_light);
    try scene.circle(input, 0.011, palette.bright);
    try scene.fillCircle(input, 0.005, palette.background);
    try scene.line(.{ power[0] + 0.028, status.center()[1] }, .{ input[0] - 0.028, status.center()[1] }, palette.faint);
}

fn drawMainConnections(scene: *Scene, board: Bounds, pedals: []const Bounds, rig: *const demo.Rig) !void {
    for (rig.connections) |connection| {
        const from = try endpointPosition(connection.from, board, pedals, rig);
        const to = try endpointPosition(connection.to, board, pedals, rig);
        const route_y = @max(from[1], to[1]) + 0.035;
        try scene.line(from, .{ from[0], route_y }, palette.cable);
        try scene.line(.{ from[0], route_y }, .{ to[0], route_y }, palette.cable);
        try scene.line(.{ to[0], route_y }, to, palette.cable);
    }
}

fn endpointPosition(endpoint: demo.Endpoint, board: Bounds, pedals: []const Bounds, rig: *const demo.Rig) ![2]f32 {
    return switch (endpoint) {
        .rig_input => blk: {
            const first_input = try projectPedalPort(pedals[0], rig.pedals[0], .input);
            break :blk .{ board.right() - 0.008, first_input.cable_anchor[1] };
        },
        .pedal_input => |index| (try projectPedalPort(pedals[index], rig.pedals[index], .input)).cable_anchor,
        .pedal_output => |index| (try projectPedalPort(pedals[index], rig.pedals[index], .output)).cable_anchor,
        .amplifier_input => blk: {
            const last_index = rig.pedals.len - 1;
            const last_output = try projectPedalPort(pedals[last_index], rig.pedals[last_index], .output);
            break :blk .{ board.left + 0.008, last_output.cable_anchor[1] };
        },
    };
}

fn projectPedalPort(bounds: Bounds, pedal: demo.Pedal, role: demo.PortRole) !PortProjection {
    for (pedal.ports) |port| {
        if (port.role == role) return projectPort(bounds, port);
    }
    return error.MissingPedalPort;
}

fn drawAmplifierView(scene: *Scene, bounds: Bounds, rig: *const demo.Rig) !void {
    try scene.fillRectangle(bounds, palette.board_a);
    try scene.rectangle(bounds, palette.faint);

    const shell = Bounds{ .left = bounds.left + 0.07, .bottom = bounds.bottom + 0.075, .width = bounds.width - 0.14, .height = bounds.height - 0.15 };
    try scene.fillRectangle(shell, palette.chrome);
    try scene.rectangle(shell, palette.mid);
    try scene.rectangle(shell.inset(0.014), palette.faint);

    const handle = Bounds{ .left = shell.left + shell.width * 0.36, .bottom = shell.top() + 0.010, .width = shell.width * 0.28, .height = 0.045 };
    try scene.fillRectangle(handle, palette.surface);
    try scene.rectangle(handle, palette.mid);
    try scene.circle(.{ handle.left, handle.bottom }, 0.012, palette.bright);
    try scene.circle(.{ handle.right(), handle.bottom }, 0.012, palette.bright);

    const panel = Bounds{ .left = shell.left + 0.055, .bottom = shell.top() - 0.270, .width = shell.width - 0.110, .height = 0.205 };
    try scene.fillRectangle(panel, Color{ .r = 0.19, .g = 0.075, .b = 0.025 });
    try scene.rectangle(panel, palette.cable);
    try scene.rectangle(panel.inset(0.010), darken(palette.cable, 0.45));

    const power = Bounds{ .left = panel.left + 0.035, .bottom = panel.bottom + 0.055, .width = 0.055, .height = 0.085 };
    try scene.fillRectangle(power, palette.background);
    try scene.rectangle(power, palette.bright);
    try scene.fillRectangle(power.inset(0.013), palette.amber);

    const control_area = Bounds{ .left = power.right() + 0.045, .bottom = panel.bottom, .width = panel.width - 0.245, .height = panel.height };
    const count = @max(@as(usize, 1), rig.amplifier.controls.len);
    for (rig.amplifier.controls, 0..) |control, index| {
        const x = control_area.left + control_area.width * (@as(f32, @floatFromInt(index)) + 0.5) / @as(f32, @floatFromInt(count));
        const center = [2]f32{ x, panel.bottom + panel.height * 0.56 };
        try drawKnob(scene, center, 0.040, control.normalized_value, palette.cable);
        if (index == 0) {
            try scene.circle(center, 0.052, palette.bright);
            try scene.addHitRegion(.{ .left = x - 0.055, .bottom = center[1] - 0.055, .width = 0.110, .height = 0.110 }, .show_lighting_lab);
        }
        try scene.line(.{ x - 0.020, panel.bottom + 0.035 }, .{ x + 0.020, panel.bottom + 0.035 }, palette.bright);
    }

    const input = [2]f32{ panel.right() - 0.055, panel.bottom + panel.height * 0.55 };
    try scene.fillCircle(input, 0.021, palette.chrome_light);
    try scene.circle(input, 0.024, palette.bright);
    try scene.fillCircle(input, 0.012, palette.background);
    try scene.line(.{ input[0], input[1] - 0.012 }, .{ input[0], panel.bottom - 0.045 }, palette.cable);

    const grille = Bounds{ .left = shell.left + 0.045, .bottom = shell.bottom + 0.045, .width = shell.width - 0.090, .height = panel.bottom - shell.bottom - 0.075 };
    try scene.fillRectangle(grille, palette.surface);
    try scene.rectangle(grille, palette.faint);
    var stripe: usize = 0;
    while (stripe < 24) : (stripe += 1) {
        const x = grille.left + grille.width * @as(f32, @floatFromInt(stripe)) / 23.0;
        try scene.line(.{ x, grille.bottom }, .{ x + 0.035, grille.top() }, if (stripe % 2 == 0) palette.faint else palette.board_b);
    }
    const badge = Bounds{ .left = grille.left + grille.width * 0.40, .bottom = grille.bottom + grille.height * 0.32, .width = grille.width * 0.20, .height = grille.height * 0.38 };
    try scene.fillRectangle(badge, Color{ .r = 0.16, .g = 0.055, .b = 0.025 });
    try scene.rectangle(badge, palette.cable);
    try drawWave(scene, badge.inset(0.012), palette.bright);

    for ([_][2]f32{
        .{ shell.left + 0.025, shell.bottom + 0.025 },
        .{ shell.right() - 0.025, shell.bottom + 0.025 },
        .{ shell.left + 0.025, shell.top() - 0.025 },
        .{ shell.right() - 0.025, shell.top() - 0.025 },
    }) |screw| try scene.circle(screw, 0.008, palette.bright);
}

fn drawLightingLabFrame(scene: *Scene) !void {
    const header = Bounds{ .left = -0.98, .bottom = 0.70, .width = 1.96, .height = 0.14 };
    const viewport = Bounds{ .left = -0.98, .bottom = -0.84, .width = 1.96, .height = 1.54 };
    try scene.fillRectangle(viewport, Color{ .r = 0.010, .g = 0.016, .b = 0.016 });
    try scene.rectangle(viewport, palette.faint);
    try scene.gradientRectangle(header, palette.chrome, palette.chrome_top);
    try scene.fillRectangle(.{ .left = header.left, .bottom = header.bottom, .width = header.width, .height = 0.006 }, palette.background);
    const comparison_split_x: f32 = 0;
    try scene.line(.{ comparison_split_x, viewport.bottom }, .{ comparison_split_x, viewport.top() }, palette.faint);

    const back = Bounds{ .left = header.left + 0.015, .bottom = header.bottom + 0.025, .width = 0.085, .height = header.height - 0.050 };
    try scene.fillRoundedRectangle(back, 0.016, palette.surface_active);
    try scene.roundedRectangle(back, 0.016, palette.amber_soft);
    try scene.line(.{ back.left + 0.056, back.bottom + 0.014 }, .{ back.left + 0.026, back.center()[1] }, palette.bright);
    try scene.line(.{ back.left + 0.026, back.center()[1] }, .{ back.left + 0.056, back.top() - 0.014 }, palette.bright);
    try scene.addHitRegion(back, .show_amplifier);

    const live = Bounds{ .left = back.right() + 0.022, .bottom = back.bottom, .width = 0.35, .height = back.height };
    try scene.fillRoundedRectangle(live, 0.016, palette.surface);
    try scene.roundedRectangle(live, 0.016, palette.faint);
    try scene.fillCircle(.{ live.left + 0.030, live.center()[1] }, 0.010, palette.green);
    try scene.line(.{ live.left + 0.055, live.center()[1] }, .{ live.right() - 0.020, live.center()[1] }, palette.mid);

    const three_d_badge = Bounds{ .left = -0.22, .bottom = back.bottom, .width = 0.16, .height = back.height };
    const layer_badge = Bounds{ .left = -0.04, .bottom = back.bottom, .width = 0.19, .height = back.height };
    try drawComparisonBadge(scene, three_d_badge, false);
    try drawComparisonBadge(scene, layer_badge, true);

    const strip = Bounds{ .left = header.right() - 0.30, .bottom = back.bottom, .width = 0.27, .height = back.height };
    try scene.fillRoundedRectangle(strip, 0.016, palette.surface);
    try scene.roundedRectangle(strip, 0.016, palette.faint);
    try scene.line(.{ strip.left + 0.025, strip.center()[1] }, .{ strip.right() - 0.025, strip.center()[1] }, palette.bright);
    try scene.circle(.{ strip.left + strip.width * 0.66, strip.center()[1] }, 0.014, palette.amber);
}

fn drawComparisonBadge(scene: *Scene, bounds: Bounds, layered: bool) !void {
    try scene.fillRoundedRectangle(bounds, 0.016, if (layered) palette.surface else palette.surface_active);
    try scene.roundedRectangle(bounds, 0.016, if (layered) palette.mid else palette.amber_soft);
    const height = bounds.height * 0.54;
    const width = height * 0.43;
    var x = bounds.left + 0.025;
    const y = bounds.bottom + (bounds.height - height) * 0.5;
    if (layered) {
        try drawDigit(scene, .{ x, y }, width, height, 2, palette.bright);
        x += width + 0.012;
        try scene.fillCircle(.{ x, y + 0.004 }, 0.004, palette.bright);
        x += 0.012;
        try drawDigit(scene, .{ x, y }, width, height, 5, palette.bright);
        x += width + 0.014;
    } else {
        try drawDigit(scene, .{ x, y }, width, height, 3, palette.amber);
        x += width + 0.016;
    }
    try drawLetterD(scene, .{ x, y }, width * 1.15, height, if (layered) palette.bright else palette.amber);
}

fn drawLetterD(scene: *Scene, origin: [2]f32, width: f32, height: f32, color: Color) !void {
    try scene.line(origin, .{ origin[0], origin[1] + height }, color);
    try scene.line(.{ origin[0], origin[1] + height }, .{ origin[0] + width * 0.68, origin[1] + height }, color);
    try scene.line(.{ origin[0] + width * 0.68, origin[1] + height }, .{ origin[0] + width, origin[1] + height * 0.72 }, color);
    try scene.line(.{ origin[0] + width, origin[1] + height * 0.72 }, .{ origin[0] + width, origin[1] + height * 0.28 }, color);
    try scene.line(.{ origin[0] + width, origin[1] + height * 0.28 }, .{ origin[0] + width * 0.68, origin[1] }, color);
    try scene.line(.{ origin[0] + width * 0.68, origin[1] }, origin, color);
}

fn drawLightingLabBrowser(scene: *Scene, bounds: Bounds) !void {
    try scene.fillRectangle(bounds, palette.chrome);
    try scene.rectangle(bounds, palette.faint);

    const title = Bounds{ .left = bounds.left + 0.018, .bottom = bounds.top() - 0.10, .width = bounds.width - 0.036, .height = 0.065 };
    try scene.fillRectangle(title, palette.surface);
    try scene.rectangle(title, palette.amber);
    try scene.circle(.{ title.left + 0.032, title.center()[1] }, 0.015, palette.bright);
    try scene.line(.{ title.left + 0.065, title.center()[1] }, .{ title.right() - 0.020, title.center()[1] }, palette.mid);

    const swatches = [_]Color{
        .{ .r = 0.18, .g = 0.22, .b = 0.21 },
        .{ .r = 0.55, .g = 0.58, .b = 0.56 },
        .{ .r = 0.12, .g = 0.055, .b = 0.025 },
        .{ .r = 0.11, .g = 0.18, .b = 0.16 },
        .{ .r = 0.50, .g = 0.22, .b = 0.04 },
        .{ .r = 0.07, .g = 0.08, .b = 0.09 },
    };
    const columns = 2;
    const cell_width = (bounds.width - 0.055) / columns;
    const cell_height: f32 = 0.25;
    for (swatches, 0..) |swatch, index| {
        const row = index / columns;
        const column = index % columns;
        const cell = Bounds{
            .left = bounds.left + 0.020 + @as(f32, @floatFromInt(column)) * cell_width,
            .bottom = title.bottom - 0.035 - @as(f32, @floatFromInt(row + 1)) * cell_height,
            .width = cell_width - 0.010,
            .height = cell_height - 0.012,
        };
        try scene.rectangle(cell, if (index == 1) palette.amber else palette.faint);
        try scene.fillCircle(.{ cell.center()[0], cell.bottom + cell.height * 0.60 }, 0.045, swatch);
        try scene.circle(.{ cell.center()[0], cell.bottom + cell.height * 0.60 }, 0.045, palette.bright);
        try scene.line(.{ cell.left + 0.025, cell.bottom + 0.030 }, .{ cell.right() - 0.025, cell.bottom + 0.030 }, if (index == 1) palette.amber else palette.faint);
    }
}

fn drawAmplifierViewBar(scene: *Scene, bounds: Bounds) !void {
    try scene.fillRectangle(bounds, palette.chrome);
    try scene.line(.{ bounds.left, bounds.top() }, .{ bounds.right(), bounds.top() }, palette.faint);

    const back = Bounds{ .left = bounds.left + 0.015, .bottom = bounds.bottom + 0.012, .width = 0.080, .height = bounds.height - 0.024 };
    try scene.fillRectangle(back, palette.surface);
    try scene.rectangle(back, palette.amber);
    try scene.line(.{ back.left + 0.052, back.bottom + 0.012 }, .{ back.left + 0.025, back.center()[1] }, palette.bright);
    try scene.line(.{ back.left + 0.025, back.center()[1] }, .{ back.left + 0.052, back.top() - 0.012 }, palette.bright);
    try scene.addHitRegion(back, .show_rig);

    const selection = Bounds{ .left = back.right() + 0.020, .bottom = back.bottom, .width = 0.44, .height = back.height };
    try scene.fillRectangle(selection, palette.surface);
    try scene.rectangle(selection, palette.faint);
    try scene.circle(.{ selection.left + 0.030, selection.center()[1] }, 0.012, palette.amber);
    try scene.line(.{ selection.left + 0.060, selection.center()[1] }, .{ selection.right() - 0.025, selection.center()[1] }, palette.mid);
}

fn drawAmplifierBrowser(scene: *Scene, bounds: Bounds) !void {
    try scene.fillRectangle(bounds, palette.chrome);
    try scene.rectangle(bounds, palette.faint);

    const search = Bounds{ .left = bounds.left + 0.018, .bottom = bounds.top() - 0.10, .width = bounds.width - 0.036, .height = 0.065 };
    try scene.fillRectangle(search, palette.surface);
    try scene.rectangle(search, palette.faint);
    try scene.circle(.{ search.left + 0.028, search.center()[1] }, 0.013, palette.mid);
    try scene.line(.{ search.left + 0.038, search.bottom + 0.022 }, .{ search.left + 0.052, search.bottom + 0.009 }, palette.mid);
    try scene.line(.{ search.left + 0.073, search.center()[1] }, .{ search.right() - 0.018, search.center()[1] }, palette.faint);

    const tabs = Bounds{ .left = search.left, .bottom = search.bottom - 0.075, .width = search.width, .height = 0.055 };
    try scene.fillRectangle(tabs, palette.surface);
    try scene.rectangle(tabs, palette.amber);
    try scene.line(.{ tabs.center()[0], tabs.bottom }, .{ tabs.center()[0], tabs.top() }, palette.faint);

    const grid_top = tabs.bottom - 0.030;
    const columns = 2;
    const rows = 5;
    const cell_width = (bounds.width - 0.055) / columns;
    const cell_height: f32 = 0.195;
    var row: usize = 0;
    while (row < rows) : (row += 1) {
        var column: usize = 0;
        while (column < columns) : (column += 1) {
            const item = row * columns + column;
            const cell = Bounds{
                .left = bounds.left + 0.020 + @as(f32, @floatFromInt(column)) * cell_width,
                .bottom = grid_top - @as(f32, @floatFromInt(row + 1)) * cell_height,
                .width = cell_width - 0.010,
                .height = cell_height - 0.012,
            };
            try scene.rectangle(cell, if (item == 2) palette.amber else palette.faint);
            const head = Bounds{ .left = cell.left + 0.020, .bottom = cell.bottom + 0.065, .width = cell.width - 0.040, .height = 0.065 };
            try drawMiniAmplifier(scene, head, 5 - item % 2, item == 2);
            try scene.line(.{ cell.left + 0.025, cell.bottom + 0.030 }, .{ cell.right() - 0.025, cell.bottom + 0.030 }, if (item == 2) palette.amber else palette.faint);
        }
    }
}

fn drawSignalChain(scene: *Scene, bounds: Bounds, rig: *const demo.Rig, view: ViewState) !void {
    try scene.fillRectangle(bounds, palette.surface);
    try scene.rectangle(bounds, palette.faint);

    const rail_y = bounds.bottom + bounds.height * 0.43;
    const input_x = bounds.right() - 0.08;
    const output_x = bounds.left + 0.07;
    try scene.line(.{ input_x, rail_y }, .{ output_x, rail_y }, palette.cable);
    try scene.line(.{ input_x - 0.08, rail_y }, .{ input_x - 0.08, bounds.bottom + 0.12 }, palette.blue);
    try scene.line(.{ input_x - 0.08, bounds.bottom + 0.12 }, .{ output_x + 0.06, bounds.bottom + 0.12 }, palette.blue);
    try scene.line(.{ output_x + 0.06, bounds.bottom + 0.12 }, .{ output_x + 0.06, rail_y }, palette.blue);

    try scene.circle(.{ input_x, rail_y }, 0.025, palette.bright);
    try scene.line(.{ input_x + 0.010, rail_y }, .{ input_x + 0.035, rail_y }, palette.bright);

    const pedal_start = input_x - 0.13;
    const pedal_spacing: f32 = 0.095;
    for (rig.pedals, 0..) |pedal, index| {
        const node_width: f32 = if (pedal.enclosure.form_factor == .double) 0.072 else 0.050;
        const node = Bounds{
            .left = pedal_start - @as(f32, @floatFromInt(index)) * pedal_spacing - node_width,
            .bottom = rail_y - 0.055,
            .width = node_width,
            .height = 0.110,
        };
        try drawMiniPedal(scene, node, accentColor(pedal.accent), index == 3);
    }

    const split = [2]f32{ pedal_start - pedal_spacing * 5.35, rail_y };
    try scene.fillRectangle(.{ .left = split[0] - 0.025, .bottom = split[1] - 0.025, .width = 0.050, .height = 0.050 }, palette.chrome_light);
    try scene.rectangle(.{ .left = split[0] - 0.025, .bottom = split[1] - 0.025, .width = 0.050, .height = 0.050 }, palette.mid);

    const amp = Bounds{ .left = split[0] - 0.34, .bottom = rail_y - 0.16, .width = 0.25, .height = 0.11 };
    const cab = Bounds{ .left = amp.left - 0.18, .bottom = rail_y - 0.17, .width = 0.13, .height = 0.13 };
    try drawMiniAmplifier(scene, amp, rig.amplifier.controls.len, view == .amplifier);
    if (view == .rig) try scene.addHitRegion(amp, .show_amplifier);
    try drawMiniCabinet(scene, cab, rig.cabinet.speaker_count);
    try scene.line(split, .{ split[0] - 0.045, split[1] }, palette.cable);
    try scene.line(.{ split[0] - 0.045, split[1] }, .{ split[0] - 0.045, amp.top() - 0.025 }, palette.cable);
    try scene.line(.{ split[0] - 0.045, amp.top() - 0.025 }, .{ amp.right(), amp.top() - 0.025 }, palette.cable);
    try scene.line(.{ amp.left, amp.bottom + amp.height * 0.5 }, .{ cab.right(), cab.bottom + cab.height * 0.5 }, palette.cable);
    try scene.line(.{ cab.left, cab.bottom + cab.height * 0.5 }, .{ output_x, rail_y }, palette.cable);

    const alternate_amp = Bounds{ .left = amp.right() - 0.22, .bottom = rail_y + 0.13, .width = 0.20, .height = 0.09 };
    const alternate_cab = Bounds{ .left = alternate_amp.left - 0.16, .bottom = rail_y + 0.11, .width = 0.11, .height = 0.12 };
    try drawMiniAmplifier(scene, alternate_amp, 4, false);
    try drawMiniCabinet(scene, alternate_cab, 1);
    try scene.line(split, .{ split[0] - 0.045, split[1] }, palette.cable);
    try scene.line(.{ split[0] - 0.045, split[1] }, .{ split[0] - 0.045, alternate_amp.bottom + 0.025 }, palette.cable);
    try scene.line(.{ split[0] - 0.045, alternate_amp.bottom + 0.025 }, .{ alternate_amp.right(), alternate_amp.bottom + 0.025 }, palette.cable);
    try scene.line(.{ alternate_amp.left, alternate_amp.bottom + alternate_amp.height * 0.5 }, .{ alternate_cab.right(), alternate_cab.bottom + alternate_cab.height * 0.5 }, palette.cable);
    try scene.line(.{ alternate_cab.left, alternate_cab.bottom + alternate_cab.height * 0.5 }, .{ output_x, rail_y }, palette.cable);

    try scene.fillCircle(.{ output_x, rail_y }, 0.028, palette.chrome_light);
    try scene.circle(.{ output_x, rail_y }, 0.028, palette.bright);
    try scene.line(.{ output_x - 0.035, rail_y }, .{ output_x - 0.070, rail_y }, palette.bright);
}

fn drawMiniPedal(scene: *Scene, bounds: Bounds, accent: Color, selected: bool) !void {
    try scene.fillRectangle(bounds, darken(accent, 0.14));
    try scene.rectangle(bounds, if (selected) palette.amber else accent);
    try scene.circle(.{ bounds.left + bounds.width * 0.34, bounds.top() - 0.027 }, 0.009, accent);
    try scene.circle(.{ bounds.left + bounds.width * 0.66, bounds.top() - 0.027 }, 0.009, accent);
    try scene.circle(.{ bounds.left + bounds.width * 0.5, bounds.bottom + 0.022 }, 0.013, palette.bright);
}

fn drawMiniAmplifier(scene: *Scene, bounds: Bounds, control_count: usize, selected: bool) !void {
    try scene.fillRectangle(bounds, Color{ .r = 0.10, .g = 0.065, .b = 0.025 });
    try scene.rectangle(bounds, if (selected) palette.bright else palette.cable);
    if (selected) try scene.rectangle(bounds.inset(0.006), palette.amber);
    try scene.rectangle(bounds.inset(0.010), palette.faint);
    const count = @min(control_count, 8);
    for (0..count) |index| {
        const x = bounds.left + bounds.width * (@as(f32, @floatFromInt(index)) + 1.0) / @as(f32, @floatFromInt(count + 1));
        try scene.circle(.{ x, bounds.bottom + 0.025 }, 0.006, palette.bright);
    }
}

fn drawMiniCabinet(scene: *Scene, bounds: Bounds, speaker_count: u8) !void {
    try scene.fillRectangle(bounds, palette.chrome);
    try scene.rectangle(bounds, palette.mid);
    const count = @max(@as(usize, 1), speaker_count);
    for (0..count) |index| {
        const x = bounds.left + bounds.width * (@as(f32, @floatFromInt(index)) + 0.5) / @as(f32, @floatFromInt(count));
        try scene.circle(.{ x, bounds.bottom + bounds.height * 0.52 }, @min(0.025, bounds.width / @as(f32, @floatFromInt(count)) * 0.32), palette.bright);
    }
}

fn drawBrowser(scene: *Scene, bounds: Bounds) !void {
    try scene.fillRectangle(bounds, palette.chrome);
    try scene.rectangle(bounds, palette.faint);

    const search = Bounds{ .left = bounds.left + 0.018, .bottom = bounds.top() - 0.10, .width = bounds.width - 0.036, .height = 0.065 };
    try scene.fillRectangle(search, palette.surface);
    try scene.rectangle(search, palette.faint);
    try scene.circle(.{ search.left + 0.028, search.bottom + search.height * 0.54 }, 0.013, palette.mid);
    try scene.line(.{ search.left + 0.038, search.bottom + 0.022 }, .{ search.left + 0.052, search.bottom + 0.009 }, palette.mid);
    try scene.line(.{ search.left + 0.073, search.bottom + search.height * 0.5 }, .{ search.right() - 0.018, search.bottom + search.height * 0.5 }, palette.faint);

    const tab_y = search.bottom - 0.080;
    var tab: usize = 0;
    while (tab < 4) : (tab += 1) {
        const cell = Bounds{ .left = bounds.left + 0.018 + @as(f32, @floatFromInt(tab)) * 0.105, .bottom = tab_y, .width = 0.090, .height = 0.060 };
        try scene.fillRectangle(cell, if (tab == 0) palette.surface else palette.chrome_light);
        try scene.rectangle(cell, if (tab == 0) palette.amber else palette.faint);
        if (tab == 0) {
            try drawMiniPedal(scene, Bounds{ .left = cell.center()[0] - 0.012, .bottom = cell.center()[1] - 0.018, .width = 0.024, .height = 0.036 }, palette.amber, false);
        } else {
            try scene.rectangle(Bounds{ .left = cell.center()[0] - 0.015, .bottom = cell.center()[1] - 0.014, .width = 0.030, .height = 0.028 }, palette.mid);
        }
    }

    const filters = Bounds{ .left = bounds.left + 0.018, .bottom = tab_y - 0.075, .width = bounds.width - 0.036, .height = 0.055 };
    try scene.fillRectangle(filters, palette.surface);
    try scene.rectangle(filters, palette.faint);
    try scene.line(.{ filters.left + filters.width * 0.5, filters.bottom }, .{ filters.left + filters.width * 0.5, filters.top() }, palette.faint);
    try scene.line(.{ filters.left + 0.020, filters.bottom + 0.018 }, .{ filters.left + 0.040, filters.bottom + 0.038 }, palette.amber);
    try scene.line(.{ filters.left + 0.040, filters.bottom + 0.038 }, .{ filters.left + 0.055, filters.bottom + 0.023 }, palette.amber);

    const grid_top = filters.bottom - 0.035;
    const columns = 3;
    const rows = 4;
    const cell_width = (bounds.width - 0.060) / columns;
    const cell_height: f32 = 0.250;
    const accents = [_]demo.Accent{ .coral, .amber, .green, .violet, .cyan, .amber, .green, .coral, .violet, .cyan, .amber, .green };
    var row: usize = 0;
    while (row < rows) : (row += 1) {
        var column: usize = 0;
        while (column < columns) : (column += 1) {
            const item_index = row * columns + column;
            const cell = Bounds{
                .left = bounds.left + 0.022 + @as(f32, @floatFromInt(column)) * cell_width,
                .bottom = grid_top - @as(f32, @floatFromInt(row + 1)) * cell_height,
                .width = cell_width - 0.010,
                .height = cell_height - 0.012,
            };
            if (item_index == 4) {
                try scene.fillRectangle(cell, Color{ .r = 0.085, .g = 0.065, .b = 0.025 });
                try scene.rectangle(cell, palette.amber);
            } else {
                try scene.rectangle(cell, palette.faint);
            }
            const mini = Bounds{
                .left = cell.left + cell.width * 0.31,
                .bottom = cell.bottom + 0.065,
                .width = cell.width * 0.38,
                .height = cell.height * 0.54,
            };
            try drawMiniPedal(scene, mini, accentColor(accents[item_index]), item_index == 4);
            try scene.line(.{ cell.left + 0.018, cell.bottom + 0.030 }, .{ cell.right() - 0.018, cell.bottom + 0.030 }, if (item_index == 4) palette.amber else palette.faint);
        }
    }
}

fn drawTransport(scene: *Scene, bounds: Bounds) !void {
    try scene.gradientRectangle(bounds, palette.chrome, palette.chrome_top);
    try scene.fillRectangle(.{ .left = bounds.left, .bottom = bounds.top() - 0.006, .width = bounds.width, .height = 0.006 }, palette.background);
    try scene.line(.{ bounds.left, bounds.top() - 0.006 }, .{ bounds.right(), bounds.top() - 0.006 }, palette.faint);

    const panel_bottom = bounds.bottom + 0.020;
    const panel_height = bounds.height - 0.040;
    const input_panel = Bounds{ .left = bounds.left + 0.018, .bottom = panel_bottom, .width = 0.335, .height = panel_height };
    try drawIoPanel(scene, input_panel, 0.66, false);

    const transport = Bounds{ .left = bounds.center()[0] - 0.365, .bottom = panel_bottom, .width = 0.535, .height = panel_height };
    try scene.fillRoundedRectangle(transport, 0.022, palette.surface);
    try scene.roundedRectangle(transport, 0.022, palette.faint);
    const spacing = transport.width / 6.0;
    const y = transport.center()[1];
    const record = [2]f32{ transport.left + spacing, y };
    try scene.fillCircle(record, 0.014, Color{ .r = 0.50, .g = 0.10, .b = 0.075 });
    try scene.circle(record, 0.014, Color{ .r = 1.0, .g = 0.31, .b = 0.23 });

    const previous = [2]f32{ transport.left + spacing * 2.0, y };
    try scene.line(.{ previous[0] - 0.017, previous[1] - 0.017 }, .{ previous[0] - 0.017, previous[1] + 0.017 }, palette.mid);
    try scene.triangle(.{ previous[0] - 0.010, previous[1] }, .{ previous[0] + 0.016, previous[1] + 0.018 }, .{ previous[0] + 0.016, previous[1] - 0.018 }, palette.bright);

    const play = [2]f32{ transport.left + spacing * 3.0, y };
    try scene.fillCircle(play, 0.034, palette.amber_soft);
    try scene.circle(play, 0.034, palette.amber);
    try scene.triangle(.{ play[0] - 0.009, play[1] - 0.016 }, .{ play[0] - 0.009, play[1] + 0.016 }, .{ play[0] + 0.018, play[1] }, palette.bright);

    const next = [2]f32{ transport.left + spacing * 4.0, y };
    try scene.triangle(.{ next[0] + 0.010, next[1] }, .{ next[0] - 0.016, next[1] + 0.018 }, .{ next[0] - 0.016, next[1] - 0.018 }, palette.bright);
    try scene.line(.{ next[0] + 0.017, next[1] - 0.017 }, .{ next[0] + 0.017, next[1] + 0.017 }, palette.mid);

    const loop = [2]f32{ transport.left + spacing * 5.0, y };
    try scene.circle(loop, 0.020, palette.amber);
    try scene.triangle(.{ loop[0] + 0.012, loop[1] + 0.018 }, .{ loop[0] + 0.026, loop[1] + 0.013 }, .{ loop[0] + 0.017, loop[1] + 0.005 }, palette.amber);

    const display = Bounds{ .left = bounds.center()[0] + 0.205, .bottom = panel_bottom, .width = 0.335, .height = panel_height };
    try scene.fillRoundedRectangle(display, 0.018, palette.background);
    try scene.roundedRectangle(display, 0.018, palette.faint);
    try scene.fillCircle(.{ display.left + 0.022, display.top() - 0.020 }, 0.004, palette.green);
    var x = display.left + 0.040;
    const digits = [_]u8{ 0, 0, 1, 1, 0, 1 };
    for (digits, 0..) |digit, index| {
        try drawDigit(scene, .{ x, display.bottom + 0.021 }, 0.021, 0.052, digit, if (index < 4) palette.bright else palette.mid);
        x += 0.035;
        if (index == 1 or index == 3) {
            try scene.fillCircle(.{ x - 0.006, display.center()[1] + 0.010 }, 0.003, palette.amber_soft);
            try scene.fillCircle(.{ x - 0.006, display.center()[1] - 0.010 }, 0.003, palette.amber_soft);
            x += 0.006;
        }
    }

    const output_panel = Bounds{ .left = bounds.right() - 0.353, .bottom = panel_bottom, .width = 0.335, .height = panel_height };
    try drawIoPanel(scene, output_panel, 0.78, true);
}

fn drawIoPanel(scene: *Scene, bounds: Bounds, level: f32, output: bool) !void {
    try scene.fillRoundedRectangle(bounds, 0.018, palette.surface);
    try scene.roundedRectangle(bounds, 0.018, palette.faint);
    const knob_x = if (output) bounds.right() - 0.036 else bounds.left + 0.036;
    const knob = [2]f32{ knob_x, bounds.center()[1] };
    try scene.fillCircle(knob, 0.021, palette.chrome_light);
    try scene.circle(knob, 0.021, palette.mid);
    try scene.line(knob, .{ knob[0] + 0.010, knob[1] + 0.014 }, palette.bright);
    const meter = Bounds{
        .left = if (output) bounds.left + 0.018 else bounds.left + 0.070,
        .bottom = bounds.bottom + 0.022,
        .width = bounds.width - 0.088,
        .height = bounds.height - 0.044,
    };
    try drawMeter(scene, meter, level);
}

fn drawMeter(scene: *Scene, bounds: Bounds, level: f32) !void {
    try scene.fillRoundedRectangle(bounds, 0.010, palette.background);
    try scene.roundedRectangle(bounds, 0.010, palette.faint);
    const bar_count = 18;
    var index: usize = 0;
    while (index < bar_count) : (index += 1) {
        const active = @as(f32, @floatFromInt(index)) / bar_count < level;
        const bar = Bounds{
            .left = bounds.left + 0.008 + @as(f32, @floatFromInt(index)) * (bounds.width - 0.016) / bar_count,
            .bottom = bounds.bottom + 0.008,
            .width = (bounds.width - 0.026) / bar_count,
            .height = bounds.height - 0.016,
        };
        try scene.fillRoundedRectangle(bar, 0.002, if (active) (if (index > 14) palette.amber else palette.green) else palette.faint);
    }
}

fn drawWave(scene: *Scene, bounds: Bounds, color: Color) !void {
    const segments = 20;
    var previous = [2]f32{ bounds.left, bounds.center()[1] };
    var index: usize = 1;
    while (index <= segments) : (index += 1) {
        const t = @as(f32, @floatFromInt(index)) / segments;
        const current = [2]f32{
            bounds.left + bounds.width * t,
            bounds.center()[1] + @sin(t * tau * 1.5) * bounds.height * 0.36,
        };
        try scene.line(previous, current, color);
        previous = current;
    }
}

fn drawDigit(scene: *Scene, origin: [2]f32, width: f32, height: f32, digit: u8, color: Color) !void {
    const segment_map = [_]u8{
        0b1111110,
        0b0110000,
        0b1101101,
        0b1111001,
        0b0110011,
        0b1011011,
        0b1011111,
        0b1110000,
        0b1111111,
        0b1111011,
    };
    const mask = segment_map[@min(digit, 9)];
    const half = height * 0.5;
    if (mask & 0b1000000 != 0) try scene.line(.{ origin[0], origin[1] + height }, .{ origin[0] + width, origin[1] + height }, color);
    if (mask & 0b0100000 != 0) try scene.line(.{ origin[0] + width, origin[1] + height }, .{ origin[0] + width, origin[1] + half }, color);
    if (mask & 0b0010000 != 0) try scene.line(.{ origin[0] + width, origin[1] + half }, .{ origin[0] + width, origin[1] }, color);
    if (mask & 0b0001000 != 0) try scene.line(.{ origin[0], origin[1] }, .{ origin[0] + width, origin[1] }, color);
    if (mask & 0b0000100 != 0) try scene.line(.{ origin[0], origin[1] + half }, .{ origin[0], origin[1] }, color);
    if (mask & 0b0000010 != 0) try scene.line(.{ origin[0], origin[1] + height }, .{ origin[0], origin[1] + half }, color);
    if (mask & 0b0000001 != 0) try scene.line(.{ origin[0], origin[1] + half }, .{ origin[0] + width, origin[1] + half }, color);
}

fn accentColor(accent: demo.Accent) Color {
    return switch (accent) {
        .cyan => .{ .r = 0.23, .g = 0.72, .b = 1.0 },
        .green => .{ .r = 0.29, .g = 0.94, .b = 0.50 },
        .amber => .{ .r = 1.0, .g = 0.55, .b = 0.10 },
        .violet => .{ .r = 0.88, .g = 0.34, .b = 0.82 },
        .coral => .{ .r = 1.0, .g = 0.31, .b = 0.23 },
    };
}

fn darken(color: Color, factor: f32) Color {
    return .{ .r = color.r * factor, .g = color.g * factor, .b = color.b * factor, .a = color.a };
}

fn vertex(point: [2]f32, color: Color) Vertex {
    return .{
        .position = .{ point[0], point[1], 0, 1 },
        .color = .{ color.r, color.g, color.b, color.a },
    };
}

fn pointOnCircle(center: [2]f32, radius: f32, angle: f32) [2]f32 {
    return .{ center[0] + @cos(angle) * radius, center[1] + @sin(angle) * radius };
}

test "semantic rig projects to finite layered geometry" {
    var scene = Scene{};
    try project(&scene, &demo.rig);
    try std.testing.expect(scene.line_len > 500);
    try std.testing.expect(scene.fill_len > 300);
    try std.testing.expectEqual(@as(usize, 0), scene.line_len % 2);
    try std.testing.expectEqual(@as(usize, 0), scene.fill_len % 3);
    for (scene.lines()) |item| {
        try expectFiniteVertex(item);
    }
    for (scene.fills()) |item| {
        try expectFiniteVertex(item);
    }
}

test "physical pedal layout follows the signal chain from right to left" {
    const board = (Layout{}).board;
    const pedals = try layoutPedalBounds(board, &demo.rig);
    const last_index = demo.rig.pedals.len - 1;
    try std.testing.expect(pedals[0].center()[0] > pedals[last_index].center()[0]);

    const side_input = try projectPedalPort(pedals[0], demo.rig.pedals[0], .input);
    const side_output = try projectPedalPort(pedals[0], demo.rig.pedals[0], .output);
    try std.testing.expect(side_input.socket[0] > side_output.socket[0]);

    const top_input = try projectPedalPort(pedals[1], demo.rig.pedals[1], .input);
    const top_output = try projectPedalPort(pedals[1], demo.rig.pedals[1], .output);
    try std.testing.expect(top_input.socket[0] > top_output.socket[0]);

    const rig_input = try endpointPosition(.rig_input, board, pedals[0..demo.rig.pedals.len], &demo.rig);
    const amp_input = try endpointPosition(.amplifier_input, board, pedals[0..demo.rig.pedals.len], &demo.rig);
    try std.testing.expect(rig_input[0] > amp_input[0]);
}

test "primary rig layout has no browser or signal-chain panels" {
    const layout = Layout{};
    try std.testing.expectApproxEqAbs(@as(f32, -0.98), layout.board.left, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.96), layout.board.width, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, -0.76), layout.board.bottom, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 1.60), layout.board.height, 0.0001);

    var scene = Scene{};
    try projectView(&scene, &demo.rig, .rig);
    try std.testing.expectEqual(@as(usize, 3), scene.hits().len);
    try std.testing.expectEqual(Action.show_rig, scene.hits()[0].action);
    try std.testing.expectEqual(Action.show_amplifier, scene.hits()[1].action);
    try std.testing.expectEqual(Action.show_lighting_lab, scene.hits()[2].action);
}

test "focused amplifier projection exposes a compact rig return" {
    var scene = Scene{};
    try projectStudioView(&scene, &demo.rig, .rig, true);
    try std.testing.expectEqual(@as(usize, 4), scene.hits().len);
    try std.testing.expectEqual(Action.show_rig, scene.hits()[3].action);
}

fn expectFiniteVertex(item: Vertex) !void {
    try std.testing.expect(std.math.isFinite(item.position[0]));
    try std.testing.expect(std.math.isFinite(item.position[1]));
    try std.testing.expect(item.position[0] >= -1.2 and item.position[0] <= 1.2);
    try std.testing.expect(item.position[1] >= -1.2 and item.position[1] <= 1.2);
}
