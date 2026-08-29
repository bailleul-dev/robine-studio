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

pub const Scene = struct {
    pub const max_line_vertices = 12_000;
    pub const max_fill_vertices = 12_000;

    line_vertices: [max_line_vertices]Vertex = undefined,
    line_len: usize = 0,
    fill_vertices: [max_fill_vertices]Vertex = undefined,
    fill_len: usize = 0,

    pub fn lines(self: *const Scene) []const Vertex {
        return self.line_vertices[0..self.line_len];
    }

    pub fn fills(self: *const Scene) []const Vertex {
        return self.fill_vertices[0..self.fill_len];
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
    board: Bounds = .{ .left = -0.98, .bottom = 0.12, .width = 1.48, .height = 0.72 },
    slot_bar: Bounds = .{ .left = -0.98, .bottom = 0.04, .width = 1.48, .height = 0.08 },
    signal: Bounds = .{ .left = -0.98, .bottom = -0.84, .width = 1.48, .height = 0.88 },
    browser: Bounds = .{ .left = 0.50, .bottom = -0.84, .width = 0.48, .height = 1.68 },
    transport: Bounds = .{ .left = -0.98, .bottom = -0.98, .width = 1.96, .height = 0.14 },
};

const palette = struct {
    const background = Color{ .r = 0.014, .g = 0.020, .b = 0.019 };
    const chrome = Color{ .r = 0.045, .g = 0.056, .b = 0.054 };
    const chrome_light = Color{ .r = 0.074, .g = 0.090, .b = 0.087 };
    const surface = Color{ .r = 0.025, .g = 0.035, .b = 0.033 };
    const board_a = Color{ .r = 0.040, .g = 0.033, .b = 0.025 };
    const board_b = Color{ .r = 0.053, .g = 0.041, .b = 0.029 };
    const faint = Color{ .r = 0.13, .g = 0.18, .b = 0.17 };
    const mid = Color{ .r = 0.25, .g = 0.35, .b = 0.33 };
    const bright = Color{ .r = 0.64, .g = 0.88, .b = 0.79 };
    const amber = Color{ .r = 1.0, .g = 0.60, .b = 0.10 };
    const cable = Color{ .r = 1.0, .g = 0.57, .b = 0.08 };
    const blue = Color{ .r = 0.08, .g = 0.55, .b = 1.0 };
    const green = Color{ .r = 0.20, .g = 0.94, .b = 0.50 };
};

pub fn project(scene: *Scene, rig: *const demo.Rig) !void {
    scene.* = Scene{};
    const layout = Layout{};

    try scene.fillRectangle(.{ .left = -1, .bottom = -1, .width = 2, .height = 2 }, palette.background);
    try drawToolbar(scene, layout.toolbar);
    const pedal_bounds = try drawPedalboard(scene, layout.board, rig.pedals);
    try drawSlotBar(scene, layout.slot_bar, pedal_bounds[0..rig.pedals.len]);
    try drawSignalChain(scene, layout.signal, rig);
    try drawBrowser(scene, layout.browser);
    try drawTransport(scene, layout.transport);
    try drawMainConnections(scene, layout.board, pedal_bounds[0..rig.pedals.len], rig.connections);
}

fn drawToolbar(scene: *Scene, bounds: Bounds) !void {
    try scene.fillRectangle(bounds, palette.chrome);
    try scene.line(.{ bounds.left, bounds.bottom }, .{ bounds.right(), bounds.bottom }, palette.faint);

    const preset = Bounds{ .left = bounds.left + 0.015, .bottom = bounds.bottom + 0.018, .width = 0.095, .height = bounds.height - 0.036 };
    try scene.fillRectangle(preset, palette.surface);
    try scene.rectangle(preset, palette.faint);
    try drawDigit(scene, .{ preset.left + 0.018, preset.bottom + 0.018 }, 0.018, 0.046, 0, palette.amber);
    try drawDigit(scene, .{ preset.left + 0.043, preset.bottom + 0.018 }, 0.018, 0.046, 0, palette.amber);
    try drawDigit(scene, .{ preset.left + 0.068, preset.bottom + 0.018 }, 0.018, 0.046, 1, palette.amber);

    const folder = Bounds{ .left = preset.right() + 0.012, .bottom = preset.bottom, .width = 0.072, .height = preset.height };
    try scene.fillRectangle(folder, palette.chrome_light);
    try scene.rectangle(folder, palette.faint);
    try scene.rectangle(folder.inset(0.020), palette.mid);
    try scene.line(.{ folder.left + 0.022, folder.top() - 0.021 }, .{ folder.left + 0.042, folder.top() - 0.021 }, palette.mid);

    const title_bar = Bounds{ .left = folder.right() + 0.012, .bottom = preset.bottom, .width = 0.30, .height = preset.height };
    try scene.fillRectangle(title_bar, palette.surface);
    try scene.rectangle(title_bar, palette.faint);
    try drawWave(scene, title_bar.inset(0.018), palette.mid);

    const logo_center = [2]f32{ bounds.left + bounds.width * 0.50, bounds.bottom + bounds.height * 0.53 };
    try scene.line(.{ logo_center[0] - 0.13, logo_center[1] }, .{ logo_center[0] + 0.13, logo_center[1] }, palette.mid);
    try scene.circle(logo_center, 0.026, palette.bright);
    try scene.circle(logo_center, 0.014, palette.amber);

    var x = bounds.right() - 0.30;
    var index: usize = 0;
    while (index < 4) : (index += 1) {
        const cell = Bounds{ .left = x, .bottom = preset.bottom, .width = 0.062, .height = preset.height };
        try scene.fillRectangle(cell, if (index == 0) palette.surface else palette.chrome_light);
        try scene.rectangle(cell, palette.faint);
        if (index == 0) {
            try scene.circle(cell.center(), 0.014, palette.amber);
            try scene.circle(.{ cell.center()[0] + 0.018, cell.center()[1] }, 0.014, palette.amber);
        } else if (index == 3) {
            var bar: usize = 0;
            while (bar < 3) : (bar += 1) {
                const y = cell.bottom + 0.024 + @as(f32, @floatFromInt(bar)) * 0.018;
                try scene.line(.{ cell.left + 0.015, y }, .{ cell.right() - 0.015, y }, palette.bright);
            }
        } else {
            try scene.circle(cell.center(), 0.020, if (index == 1) palette.mid else palette.bright);
        }
        x += 0.068;
    }
}

fn drawPedalboard(scene: *Scene, bounds: Bounds, pedals: []const demo.Pedal) ![8]Bounds {
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

    var weights: [8]f32 = undefined;
    var total_weight: f32 = 0;
    for (pedals, 0..) |pedal, index| {
        weights[index] = pedal.enclosure.footprint_units;
        total_weight += weights[index];
    }

    const gap: f32 = 0.026;
    const margin: f32 = 0.025;
    const available = bounds.width - margin * 2.0 - gap * @as(f32, @floatFromInt(pedals.len - 1));
    var cursor = bounds.left + margin;
    var result: [8]Bounds = undefined;
    for (pedals, 0..) |pedal, index| {
        const width = available * weights[index] / total_weight;
        const pedal_bounds = Bounds{
            .left = cursor,
            .bottom = bounds.bottom + 0.115,
            .width = width,
            .height = bounds.height - 0.22,
        };
        result[index] = pedal_bounds;
        if (pedal.presentation == .open)
            try drawOpenPedal(scene, pedal_bounds, &pedal)
        else
            try drawClosedPedal(scene, pedal_bounds, &pedal);
        cursor += width + gap;
    }

    return result;
}

fn drawClosedPedal(scene: *Scene, bounds: Bounds, pedal: *const demo.Pedal) !void {
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
    try drawJacks(scene, bounds);
}

fn drawOpenPedal(scene: *Scene, bounds: Bounds, pedal: *const demo.Pedal) !void {
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
    try drawJacks(scene, bounds);
}

fn drawJacks(scene: *Scene, bounds: Bounds) !void {
    const input = [2]f32{ bounds.left, bounds.top() - 0.12 };
    const output = [2]f32{ bounds.right(), bounds.top() - 0.12 };
    try scene.fillCircle(input, 0.014, palette.chrome);
    try scene.circle(input, 0.018, palette.cable);
    try scene.fillCircle(output, 0.014, palette.chrome);
    try scene.circle(output, 0.018, palette.cable);
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

fn drawSlotBar(scene: *Scene, bounds: Bounds, pedals: []const Bounds) !void {
    try scene.fillRectangle(bounds, palette.chrome);
    try scene.line(.{ bounds.left, bounds.top() }, .{ bounds.right(), bounds.top() }, palette.faint);
    for (pedals, 0..) |pedal, index| {
        const slot = Bounds{ .left = pedal.left, .bottom = bounds.bottom + 0.010, .width = pedal.width, .height = bounds.height - 0.020 };
        try scene.fillRectangle(slot, palette.surface);
        try scene.rectangle(slot, palette.faint);
        const power = [2]f32{ slot.left + 0.025, slot.bottom + slot.height * 0.5 };
        try scene.circle(power, 0.010, if (index == 1) palette.cable else palette.amber);
        try scene.line(power, .{ power[0], power[1] + 0.015 }, palette.amber);
        try scene.line(.{ slot.right() - 0.022, slot.top() - 0.018 }, .{ slot.right() - 0.013, slot.top() - 0.028 }, palette.mid);
        try scene.line(.{ slot.right() - 0.013, slot.top() - 0.028 }, .{ slot.right() - 0.004, slot.top() - 0.018 }, palette.mid);
    }
}

fn drawMainConnections(scene: *Scene, board: Bounds, pedals: []const Bounds, connections: []const demo.Connection) !void {
    for (pedals, 0..) |pedal, index| {
        const top_input = [2]f32{ pedal.left + pedal.width * 0.28, pedal.top() };
        const top_output = [2]f32{ pedal.left + pedal.width * 0.72, pedal.top() };
        const rail_y = board.top() - 0.035 - @as(f32, @floatFromInt(index % 2)) * 0.025;
        try scene.line(top_input, .{ top_input[0], rail_y }, palette.cable);
        try scene.line(top_output, .{ top_output[0], rail_y }, palette.cable);
        try scene.circle(top_input, 0.010, palette.cable);
        try scene.circle(top_output, 0.010, palette.cable);
    }

    for (connections) |connection| {
        const from = endpointPosition(connection.from, board, pedals);
        const to = endpointPosition(connection.to, board, pedals);
        const route_y = @max(from[1], to[1]) + 0.035;
        try scene.line(from, .{ from[0], route_y }, palette.cable);
        try scene.line(.{ from[0], route_y }, .{ to[0], route_y }, palette.cable);
        try scene.line(.{ to[0], route_y }, to, palette.cable);
    }
}

fn endpointPosition(endpoint: demo.Endpoint, board: Bounds, pedals: []const Bounds) [2]f32 {
    return switch (endpoint) {
        .rig_input => .{ board.left + 0.008, pedals[0].top() - 0.12 },
        .pedal_input => |index| .{ pedals[index].left, pedals[index].top() - 0.12 },
        .pedal_output => |index| .{ pedals[index].right(), pedals[index].top() - 0.12 },
        .amplifier_input => .{ board.right() - 0.008, pedals[pedals.len - 1].top() - 0.12 },
    };
}

fn drawSignalChain(scene: *Scene, bounds: Bounds, rig: *const demo.Rig) !void {
    try scene.fillRectangle(bounds, palette.surface);
    try scene.rectangle(bounds, palette.faint);

    const rail_y = bounds.bottom + bounds.height * 0.43;
    const input_x = bounds.left + 0.08;
    const output_x = bounds.right() - 0.07;
    try scene.line(.{ input_x, rail_y }, .{ output_x, rail_y }, palette.cable);
    try scene.line(.{ input_x + 0.08, rail_y }, .{ input_x + 0.08, bounds.bottom + 0.12 }, palette.blue);
    try scene.line(.{ input_x + 0.08, bounds.bottom + 0.12 }, .{ output_x - 0.06, bounds.bottom + 0.12 }, palette.blue);
    try scene.line(.{ output_x - 0.06, bounds.bottom + 0.12 }, .{ output_x - 0.06, rail_y }, palette.blue);

    try scene.circle(.{ input_x, rail_y }, 0.025, palette.bright);
    try scene.line(.{ input_x - 0.035, rail_y }, .{ input_x - 0.010, rail_y }, palette.bright);

    const pedal_start = input_x + 0.13;
    const pedal_spacing: f32 = 0.095;
    for (rig.pedals, 0..) |pedal, index| {
        const node = Bounds{
            .left = pedal_start + @as(f32, @floatFromInt(index)) * pedal_spacing,
            .bottom = rail_y - 0.055,
            .width = if (pedal.enclosure.form_factor == .double) 0.072 else 0.050,
            .height = 0.110,
        };
        try drawMiniPedal(scene, node, accentColor(pedal.accent), index == 3);
    }

    const split = [2]f32{ pedal_start + pedal_spacing * 5.35, rail_y };
    try scene.fillRectangle(.{ .left = split[0] - 0.025, .bottom = split[1] - 0.025, .width = 0.050, .height = 0.050 }, palette.chrome_light);
    try scene.rectangle(.{ .left = split[0] - 0.025, .bottom = split[1] - 0.025, .width = 0.050, .height = 0.050 }, palette.mid);

    const amp = Bounds{ .left = split[0] + 0.09, .bottom = rail_y - 0.16, .width = 0.25, .height = 0.11 };
    const cab = Bounds{ .left = amp.right() + 0.05, .bottom = rail_y - 0.17, .width = 0.13, .height = 0.13 };
    try drawMiniAmplifier(scene, amp, rig.amplifier.controls.len);
    try drawMiniCabinet(scene, cab, rig.cabinet.speaker_count);
    try scene.line(split, .{ split[0] + 0.045, split[1] }, palette.cable);
    try scene.line(.{ split[0] + 0.045, split[1] }, .{ split[0] + 0.045, amp.top() - 0.025 }, palette.cable);
    try scene.line(.{ split[0] + 0.045, amp.top() - 0.025 }, .{ amp.left, amp.top() - 0.025 }, palette.cable);
    try scene.line(.{ amp.right(), amp.bottom + amp.height * 0.5 }, .{ cab.left, cab.bottom + cab.height * 0.5 }, palette.cable);
    try scene.line(.{ cab.right(), cab.bottom + cab.height * 0.5 }, .{ output_x, rail_y }, palette.cable);

    const alternate_amp = Bounds{ .left = amp.left + 0.02, .bottom = rail_y + 0.13, .width = 0.20, .height = 0.09 };
    const alternate_cab = Bounds{ .left = alternate_amp.right() + 0.05, .bottom = rail_y + 0.11, .width = 0.11, .height = 0.12 };
    try drawMiniAmplifier(scene, alternate_amp, 4);
    try drawMiniCabinet(scene, alternate_cab, 1);
    try scene.line(split, .{ split[0] + 0.045, split[1] }, palette.cable);
    try scene.line(.{ split[0] + 0.045, split[1] }, .{ split[0] + 0.045, alternate_amp.bottom + 0.025 }, palette.cable);
    try scene.line(.{ split[0] + 0.045, alternate_amp.bottom + 0.025 }, .{ alternate_amp.left, alternate_amp.bottom + 0.025 }, palette.cable);
    try scene.line(.{ alternate_amp.right(), alternate_amp.bottom + alternate_amp.height * 0.5 }, .{ alternate_cab.left, alternate_cab.bottom + alternate_cab.height * 0.5 }, palette.cable);
    try scene.line(.{ alternate_cab.right(), alternate_cab.bottom + alternate_cab.height * 0.5 }, .{ output_x, rail_y }, palette.cable);

    try scene.fillCircle(.{ output_x, rail_y }, 0.028, palette.chrome_light);
    try scene.circle(.{ output_x, rail_y }, 0.028, palette.bright);
    try scene.line(.{ output_x + 0.035, rail_y }, .{ output_x + 0.070, rail_y }, palette.bright);
}

fn drawMiniPedal(scene: *Scene, bounds: Bounds, accent: Color, selected: bool) !void {
    try scene.fillRectangle(bounds, darken(accent, 0.14));
    try scene.rectangle(bounds, if (selected) palette.amber else accent);
    try scene.circle(.{ bounds.left + bounds.width * 0.34, bounds.top() - 0.027 }, 0.009, accent);
    try scene.circle(.{ bounds.left + bounds.width * 0.66, bounds.top() - 0.027 }, 0.009, accent);
    try scene.circle(.{ bounds.left + bounds.width * 0.5, bounds.bottom + 0.022 }, 0.013, palette.bright);
}

fn drawMiniAmplifier(scene: *Scene, bounds: Bounds, control_count: usize) !void {
    try scene.fillRectangle(bounds, Color{ .r = 0.10, .g = 0.065, .b = 0.025 });
    try scene.rectangle(bounds, palette.cable);
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
    try scene.fillRectangle(bounds, palette.chrome);
    try scene.line(.{ bounds.left, bounds.top() }, .{ bounds.right(), bounds.top() }, palette.faint);

    const meter_left = Bounds{ .left = bounds.left + 0.020, .bottom = bounds.bottom + 0.032, .width = 0.18, .height = 0.050 };
    try drawMeter(scene, meter_left, 0.66);

    const controls = Bounds{ .left = bounds.left + 0.25, .bottom = bounds.bottom + 0.016, .width = 0.44, .height = bounds.height - 0.032 };
    try scene.fillRectangle(controls, palette.surface);
    try scene.rectangle(controls, palette.faint);
    const record = [2]f32{ controls.left + 0.085, controls.center()[1] };
    try scene.fillCircle(record, 0.022, palette.bright);
    const play_center = [2]f32{ controls.left + 0.16, controls.center()[1] };
    try scene.triangle(.{ play_center[0] - 0.015, play_center[1] - 0.024 }, .{ play_center[0] - 0.015, play_center[1] + 0.024 }, .{ play_center[0] + 0.025, play_center[1] }, palette.bright);
    try scene.line(.{ controls.left + 0.235, controls.center()[1] - 0.022 }, .{ controls.left + 0.235, controls.center()[1] + 0.022 }, palette.bright);
    try scene.line(.{ controls.left + 0.245, controls.center()[1] }, .{ controls.left + 0.280, controls.center()[1] + 0.022 }, palette.bright);
    try scene.line(.{ controls.left + 0.245, controls.center()[1] }, .{ controls.left + 0.280, controls.center()[1] - 0.022 }, palette.bright);
    try scene.circle(.{ controls.left + 0.345, controls.center()[1] }, 0.023, palette.amber);
    try scene.line(.{ controls.left + 0.327, controls.center()[1] + 0.015 }, .{ controls.left + 0.360, controls.center()[1] + 0.015 }, palette.amber);

    const display = Bounds{ .left = controls.right() + 0.030, .bottom = controls.bottom, .width = 0.33, .height = controls.height };
    try scene.fillRectangle(display, palette.surface);
    try scene.rectangle(display, palette.faint);
    var x = display.left + 0.030;
    const digits = [_]u8{ 0, 0, 1, 1, 0, 1 };
    for (digits, 0..) |digit, index| {
        try drawDigit(scene, .{ x, display.bottom + 0.020 }, 0.024, 0.056, digit, if (index < 2) palette.bright else palette.mid);
        x += 0.040;
        if (index == 1 or index == 3) x += 0.012;
    }

    const meter_right = Bounds{ .left = bounds.right() - 0.205, .bottom = bounds.bottom + 0.032, .width = 0.18, .height = 0.050 };
    try drawMeter(scene, meter_right, 0.78);
}

fn drawMeter(scene: *Scene, bounds: Bounds, level: f32) !void {
    try scene.fillRectangle(bounds, palette.surface);
    try scene.rectangle(bounds, palette.faint);
    const bar_count = 14;
    var index: usize = 0;
    while (index < bar_count) : (index += 1) {
        const active = @as(f32, @floatFromInt(index)) / bar_count < level;
        const bar = Bounds{
            .left = bounds.left + 0.006 + @as(f32, @floatFromInt(index)) * (bounds.width - 0.012) / bar_count,
            .bottom = bounds.bottom + 0.010,
            .width = (bounds.width - 0.020) / bar_count,
            .height = bounds.height - 0.020,
        };
        try scene.fillRectangle(bar, if (active) (if (index > 10) palette.amber else palette.green) else palette.faint);
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

fn expectFiniteVertex(item: Vertex) !void {
    try std.testing.expect(std.math.isFinite(item.position[0]));
    try std.testing.expect(std.math.isFinite(item.position[1]));
    try std.testing.expect(item.position[0] >= -1.2 and item.position[0] <= 1.2);
    try std.testing.expect(item.position[1] >= -1.2 and item.position[1] <= 1.2);
}
