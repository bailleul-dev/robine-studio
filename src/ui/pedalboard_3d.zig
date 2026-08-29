const std = @import("std");
const demo = @import("../model/demo.zig");
const lighting = @import("lighting_lab.zig");

pub const Vertex = lighting.Vertex;
pub const Material = lighting.Material;

pub const EmissiveLight = struct {
    position: [3]f32,
    radius: f32,
    color: [3]f32,
    intensity: f32,
};

pub const ViewProfile = struct {
    camera: [3]f32,
    target: [3]f32,
    key_position: [3]f32,
    key_size: [2]f32,
    key_intensity: f32,
    exposure: f32,
    environment_strength: f32,
    fill_radiance: [3]f32,
};

pub const studio_profile = ViewProfile{
    .camera = .{ 0, 10.8, 4.8 },
    .target = .{ 0, 0.52, 0.10 },
    .key_position = .{ -9.0, 10.0, 6.5 },
    .key_size = .{ 3.2, 9.0 },
    .key_intensity = 520.0,
    .exposure = 1.42,
    .environment_strength = 0.88,
    .fill_radiance = .{ 0.90, 1.20, 1.60 },
};

pub const Mesh = struct {
    pub const max_vertices = 80_000;
    pub const max_emissive_lights = 16;

    vertices: [max_vertices]Vertex = undefined,
    len: usize = 0,
    emissive_lights: [max_emissive_lights]EmissiveLight = undefined,
    emissive_light_len: usize = 0,

    pub fn items(self: *const Mesh) []const Vertex {
        return self.vertices[0..self.len];
    }

    pub fn emissiveLights(self: *const Mesh) []const EmissiveLight {
        return self.emissive_lights[0..self.emissive_light_len];
    }

    fn triangle(self: *Mesh, a: Vertex, b: Vertex, c: Vertex) !void {
        if (self.len + 3 > self.vertices.len) return error.MeshCapacityExceeded;
        self.vertices[self.len] = a;
        self.vertices[self.len + 1] = b;
        self.vertices[self.len + 2] = c;
        self.len += 3;
    }

    fn addEmissiveLight(self: *Mesh, light: EmissiveLight) !void {
        if (self.emissive_light_len >= self.emissive_lights.len) return error.TooManyEmissiveLights;
        self.emissive_lights[self.emissive_light_len] = light;
        self.emissive_light_len += 1;
    }
};

const materials = struct {
    const board_base = Material{ .base_color = .{ 0.032, 0.022, 0.016 }, .roughness = 0.72, .metallic = 0.08 };
    const wood_a = Material{ .base_color = .{ 0.115, 0.052, 0.021 }, .roughness = 0.58, .metallic = 0.02 };
    const wood_b = Material{ .base_color = .{ 0.075, 0.030, 0.014 }, .roughness = 0.66, .metallic = 0.02 };
    const wood_c = Material{ .base_color = .{ 0.145, 0.070, 0.030 }, .roughness = 0.61, .metallic = 0.02 };
    const black_metal = Material{ .base_color = .{ 0.025, 0.032, 0.031 }, .roughness = 0.19, .metallic = 0.82 };
    const chrome = Material{ .base_color = .{ 0.48, 0.52, 0.50 }, .roughness = 0.14, .metallic = 1.0 };
    const polished_chrome = Material{ .base_color = .{ 0.76, 0.80, 0.78 }, .roughness = 0.055, .metallic = 1.0 };
    const knob_plastic = Material{ .base_color = .{ 0.018, 0.022, 0.021 }, .roughness = 0.28, .metallic = 0.04 };
    const knob_indicator = Material{ .base_color = .{ 0.92, 0.84, 0.58 }, .roughness = 0.34, .metallic = 0.02 };
    const rubber = Material{ .base_color = .{ 0.012, 0.015, 0.014 }, .roughness = 0.78, .metallic = 0.0 };
    const pcb = Material{ .base_color = .{ 0.025, 0.19, 0.105 }, .roughness = 0.38, .metallic = 0.08 };
    const pointer = Material{ .base_color = .{ 0.95, 0.67, 0.18 }, .roughness = 0.28, .metallic = 0.30 };
};

const Axis = enum { x, y, z };

const LatheRing = struct {
    height: f32,
    radius: f32,
};

pub fn build(mesh: *Mesh, rig: *const demo.Rig) !void {
    mesh.* = .{};
    try addPedalboard(mesh);

    const millimetres_to_world: f32 = 0.022;
    const gap: f32 = 0.30;
    var total_width: f32 = gap * @as(f32, @floatFromInt(rig.pedals.len - 1));
    for (rig.pedals) |pedal| total_width += pedal.enclosure.dimensions.width * millimetres_to_world;

    var cursor = total_width * 0.5;
    for (rig.pedals) |pedal| {
        const width = pedal.enclosure.dimensions.width * millimetres_to_world;
        const depth = pedal.enclosure.dimensions.depth * millimetres_to_world;
        const height = pedal.enclosure.dimensions.height * millimetres_to_world;
        const center_x = cursor - width * 0.5;
        try addPedal(mesh, pedal, .{ center_x, 0.24, 0 }, .{ width, height, depth });
        cursor -= width + gap;
    }
}

fn addPedalboard(mesh: *Mesh) !void {
    const floor_width: f32 = 19.2;
    const floor_depth: f32 = 11.5;
    const column_count: usize = 17;
    const plank_length: f32 = 7.4;
    const groove: f32 = 0.055;
    const plank_width = (floor_width - groove * @as(f32, @floatFromInt(column_count - 1))) /
        @as(f32, @floatFromInt(column_count));

    try addBox(mesh, .{ 0, -0.02, 0 }, .{ floor_width + 0.28, 0.38, floor_depth + 0.28 }, materials.board_base);

    for (0..column_count) |column| {
        const x = -floor_width * 0.5 + plank_width * 0.5 +
            @as(f32, @floatFromInt(column)) * (plank_width + groove);
        const stagger = switch (column % 3) {
            0 => 0.0,
            1 => plank_length * 0.34,
            else => plank_length * 0.67,
        };
        var front = -floor_depth * 0.5 - stagger;
        var segment: usize = 0;
        while (front < floor_depth * 0.5) : ({
            front += plank_length;
            segment += 1;
        }) {
            const visible_front = @max(front, -floor_depth * 0.5);
            const visible_back = @min(front + plank_length - groove, floor_depth * 0.5);
            const visible_depth = visible_back - visible_front;
            if (visible_depth <= 0.08) continue;
            const material = switch ((column * 2 + segment) % 3) {
                0 => materials.wood_a,
                1 => materials.wood_b,
                else => materials.wood_c,
            };
            try addBox(mesh, .{ x, 0.18, (visible_front + visible_back) * 0.5 }, .{
                plank_width,
                0.20,
                visible_depth,
            }, material);
        }
    }
}

fn addPedal(mesh: *Mesh, pedal: demo.Pedal, base: [3]f32, size: [3]f32) !void {
    const body_material = accentMaterial(pedal.accent);
    if (pedal.presentation == .open) {
        const tray_height = size[1] * 0.42;
        try addBeveledBox(mesh, .{ base[0], base[1] + tray_height * 0.5, base[2] }, .{ size[0], tray_height, size[2] }, 0.10, darkened(body_material, 0.55));
        try addBox(mesh, .{ base[0], base[1] + tray_height + 0.035, base[2] }, .{ size[0] * 0.78, 0.07, size[2] * 0.72 }, materials.pcb);
        try addOpenLid(mesh, base, size, body_material);
        try addComponents(mesh, base, size, tray_height);
    } else {
        try addBeveledBox(mesh, .{ base[0], base[1] + size[1] * 0.5, base[2] }, size, 0.10, body_material);
        try addControls(mesh, pedal, base, size);
        try addFootswitches(mesh, pedal, base, size);
    }
    try addPorts(mesh, pedal, base, size);
}

fn addOpenLid(mesh: *Mesh, base: [3]f32, size: [3]f32, material: Material) !void {
    const lid_center = [3]f32{ base[0], base[1] + size[1] * 0.82, base[2] - size[2] * 0.53 };
    try addBox(mesh, lid_center, .{ size[0] * 0.96, size[1] * 1.25, 0.12 }, material);
    try addBox(mesh, .{ lid_center[0], lid_center[1], lid_center[2] + 0.07 }, .{ size[0] * 0.76, size[1] * 0.96, 0.04 }, darkened(material, 0.18));
}

fn addComponents(mesh: *Mesh, base: [3]f32, size: [3]f32, tray_height: f32) !void {
    const top = base[1] + tray_height + 0.10;
    var row: usize = 0;
    while (row < 3) : (row += 1) {
        var column: usize = 0;
        while (column < 3) : (column += 1) {
            const x = base[0] + (@as(f32, @floatFromInt(column)) - 1.0) * size[0] * 0.23;
            const z = base[2] + (@as(f32, @floatFromInt(row)) - 1.0) * size[2] * 0.18;
            const material = if ((row + column) % 2 == 0) materials.pointer else materials.black_metal;
            try addBox(mesh, .{ x, top + 0.055, z }, .{ size[0] * 0.13, 0.11, size[2] * 0.08 }, material);
        }
    }
}

fn addControls(mesh: *Mesh, pedal: demo.Pedal, base: [3]f32, size: [3]f32) !void {
    const count = pedal.controls.len;
    if (count == 0) return;
    const columns: usize = if (pedal.enclosure.form_factor == .double) @min(count, 4) else @min(count, 2);
    const rows = (count + columns - 1) / columns;
    const radius = @min(0.27, size[0] / (@as(f32, @floatFromInt(columns)) * 3.4));
    for (pedal.controls, 0..) |control, index| {
        const column = index % columns;
        const row = index / columns;
        const x = base[0] + size[0] * ((@as(f32, @floatFromInt(column)) + 0.5) / @as(f32, @floatFromInt(columns)) - 0.5) * 0.78;
        const z = base[2] - size[2] * 0.25 + @as(f32, @floatFromInt(row)) * size[2] * 0.22 / @as(f32, @floatFromInt(@max(rows, 1)));
        const knob_base = base[1] + size[1];
        const angle = (-0.75 + control.normalized_value * 1.5) * std.math.pi;
        try addChickenHeadKnob(mesh, .{ x, knob_base, z }, radius, angle);
    }
}

fn addFootswitches(mesh: *Mesh, pedal: demo.Pedal, base: [3]f32, size: [3]f32) !void {
    const count = @max(@as(usize, 1), @as(usize, pedal.footswitch_count));
    const brightness = std.math.clamp(pedal.indicator_brightness, 0, 1);
    for (0..count) |index| {
        const x = base[0] + size[0] * ((@as(f32, @floatFromInt(index)) + 1.0) / @as(f32, @floatFromInt(count + 1)) - 0.5) * 0.72;
        const z = base[2] + size[2] * 0.29;
        const top = base[1] + size[1];
        const led_z = z - size[2] * 0.16;
        try addFootswitchHardware(mesh, .{ x, top, z });
        try addIndicatorWasher(mesh, .{ x, top + 0.004, led_z }, 0.063, 0.112);
        try addCylinder(mesh, .{ x, top + 0.072, led_z }, 0.060, 0.080, ledLensMaterial(brightness), .y);
        try addCylinder(mesh, .{ x, top + 0.126, led_z }, 0.018, 0.024, ledCoreMaterial(brightness), .y);
        try mesh.addEmissiveLight(.{
            .position = .{ x, top + 0.16, led_z },
            .radius = 0.62,
            .color = .{ 0.012, 1.0, 0.075 },
            .intensity = 1.55 * brightness,
        });
    }
}

fn addChickenHeadKnob(mesh: *Mesh, origin: [3]f32, radius: f32, angle: f32) !void {
    const direction = [3]f32{ @sin(angle), 0, -@cos(angle) };
    const perpendicular = [3]f32{ @cos(angle), 0, @sin(angle) };
    const skirt_profile = [_]LatheRing{
        .{ .height = 0.00, .radius = radius * 1.22 },
        .{ .height = 0.08, .radius = radius * 1.22 },
        .{ .height = 0.13, .radius = radius * 1.02 },
        .{ .height = 0.18, .radius = radius * 0.76 },
    };
    try addLathedY(mesh, origin, &skirt_profile, materials.knob_plastic);
    try addBeveledChickenGrip(mesh, origin, direction, perpendicular, radius);

    const stripe_center = knobPoint(origin, direction, perpendicular, radius * 0.22, 0, 0.512);
    try addOrientedBox(mesh, stripe_center, direction, perpendicular, radius * 0.060, radius * 0.48, 0.018, materials.knob_indicator);

    const stripe_top_left = knobPoint(origin, direction, perpendicular, radius * 0.728, -radius * 0.060, 0.475);
    const stripe_top_right = knobPoint(origin, direction, perpendicular, radius * 0.728, radius * 0.060, 0.475);
    const stripe_bottom_right = knobPoint(origin, direction, perpendicular, radius * 0.728, radius * 0.060, 0.18);
    const stripe_bottom_left = knobPoint(origin, direction, perpendicular, radius * 0.728, -radius * 0.060, 0.18);
    try addQuad(mesh, stripe_top_left, stripe_bottom_left, stripe_bottom_right, stripe_top_right, direction, materials.knob_indicator);
}

fn addBeveledChickenGrip(mesh: *Mesh, origin: [3]f32, direction: [3]f32, perpendicular: [3]f32, radius: f32) !void {
    const footprint = [_][2]f32{
        .{ -0.52, -0.30 },
        .{ -0.40, -0.44 },
        .{ 0.50, -0.44 },
        .{ 0.72, -0.28 },
        .{ 0.72, 0.28 },
        .{ 0.50, 0.44 },
        .{ -0.40, 0.44 },
        .{ -0.52, 0.30 },
    };
    const lower_height: f32 = 0.12;
    const shoulder_height: f32 = 0.43;
    const top_height: f32 = 0.50;
    const top_scale: f32 = 0.86;

    for (0..footprint.len) |index| {
        const next = (index + 1) % footprint.len;
        const lower0 = knobPoint(origin, direction, perpendicular, footprint[index][0] * radius, footprint[index][1] * radius, lower_height);
        const lower1 = knobPoint(origin, direction, perpendicular, footprint[next][0] * radius, footprint[next][1] * radius, lower_height);
        const shoulder0 = knobPoint(origin, direction, perpendicular, footprint[index][0] * radius, footprint[index][1] * radius, shoulder_height);
        const shoulder1 = knobPoint(origin, direction, perpendicular, footprint[next][0] * radius, footprint[next][1] * radius, shoulder_height);
        const top0 = knobPoint(origin, direction, perpendicular, footprint[index][0] * radius * top_scale, footprint[index][1] * radius * top_scale, top_height);
        const top1 = knobPoint(origin, direction, perpendicular, footprint[next][0] * radius * top_scale, footprint[next][1] * radius * top_scale, top_height);
        const edge = [3]f32{ lower1[0] - lower0[0], 0, lower1[2] - lower0[2] };
        const outward = normalized3(.{ edge[2], 0, -edge[0] });
        const bevel_normal = normalized3(.{ outward[0] * 0.68, 0.74, outward[2] * 0.68 });
        try addSmoothQuad(mesh, lower0, lower1, shoulder1, shoulder0, outward, outward, outward, outward, materials.knob_plastic);
        try addSmoothQuad(mesh, shoulder0, shoulder1, top1, top0, bevel_normal, bevel_normal, bevel_normal, bevel_normal, materials.knob_plastic);
    }

    const top_center = [3]f32{ origin[0], origin[1] + top_height, origin[2] };
    for (0..footprint.len) |index| {
        const next = (index + 1) % footprint.len;
        const top0 = knobPoint(origin, direction, perpendicular, footprint[index][0] * radius * top_scale, footprint[index][1] * radius * top_scale, top_height);
        const top1 = knobPoint(origin, direction, perpendicular, footprint[next][0] * radius * top_scale, footprint[next][1] * radius * top_scale, top_height);
        try mesh.triangle(vertex(top_center, .{ 0, 1, 0 }, materials.knob_plastic), vertex(top1, .{ 0, 1, 0 }, materials.knob_plastic), vertex(top0, .{ 0, 1, 0 }, materials.knob_plastic));
    }
}

fn addFootswitchHardware(mesh: *Mesh, origin: [3]f32) !void {
    try addCylinderSegments(mesh, .{ origin[0], origin[1] + 0.027, origin[2] }, 0.23, 0.054, materials.polished_chrome, .y, 6);
    try addIndicatorWasher(mesh, .{ origin[0], origin[1] + 0.052, origin[2] }, 0.112, 0.205);
    const actuator_profile = [_]LatheRing{
        .{ .height = 0.00, .radius = 0.112 },
        .{ .height = 0.10, .radius = 0.112 },
        .{ .height = 0.125, .radius = 0.155 },
        .{ .height = 0.215, .radius = 0.155 },
        .{ .height = 0.240, .radius = 0.140 },
    };
    try addLathedY(mesh, .{ origin[0], origin[1] + 0.060, origin[2] }, &actuator_profile, materials.polished_chrome);
}

fn knobPoint(origin: [3]f32, direction: [3]f32, perpendicular: [3]f32, along: f32, lateral: f32, height: f32) [3]f32 {
    return .{
        origin[0] + direction[0] * along + perpendicular[0] * lateral,
        origin[1] + height,
        origin[2] + direction[2] * along + perpendicular[2] * lateral,
    };
}

fn addOrientedBox(
    mesh: *Mesh,
    center: [3]f32,
    direction: [3]f32,
    perpendicular: [3]f32,
    half_width: f32,
    half_length: f32,
    height: f32,
    material: Material,
) !void {
    const bottom_center = [3]f32{ center[0], center[1] - height * 0.5, center[2] };
    const top_center = [3]f32{ center[0], center[1] + height * 0.5, center[2] };
    const bottom_back_left = knobPoint(bottom_center, direction, perpendicular, -half_length, -half_width, 0);
    const bottom_back_right = knobPoint(bottom_center, direction, perpendicular, -half_length, half_width, 0);
    const bottom_front_left = knobPoint(bottom_center, direction, perpendicular, half_length, -half_width, 0);
    const bottom_front_right = knobPoint(bottom_center, direction, perpendicular, half_length, half_width, 0);
    const top_back_left = knobPoint(top_center, direction, perpendicular, -half_length, -half_width, 0);
    const top_back_right = knobPoint(top_center, direction, perpendicular, -half_length, half_width, 0);
    const top_front_left = knobPoint(top_center, direction, perpendicular, half_length, -half_width, 0);
    const top_front_right = knobPoint(top_center, direction, perpendicular, half_length, half_width, 0);
    try addQuad(mesh, top_back_left, top_back_right, top_front_right, top_front_left, .{ 0, 1, 0 }, material);
    try addQuad(mesh, bottom_front_left, bottom_front_right, bottom_back_right, bottom_back_left, .{ 0, -1, 0 }, material);
    try addQuad(mesh, bottom_back_left, top_back_left, top_front_left, bottom_front_left, .{ -perpendicular[0], 0, -perpendicular[2] }, material);
    try addQuad(mesh, bottom_front_right, top_front_right, top_back_right, bottom_back_right, perpendicular, material);
    try addQuad(mesh, bottom_back_right, top_back_right, top_back_left, bottom_back_left, .{ -direction[0], 0, -direction[2] }, material);
    try addQuad(mesh, bottom_front_left, top_front_left, top_front_right, bottom_front_right, direction, material);
}

fn addPorts(mesh: *Mesh, pedal: demo.Pedal, base: [3]f32, size: [3]f32) !void {
    for (pedal.ports) |port| {
        const slot: f32 = switch (port.slot) {
            .start => -0.30,
            .center => 0,
            .end => 0.30,
        };
        switch (port.surface) {
            .top => {
                const x = base[0] + slot * size[0];
                const z = base[2] - size[2] * 0.39;
                try addCylinder(mesh, .{ x, base[1] + size[1] + 0.08, z }, 0.14, 0.16, materials.chrome, .y);
                try addCylinder(mesh, .{ x, base[1] + size[1] + 0.17, z }, 0.075, 0.08, materials.rubber, .y);
            },
            .left_side => {
                const x = base[0] - size[0] * 0.5 - 0.06;
                try addCylinder(mesh, .{ x, base[1] + size[1] * 0.56, base[2] + slot * size[2] }, 0.15, 0.14, materials.chrome, .x);
                try addCylinder(mesh, .{ x - 0.09, base[1] + size[1] * 0.56, base[2] + slot * size[2] }, 0.08, 0.10, materials.rubber, .x);
            },
            .right_side => {
                const x = base[0] + size[0] * 0.5 + 0.06;
                try addCylinder(mesh, .{ x, base[1] + size[1] * 0.56, base[2] + slot * size[2] }, 0.15, 0.14, materials.chrome, .x);
                try addCylinder(mesh, .{ x + 0.09, base[1] + size[1] * 0.56, base[2] + slot * size[2] }, 0.08, 0.10, materials.rubber, .x);
            },
        }
    }
}

fn addBeveledBox(mesh: *Mesh, center: [3]f32, size: [3]f32, bevel: f32, material: Material) !void {
    const ring_len = 36;
    const fillet_segments: usize = if (bevel >= 0.10) 5 else 3;
    const half_x = size[0] * 0.5;
    const half_z = size[2] * 0.5;
    const y0 = center[1] - size[1] * 0.5;
    const y1 = center[1] + size[1] * 0.5;
    const lower_y = @min(y0 + bevel, y1);
    const upper_y = @max(y1 - bevel, y0);
    const outer_radius = @min(bevel * 1.65, @min(half_x, half_z) * 0.45);
    const outer = roundedRing(center, half_x, half_z, outer_radius);

    for (0..ring_len) |index| {
        const next = (index + 1) % ring_len;
        const normal = roundedRingNormal(center, half_x, half_z, outer_radius, outer[index]);
        const next_normal = roundedRingNormal(center, half_x, half_z, outer_radius, outer[next]);
        try addSmoothQuad(
            mesh,
            .{ outer[index][0], lower_y, outer[index][1] },
            .{ outer[next][0], lower_y, outer[next][1] },
            .{ outer[next][0], upper_y, outer[next][1] },
            .{ outer[index][0], upper_y, outer[index][1] },
            normal,
            next_normal,
            next_normal,
            normal,
            material,
        );
    }

    for (0..fillet_segments) |segment| {
        const angle0 = @as(f32, @floatFromInt(segment)) * std.math.pi * 0.5 / @as(f32, @floatFromInt(fillet_segments));
        const angle1 = @as(f32, @floatFromInt(segment + 1)) * std.math.pi * 0.5 / @as(f32, @floatFromInt(fillet_segments));
        const inset0 = bevel * (1.0 - @cos(angle0));
        const inset1 = bevel * (1.0 - @cos(angle1));
        const half_x0 = @max(half_x - inset0, 0.01);
        const half_z0 = @max(half_z - inset0, 0.01);
        const half_x1 = @max(half_x - inset1, 0.01);
        const half_z1 = @max(half_z - inset1, 0.01);
        const radius0 = @min(@max(outer_radius - inset0 * 0.45, 0.018), @min(half_x0, half_z0) * 0.45);
        const radius1 = @min(@max(outer_radius - inset1 * 0.45, 0.018), @min(half_x1, half_z1) * 0.45);
        const ring0 = roundedRing(center, half_x0, half_z0, radius0);
        const ring1 = roundedRing(center, half_x1, half_z1, radius1);
        const y_ring0 = upper_y + @sin(angle0) * bevel;
        const y_ring1 = upper_y + @sin(angle1) * bevel;
        for (0..ring_len) |index| {
            const next = (index + 1) % ring_len;
            const outward00 = roundedRingNormal(center, half_x0, half_z0, radius0, ring0[index]);
            const outward01 = roundedRingNormal(center, half_x0, half_z0, radius0, ring0[next]);
            const outward10 = roundedRingNormal(center, half_x1, half_z1, radius1, ring1[index]);
            const outward11 = roundedRingNormal(center, half_x1, half_z1, radius1, ring1[next]);
            const normal00 = [3]f32{ outward00[0] * @cos(angle0), @sin(angle0), outward00[2] * @cos(angle0) };
            const normal01 = [3]f32{ outward01[0] * @cos(angle0), @sin(angle0), outward01[2] * @cos(angle0) };
            const normal10 = [3]f32{ outward10[0] * @cos(angle1), @sin(angle1), outward10[2] * @cos(angle1) };
            const normal11 = [3]f32{ outward11[0] * @cos(angle1), @sin(angle1), outward11[2] * @cos(angle1) };
            try addSmoothQuad(
                mesh,
                .{ ring0[index][0], y_ring0, ring0[index][1] },
                .{ ring0[next][0], y_ring0, ring0[next][1] },
                .{ ring1[next][0], y_ring1, ring1[next][1] },
                .{ ring1[index][0], y_ring1, ring1[index][1] },
                normal00,
                normal01,
                normal11,
                normal10,
                material,
            );
        }
    }

    const inner_half_x = @max(half_x - bevel, 0.01);
    const inner_half_z = @max(half_z - bevel, 0.01);
    const inner_radius = @min(@max(outer_radius - bevel * 0.45, 0.018), @min(inner_half_x, inner_half_z) * 0.45);
    const inner = roundedRing(center, inner_half_x, inner_half_z, inner_radius);
    const top_center = [3]f32{ center[0], y1, center[2] };
    for (0..ring_len) |index| {
        const next = (index + 1) % ring_len;
        try mesh.triangle(
            vertex(top_center, .{ 0, 1, 0 }, material),
            vertex(.{ inner[next][0], y1, inner[next][1] }, .{ 0, 1, 0 }, material),
            vertex(.{ inner[index][0], y1, inner[index][1] }, .{ 0, 1, 0 }, material),
        );
    }
}

fn roundedRing(center: [3]f32, half_x: f32, half_z: f32, radius: f32) [36][2]f32 {
    const segments_per_corner = 8;
    var result: [36][2]f32 = undefined;
    var cursor: usize = 0;
    for (0..4) |corner| {
        const corner_x: f32 = if (corner == 0 or corner == 3) half_x - radius else -half_x + radius;
        const corner_z: f32 = if (corner == 0 or corner == 1) half_z - radius else -half_z + radius;
        for (0..segments_per_corner + 1) |segment| {
            const angle = @as(f32, @floatFromInt(corner)) * std.math.pi * 0.5 +
                @as(f32, @floatFromInt(segment)) * std.math.pi * 0.5 / segments_per_corner;
            result[cursor] = .{
                center[0] + corner_x + @cos(angle) * radius,
                center[2] + corner_z + @sin(angle) * radius,
            };
            cursor += 1;
        }
    }
    return result;
}

fn roundedRingNormal(center: [3]f32, half_x: f32, half_z: f32, radius: f32, point: [2]f32) [3]f32 {
    const local_x = point[0] - center[0];
    const local_z = point[1] - center[2];
    const corner_x: f32 = if (local_x >= 0) half_x - radius else -half_x + radius;
    const corner_z: f32 = if (local_z >= 0) half_z - radius else -half_z + radius;
    return normalized3(.{ local_x - corner_x, 0, local_z - corner_z });
}

fn addIndicatorWasher(mesh: *Mesh, center: [3]f32, inner_radius: f32, outer_radius: f32) !void {
    const ProfilePoint = struct {
        radius: f32,
        height: f32,
        radial_normal: f32,
        up_normal: f32,
    };
    const profile = [_]ProfilePoint{
        .{ .radius = outer_radius, .height = 0.000, .radial_normal = 0.99, .up_normal = 0.12 },
        .{ .radius = outer_radius * 0.96, .height = 0.018, .radial_normal = 0.76, .up_normal = 0.65 },
        .{ .radius = inner_radius + (outer_radius - inner_radius) * 0.67, .height = 0.036, .radial_normal = 0.15, .up_normal = 0.99 },
        .{ .radius = inner_radius + (outer_radius - inner_radius) * 0.24, .height = 0.031, .radial_normal = -0.35, .up_normal = 0.94 },
        .{ .radius = inner_radius, .height = 0.010, .radial_normal = -0.80, .up_normal = 0.60 },
    };
    const segments: usize = 48;
    for (0..profile.len - 1) |profile_index| {
        const outer = profile[profile_index];
        const inner = profile[profile_index + 1];
        for (0..segments) |segment| {
            const angle0 = std.math.tau * @as(f32, @floatFromInt(segment)) / @as(f32, @floatFromInt(segments));
            const angle1 = std.math.tau * @as(f32, @floatFromInt(segment + 1)) / @as(f32, @floatFromInt(segments));
            const outer0 = [3]f32{ center[0] + @cos(angle0) * outer.radius, center[1] + outer.height, center[2] + @sin(angle0) * outer.radius };
            const outer1 = [3]f32{ center[0] + @cos(angle1) * outer.radius, center[1] + outer.height, center[2] + @sin(angle1) * outer.radius };
            const inner0 = [3]f32{ center[0] + @cos(angle0) * inner.radius, center[1] + inner.height, center[2] + @sin(angle0) * inner.radius };
            const inner1 = [3]f32{ center[0] + @cos(angle1) * inner.radius, center[1] + inner.height, center[2] + @sin(angle1) * inner.radius };
            const normal_outer0 = normalized3(.{ @cos(angle0) * outer.radial_normal, outer.up_normal, @sin(angle0) * outer.radial_normal });
            const normal_outer1 = normalized3(.{ @cos(angle1) * outer.radial_normal, outer.up_normal, @sin(angle1) * outer.radial_normal });
            const normal_inner0 = normalized3(.{ @cos(angle0) * inner.radial_normal, inner.up_normal, @sin(angle0) * inner.radial_normal });
            const normal_inner1 = normalized3(.{ @cos(angle1) * inner.radial_normal, inner.up_normal, @sin(angle1) * inner.radial_normal });
            try addSmoothQuad(
                mesh,
                outer0,
                outer1,
                inner1,
                inner0,
                normal_outer0,
                normal_outer1,
                normal_inner1,
                normal_inner0,
                materials.polished_chrome,
            );
        }
    }
}

fn addLathedY(mesh: *Mesh, origin: [3]f32, rings: []const LatheRing, material: Material) !void {
    const segments: usize = 48;
    for (0..rings.len - 1) |ring_index| {
        const lower = rings[ring_index];
        const upper = rings[ring_index + 1];
        const delta_height = upper.height - lower.height;
        const delta_radius = upper.radius - lower.radius;
        for (0..segments) |segment| {
            const angle0 = std.math.tau * @as(f32, @floatFromInt(segment)) / @as(f32, @floatFromInt(segments));
            const angle1 = std.math.tau * @as(f32, @floatFromInt(segment + 1)) / @as(f32, @floatFromInt(segments));
            const lower0 = [3]f32{ origin[0] + @cos(angle0) * lower.radius, origin[1] + lower.height, origin[2] + @sin(angle0) * lower.radius };
            const lower1 = [3]f32{ origin[0] + @cos(angle1) * lower.radius, origin[1] + lower.height, origin[2] + @sin(angle1) * lower.radius };
            const upper0 = [3]f32{ origin[0] + @cos(angle0) * upper.radius, origin[1] + upper.height, origin[2] + @sin(angle0) * upper.radius };
            const upper1 = [3]f32{ origin[0] + @cos(angle1) * upper.radius, origin[1] + upper.height, origin[2] + @sin(angle1) * upper.radius };
            const normal0 = normalized3(.{ @cos(angle0) * delta_height, -delta_radius, @sin(angle0) * delta_height });
            const normal1 = normalized3(.{ @cos(angle1) * delta_height, -delta_radius, @sin(angle1) * delta_height });
            try addSmoothQuad(mesh, lower0, lower1, upper1, upper0, normal0, normal1, normal1, normal0, material);
        }
    }

    const top = rings[rings.len - 1];
    for (0..segments) |segment| {
        const angle0 = std.math.tau * @as(f32, @floatFromInt(segment)) / @as(f32, @floatFromInt(segments));
        const angle1 = std.math.tau * @as(f32, @floatFromInt(segment + 1)) / @as(f32, @floatFromInt(segments));
        const center = [3]f32{ origin[0], origin[1] + top.height, origin[2] };
        const edge0 = [3]f32{ origin[0] + @cos(angle0) * top.radius, center[1], origin[2] + @sin(angle0) * top.radius };
        const edge1 = [3]f32{ origin[0] + @cos(angle1) * top.radius, center[1], origin[2] + @sin(angle1) * top.radius };
        try mesh.triangle(vertex(center, .{ 0, 1, 0 }, material), vertex(edge1, .{ 0, 1, 0 }, material), vertex(edge0, .{ 0, 1, 0 }, material));
    }
}

fn addCylinder(mesh: *Mesh, center: [3]f32, radius: f32, length: f32, material: Material, axis: Axis) !void {
    try addCylinderSegments(mesh, center, radius, length, material, axis, 48);
}

fn addCylinderSegments(mesh: *Mesh, center: [3]f32, radius: f32, length: f32, material: Material, axis: Axis, segments: usize) !void {
    for (0..segments) |index| {
        const a0 = std.math.tau * @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(segments));
        const a1 = std.math.tau * @as(f32, @floatFromInt(index + 1)) / @as(f32, @floatFromInt(segments));
        const n0 = radialVector(axis, a0);
        const n1 = radialVector(axis, a1);
        const p00 = cylinderPoint(center, axis, -length * 0.5, radius, a0);
        const p01 = cylinderPoint(center, axis, -length * 0.5, radius, a1);
        const p10 = cylinderPoint(center, axis, length * 0.5, radius, a0);
        const p11 = cylinderPoint(center, axis, length * 0.5, radius, a1);
        try mesh.triangle(vertex(p00, n0, material), vertex(p10, n0, material), vertex(p11, n1, material));
        try mesh.triangle(vertex(p00, n0, material), vertex(p11, n1, material), vertex(p01, n1, material));

        const positive_normal = axisVector(axis, 1);
        try mesh.triangle(
            vertex(axisPoint(center, axis, length * 0.5), positive_normal, material),
            vertex(p11, positive_normal, material),
            vertex(p10, positive_normal, material),
        );
    }
}

fn cylinderPoint(center: [3]f32, axis: Axis, axial: f32, radius: f32, angle: f32) [3]f32 {
    const radial = radialVector(axis, angle);
    const along = axisVector(axis, axial);
    return .{
        center[0] + along[0] + radial[0] * radius,
        center[1] + along[1] + radial[1] * radius,
        center[2] + along[2] + radial[2] * radius,
    };
}

fn axisPoint(center: [3]f32, axis: Axis, axial: f32) [3]f32 {
    const along = axisVector(axis, axial);
    return .{ center[0] + along[0], center[1] + along[1], center[2] + along[2] };
}

fn axisVector(axis: Axis, amount: f32) [3]f32 {
    return switch (axis) {
        .x => .{ amount, 0, 0 },
        .y => .{ 0, amount, 0 },
        .z => .{ 0, 0, amount },
    };
}

fn radialVector(axis: Axis, angle: f32) [3]f32 {
    return switch (axis) {
        .x => .{ 0, @cos(angle), @sin(angle) },
        .y => .{ @cos(angle), 0, @sin(angle) },
        .z => .{ @cos(angle), @sin(angle), 0 },
    };
}

fn addBox(mesh: *Mesh, center: [3]f32, size: [3]f32, material: Material) !void {
    const x0 = center[0] - size[0] * 0.5;
    const x1 = center[0] + size[0] * 0.5;
    const y0 = center[1] - size[1] * 0.5;
    const y1 = center[1] + size[1] * 0.5;
    const z0 = center[2] - size[2] * 0.5;
    const z1 = center[2] + size[2] * 0.5;
    try addQuad(mesh, .{ x0, y1, z0 }, .{ x0, y1, z1 }, .{ x1, y1, z1 }, .{ x1, y1, z0 }, .{ 0, 1, 0 }, material);
    try addQuad(mesh, .{ x0, y0, z1 }, .{ x0, y0, z0 }, .{ x1, y0, z0 }, .{ x1, y0, z1 }, .{ 0, -1, 0 }, material);
    try addQuad(mesh, .{ x0, y0, z0 }, .{ x0, y1, z0 }, .{ x1, y1, z0 }, .{ x1, y0, z0 }, .{ 0, 0, -1 }, material);
    try addQuad(mesh, .{ x1, y0, z1 }, .{ x1, y1, z1 }, .{ x0, y1, z1 }, .{ x0, y0, z1 }, .{ 0, 0, 1 }, material);
    try addQuad(mesh, .{ x0, y0, z1 }, .{ x0, y1, z1 }, .{ x0, y1, z0 }, .{ x0, y0, z0 }, .{ -1, 0, 0 }, material);
    try addQuad(mesh, .{ x1, y0, z0 }, .{ x1, y1, z0 }, .{ x1, y1, z1 }, .{ x1, y0, z1 }, .{ 1, 0, 0 }, material);
}

fn addQuad(mesh: *Mesh, a: [3]f32, b: [3]f32, c: [3]f32, d: [3]f32, normal: [3]f32, material: Material) !void {
    try mesh.triangle(vertex(a, normal, material), vertex(b, normal, material), vertex(c, normal, material));
    try mesh.triangle(vertex(a, normal, material), vertex(c, normal, material), vertex(d, normal, material));
}

fn addQuadAutoNormal(mesh: *Mesh, a: [3]f32, b: [3]f32, c: [3]f32, d: [3]f32, material: Material) !void {
    const ab = [3]f32{ b[0] - a[0], b[1] - a[1], b[2] - a[2] };
    const ac = [3]f32{ c[0] - a[0], c[1] - a[1], c[2] - a[2] };
    const normal = normalized3(.{
        ab[1] * ac[2] - ab[2] * ac[1],
        ab[2] * ac[0] - ab[0] * ac[2],
        ab[0] * ac[1] - ab[1] * ac[0],
    });
    try addQuad(mesh, a, b, c, d, normal, material);
}

fn addSmoothQuad(
    mesh: *Mesh,
    a: [3]f32,
    b: [3]f32,
    c: [3]f32,
    d: [3]f32,
    normal_a: [3]f32,
    normal_b: [3]f32,
    normal_c: [3]f32,
    normal_d: [3]f32,
    material: Material,
) !void {
    try mesh.triangle(vertex(a, normal_a, material), vertex(b, normal_b, material), vertex(c, normal_c, material));
    try mesh.triangle(vertex(a, normal_a, material), vertex(c, normal_c, material), vertex(d, normal_d, material));
}

fn vertex(position: [3]f32, normal: [3]f32, material: Material) Vertex {
    return .{
        .position = .{ position[0], position[1], position[2], 1 },
        .normal = .{ normal[0], normal[1], normal[2], 0 },
        .base_color = .{ material.base_color[0], material.base_color[1], material.base_color[2], 1 },
        .material = .{ material.roughness, material.metallic, material.emissive, 0 },
    };
}

fn ledLensMaterial(brightness: f32) Material {
    return .{
        .base_color = .{ 0.004, 0.78, 0.025 },
        .roughness = 0.09,
        .metallic = 0.02,
        .emissive = 1.8 * brightness,
    };
}

fn ledCoreMaterial(brightness: f32) Material {
    return .{
        .base_color = .{ 0.012, 1.0, 0.055 },
        .roughness = 0.05,
        .metallic = 0,
        .emissive = 4.6 * brightness,
    };
}

fn accentMaterial(accent: demo.Accent) Material {
    return .{
        .base_color = switch (accent) {
            .cyan => .{ 0.055, 0.31, 0.42 },
            .green => .{ 0.055, 0.32, 0.18 },
            .amber => .{ 0.58, 0.20, 0.025 },
            .violet => .{ 0.28, 0.075, 0.32 },
            .coral => .{ 0.52, 0.055, 0.035 },
        },
        .roughness = 0.16,
        .metallic = 0.58,
    };
}

fn darkened(material: Material, factor: f32) Material {
    var result = material;
    result.base_color = .{ material.base_color[0] * factor, material.base_color[1] * factor, material.base_color[2] * factor };
    result.roughness = @min(material.roughness + 0.12, 1.0);
    return result;
}

fn normalized3(value: [3]f32) [3]f32 {
    const length = @sqrt(value[0] * value[0] + value[1] * value[1] + value[2] * value[2]);
    if (length < 0.0001) return .{ 0, 1, 0 };
    return .{ value[0] / length, value[1] / length, value[2] / length };
}

test "semantic pedalboard produces bounded 3D geometry" {
    var mesh = Mesh{};
    try build(&mesh, &demo.rig);
    try std.testing.expect(mesh.len > 30_000);
    try std.testing.expect(mesh.len < Mesh.max_vertices);
    try std.testing.expectEqual(@as(usize, 7), mesh.emissiveLights().len);
    try std.testing.expectEqual(@as(usize, 0), mesh.len % 3);
    for (mesh.items()) |item| {
        for (item.position) |value| try std.testing.expect(std.math.isFinite(value));
        for (item.normal) |value| try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(item.material[0] >= 0.04 and item.material[0] <= 1.0);
        try std.testing.expect(item.material[1] >= 0 and item.material[1] <= 1.0);
        try std.testing.expect(item.material[2] >= 0 and item.material[2] <= 16.0);
    }
    for (mesh.emissiveLights()) |light| {
        try std.testing.expect(light.radius > 0 and light.radius <= 1.0);
        try std.testing.expect(light.intensity > 0 and light.intensity <= 4.0);
    }
}

test "open presentation remains available outside the default rig" {
    var pedals: [5]demo.Pedal = undefined;
    for (demo.rig.pedals, 0..) |pedal, index| pedals[index] = pedal;
    pedals[1].presentation = .open;
    var rig = demo.rig;
    rig.pedals = &pedals;
    var mesh = Mesh{};
    try build(&mesh, &rig);
    try std.testing.expect(mesh.len > 35_000);
}
