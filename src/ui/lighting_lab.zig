const std = @import("std");

pub const Material = struct {
    base_color: [3]f32,
    roughness: f32,
    metallic: f32,
};

pub const LightingProfile = struct {
    id: []const u8,
    exposure: f32,
    strip_width: f32,
    strip_height: f32,
    orbit_seconds: f32,
    environment_strength: f32,
};

pub const studio_profile = LightingProfile{
    .id = "robine.studio.product-dark",
    .exposure = 1.20,
    .strip_width = 1.15,
    .strip_height = 3.8,
    .orbit_seconds = 8.0,
    .environment_strength = 0.52,
};

pub const materials = struct {
    pub const panel = Material{
        .base_color = .{ 0.050, 0.075, 0.068 },
        .roughness = 0.31,
        .metallic = 0.42,
    };
    pub const knob = Material{
        .base_color = .{ 0.070, 0.088, 0.084 },
        .roughness = 0.14,
        .metallic = 0.96,
    };
    pub const collar = Material{
        .base_color = .{ 0.32, 0.35, 0.34 },
        .roughness = 0.19,
        .metallic = 1.0,
    };
    pub const indicator = Material{
        .base_color = .{ 0.95, 0.42, 0.055 },
        .roughness = 0.25,
        .metallic = 0.35,
    };
};

pub const Vertex = extern struct {
    position: [4]f32,
    normal: [4]f32,
    base_color: [4]f32,
    material: [4]f32,
};

pub const Mesh = struct {
    pub const max_vertices = 4096;

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

pub fn build(mesh: *Mesh) !void {
    mesh.* = .{};
    try addBox(mesh, .{ 0, -0.16, 0 }, .{ 6.2, 0.32, 3.8 }, materials.panel);
    try addCylinder(mesh, .{ 0, 0.01, 0 }, &.{
        .{ .height = 0.00, .radius = 1.02 },
        .{ .height = 0.12, .radius = 1.02 },
        .{ .height = 0.20, .radius = 0.91 },
    }, materials.collar, false);
    try addCylinder(mesh, .{ 0, 0.16, 0 }, &.{
        .{ .height = 0.00, .radius = 0.91 },
        .{ .height = 0.10, .radius = 0.99 },
        .{ .height = 0.76, .radius = 0.99 },
        .{ .height = 0.91, .radius = 0.82 },
    }, materials.knob, true);
    try addBox(mesh, .{ 0, 1.105, -0.46 }, .{ 0.13, 0.055, 0.62 }, materials.indicator);
}

const Ring = struct {
    height: f32,
    radius: f32,
};

fn addCylinder(mesh: *Mesh, origin: [3]f32, rings: []const Ring, material: Material, cap: bool) !void {
    const segments = 64;
    var ring_index: usize = 0;
    while (ring_index + 1 < rings.len) : (ring_index += 1) {
        const lower = rings[ring_index];
        const upper = rings[ring_index + 1];
        var segment: usize = 0;
        while (segment < segments) : (segment += 1) {
            const a0 = std.math.tau * @as(f32, @floatFromInt(segment)) / segments;
            const a1 = std.math.tau * @as(f32, @floatFromInt(segment + 1)) / segments;
            const slope = (upper.radius - lower.radius) / @max(upper.height - lower.height, 0.0001);
            const normal_y = -slope;
            const normal_scale = 1.0 / @sqrt(1.0 + normal_y * normal_y);
            const n0 = [3]f32{ @cos(a0) * normal_scale, normal_y * normal_scale, @sin(a0) * normal_scale };
            const n1 = [3]f32{ @cos(a1) * normal_scale, normal_y * normal_scale, @sin(a1) * normal_scale };
            const p00 = radialPoint(origin, lower, a0);
            const p01 = radialPoint(origin, lower, a1);
            const p10 = radialPoint(origin, upper, a0);
            const p11 = radialPoint(origin, upper, a1);
            try mesh.triangle(vertex(p00, n0, material), vertex(p10, n0, material), vertex(p11, n1, material));
            try mesh.triangle(vertex(p00, n0, material), vertex(p11, n1, material), vertex(p01, n1, material));
        }
    }

    if (cap) {
        const top = rings[rings.len - 1];
        const center = [3]f32{ origin[0], origin[1] + top.height, origin[2] };
        var segment: usize = 0;
        while (segment < segments) : (segment += 1) {
            const a0 = std.math.tau * @as(f32, @floatFromInt(segment)) / segments;
            const a1 = std.math.tau * @as(f32, @floatFromInt(segment + 1)) / segments;
            try mesh.triangle(
                vertex(center, .{ 0, 1, 0 }, material),
                vertex(radialPoint(origin, top, a1), .{ 0, 1, 0 }, material),
                vertex(radialPoint(origin, top, a0), .{ 0, 1, 0 }, material),
            );
        }
    }
}

fn radialPoint(origin: [3]f32, ring: Ring, angle: f32) [3]f32 {
    return .{
        origin[0] + @cos(angle) * ring.radius,
        origin[1] + ring.height,
        origin[2] + @sin(angle) * ring.radius,
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

test "lighting lab geometry is finite and material bounded" {
    var mesh = Mesh{};
    try build(&mesh);
    try std.testing.expect(mesh.len > 1000);
    try std.testing.expectEqual(@as(usize, 0), mesh.len % 3);
    for (mesh.items()) |item| {
        for (item.position) |value| try std.testing.expect(std.math.isFinite(value));
        for (item.normal) |value| try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(item.material[0] >= 0.04 and item.material[0] <= 1.0);
        try std.testing.expect(item.material[1] >= 0 and item.material[1] <= 1.0);
    }
}
