const std = @import("std");
const demo = @import("../model/demo.zig");
const lighting = @import("lighting_lab.zig");

pub const Vertex = lighting.Vertex;
pub const Material = lighting.Material;

pub const Mesh = struct {
    pub const max_vertices = 32_000;

    vertices: [max_vertices]Vertex = undefined,
    len: usize = 0,

    pub fn items(self: *const Mesh) []const Vertex {
        return self.vertices[0..self.len];
    }

    fn triangle(self: *Mesh, a: Vertex, b: Vertex, c: Vertex) !void {
        if (self.len + 3 > self.vertices.len) return error.MeshCapacityExceeded;
        self.vertices[self.len] = a;
        self.vertices[self.len + 1] = b;
        self.vertices[self.len + 2] = c;
        self.len += 3;
    }
};

const materials = struct {
    const board_base = Material{ .base_color = .{ 0.032, 0.022, 0.016 }, .roughness = 0.72, .metallic = 0.08 };
    const wood_a = Material{ .base_color = .{ 0.115, 0.052, 0.021 }, .roughness = 0.58, .metallic = 0.02 };
    const wood_b = Material{ .base_color = .{ 0.075, 0.030, 0.014 }, .roughness = 0.66, .metallic = 0.02 };
    const black_metal = Material{ .base_color = .{ 0.025, 0.032, 0.031 }, .roughness = 0.19, .metallic = 0.82 };
    const chrome = Material{ .base_color = .{ 0.48, 0.52, 0.50 }, .roughness = 0.14, .metallic = 1.0 };
    const rubber = Material{ .base_color = .{ 0.012, 0.015, 0.014 }, .roughness = 0.78, .metallic = 0.0 };
    const pcb = Material{ .base_color = .{ 0.025, 0.19, 0.105 }, .roughness = 0.38, .metallic = 0.08 };
    const led = Material{ .base_color = .{ 0.16, 0.95, 0.42 }, .roughness = 0.16, .metallic = 0.12 };
    const pointer = Material{ .base_color = .{ 0.95, 0.67, 0.18 }, .roughness = 0.28, .metallic = 0.30 };
};

const Axis = enum { x, y, z };

pub fn build(mesh: *Mesh, rig: *const demo.Rig) !void {
    mesh.* = .{};
    try addPedalboard(mesh);

    const millimetres_to_world: f32 = 0.022;
    const gap: f32 = 0.30;
    var total_width: f32 = gap * @as(f32, @floatFromInt(rig.pedals.len - 1));
    for (rig.pedals) |pedal| total_width += pedal.enclosure.dimensions.width * millimetres_to_world;

    var cursor = -total_width * 0.5;
    for (rig.pedals) |pedal| {
        const width = pedal.enclosure.dimensions.width * millimetres_to_world;
        const depth = pedal.enclosure.dimensions.depth * millimetres_to_world;
        const height = pedal.enclosure.dimensions.height * millimetres_to_world;
        const center_x = cursor + width * 0.5;
        try addPedal(mesh, pedal, .{ center_x, 0.24, 0 }, .{ width, height, depth });
        cursor += width + gap;
    }
}

fn addPedalboard(mesh: *Mesh) !void {
    try addBox(mesh, .{ 0, -0.02, 0 }, .{ 12.7, 0.38, 6.0 }, materials.board_base);
    const plank_count = 11;
    const gap: f32 = 0.055;
    const width = (12.4 - gap * (plank_count - 1)) / plank_count;
    var index: usize = 0;
    while (index < plank_count) : (index += 1) {
        const x = -6.2 + width * 0.5 + @as(f32, @floatFromInt(index)) * (width + gap);
        try addBeveledBox(mesh, .{ x, 0.18, 0 }, .{ width, 0.20, 5.72 }, 0.055, if (index % 2 == 0) materials.wood_a else materials.wood_b);
    }
    try addBox(mesh, .{ 0, -0.22, -2.45 }, .{ 12.8, 0.30, 0.24 }, materials.black_metal);
    try addBox(mesh, .{ 0, -0.22, 2.45 }, .{ 12.8, 0.30, 0.24 }, materials.black_metal);
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
        try addBeveledBox(mesh, .{ base[0], base[1] + size[1] * 0.5, base[2] }, size, 0.12, body_material);
        try addControls(mesh, pedal, base, size);
        try addFootswitches(mesh, pedal, base, size);
        try addScrews(mesh, base, size);
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
        try addCylinder(mesh, .{ x, knob_base + 0.11, z }, radius * 1.14, 0.12, materials.chrome, .y);
        try addCylinder(mesh, .{ x, knob_base + 0.29, z }, radius, 0.32, materials.black_metal, .y);
        const angle = (-0.75 + control.normalized_value * 1.5) * std.math.pi;
        try addBox(mesh, .{ x + @sin(angle) * radius * 0.55, knob_base + 0.465, z - @cos(angle) * radius * 0.55 }, .{ radius * 0.15, 0.035, radius * 0.62 }, materials.pointer);
    }
}

fn addFootswitches(mesh: *Mesh, pedal: demo.Pedal, base: [3]f32, size: [3]f32) !void {
    const count = @max(@as(usize, 1), @as(usize, pedal.footswitch_count));
    for (0..count) |index| {
        const x = base[0] + size[0] * ((@as(f32, @floatFromInt(index)) + 1.0) / @as(f32, @floatFromInt(count + 1)) - 0.5) * 0.72;
        const z = base[2] + size[2] * 0.29;
        const top = base[1] + size[1];
        try addCylinder(mesh, .{ x, top + 0.09, z }, 0.18, 0.16, materials.chrome, .y);
        try addCylinder(mesh, .{ x, top + 0.19, z }, 0.125, 0.12, materials.rubber, .y);
        try addCylinder(mesh, .{ x, top + 0.055, z - size[2] * 0.16 }, 0.055, 0.08, materials.led, .y);
    }
}

fn addScrews(mesh: *Mesh, base: [3]f32, size: [3]f32) !void {
    const top = base[1] + size[1] + 0.025;
    const inset: f32 = 0.14;
    const corners = [_][2]f32{
        .{ -1, -1 }, .{ 1, -1 }, .{ 1, 1 }, .{ -1, 1 },
    };
    for (corners) |corner| {
        try addCylinder(mesh, .{
            base[0] + corner[0] * (size[0] * 0.5 - inset),
            top,
            base[2] + corner[1] * (size[2] * 0.5 - inset),
        }, 0.055, 0.05, materials.chrome, .y);
    }
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
    const half_x = size[0] * 0.5;
    const half_z = size[2] * 0.5;
    const y0 = center[1] - size[1] * 0.5;
    const y1 = center[1] + size[1] * 0.5;
    const lower_y = @min(y0 + bevel, y1);
    const upper_y = @max(y1 - bevel, y0);
    const outer = chamferRing(center, half_x, half_z, @min(bevel, @min(half_x, half_z) * 0.45));
    const inner = chamferRing(center, @max(half_x - bevel, 0.01), @max(half_z - bevel, 0.01), @min(bevel, @min(half_x, half_z) * 0.45));

    for (0..8) |index| {
        const next = (index + 1) % 8;
        const outward = normalized3(.{ outer[index][0] - center[0], 0, outer[index][1] - center[2] });
        try addQuad(
            mesh,
            .{ outer[index][0], lower_y, outer[index][1] },
            .{ outer[next][0], lower_y, outer[next][1] },
            .{ outer[next][0], upper_y, outer[next][1] },
            .{ outer[index][0], upper_y, outer[index][1] },
            outward,
            material,
        );
        const bevel_normal = normalized3(.{ outward[0], 0.72, outward[2] });
        try addQuad(
            mesh,
            .{ outer[index][0], upper_y, outer[index][1] },
            .{ outer[next][0], upper_y, outer[next][1] },
            .{ inner[next][0], y1, inner[next][1] },
            .{ inner[index][0], y1, inner[index][1] },
            bevel_normal,
            material,
        );
    }
    const top_center = [3]f32{ center[0], y1, center[2] };
    for (0..8) |index| {
        const next = (index + 1) % 8;
        try mesh.triangle(
            vertex(top_center, .{ 0, 1, 0 }, material),
            vertex(.{ inner[next][0], y1, inner[next][1] }, .{ 0, 1, 0 }, material),
            vertex(.{ inner[index][0], y1, inner[index][1] }, .{ 0, 1, 0 }, material),
        );
    }
}

fn chamferRing(center: [3]f32, half_x: f32, half_z: f32, chamfer: f32) [8][2]f32 {
    return .{
        .{ center[0] - half_x + chamfer, center[2] - half_z },
        .{ center[0] + half_x - chamfer, center[2] - half_z },
        .{ center[0] + half_x, center[2] - half_z + chamfer },
        .{ center[0] + half_x, center[2] + half_z - chamfer },
        .{ center[0] + half_x - chamfer, center[2] + half_z },
        .{ center[0] - half_x + chamfer, center[2] + half_z },
        .{ center[0] - half_x, center[2] + half_z - chamfer },
        .{ center[0] - half_x, center[2] - half_z + chamfer },
    };
}

fn addCylinder(mesh: *Mesh, center: [3]f32, radius: f32, length: f32, material: Material, axis: Axis) !void {
    const segments = 24;
    for (0..segments) |index| {
        const a0 = std.math.tau * @as(f32, @floatFromInt(index)) / segments;
        const a1 = std.math.tau * @as(f32, @floatFromInt(index + 1)) / segments;
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

fn vertex(position: [3]f32, normal: [3]f32, material: Material) Vertex {
    return .{
        .position = .{ position[0], position[1], position[2], 1 },
        .normal = .{ normal[0], normal[1], normal[2], 0 },
        .base_color = .{ material.base_color[0], material.base_color[1], material.base_color[2], 1 },
        .material = .{ material.roughness, material.metallic, 0, 0 },
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
        .roughness = 0.29,
        .metallic = 0.54,
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
    try std.testing.expect(mesh.len > 4_000);
    try std.testing.expect(mesh.len < Mesh.max_vertices);
    try std.testing.expectEqual(@as(usize, 0), mesh.len % 3);
    for (mesh.items()) |item| {
        for (item.position) |value| try std.testing.expect(std.math.isFinite(value));
        for (item.normal) |value| try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(item.material[0] >= 0.04 and item.material[0] <= 1.0);
        try std.testing.expect(item.material[1] >= 0 and item.material[1] <= 1.0);
    }
}
