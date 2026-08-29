const std = @import("std");
const demo = @import("../model/demo.zig");
const equipment_state = @import("../core/equipment_state.zig");
const ThreePosition = equipment_state.ThreePosition;
const lighting = @import("lighting_lab.zig");

pub const AmplifierId = equipment_state.AmplifierId;

pub const Vertex = lighting.Vertex;
pub const Material = lighting.Material;

pub const EmissiveLight = struct {
    position: [3]f32,
    radius: f32,
    color: [3]f32,
    intensity: f32,
    direction: [3]f32 = .{ 0, 0, 0 },
    cone_cosine: f32 = -1.0,
};

pub const ViewProfile = struct {
    camera: [3]f32,
    target: [3]f32,
    field_of_view_degrees: f32,
    key_position: [3]f32,
    key_size: [2]f32,
    key_intensity: f32,
    exposure: f32,
    environment_strength: f32,
    fill_radiance: [3]f32,
};

pub const studio_profile = ViewProfile{
    .camera = .{ -15.0, 10.0, 0 },
    .target = .{ -17.30, 0.50, 0 },
    .field_of_view_degrees = 14.0,
    .key_position = .{ 5.5, 10.5, -13.5 },
    .key_size = .{ 2.40, 3.20 },
    .key_intensity = 1_050.0,
    .exposure = 1.14,
    .environment_strength = 0.78,
    .fill_radiance = .{ 0.16, 0.21, 0.28 },
};

pub const CameraPose = struct {
    camera: [3]f32,
    target: [3]f32,
    field_of_view_degrees: f32,
};

pub const rig_camera = CameraPose{
    .camera = studio_profile.camera,
    .target = studio_profile.target,
    .field_of_view_degrees = studio_profile.field_of_view_degrees,
};

pub const studio_viewport = struct {
    pub const left: f32 = 0.0;
    pub const top: f32 = 0.0;
    pub const width: f32 = 1.0;
    pub const height: f32 = 1.0;
};

pub const BuildState = struct {
    /// Optional per-pedal runtime bypass state. Missing entries default to on.
    pedal_enabled: []const bool = &.{},
    /// Optional per-pedal three-way selector state.
    pedal_modes: []const ThreePosition = &.{},
    /// Optional per-pedal footswitch bit masks. Bit zero is the leftmost
    /// footswitch. Missing entries inherit the pedal-wide enabled state.
    pedal_footswitch_masks: []const u8 = &.{},
    /// Exactly one amplifier is powered at a time.
    active_amplifier: AmplifierId = .dumble,
};

// One world unit is 200 mm. Scene architecture, equipment bodies, and their
// hardware all share this physical scale.
const millimetres_to_world: f32 = 0.005;
const legacy_pedal_scale: f32 = 0.022;
const pedal_detail_scale: f32 = millimetres_to_world / legacy_pedal_scale;

const equipment_floor_top: f32 = 0.28;

// Reference combo: 620 x 500 x 260 mm.
const combo_center = [3]f32{ 0, 1.53, -4.28 };
const combo_size = [3]f32{ 3.10, 2.50, 1.30 };

// Bogner Shiva head (680 x 270 x 270 mm) over a wide 4x12 cabinet
// (780 x 740 x 360 mm), separated by the cabinet feet.
const bogner_head_size = [3]f32{ 3.40, 1.35, 1.35 };
const bogner_cabinet_size = [3]f32{ 3.90, 3.70, 1.80 };
const head_cabinet_gap: f32 = 0.10;
const bogner_stack_size = [3]f32{
    bogner_cabinet_size[0],
    bogner_cabinet_size[1] + head_cabinet_gap + bogner_head_size[1],
    bogner_cabinet_size[2],
};

pub const AmplifierFormat = enum {
    combo,
    head_and_4x12,
};

const AmplifierPlacement = struct {
    center: [3]f32,
    yaw_degrees: f32,
    id: AmplifierId,
    format: AmplifierFormat,
};
const amplifier_placements = [_]AmplifierPlacement{
    // The side amplifiers move toward the listener and toe inward to form
    // a shallow listening arc around the original amplifier.
    .{
        .center = .{ 3.85, equipment_floor_top + bogner_stack_size[1] * 0.5, -3.73 },
        .yaw_degrees = -12.0,
        .id = .bogner,
        .format = .head_and_4x12,
    },
    .{ .center = combo_center, .yaw_degrees = 0, .id = .dumble, .format = .combo },
    .{ .center = .{ -3.25, 1.53, -3.73 }, .yaw_degrees = 12.0, .id = .mesa, .format = .combo },
};
const equipment_offset_x: f32 = -14.52;
// 65 mm clear space leaves opposing side jacks readable without scattering the
// input chain across the room.
const pedal_gap: f32 = 0.325;
// The whole board sits close to the amplifier while retaining two readable
// rows. The effects-loop row remains 180 mm behind the input chain, leaving
// roughly 60 mm between enclosure edges.
const input_row_depth: f32 = -2.0;
const effects_loop_row_depth: f32 = input_row_depth - 0.90;

fn pedalDetail(value: f32) f32 {
    return value * pedal_detail_scale;
}

pub const Mesh = struct {
    pub const max_vertices = 140_000;
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
    const amplifier_vinyl = Material{ .base_color = .{ 0.020, 0.024, 0.023 }, .roughness = 0.56, .metallic = 0.05 };
    const amplifier_grille = Material{ .base_color = .{ 0.115, 0.105, 0.085 }, .roughness = 0.82, .metallic = 0.02 };
    const amplifier_grille_thread = Material{ .base_color = .{ 0.055, 0.052, 0.045 }, .roughness = 0.88, .metallic = 0.01 };
    const amplifier_panel = Material{ .base_color = .{ 0.39, 0.36, 0.28 }, .roughness = 0.25, .metallic = 0.68 };
    const amplifier_piping = Material{ .base_color = .{ 0.76, 0.65, 0.41 }, .roughness = 0.31, .metallic = 0.38 };
    const amplifier_badge = Material{ .base_color = .{ 0.84, 0.67, 0.30 }, .roughness = 0.20, .metallic = 0.82 };
    const bogner_vinyl = Material{ .base_color = .{ 0.055, 0.026, 0.015 }, .roughness = 0.60, .metallic = 0.03 };
    const bogner_grille = Material{ .base_color = .{ 0.22, 0.13, 0.065 }, .roughness = 0.86, .metallic = 0.01 };
    const bogner_panel = Material{ .base_color = .{ 0.48, 0.33, 0.14 }, .roughness = 0.27, .metallic = 0.55 };
    const mesa_vinyl = Material{ .base_color = .{ 0.115, 0.085, 0.055 }, .roughness = 0.57, .metallic = 0.03 };
    const mesa_grille = Material{ .base_color = .{ 0.42, 0.36, 0.25 }, .roughness = 0.88, .metallic = 0.01 };
    const mesa_panel = Material{ .base_color = .{ 0.64, 0.61, 0.52 }, .roughness = 0.20, .metallic = 0.72 };
    const studio_wall = Material{ .base_color = .{ 0.235, 0.205, 0.168 }, .roughness = 0.96, .metallic = 0.0 };
    const studio_wall_trim = Material{ .base_color = .{ 0.255, 0.105, 0.030 }, .roughness = 0.62, .metallic = 0.02 };
    const acoustic_panel = Material{ .base_color = .{ 0.025, 0.042, 0.041 }, .roughness = 0.96, .metallic = 0.0 };
    const acoustic_slats = Material{ .base_color = .{ 0.245, 0.095, 0.025 }, .roughness = 0.57, .metallic = 0.01 };
    const walnut = Material{ .base_color = .{ 0.205, 0.070, 0.018 }, .roughness = 0.48, .metallic = 0.01 };
    const walnut_dark = Material{ .base_color = .{ 0.060, 0.025, 0.014 }, .roughness = 0.62, .metallic = 0.01 };
    const limestone = Material{ .base_color = .{ 0.42, 0.365, 0.285 }, .roughness = 0.91, .metallic = 0.0 };
    const linen = Material{ .base_color = .{ 0.39, 0.315, 0.235 }, .roughness = 0.98, .metallic = 0.0 };
    const olive_linen = Material{ .base_color = .{ 0.145, 0.185, 0.105 }, .roughness = 0.98, .metallic = 0.0 };
    const ceramic = Material{ .base_color = .{ 0.105, 0.075, 0.052 }, .roughness = 0.71, .metallic = 0.02 };
    const foliage_a = Material{ .base_color = .{ 0.045, 0.155, 0.070 }, .roughness = 0.84, .metallic = 0.0 };
    const foliage_b = Material{ .base_color = .{ 0.095, 0.235, 0.105 }, .roughness = 0.80, .metallic = 0.0 };
    const lamp_warm = Material{ .base_color = .{ 0.82, 0.34, 0.075 }, .roughness = 0.28, .metallic = 0.0, .emissive = 1.45 };
    const lamp_cool = Material{ .base_color = .{ 0.60, 0.78, 1.0 }, .roughness = 0.18, .metallic = 0.0, .emissive = 3.0 };
    const sconce_oak = Material{ .base_color = .{ 0.52, 0.245, 0.070 }, .roughness = 0.64, .metallic = 0.01 };
    const window_frame = Material{ .base_color = .{ 0.020, 0.025, 0.024 }, .roughness = 0.24, .metallic = 0.72 };
    const sky = Material{ .base_color = .{ 0.30, 0.46, 0.55 }, .roughness = 1.0, .metallic = 0.0, .emissive = 0.72 };
    const horizon = Material{ .base_color = .{ 0.58, 0.47, 0.32 }, .roughness = 1.0, .metallic = 0.0, .emissive = 0.24 };
    const distant_ridge = Material{ .base_color = .{ 0.105, 0.165, 0.165 }, .roughness = 0.98, .metallic = 0.0, .emissive = 0.10 };
    const middle_ridge = Material{ .base_color = .{ 0.075, 0.135, 0.105 }, .roughness = 0.96, .metallic = 0.0, .emissive = 0.055 };
    const valley = Material{ .base_color = .{ 0.055, 0.105, 0.060 }, .roughness = 0.94, .metallic = 0.0, .emissive = 0.025 };
    const sun = Material{ .base_color = .{ 1.0, 0.64, 0.24 }, .roughness = 0.30, .metallic = 0.0, .emissive = 4.0 };
    const rug_base = Material{ .base_color = .{ 0.82, 0.78, 0.70 }, .roughness = 0.96, .metallic = 0.0, .texture_slot = 1.0 };
    const rug_border = Material{ .base_color = .{ 0.42, 0.205, 0.075 }, .roughness = 0.94, .metallic = 0.01 };
    const rug_detail = Material{ .base_color = .{ 0.115, 0.155, 0.115 }, .roughness = 0.98, .metallic = 0.0 };
};

const Axis = enum { x, y, z };

const LatheRing = struct {
    height: f32,
    radius: f32,
};

pub fn build(mesh: *Mesh, rig: *const demo.Rig, state: BuildState) !void {
    mesh.* = .{};
    try addPedalboard(mesh);
    try addStudioRoom(mesh);
    const equipment_vertex_start = mesh.len;
    const equipment_light_start = mesh.emissive_light_len;
    for (amplifier_placements) |placement| {
        try addAmplifier(mesh, placement, placement.id == state.active_amplifier);
    }

    for (rig.pedals, 0..) |pedal, index| {
        const placement = pedalPlacement(rig, index) orelse unreachable;
        const enabled = if (index < state.pedal_enabled.len) state.pedal_enabled[index] else true;
        const mode = if (index < state.pedal_modes.len)
            state.pedal_modes[index]
        else if (pedal.mode_switch) |mode_switch|
            mode_switch.default_position
        else
            .middle;
        const footswitch_mask: ?u8 = if (index < state.pedal_footswitch_masks.len)
            state.pedal_footswitch_masks[index]
        else
            null;
        try addPedal(mesh, pedal, placement.base, placement.size, enabled, mode, footswitch_mask);
    }
    transformEquipment(mesh, equipment_vertex_start, equipment_light_start);
}

/// Rotate the canonical rig a quarter-turn so enclosure fronts point away from
/// the left wall, then translate the combo until its back is close to it.
fn equipmentPoint(point: [3]f32) [3]f32 {
    return .{ equipment_offset_x + point[2], point[1], -point[0] };
}

fn equipmentDirection(direction: [3]f32) [3]f32 {
    return .{ direction[2], direction[1], -direction[0] };
}

fn amplifierPlacement(id: AmplifierId) AmplifierPlacement {
    return amplifier_placements[@intFromEnum(id)];
}

fn amplifierSize(placement: AmplifierPlacement) [3]f32 {
    return switch (placement.format) {
        .combo => combo_size,
        .head_and_4x12 => bogner_stack_size,
    };
}

pub fn amplifierCamera(id: AmplifierId) CameraPose {
    const placement = amplifierPlacement(id);
    const size = amplifierSize(placement);
    const center = equipmentPoint(placement.center);
    const front = equipmentDirection(rotateDirectionY(.{ 0, 0, 1 }, placement.yaw_degrees));
    const distance = switch (placement.format) {
        .combo => 4.35,
        .head_and_4x12 => size[1] * 1.45,
    };
    const camera_y = switch (placement.format) {
        .combo => 2.70,
        .head_and_4x12 => center[1] + 0.32,
    };
    const target_y = switch (placement.format) {
        .combo => 1.35,
        .head_and_4x12 => center[1],
    };
    return .{
        .camera = .{ center[0] + front[0] * distance, camera_y, center[2] + front[2] * distance },
        .target = .{ center[0], target_y, center[2] },
        .field_of_view_degrees = if (placement.format == .combo) 50.0 else 44.0,
    };
}

pub const amplifier_camera = amplifierCamera(.dumble);

fn transformEquipment(mesh: *Mesh, vertex_start: usize, light_start: usize) void {
    for (mesh.vertices[vertex_start..mesh.len]) |*item| {
        const position = equipmentPoint(.{ item.position[0], item.position[1], item.position[2] });
        const normal = equipmentDirection(.{ item.normal[0], item.normal[1], item.normal[2] });
        item.position = .{ position[0], position[1], position[2], item.position[3] };
        item.normal = .{ normal[0], normal[1], normal[2], item.normal[3] };
    }
    for (mesh.emissive_lights[light_start..mesh.emissive_light_len]) |*light| {
        light.position = equipmentPoint(light.position);
        light.direction = equipmentDirection(light.direction);
    }
}

pub fn hitTestPedalModeSwitch(
    point: [2]f32,
    window_aspect: f32,
    rig: *const demo.Rig,
    pedal_index: usize,
) bool {
    const placement = pedalPlacement(rig, pedal_index) orelse return false;
    if (rig.pedals[pedal_index].mode_switch == null) return false;
    const canonical_center = modeSwitchCenter(placement);
    const center_world = equipmentPoint(canonical_center);
    const viewport_aspect = window_aspect * studio_viewport.width / studio_viewport.height;
    const center = projectToWindow(center_world, rig_camera, viewport_aspect) orelse return false;
    const edge_x = projectToWindow(equipmentPoint(.{ canonical_center[0] + pedalDetail(0.30), canonical_center[1], canonical_center[2] }), rig_camera, viewport_aspect) orelse return false;
    const edge_z = projectToWindow(equipmentPoint(.{ canonical_center[0], canonical_center[1], canonical_center[2] + pedalDetail(0.38) }), rig_camera, viewport_aspect) orelse return false;
    const radius_x = @max(@abs(edge_x[0] - center[0]) * 1.6, 0.025);
    const radius_y = @max(@abs(edge_z[1] - center[1]) * 1.6, 0.035);
    const dx = (point[0] - center[0]) / radius_x;
    const dy = (point[1] - center[1]) / radius_y;
    return dx * dx + dy * dy <= 1.0;
}

pub fn hitTestPedalFootswitch(
    point: [2]f32,
    window_aspect: f32,
    rig: *const demo.Rig,
    pedal_index: usize,
    footswitch_index: usize,
) bool {
    const placement = pedalPlacement(rig, pedal_index) orelse return false;
    const pedal = rig.pedals[pedal_index];
    const count = @max(@as(usize, 1), @as(usize, pedal.footswitch_count));
    if (footswitch_index >= count) return false;
    const x = placement.base[0] + placement.size[0] *
        ((@as(f32, @floatFromInt(footswitch_index)) + 1.0) /
            @as(f32, @floatFromInt(count + 1)) - 0.5) * 0.72;
    const z = placement.base[2] + placement.size[2] * 0.29;
    const canonical_center = [3]f32{ x, placement.base[1] + placement.size[1] + pedalDetail(0.18), z };
    const center_world = equipmentPoint(canonical_center);
    const viewport_aspect = window_aspect * studio_viewport.width / studio_viewport.height;
    const center = projectToWindow(center_world, rig_camera, viewport_aspect) orelse return false;
    const edge_x = projectToWindow(equipmentPoint(.{ canonical_center[0] + pedalDetail(0.34), canonical_center[1], canonical_center[2] }), rig_camera, viewport_aspect) orelse return false;
    const edge_z = projectToWindow(equipmentPoint(.{ canonical_center[0], canonical_center[1], canonical_center[2] + pedalDetail(0.34) }), rig_camera, viewport_aspect) orelse return false;
    const radius_x = @max(@abs(edge_x[0] - center[0]) * 1.55, 0.025);
    const radius_y = @max(@abs(edge_z[1] - center[1]) * 1.55, 0.030);
    const dx = (point[0] - center[0]) / radius_x;
    const dy = (point[1] - center[1]) / radius_y;
    return dx * dx + dy * dy <= 1.0;
}

const PedalPlacement = struct {
    base: [3]f32,
    size: [3]f32,
};

fn modeSwitchCenter(placement: PedalPlacement) [3]f32 {
    return .{
        placement.base[0],
        placement.base[1] + placement.size[1] + pedalDetail(0.29),
        placement.base[2] - placement.size[2] * 0.01,
    };
}

fn pedalPlacement(rig: *const demo.Rig, pedal_index: usize) ?PedalPlacement {
    if (pedal_index >= rig.pedals.len) return null;
    const signal_stage = rig.pedals[pedal_index].signal_stage;
    var lane_count: usize = 0;
    var total_width: f32 = 0;
    for (rig.pedals) |pedal| {
        if (pedal.signal_stage != signal_stage) continue;
        if (lane_count > 0) total_width += pedal_gap;
        total_width += pedal.enclosure.dimensions.width * millimetres_to_world;
        lane_count += 1;
    }
    var cursor = total_width * 0.5;
    for (rig.pedals, 0..) |pedal, index| {
        if (pedal.signal_stage != signal_stage) continue;
        const size = [3]f32{
            pedal.enclosure.dimensions.width * millimetres_to_world,
            pedal.enclosure.dimensions.height * millimetres_to_world,
            pedal.enclosure.dimensions.depth * millimetres_to_world,
        };
        const center_x = cursor - size[0] * 0.5;
        const row_depth: f32 = switch (signal_stage) {
            .before_amplifier => input_row_depth,
            .effects_loop => effects_loop_row_depth,
        };
        if (index == pedal_index) return .{ .base = .{ center_x, 0.37, row_depth }, .size = size };
        cursor -= size[0] + pedal_gap;
    }
    return null;
}

pub fn amplifierAt(point: [2]f32, window_aspect: f32) ?AmplifierId {
    const viewport_aspect = window_aspect * studio_viewport.width / studio_viewport.height;
    var result: ?AmplifierId = null;
    var nearest_distance_squared = std.math.inf(f32);
    for (amplifier_placements) |placement| {
        if (!hitTestAmplifierPlacement(point, viewport_aspect, rig_camera, placement)) continue;
        const projected = projectToWindow(equipmentPoint(placement.center), rig_camera, viewport_aspect) orelse continue;
        const dx = point[0] - projected[0];
        const dy = point[1] - projected[1];
        const distance_squared = dx * dx + dy * dy;
        if (distance_squared < nearest_distance_squared) {
            nearest_distance_squared = distance_squared;
            result = placement.id;
        }
    }
    return result;
}

pub fn hitTestAmplifier(point: [2]f32, window_aspect: f32) bool {
    return amplifierAt(point, window_aspect) != null;
}

pub fn hitTestFocusedAmplifier(point: [2]f32, window_aspect: f32, id: AmplifierId) bool {
    const viewport_aspect = window_aspect * studio_viewport.width / studio_viewport.height;
    return hitTestAmplifierPlacement(point, viewport_aspect, amplifierCamera(id), amplifierPlacement(id));
}

pub fn hitTestAmplifierPower(point: [2]f32, window_aspect: f32, id: AmplifierId) bool {
    const placement = amplifierPlacement(id);
    const viewport_aspect = window_aspect * studio_viewport.width / studio_viewport.height;
    const camera = amplifierCamera(id);
    const scale_y = switch (placement.format) {
        .combo => combo_size[1] / 3.0,
        .head_and_4x12 => bogner_head_size[1] / 1.35,
    };
    const canonical_center = amplifierPowerCanonicalCenter(placement);
    const x_offset = rotateDirectionY(.{ 0.16, 0, 0 }, placement.yaw_degrees);
    const canonical_x_edge = [3]f32{
        canonical_center[0] + x_offset[0],
        canonical_center[1],
        canonical_center[2] + x_offset[2],
    };
    const center = projectToWindow(equipmentPoint(canonical_center), camera, viewport_aspect) orelse return false;
    const x_edge = projectToWindow(equipmentPoint(canonical_x_edge), camera, viewport_aspect) orelse return false;
    const y_edge = projectToWindow(equipmentPoint(.{ canonical_center[0], canonical_center[1] + 0.18 * scale_y, canonical_center[2] }), camera, viewport_aspect) orelse return false;
    const half_width = @max(@abs(x_edge[0] - center[0]), 0.018);
    const half_height = @max(@abs(y_edge[1] - center[1]), 0.018);
    const padding: f32 = 0.014;
    return @abs(point[0] - center[0]) <= half_width + padding and
        @abs(point[1] - center[1]) <= half_height + padding;
}

fn amplifierPowerCanonicalCenter(placement: AmplifierPlacement) [3]f32 {
    const canonical_center = switch (placement.format) {
        .combo => blk: {
            const scale_x = combo_size[0] / 5.15;
            const scale_y = combo_size[1] / 3.0;
            const scale_z = combo_size[2] / 1.34;
            const front_z = placement.center[2] + combo_size[2] * 0.5;
            const panel_y = equipment_floor_top + combo_size[1] - 0.34 * scale_y;
            break :blk [3]f32{ placement.center[0] - 1.82 * scale_x, panel_y, front_z + 0.150 * scale_z };
        },
        .head_and_4x12 => blk: {
            const head_center_y = equipment_floor_top + bogner_cabinet_size[1] +
                head_cabinet_gap + bogner_head_size[1] * 0.5;
            break :blk [3]f32{
                placement.center[0] - bogner_head_size[0] * 0.40,
                head_center_y,
                placement.center[2] + bogner_head_size[2] * 0.5 + 0.075,
            };
        },
    };
    return rotatePointY(canonical_center, placement.center, placement.yaw_degrees);
}

fn hitTestAmplifierPlacement(
    point: [2]f32,
    viewport_aspect: f32,
    camera: CameraPose,
    placement: AmplifierPlacement,
) bool {
    const size = amplifierSize(placement);
    const half = [3]f32{ size[0] * 0.5, size[1] * 0.5, size[2] * 0.5 };
    var minimum = [2]f32{ std.math.inf(f32), std.math.inf(f32) };
    var maximum = [2]f32{ -std.math.inf(f32), -std.math.inf(f32) };
    for (0..8) |index| {
        const corner = rotatePointY(.{
            placement.center[0] + (if (index & 1 == 0) -half[0] else half[0]),
            placement.center[1] + (if (index & 2 == 0) -half[1] else half[1]),
            placement.center[2] + (if (index & 4 == 0) -half[2] else half[2]),
        }, placement.center, placement.yaw_degrees);
        const projected = projectToWindow(equipmentPoint(corner), camera, viewport_aspect) orelse continue;
        minimum[0] = @min(minimum[0], projected[0]);
        minimum[1] = @min(minimum[1], projected[1]);
        maximum[0] = @max(maximum[0], projected[0]);
        maximum[1] = @max(maximum[1], projected[1]);
    }
    const padding: f32 = 0.018;
    return point[0] >= minimum[0] - padding and point[0] <= maximum[0] + padding and
        point[1] >= minimum[1] - padding and point[1] <= maximum[1] + padding;
}

fn addPedalboard(mesh: *Mesh) !void {
    const floor_width: f32 = 42.0;
    const floor_depth: f32 = 36.0;
    const floor_center_z: f32 = 9.0;
    const floor_min_z = floor_center_z - floor_depth * 0.5;
    const floor_max_z = floor_center_z + floor_depth * 0.5;
    // 180 mm boards, 4 mm expansion grooves, and 1.48 m staggered lengths.
    const column_count: usize = 46;
    const plank_length: f32 = 7.4;
    const groove: f32 = 0.020;
    const plank_width = (floor_width - groove * @as(f32, @floatFromInt(column_count - 1))) /
        @as(f32, @floatFromInt(column_count));

    try addBox(mesh, .{ 0, -0.02, floor_center_z }, .{ floor_width + 0.28, 0.38, floor_depth + 0.28 }, materials.board_base);

    for (0..column_count) |column| {
        const x = -floor_width * 0.5 + plank_width * 0.5 +
            @as(f32, @floatFromInt(column)) * (plank_width + groove);
        const stagger = switch (column % 3) {
            0 => 0.0,
            1 => plank_length * 0.34,
            else => plank_length * 0.67,
        };
        var front = floor_min_z - stagger;
        var segment: usize = 0;
        while (front < floor_max_z) : ({
            front += plank_length;
            segment += 1;
        }) {
            const visible_front = @max(front, floor_min_z);
            const visible_back = @min(front + plank_length - groove, floor_max_z);
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

fn addStudioRoom(mesh: *Mesh) !void {
    const floor_top: f32 = 0.28;
    // 3.2 m studio walls and a nearly floor-to-ceiling 2.66 m overlook.
    const wall_height: f32 = 16.0;
    const back_z: f32 = -8.92;
    const side_x: f32 = 20.96;
    const side_center_z: f32 = 9.0;
    const side_depth: f32 = 36.0;
    const wall_center_y = floor_top + wall_height * 0.5;

    // The rear wall is architectural geometry around a broad overlook, not a
    // textured photograph pasted onto the room.
    const window_bottom: f32 = 0.90;
    const window_top: f32 = 14.20;
    const window_half_width: f32 = 17.55;
    try addBox(mesh, .{ -19.25, wall_center_y, back_z }, .{ 3.42, wall_height, 0.24 }, materials.studio_wall);
    try addBox(mesh, .{ 19.25, wall_center_y, back_z }, .{ 3.42, wall_height, 0.24 }, materials.studio_wall);
    try addBox(mesh, .{ 0, floor_top + (window_bottom - floor_top) * 0.5, back_z }, .{ window_half_width * 2.0, window_bottom - floor_top, 0.24 }, materials.studio_wall);
    try addBox(mesh, .{ 0, window_top + (floor_top + wall_height - window_top) * 0.5, back_z }, .{ window_half_width * 2.0, floor_top + wall_height - window_top, 0.24 }, materials.studio_wall);
    try addBox(mesh, .{ -side_x, wall_center_y, side_center_z }, .{ 0.24, wall_height, side_depth }, materials.studio_wall);
    try addBox(mesh, .{ side_x, wall_center_y, side_center_z }, .{ 0.24, wall_height, side_depth }, materials.studio_wall);

    try addBox(mesh, .{ 0, floor_top + 0.18, back_z + 0.15 }, .{ 41.8, 0.34, 0.16 }, materials.studio_wall_trim);
    try addBox(mesh, .{ -side_x + 0.15, floor_top + 0.18, side_center_z }, .{ 0.16, 0.34, side_depth - 0.2 }, materials.studio_wall_trim);
    try addBox(mesh, .{ side_x - 0.15, floor_top + 0.18, side_center_z }, .{ 0.16, 0.34, side_depth - 0.2 }, materials.studio_wall_trim);

    try addStudioRug(mesh);
    try addRigFeatureWall(mesh, side_x);
    try addCeilingCanopy(mesh);
    try addWindowSeat(mesh, back_z);
    try addSculpturalPlant(mesh, .{ 2.4, floor_top, -6.25 });

    try addWindowWall(mesh, back_z, window_bottom, window_top, window_half_width);
    try addOverlookLandscape(mesh, back_z);

    try addWindowRevealLighting(mesh, back_z);
}

fn addStudioRug(mesh: *Mesh) !void {
    // Keep the rug as a distinct furnishing rather than a second floor. Its
    // rear edge sits 170 mm clear of the feature wall and the tighter footprint
    // gives the generated artwork a denser, more credible physical scale.
    const center = [3]f32{ -16.50, 0.315, 0.15 };
    try addBox(mesh, center, .{ 6.80, 0.055, 7.40 }, materials.rug_base);
}

fn addRigFeatureWall(mesh: *Mesh, side_x: f32) !void {
    const wall_x = -side_x;

    // A full-height acoustic wall gives the rig a deliberate architectural
    // home. Horizontal walnut boards calm the center bay while vertical slats
    // absorb and frame it without hiding the amplifier silhouette.
    try addBox(mesh, .{ wall_x + 0.19, 7.85, 0 }, .{ 0.24, 14.7, 18.6 }, materials.walnut_dark);
    try addBox(mesh, .{ wall_x + 0.31, 5.75, 0 }, .{ 0.14, 10.5, 6.9 }, materials.walnut_dark);
    const board_count: usize = 16;
    const board_height: f32 = 0.62;
    const board_gap: f32 = 0.035;
    const panel_height = @as(f32, @floatFromInt(board_count)) * board_height +
        @as(f32, @floatFromInt(board_count - 1)) * board_gap;
    for (0..board_count) |index| {
        const y = 5.75 - panel_height * 0.5 + board_height * 0.5 +
            @as(f32, @floatFromInt(index)) * (board_height + board_gap);
        const material = if (index % 3 == 1) materials.acoustic_slats else materials.walnut;
        try addBox(mesh, .{ wall_x + 0.40, y, 0 }, .{ 0.15, board_height, 6.82 }, material);
    }

    const slat_count: usize = 38;
    const span: f32 = 18.0;
    for (0..slat_count) |index| {
        const z = -span * 0.5 + (@as(f32, @floatFromInt(index)) + 0.5) * span /
            @as(f32, @floatFromInt(slat_count));
        if (@abs(z) < 3.75) continue;
        try addBox(mesh, .{ wall_x + 0.39, 7.75, z }, .{ 0.20, 13.6, 0.22 }, materials.acoustic_slats);
    }

    try addBox(mesh, .{ wall_x + 0.42, 11.05, 0 }, .{ 0.22, 0.28, 7.55 }, materials.walnut);
    try addBox(mesh, .{ wall_x + 0.42, 5.85, -3.68 }, .{ 0.22, 10.7, 0.26 }, materials.walnut);
    try addBox(mesh, .{ wall_x + 0.42, 5.85, 3.68 }, .{ 0.22, 10.7, 0.26 }, materials.walnut);

    // Layered acoustic artwork and a slim display ledge break the center bay
    // into human-scale zones while leaving the amplifier visually dominant.
    try addCylinder(mesh, .{ wall_x + 0.48, 8.10, 0 }, 2.25, 0.16, materials.walnut_dark, .x);
    try addCylinder(mesh, .{ wall_x + 0.59, 8.10, 0 }, 1.72, 0.13, materials.rug_detail, .x);
    try addCylinder(mesh, .{ wall_x + 0.68, 8.10, 0 }, 0.62, 0.10, materials.amplifier_piping, .x);
    try addBox(mesh, .{ wall_x + 0.64, 4.38, 0 }, .{ 0.72, 0.16, 5.1 }, materials.walnut);
    try addCylinder(mesh, .{ wall_x + 0.82, 4.83, -1.45 }, 0.28, 0.82, materials.ceramic, .y);
    try addCylinder(mesh, .{ wall_x + 0.82, 4.73, 0.15 }, 0.38, 0.62, materials.limestone, .y);
    try addCylinder(mesh, .{ wall_x + 0.82, 4.91, 1.55 }, 0.22, 0.98, materials.rug_border, .y);

    for ([_]f32{ -4.08, 4.08 }) |z| {
        try addBox(mesh, .{ wall_x + 0.53, 6.85, z }, .{ 0.06, 11.2, 0.10 }, materials.lamp_warm);
        try mesh.addEmissiveLight(.{
            .position = .{ wall_x + 0.82, 6.6, z },
            .radius = 5.4,
            .color = .{ 1.0, 0.60, 0.30 },
            .intensity = 2.5,
            .direction = .{ 0.94, -0.12, if (z < 0) 0.18 else -0.18 },
            .cone_cosine = 0.52,
        });
    }
}

fn addCeilingCanopy(mesh: *Mesh) !void {
    // A floating walnut raft lowers the visual ceiling above the listening area
    // while leaving the panoramic side of the room open and airy.
    try addBox(mesh, .{ -12.8, 15.65, 1.1 }, .{ 14.8, 0.42, 15.6 }, materials.walnut_dark);
    for (0..9) |index| {
        const z = -5.9 + @as(f32, @floatFromInt(index)) * 1.72;
        try addBox(mesh, .{ -12.8, 15.36, z }, .{ 13.8, 0.16, 0.36 }, materials.walnut);
    }
    try addBox(mesh, .{ -12.8, 15.22, -6.55 }, .{ 13.4, 0.07, 0.10 }, materials.lamp_warm);
    try addBox(mesh, .{ -12.8, 15.22, 8.75 }, .{ 13.4, 0.07, 0.10 }, materials.lamp_warm);
}

fn addWindowSeat(mesh: *Mesh, back_z: f32) !void {
    const center = [3]f32{ -4.4, 1.05, back_z + 1.30 };
    try addBox(mesh, center, .{ 10.6, 1.50, 2.15 }, materials.walnut_dark);
    try addBox(mesh, .{ center[0], center[1] + 0.84, center[2] + 0.08 }, .{ 9.95, 0.38, 1.82 }, materials.linen);
    try addBox(mesh, .{ center[0] - 3.20, center[1] + 1.37, center[2] - 0.62 }, .{ 2.75, 1.20, 0.38 }, materials.olive_linen);
    try addBox(mesh, .{ center[0], center[1] + 1.37, center[2] - 0.62 }, .{ 2.75, 1.20, 0.38 }, materials.linen);
    try addBox(mesh, .{ center[0] + 3.20, center[1] + 1.37, center[2] - 0.62 }, .{ 2.75, 1.20, 0.38 }, materials.rug_border);
}

fn addSculpturalPlant(mesh: *Mesh, base: [3]f32) !void {
    try addCylinder(mesh, .{ base[0], base[1] + 0.55, base[2] }, 0.72, 1.10, materials.ceramic, .y);
    try addCylinder(mesh, .{ base[0], base[1] + 1.48, base[2] }, 0.16, 1.10, materials.walnut_dark, .y);

    const directions = [_][2]f32{
        .{ -0.70, -0.45 },
        .{ 0.62, -0.58 },
        .{ -0.82, 0.30 },
        .{ 0.78, 0.36 },
        .{ -0.28, 0.86 },
        .{ 0.30, 0.92 },
        .{ 0.04, -0.96 },
    };
    for (directions, 0..) |direction_2d, index| {
        const direction = normalized3(.{ direction_2d[0], 0, direction_2d[1] });
        const perpendicular = [3]f32{ -direction[2], 0, direction[0] };
        const height = 2.15 + @as(f32, @floatFromInt(index % 3)) * 0.48;
        const center = [3]f32{
            base[0] + direction[0] * (0.70 + @as(f32, @floatFromInt(index % 2)) * 0.28),
            base[1] + height,
            base[2] + direction[2] * (0.70 + @as(f32, @floatFromInt(index % 2)) * 0.28),
        };
        try addOrientedBox(
            mesh,
            center,
            direction,
            perpendicular,
            0.34,
            1.05,
            0.10,
            if (index % 2 == 0) materials.foliage_a else materials.foliage_b,
        );
    }
}

fn addWindowRevealLighting(mesh: *Mesh, back_z: f32) !void {
    for ([_]f32{ -18.15, 18.15 }) |x| {
        try addBox(mesh, .{ x, 7.65, back_z + 0.37 }, .{ 0.10, 12.2, 0.07 }, materials.lamp_warm);
        try mesh.addEmissiveLight(.{
            .position = .{ x, 7.0, back_z + 0.75 },
            .radius = 6.8,
            .color = .{ 1.0, 0.54, 0.26 },
            .intensity = 2.1,
            .direction = .{ if (x < 0) 0.32 else -0.32, -0.08, 0.93 },
            .cone_cosine = 0.46,
        });
    }
}

fn addLeftWallAcousticPanel(mesh: *Mesh, z: f32, width: f32, height: f32) !void {
    const wall_x: f32 = -20.96;
    const center_y: f32 = 7.5;
    try addBox(mesh, .{ wall_x + 0.20, center_y, z }, .{ 0.22, height, width }, materials.acoustic_panel);
    const slat_count: usize = 14;
    for (0..slat_count) |index| {
        const slat_z = z - width * 0.5 + (@as(f32, @floatFromInt(index)) + 0.5) * width /
            @as(f32, @floatFromInt(slat_count));
        try addBox(mesh, .{ wall_x + 0.335, center_y, slat_z }, .{ 0.075, height * 0.94, 0.085 }, materials.acoustic_slats);
    }
}

fn addWindowWall(mesh: *Mesh, back_z: f32, bottom: f32, top: f32, half_width: f32) !void {
    const front_z = back_z + 0.18;
    const frame_depth: f32 = 0.28;
    const frame_width: f32 = 0.18;
    const height = top - bottom;
    try addBox(mesh, .{ 0, bottom, front_z }, .{ half_width * 2.0, frame_width, frame_depth }, materials.window_frame);
    try addBox(mesh, .{ 0, top, front_z }, .{ half_width * 2.0, frame_width, frame_depth }, materials.window_frame);
    try addBox(mesh, .{ -half_width, bottom + height * 0.5, front_z }, .{ frame_width, height, frame_depth }, materials.window_frame);
    try addBox(mesh, .{ half_width, bottom + height * 0.5, front_z }, .{ frame_width, height, frame_depth }, materials.window_frame);
    for (1..6) |index| {
        const x = -half_width + @as(f32, @floatFromInt(index)) * half_width * 2.0 / 6.0;
        try addBox(mesh, .{ x, bottom + height * 0.5, front_z }, .{ 0.12, height, frame_depth }, materials.window_frame);
    }
    try addBox(mesh, .{ 0, bottom - 0.04, front_z + 0.18 }, .{ half_width * 2.0 + 0.42, 0.24, 0.62 }, materials.studio_wall_trim);
}

fn addOverlookLandscape(mesh: *Mesh, back_z: f32) !void {
    // The view is assembled from a luminous sky and independent terrain
    // layers. Its silhouette intentionally does not reproduce the reference.
    try addBox(mesh, .{ 0, 12.0, back_z - 20.0 }, .{ 60.0, 30.0, 0.18 }, materials.sky);
    try addBox(mesh, .{ 0, 2.15, back_z - 19.8 }, .{ 60.0, 1.8, 0.20 }, materials.horizon);
    try addBox(mesh, .{ 0, 0.04, back_z - 9.8 }, .{ 60.0, 0.18, 20.0 }, materials.valley);
    try addCylinder(mesh, .{ -7.4, 5.85, back_z - 19.65 }, 0.58, 0.16, materials.sun, .z);

    const distant = [_]f32{ 2.10, 2.75, 2.42, 3.25, 2.62, 3.72, 2.85, 3.48, 2.56, 3.05, 2.35, 2.78, 2.05 };
    const middle = [_]f32{ 1.15, 1.58, 1.30, 2.05, 1.48, 2.28, 1.62, 2.12, 1.42, 1.90, 1.22, 1.55, 1.08 };
    try addLandscapeRidge(mesh, back_z - 14.5, 0.12, 28.0, &distant, materials.distant_ridge);
    try addLandscapeRidge(mesh, back_z - 8.0, 0.10, 27.0, &middle, materials.middle_ridge);
}

fn addLandscapeRidge(
    mesh: *Mesh,
    z: f32,
    base_y: f32,
    half_width: f32,
    heights: []const f32,
    material: Material,
) !void {
    if (heights.len < 2) return;
    const normal = [3]f32{ 0, 0, 1 };
    for (0..heights.len - 1) |index| {
        const divisor = @as(f32, @floatFromInt(heights.len - 1));
        const x0 = -half_width + @as(f32, @floatFromInt(index)) * half_width * 2.0 / divisor;
        const x1 = -half_width + @as(f32, @floatFromInt(index + 1)) * half_width * 2.0 / divisor;
        try mesh.triangle(
            vertex(.{ x0, base_y, z }, normal, material),
            vertex(.{ x1, base_y, z }, normal, material),
            vertex(.{ x1, heights[index + 1], z }, normal, material),
        );
        try mesh.triangle(
            vertex(.{ x0, base_y, z }, normal, material),
            vertex(.{ x1, heights[index + 1], z }, normal, material),
            vertex(.{ x0, heights[index], z }, normal, material),
        );
    }
}

fn addWoodWallSconce(mesh: *Mesh, center: [3]f32) !void {
    try addBeveledBox(mesh, center, .{ 1.62, 1.62, 0.38 }, 0.075, materials.sconce_oak);
    try addBox(mesh, .{ center[0], center[1] + 0.84, center[2] + 0.08 }, .{ 1.30, 0.10, 0.28 }, materials.lamp_warm);
    try addBox(mesh, .{ center[0], center[1] - 0.84, center[2] + 0.08 }, .{ 1.30, 0.10, 0.28 }, materials.lamp_warm);
    try mesh.addEmissiveLight(.{
        .position = .{ center[0], center[1] + 0.98, center[2] + 0.48 },
        .radius = 5.2,
        .color = .{ 1.0, 0.68, 0.36 },
        .intensity = 4.0,
        .direction = .{ 0, 0.80, -0.60 },
        .cone_cosine = 0.70,
    });
    try mesh.addEmissiveLight(.{
        .position = .{ center[0], center[1] - 0.98, center[2] + 0.48 },
        .radius = 4.7,
        .color = .{ 1.0, 0.62, 0.30 },
        .intensity = 3.0,
        .direction = .{ 0, -0.80, -0.60 },
        .cone_cosine = 0.70,
    });
}

fn addSideWoodSconce(mesh: *Mesh, center: [3]f32, left: bool) !void {
    const direction = if (left) [3]f32{ 1, 0, 0 } else [3]f32{ -1, 0, 0 };
    const perpendicular = [3]f32{ 0, 0, 1 };
    try addOrientedBox(mesh, center, direction, perpendicular, 0.81, 0.19, 1.62, materials.sconce_oak);
    try addOrientedBox(mesh, .{ center[0], center[1] + 0.84, center[2] }, direction, perpendicular, 0.65, 0.22, 0.10, materials.lamp_warm);
    try addOrientedBox(mesh, .{ center[0], center[1] - 0.84, center[2] }, direction, perpendicular, 0.65, 0.22, 0.10, materials.lamp_warm);
    try mesh.addEmissiveLight(.{
        .position = .{ center[0] + direction[0] * 0.48, center[1] + 0.98, center[2] },
        .radius = 6.8,
        .color = .{ 1.0, 0.64, 0.32 },
        .intensity = 3.2,
        .direction = .{ direction[0] * 0.64, 0.77, direction[2] * 0.64 },
        .cone_cosine = 0.62,
    });
    try mesh.addEmissiveLight(.{
        .position = .{ center[0] + direction[0] * 0.48, center[1] - 0.98, center[2] },
        .radius = 6.0,
        .color = .{ 1.0, 0.56, 0.26 },
        .intensity = 2.6,
        .direction = .{ direction[0] * 0.64, -0.77, direction[2] * 0.64 },
        .cone_cosine = 0.62,
    });
}

fn addAcousticPanel(mesh: *Mesh, x: f32, y: f32, z: f32, width: f32, height: f32) !void {
    try addBox(mesh, .{ x, y, z }, .{ width, height, 0.20 }, materials.acoustic_panel);
    const slat_count: usize = 8;
    for (0..slat_count) |index| {
        const slat_x = x - width * 0.5 + (@as(f32, @floatFromInt(index)) + 0.5) * width /
            @as(f32, @floatFromInt(slat_count));
        try addBox(mesh, .{ slat_x, y, z + 0.125 }, .{ 0.075, height * 0.94, 0.055 }, materials.acoustic_slats);
    }
}

fn addStandingStudioLamp(mesh: *Mesh, base: [3]f32, warm: bool) !void {
    const frame = materials.black_metal;
    try addCylinder(mesh, .{ base[0], base[1] + 0.075, base[2] }, 0.46, 0.15, frame, .y);
    for (0..3) |index| {
        const angle = std.math.tau * @as(f32, @floatFromInt(index)) / 3.0;
        const direction = [3]f32{ @sin(angle), 0, -@cos(angle) };
        const perpendicular = [3]f32{ @cos(angle), 0, @sin(angle) };
        const center = [3]f32{
            base[0] + direction[0] * 0.42,
            base[1] + 0.14,
            base[2] + direction[2] * 0.42,
        };
        try addOrientedBox(mesh, center, direction, perpendicular, 0.055, 0.56, 0.075, frame);
    }
    try addCylinder(mesh, .{ base[0], base[1] + 2.45, base[2] }, 0.075, 4.65, frame, .y);
    try addCylinder(mesh, .{ base[0], base[1] + 4.68, base[2] }, 0.22, 0.20, materials.chrome, .y);

    const head_y: f32 = base[1] + 5.15;
    try addBeveledBox(mesh, .{ base[0], head_y, base[2] }, .{ 1.75, 2.15, 0.42 }, 0.075, frame);
    const panel_material = if (warm) materials.lamp_warm else materials.lamp_cool;
    try addBox(mesh, .{ base[0], head_y, base[2] + 0.235 }, .{ 1.43, 1.82, 0.075 }, panel_material);
    try mesh.addEmissiveLight(.{
        .position = .{ base[0], head_y, base[2] + 0.55 },
        .radius = 8.5,
        .color = if (warm) .{ 1.0, 0.72, 0.46 } else .{ 0.55, 0.72, 1.0 },
        .intensity = if (warm) 2.2 else 1.8,
    });
}

fn addWallSconce(mesh: *Mesh, center: [3]f32) !void {
    try addCylinder(mesh, .{ center[0], center[1], center[2] - 0.04 }, 0.30, 0.16, materials.amplifier_piping, .z);
    try addBox(mesh, .{ center[0], center[1] - 0.34, center[2] + 0.09 }, .{ 0.18, 0.74, 0.18 }, materials.amplifier_piping);
    try addBeveledBox(mesh, .{ center[0], center[1] - 0.88, center[2] + 0.13 }, .{ 0.62, 0.88, 0.32 }, 0.07, materials.black_metal);
    try addBox(mesh, .{ center[0], center[1] - 0.88, center[2] + 0.31 }, .{ 0.44, 0.66, 0.08 }, materials.lamp_warm);
    try mesh.addEmissiveLight(.{
        .position = .{ center[0], center[1] - 0.88, center[2] + 0.58 },
        .radius = 6.0,
        .color = .{ 1.0, 0.66, 0.36 },
        .intensity = 1.6,
    });
}

const AmplifierPalette = struct {
    vinyl: Material,
    grille: Material,
    grille_thread: Material,
    panel: Material,
    piping: Material,
    badge: Material,
};

fn amplifierPalette(style: AmplifierId) AmplifierPalette {
    return switch (style) {
        .dumble => .{
            .vinyl = materials.amplifier_vinyl,
            .grille = materials.amplifier_grille,
            .grille_thread = materials.amplifier_grille_thread,
            .panel = materials.amplifier_panel,
            .piping = materials.amplifier_piping,
            .badge = materials.amplifier_badge,
        },
        .bogner => .{
            .vinyl = materials.bogner_vinyl,
            .grille = materials.bogner_grille,
            .grille_thread = materials.amplifier_vinyl,
            .panel = materials.bogner_panel,
            .piping = materials.amplifier_piping,
            .badge = materials.amplifier_badge,
        },
        .mesa => .{
            .vinyl = materials.mesa_vinyl,
            .grille = materials.mesa_grille,
            .grille_thread = materials.amplifier_panel,
            .panel = materials.mesa_panel,
            .piping = materials.chrome,
            .badge = materials.polished_chrome,
        },
    };
}

fn addAmplifier(mesh: *Mesh, placement: AmplifierPlacement, powered: bool) !void {
    switch (placement.format) {
        .combo => try addComboAmplifier(mesh, placement, powered),
        .head_and_4x12 => try addHeadAndCabinetAmplifier(mesh, placement, powered),
    }
}

fn addComboAmplifier(mesh: *Mesh, placement: AmplifierPlacement, powered: bool) !void {
    const floor_top = equipment_floor_top;
    const center = placement.center;
    const size = combo_size;
    const palette = amplifierPalette(placement.id);
    const vertex_start = mesh.len;
    const front_z = center[2] + size[2] * 0.5;
    const scale_x = size[0] / 5.15;
    const scale_y = size[1] / 3.0;
    const scale_z = size[2] / 1.34;
    const control_scale = @min(scale_x, scale_y);

    try addBeveledBox(mesh, center, size, 0.18, palette.vinyl);

    const grille_center_y = floor_top + 1.22 * scale_y;
    const grille_size = [3]f32{ size[0] - 0.50 * scale_x, 2.05 * scale_y, 0.075 * scale_z };
    try addBox(mesh, .{ center[0], grille_center_y, front_z + 0.045 * scale_z }, grille_size, palette.grille);

    const speaker_z = front_z + 0.090 * scale_z;
    try addCylinder(mesh, .{ center[0], grille_center_y - 0.05 * scale_y, speaker_z }, 0.80 * control_scale, 0.035 * scale_z, materials.rubber, .z);
    try addCylinder(mesh, .{ center[0], grille_center_y - 0.05 * scale_y, speaker_z + 0.025 * scale_z }, 0.30 * control_scale, 0.026 * scale_z, materials.black_metal, .z);

    const grille_left = center[0] - grille_size[0] * 0.5;
    const grille_bottom = grille_center_y - grille_size[1] * 0.5;
    for (0..18) |index| {
        const x = grille_left + (@as(f32, @floatFromInt(index)) + 0.5) * grille_size[0] / 18.0;
        try addBox(mesh, .{ x, grille_center_y, front_z + 0.120 * scale_z }, .{ 0.018 * scale_x, grille_size[1], 0.020 * scale_z }, palette.grille_thread);
    }
    for (0..8) |index| {
        const y = grille_bottom + (@as(f32, @floatFromInt(index)) + 0.5) * grille_size[1] / 8.0;
        try addBox(mesh, .{ center[0], y, front_z + 0.126 * scale_z }, .{ grille_size[0], 0.014 * scale_y, 0.018 * scale_z }, palette.grille_thread);
    }

    const piping_depth: f32 = 0.035 * scale_z;
    const piping_z = front_z + 0.148 * scale_z;
    try addBox(mesh, .{ center[0], grille_center_y + grille_size[1] * 0.5, piping_z }, .{ grille_size[0] + 0.10 * scale_x, 0.050 * scale_y, piping_depth }, palette.piping);
    try addBox(mesh, .{ center[0], grille_center_y - grille_size[1] * 0.5, piping_z }, .{ grille_size[0] + 0.10 * scale_x, 0.050 * scale_y, piping_depth }, palette.piping);
    try addBox(mesh, .{ grille_left, grille_center_y, piping_z }, .{ 0.050 * scale_x, grille_size[1], piping_depth }, palette.piping);
    try addBox(mesh, .{ center[0] + grille_size[0] * 0.5, grille_center_y, piping_z }, .{ 0.050 * scale_x, grille_size[1], piping_depth }, palette.piping);

    const panel_y = floor_top + size[1] - 0.34 * scale_y;
    try addBox(mesh, .{ center[0], panel_y, front_z + 0.080 * scale_z }, .{ size[0] - 0.48 * scale_x, 0.43 * scale_y, 0.11 * scale_z }, palette.panel);
    const power_material = if (powered)
        Material{ .base_color = .{ 0.95, 0.26, 0.035 }, .roughness = 0.18, .metallic = 0.18, .emissive = 2.8 }
    else
        materials.black_metal;
    try addBox(mesh, .{ center[0] - 1.82 * scale_x, panel_y, front_z + 0.150 * scale_z }, .{ 0.18 * scale_x, 0.24 * scale_y, 0.05 * scale_z }, power_material);
    for (0..6) |index| {
        const x = center[0] - 1.20 * scale_x + @as(f32, @floatFromInt(index)) * 0.47 * scale_x;
        try addCylinder(mesh, .{ x, panel_y, front_z + 0.175 * scale_z }, 0.105 * control_scale, 0.105 * scale_z, materials.knob_plastic, .z);
        try addBox(mesh, .{ x, panel_y + 0.070 * scale_y, front_z + 0.235 * scale_z }, .{ 0.018 * scale_x, 0.065 * scale_y, 0.018 * scale_z }, materials.knob_indicator);
    }
    try addCylinder(mesh, .{ center[0] + 1.77 * scale_x, panel_y, front_z + 0.175 * scale_z }, 0.115 * control_scale, 0.11 * scale_z, materials.chrome, .z);
    try addCylinder(mesh, .{ center[0] + 1.77 * scale_x, panel_y, front_z + 0.245 * scale_z }, 0.065 * control_scale, 0.055 * scale_z, materials.rubber, .z);

    try addBox(mesh, .{ center[0] - 1.55 * scale_x, grille_center_y + 0.49 * scale_y, piping_z + 0.035 * scale_z }, .{ 0.62 * scale_x, 0.18 * scale_y, 0.055 * scale_z }, palette.badge);

    const top_y = center[1] + size[1] * 0.5;
    try addBox(mesh, .{ center[0] - 0.72 * scale_x, top_y + 0.11 * scale_y, center[2] }, .{ 0.18 * scale_x, 0.22 * scale_y, 0.38 * scale_z }, materials.chrome);
    try addBox(mesh, .{ center[0] + 0.72 * scale_x, top_y + 0.11 * scale_y, center[2] }, .{ 0.18 * scale_x, 0.22 * scale_y, 0.38 * scale_z }, materials.chrome);
    try addBeveledBox(mesh, .{ center[0], top_y + 0.28 * scale_y, center[2] }, .{ 1.55 * scale_x, 0.22 * scale_y, 0.34 * scale_z }, 0.075, materials.rubber);

    try addBox(mesh, .{ center[0] - size[0] * 0.34, floor_top - 0.035, center[2] }, .{ 0.46 * scale_x, 0.21 * scale_y, 0.62 * scale_z }, materials.rubber);
    try addBox(mesh, .{ center[0] + size[0] * 0.34, floor_top - 0.035, center[2] }, .{ 0.46 * scale_x, 0.21 * scale_y, 0.62 * scale_z }, materials.rubber);

    rotateMeshRangeY(mesh, vertex_start, center, placement.yaw_degrees);
}

fn addHeadAndCabinetAmplifier(mesh: *Mesh, placement: AmplifierPlacement, powered: bool) !void {
    const center = placement.center;
    const palette = amplifierPalette(placement.id);
    const vertex_start = mesh.len;

    // A cabinet is a semantic speaker grid rather than a stretched combo. The
    // same two-by-two layout can later expose four individual speaker targets.
    const cabinet_center = [3]f32{
        center[0],
        equipment_floor_top + bogner_cabinet_size[1] * 0.5,
        center[2],
    };
    const cabinet_front_z = center[2] + bogner_cabinet_size[2] * 0.5;
    try addBeveledBox(mesh, cabinet_center, bogner_cabinet_size, 0.20, palette.vinyl);

    const grille_size = [3]f32{
        bogner_cabinet_size[0] - 0.34,
        bogner_cabinet_size[1] - 0.38,
        0.075,
    };
    const grille_center = [3]f32{
        center[0],
        cabinet_center[1] - 0.02,
        cabinet_front_z + 0.055,
    };
    try addBox(mesh, grille_center, grille_size, palette.grille);

    const speaker_radius: f32 = 0.69;
    const speaker_x_offset: f32 = 0.91;
    const speaker_y_offset: f32 = 0.82;
    for (0..2) |row| {
        for (0..2) |column| {
            const speaker_center = [3]f32{
                center[0] + (if (column == 0) -speaker_x_offset else speaker_x_offset),
                grille_center[1] + (if (row == 0) speaker_y_offset else -speaker_y_offset),
                cabinet_front_z + 0.095,
            };
            try addCylinder(mesh, speaker_center, speaker_radius, 0.045, materials.rubber, .z);
            try addCylinder(mesh, .{ speaker_center[0], speaker_center[1], speaker_center[2] + 0.030 }, speaker_radius * 0.34, 0.035, materials.black_metal, .z);
        }
    }

    const grille_left = center[0] - grille_size[0] * 0.5;
    const grille_bottom = grille_center[1] - grille_size[1] * 0.5;
    for (0..22) |index| {
        const x = grille_left + (@as(f32, @floatFromInt(index)) + 0.5) * grille_size[0] / 22.0;
        try addBox(mesh, .{ x, grille_center[1], cabinet_front_z + 0.135 }, .{ 0.014, grille_size[1], 0.016 }, palette.grille_thread);
    }
    for (0..20) |index| {
        const y = grille_bottom + (@as(f32, @floatFromInt(index)) + 0.5) * grille_size[1] / 20.0;
        try addBox(mesh, .{ center[0], y, cabinet_front_z + 0.140 }, .{ grille_size[0], 0.012, 0.014 }, palette.grille_thread);
    }

    const piping_z = cabinet_front_z + 0.155;
    try addBox(mesh, .{ center[0], grille_center[1] + grille_size[1] * 0.5, piping_z }, .{ grille_size[0] + 0.10, 0.045, 0.030 }, palette.piping);
    try addBox(mesh, .{ center[0], grille_center[1] - grille_size[1] * 0.5, piping_z }, .{ grille_size[0] + 0.10, 0.045, 0.030 }, palette.piping);
    try addBox(mesh, .{ grille_left, grille_center[1], piping_z }, .{ 0.045, grille_size[1], 0.030 }, palette.piping);
    try addBox(mesh, .{ center[0] + grille_size[0] * 0.5, grille_center[1], piping_z }, .{ 0.045, grille_size[1], 0.030 }, palette.piping);
    try addBox(mesh, .{ center[0] - 1.17, grille_center[1] + 1.29, piping_z + 0.025 }, .{ 0.72, 0.17, 0.045 }, palette.badge);

    // Rubber cabinet feet and the small air gap make the head visibly separate
    // from the 4x12 instead of reading as one oversized enclosure.
    try addBox(mesh, .{ center[0] - 1.30, equipment_floor_top - 0.035, center[2] }, .{ 0.42, 0.20, 0.72 }, materials.rubber);
    try addBox(mesh, .{ center[0] + 1.30, equipment_floor_top - 0.035, center[2] }, .{ 0.42, 0.20, 0.72 }, materials.rubber);

    const cabinet_top = equipment_floor_top + bogner_cabinet_size[1];
    const head_center = [3]f32{
        center[0],
        cabinet_top + head_cabinet_gap + bogner_head_size[1] * 0.5,
        center[2],
    };
    try addBox(mesh, .{ center[0] - 1.22, cabinet_top + head_cabinet_gap * 0.5, center[2] }, .{ 0.32, head_cabinet_gap, 0.55 }, materials.rubber);
    try addBox(mesh, .{ center[0] + 1.22, cabinet_top + head_cabinet_gap * 0.5, center[2] }, .{ 0.32, head_cabinet_gap, 0.55 }, materials.rubber);
    try addBeveledBox(mesh, head_center, bogner_head_size, 0.15, palette.vinyl);

    const head_front_z = center[2] + bogner_head_size[2] * 0.5;
    const panel_size = [3]f32{ bogner_head_size[0] - 0.30, 0.50, 0.09 };
    try addBox(mesh, .{ center[0], head_center[1], head_front_z + 0.060 }, panel_size, palette.panel);
    try addBox(mesh, .{ center[0], head_center[1] + 0.39, head_front_z + 0.045 }, .{ panel_size[0], 0.20, 0.075 }, palette.grille);

    const power_material = if (powered)
        Material{ .base_color = .{ 0.95, 0.26, 0.035 }, .roughness = 0.18, .metallic = 0.18, .emissive = 2.8 }
    else
        materials.black_metal;
    try addBox(mesh, .{ center[0] - bogner_head_size[0] * 0.40, head_center[1], head_front_z + 0.075 }, .{ 0.15, 0.28, 0.055 }, power_material);

    for (0..7) |index| {
        const x = center[0] - 1.00 + @as(f32, @floatFromInt(index)) * 0.32;
        try addCylinder(mesh, .{ x, head_center[1], head_front_z + 0.105 }, 0.090, 0.085, materials.knob_plastic, .z);
        try addBox(mesh, .{ x, head_center[1] + 0.058, head_front_z + 0.157 }, .{ 0.014, 0.050, 0.014 }, materials.knob_indicator);
    }
    try addCylinder(mesh, .{ center[0] + 1.37, head_center[1], head_front_z + 0.105 }, 0.105, 0.09, materials.chrome, .z);
    try addCylinder(mesh, .{ center[0] + 1.37, head_center[1], head_front_z + 0.165 }, 0.057, 0.045, materials.rubber, .z);
    try addBox(mesh, .{ center[0] - 1.00, head_center[1] + 0.39, head_front_z + 0.095 }, .{ 0.66, 0.12, 0.04 }, palette.badge);

    const head_top = head_center[1] + bogner_head_size[1] * 0.5;
    try addBox(mesh, .{ center[0] - 0.62, head_top + 0.07, center[2] }, .{ 0.14, 0.14, 0.34 }, materials.chrome);
    try addBox(mesh, .{ center[0] + 0.62, head_top + 0.07, center[2] }, .{ 0.14, 0.14, 0.34 }, materials.chrome);
    try addBeveledBox(mesh, .{ center[0], head_top + 0.18, center[2] }, .{ 1.34, 0.18, 0.29 }, 0.065, materials.rubber);

    rotateMeshRangeY(mesh, vertex_start, center, placement.yaw_degrees);
}

fn rotatePointY(point: [3]f32, center: [3]f32, degrees: f32) [3]f32 {
    const direction = rotateDirectionY(.{ point[0] - center[0], point[1] - center[1], point[2] - center[2] }, degrees);
    return .{ center[0] + direction[0], center[1] + direction[1], center[2] + direction[2] };
}

fn rotateDirectionY(direction: [3]f32, degrees: f32) [3]f32 {
    if (degrees == 0) return direction;
    const radians = degrees * std.math.pi / 180.0;
    const cosine = @cos(radians);
    const sine = @sin(radians);
    return .{
        direction[0] * cosine + direction[2] * sine,
        direction[1],
        -direction[0] * sine + direction[2] * cosine,
    };
}

fn rotateMeshRangeY(mesh: *Mesh, vertex_start: usize, center: [3]f32, degrees: f32) void {
    if (degrees == 0) return;
    for (mesh.vertices[vertex_start..mesh.len]) |*item| {
        const position = rotatePointY(.{ item.position[0], item.position[1], item.position[2] }, center, degrees);
        const normal = rotateDirectionY(.{ item.normal[0], item.normal[1], item.normal[2] }, degrees);
        item.position[0] = position[0];
        item.position[1] = position[1];
        item.position[2] = position[2];
        item.normal[0] = normal[0];
        item.normal[1] = normal[1];
        item.normal[2] = normal[2];
    }
}

fn addPedal(
    mesh: *Mesh,
    pedal: demo.Pedal,
    base: [3]f32,
    size: [3]f32,
    enabled: bool,
    mode: ThreePosition,
    footswitch_mask: ?u8,
) !void {
    const body_material = accentMaterial(pedal.accent);
    if (pedal.presentation == .open) {
        const tray_height = size[1] * 0.42;
        try addBeveledBox(mesh, .{ base[0], base[1] + tray_height * 0.5, base[2] }, .{ size[0], tray_height, size[2] }, pedalDetail(0.10), darkened(body_material, 0.55));
        try addBox(mesh, .{ base[0], base[1] + tray_height + pedalDetail(0.035), base[2] }, .{ size[0] * 0.78, pedalDetail(0.07), size[2] * 0.72 }, materials.pcb);
        try addOpenLid(mesh, base, size, body_material);
        try addComponents(mesh, base, size, tray_height);
    } else {
        try addBeveledBox(mesh, .{ base[0], base[1] + size[1] * 0.5, base[2] }, size, pedalDetail(0.10), body_material);
        try addControls(mesh, pedal, base, size);
        if (pedal.mode_switch != null) try addThreeWayToggle(mesh, base, size, mode);
        try addFootswitches(mesh, pedal, base, size, enabled, footswitch_mask);
    }
    try addPorts(mesh, pedal, base, size);
}

fn addThreeWayToggle(
    mesh: *Mesh,
    base: [3]f32,
    size: [3]f32,
    mode: ThreePosition,
) !void {
    const top = base[1] + size[1];
    const origin = [3]f32{ base[0], top, base[2] - size[2] * 0.01 };

    // Hex nut, raised threaded collar, and reflective washer remain stationary.
    try addCylinderSegments(mesh, .{ origin[0], top + pedalDetail(0.035), origin[2] }, pedalDetail(0.145), pedalDetail(0.070), materials.polished_chrome, .y, 6);
    try addIndicatorWasher(mesh, .{ origin[0], top + pedalDetail(0.070), origin[2] }, pedalDetail(0.070), pedalDetail(0.126));
    try addCylinder(mesh, .{ origin[0], top + pedalDetail(0.105), origin[2] }, pedalDetail(0.073), pedalDetail(0.110), materials.chrome, .y);

    const depth_tilt: f32 = switch (mode) {
        .low => 0.36,
        .middle => 0.0,
        .high => -0.36,
    };
    const direction = normalized3(.{ 0, 0.94, depth_tilt });
    const lever_start = [3]f32{ origin[0], top + pedalDetail(0.125), origin[2] };
    const lever_length: f32 = pedalDetail(0.54);
    const center = [3]f32{
        lever_start[0] + direction[0] * lever_length * 0.5,
        lever_start[1] + direction[1] * lever_length * 0.5,
        lever_start[2] + direction[2] * lever_length * 0.5,
    };
    try addOrientedCylinder(mesh, center, direction, pedalDetail(0.052), lever_length, materials.polished_chrome, 32);
}

fn addOpenLid(mesh: *Mesh, base: [3]f32, size: [3]f32, material: Material) !void {
    const lid_center = [3]f32{ base[0], base[1] + size[1] * 0.82, base[2] - size[2] * 0.53 };
    try addBox(mesh, lid_center, .{ size[0] * 0.96, size[1] * 1.25, pedalDetail(0.12) }, material);
    try addBox(mesh, .{ lid_center[0], lid_center[1], lid_center[2] + pedalDetail(0.07) }, .{ size[0] * 0.76, size[1] * 0.96, pedalDetail(0.04) }, darkened(material, 0.18));
}

fn addComponents(mesh: *Mesh, base: [3]f32, size: [3]f32, tray_height: f32) !void {
    const top = base[1] + tray_height + pedalDetail(0.10);
    var row: usize = 0;
    while (row < 3) : (row += 1) {
        var column: usize = 0;
        while (column < 3) : (column += 1) {
            const x = base[0] + (@as(f32, @floatFromInt(column)) - 1.0) * size[0] * 0.23;
            const z = base[2] + (@as(f32, @floatFromInt(row)) - 1.0) * size[2] * 0.18;
            const material = if ((row + column) % 2 == 0) materials.pointer else materials.black_metal;
            try addBox(mesh, .{ x, top + pedalDetail(0.055), z }, .{ size[0] * 0.13, pedalDetail(0.11), size[2] * 0.08 }, material);
        }
    }
}

fn addControls(mesh: *Mesh, pedal: demo.Pedal, base: [3]f32, size: [3]f32) !void {
    const count = pedal.controls.len;
    if (count == 0) return;
    const columns: usize = if (pedal.enclosure.form_factor == .single and (count == 3 or count == 5))
        3
    else if (pedal.enclosure.form_factor == .double and count == 6)
        3
    else if (pedal.enclosure.form_factor == .double)
        @min(count, 4)
    else
        @min(count, 2);
    const rows = (count + columns - 1) / columns;
    const radius = @min(pedalDetail(0.27), size[0] / (@as(f32, @floatFromInt(columns)) * 3.4));
    for (pedal.controls, 0..) |control, index| {
        const column = index % columns;
        const row = index / columns;
        const controls_in_row = @min(columns, count - row * columns);
        const x = base[0] + size[0] *
            ((@as(f32, @floatFromInt(column)) + 0.5) /
                @as(f32, @floatFromInt(controls_in_row)) - 0.5) * 0.78;
        const row_fraction = if (rows <= 1)
            @as(f32, 0)
        else
            @as(f32, @floatFromInt(row)) / @as(f32, @floatFromInt(rows - 1));
        const z = base[2] + size[2] * (-0.30 + row_fraction * 0.25);
        const knob_base = base[1] + size[1];
        const angle = (-0.75 + control.normalized_value * 1.5) * std.math.pi;
        try addChickenHeadKnob(mesh, .{ x, knob_base, z }, radius, angle);
    }
}

fn addFootswitches(
    mesh: *Mesh,
    pedal: demo.Pedal,
    base: [3]f32,
    size: [3]f32,
    enabled: bool,
    footswitch_mask: ?u8,
) !void {
    const count = @max(@as(usize, 1), @as(usize, pedal.footswitch_count));
    for (0..count) |index| {
        const switch_enabled = if (footswitch_mask) |mask|
            (mask & (@as(u8, 1) << @intCast(index))) != 0
        else
            enabled;
        const brightness = if (switch_enabled) std.math.clamp(pedal.indicator_brightness, 0, 1) else 0;
        const indicator_color = if (index < pedal.indicator_colors.len)
            pedal.indicator_colors[index]
        else
            .green;
        const x = base[0] + size[0] * ((@as(f32, @floatFromInt(index)) + 1.0) / @as(f32, @floatFromInt(count + 1)) - 0.5) * 0.72;
        const z = base[2] + size[2] * 0.29;
        const top = base[1] + size[1];
        const led_z = z - size[2] * 0.16;
        try addFootswitchHardware(mesh, .{ x, top, z });
        try addIndicatorWasher(mesh, .{ x, top + pedalDetail(0.004), led_z }, pedalDetail(0.063), pedalDetail(0.112));
        try addCylinder(mesh, .{ x, top + pedalDetail(0.072), led_z }, pedalDetail(0.060), pedalDetail(0.080), ledLensMaterial(brightness, indicator_color), .y);
        try addCylinder(mesh, .{ x, top + pedalDetail(0.126), led_z }, pedalDetail(0.018), pedalDetail(0.024), ledCoreMaterial(brightness, indicator_color), .y);
        try mesh.addEmissiveLight(.{
            .position = .{ x, top + pedalDetail(0.16), led_z },
            .radius = pedalDetail(0.62),
            .color = indicatorLightColor(indicator_color),
            .intensity = 1.55 * brightness,
        });
    }
}

fn addChickenHeadKnob(mesh: *Mesh, origin: [3]f32, radius: f32, angle: f32) !void {
    const direction = [3]f32{ @sin(angle), 0, -@cos(angle) };
    const perpendicular = [3]f32{ @cos(angle), 0, @sin(angle) };
    const skirt_profile = [_]LatheRing{
        .{ .height = 0.00, .radius = radius * 1.22 },
        .{ .height = pedalDetail(0.08), .radius = radius * 1.22 },
        .{ .height = pedalDetail(0.13), .radius = radius * 1.02 },
        .{ .height = pedalDetail(0.18), .radius = radius * 0.76 },
    };
    try addLathedY(mesh, origin, &skirt_profile, materials.knob_plastic);
    try addBeveledChickenGrip(mesh, origin, direction, perpendicular, radius);

    const stripe_center = knobPoint(origin, direction, perpendicular, radius * 0.22, 0, pedalDetail(0.512));
    try addOrientedBox(mesh, stripe_center, direction, perpendicular, radius * 0.060, radius * 0.48, pedalDetail(0.018), materials.knob_indicator);

    const stripe_top_left = knobPoint(origin, direction, perpendicular, radius * 0.728, -radius * 0.060, pedalDetail(0.475));
    const stripe_top_right = knobPoint(origin, direction, perpendicular, radius * 0.728, radius * 0.060, pedalDetail(0.475));
    const stripe_bottom_right = knobPoint(origin, direction, perpendicular, radius * 0.728, radius * 0.060, pedalDetail(0.18));
    const stripe_bottom_left = knobPoint(origin, direction, perpendicular, radius * 0.728, -radius * 0.060, pedalDetail(0.18));
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
    const lower_height: f32 = pedalDetail(0.12);
    const shoulder_height: f32 = pedalDetail(0.43);
    const top_height: f32 = pedalDetail(0.50);
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
    try addCylinderSegments(mesh, .{ origin[0], origin[1] + pedalDetail(0.027), origin[2] }, pedalDetail(0.23), pedalDetail(0.054), materials.polished_chrome, .y, 6);
    try addIndicatorWasher(mesh, .{ origin[0], origin[1] + pedalDetail(0.052), origin[2] }, pedalDetail(0.112), pedalDetail(0.205));
    const actuator_profile = [_]LatheRing{
        .{ .height = 0.00, .radius = pedalDetail(0.112) },
        .{ .height = pedalDetail(0.10), .radius = pedalDetail(0.112) },
        .{ .height = pedalDetail(0.125), .radius = pedalDetail(0.155) },
        .{ .height = pedalDetail(0.215), .radius = pedalDetail(0.155) },
        .{ .height = pedalDetail(0.240), .radius = pedalDetail(0.140) },
    };
    try addLathedY(mesh, .{ origin[0], origin[1] + pedalDetail(0.060), origin[2] }, &actuator_profile, materials.polished_chrome);
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
                try addCylinder(mesh, .{ x, base[1] + size[1] + pedalDetail(0.08), z }, pedalDetail(0.14), pedalDetail(0.16), materials.chrome, .y);
                try addCylinder(mesh, .{ x, base[1] + size[1] + pedalDetail(0.17), z }, pedalDetail(0.075), pedalDetail(0.08), materials.rubber, .y);
            },
            .left_side => {
                try addSideJack(
                    mesh,
                    .{ base[0] - size[0] * 0.5, base[1] + size[1] * 0.68, base[2] + slot * size[2] },
                    -1,
                );
            },
            .right_side => {
                try addSideJack(
                    mesh,
                    .{ base[0] + size[0] * 0.5, base[1] + size[1] * 0.68, base[2] + slot * size[2] },
                    1,
                );
            },
        }
    }
}

fn addSideJack(mesh: *Mesh, mount: [3]f32, outward: f32) !void {
    // A real side socket reads as a layered assembly: mounting nut, washer,
    // threaded barrel, insulating collar, then the recessed connector mouth.
    try addCylinderSegments(
        mesh,
        .{ mount[0] + outward * pedalDetail(0.035), mount[1], mount[2] },
        pedalDetail(0.185),
        pedalDetail(0.070),
        materials.polished_chrome,
        .x,
        6,
    );
    try addCylinder(
        mesh,
        .{ mount[0] + outward * pedalDetail(0.078), mount[1], mount[2] },
        pedalDetail(0.158),
        pedalDetail(0.034),
        materials.polished_chrome,
        .x,
    );
    try addCylinder(
        mesh,
        .{ mount[0] + outward * pedalDetail(0.130), mount[1], mount[2] },
        pedalDetail(0.119),
        pedalDetail(0.105),
        materials.chrome,
        .x,
    );
    try addCylinder(
        mesh,
        .{ mount[0] + outward * pedalDetail(0.187), mount[1], mount[2] },
        pedalDetail(0.101),
        pedalDetail(0.045),
        materials.black_metal,
        .x,
    );
    try addCylinder(
        mesh,
        .{ mount[0] + outward * pedalDetail(0.213), mount[1], mount[2] },
        pedalDetail(0.083),
        pedalDetail(0.026),
        materials.polished_chrome,
        .x,
    );
    try addAxialDisc(
        mesh,
        .{ mount[0] + outward * pedalDetail(0.228), mount[1], mount[2] },
        pedalDetail(0.058),
        .x,
        outward,
        materials.rubber,
    );
}

fn addAxialDisc(
    mesh: *Mesh,
    center: [3]f32,
    radius: f32,
    axis: Axis,
    facing: f32,
    material: Material,
) !void {
    const segments: usize = 48;
    const normal = axisVector(axis, facing);
    for (0..segments) |segment| {
        const angle0 = std.math.tau * @as(f32, @floatFromInt(segment)) / @as(f32, @floatFromInt(segments));
        const angle1 = std.math.tau * @as(f32, @floatFromInt(segment + 1)) / @as(f32, @floatFromInt(segments));
        const edge0 = cylinderPoint(center, axis, 0, radius, angle0);
        const edge1 = cylinderPoint(center, axis, 0, radius, angle1);
        if (facing > 0) {
            try mesh.triangle(vertex(center, normal, material), vertex(edge1, normal, material), vertex(edge0, normal, material));
        } else {
            try mesh.triangle(vertex(center, normal, material), vertex(edge0, normal, material), vertex(edge1, normal, material));
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
        .{ .radius = outer_radius * 0.96, .height = pedalDetail(0.018), .radial_normal = 0.76, .up_normal = 0.65 },
        .{ .radius = inner_radius + (outer_radius - inner_radius) * 0.67, .height = pedalDetail(0.036), .radial_normal = 0.15, .up_normal = 0.99 },
        .{ .radius = inner_radius + (outer_radius - inner_radius) * 0.24, .height = pedalDetail(0.031), .radial_normal = -0.35, .up_normal = 0.94 },
        .{ .radius = inner_radius, .height = pedalDetail(0.010), .radial_normal = -0.80, .up_normal = 0.60 },
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

fn addOrientedCylinder(
    mesh: *Mesh,
    center: [3]f32,
    direction_value: [3]f32,
    radius: f32,
    length: f32,
    material: Material,
    segments: usize,
) !void {
    const direction = normalized3(direction_value);
    const tangent = normalized3(cross3(direction, .{ 1, 0, 0 }));
    const bitangent = normalized3(cross3(direction, tangent));
    const half_axis = [3]f32{
        direction[0] * length * 0.5,
        direction[1] * length * 0.5,
        direction[2] * length * 0.5,
    };
    const lower_center = [3]f32{ center[0] - half_axis[0], center[1] - half_axis[1], center[2] - half_axis[2] };
    const upper_center = [3]f32{ center[0] + half_axis[0], center[1] + half_axis[1], center[2] + half_axis[2] };
    for (0..segments) |index| {
        const angle0 = std.math.tau * @as(f32, @floatFromInt(index)) / @as(f32, @floatFromInt(segments));
        const angle1 = std.math.tau * @as(f32, @floatFromInt(index + 1)) / @as(f32, @floatFromInt(segments));
        const normal0 = normalized3(.{
            tangent[0] * @cos(angle0) + bitangent[0] * @sin(angle0),
            tangent[1] * @cos(angle0) + bitangent[1] * @sin(angle0),
            tangent[2] * @cos(angle0) + bitangent[2] * @sin(angle0),
        });
        const normal1 = normalized3(.{
            tangent[0] * @cos(angle1) + bitangent[0] * @sin(angle1),
            tangent[1] * @cos(angle1) + bitangent[1] * @sin(angle1),
            tangent[2] * @cos(angle1) + bitangent[2] * @sin(angle1),
        });
        const lower0 = [3]f32{ lower_center[0] + normal0[0] * radius, lower_center[1] + normal0[1] * radius, lower_center[2] + normal0[2] * radius };
        const lower1 = [3]f32{ lower_center[0] + normal1[0] * radius, lower_center[1] + normal1[1] * radius, lower_center[2] + normal1[2] * radius };
        const upper0 = [3]f32{ upper_center[0] + normal0[0] * radius, upper_center[1] + normal0[1] * radius, upper_center[2] + normal0[2] * radius };
        const upper1 = [3]f32{ upper_center[0] + normal1[0] * radius, upper_center[1] + normal1[1] * radius, upper_center[2] + normal1[2] * radius };
        try mesh.triangle(vertex(lower0, normal0, material), vertex(upper0, normal0, material), vertex(upper1, normal1, material));
        try mesh.triangle(vertex(lower0, normal0, material), vertex(upper1, normal1, material), vertex(lower1, normal1, material));
        try mesh.triangle(vertex(upper_center, direction, material), vertex(upper1, direction, material), vertex(upper0, direction, material));
        const lower_normal = [3]f32{ -direction[0], -direction[1], -direction[2] };
        try mesh.triangle(vertex(lower_center, lower_normal, material), vertex(lower0, lower_normal, material), vertex(lower1, lower_normal, material));
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
        .material = .{ material.roughness, material.metallic, material.emissive, material.texture_slot },
    };
}

fn indicatorLightColor(color: demo.IndicatorColor) [3]f32 {
    return switch (color) {
        .green => .{ 0.012, 1.0, 0.075 },
        .amber => .{ 1.0, 0.34, 0.008 },
        .red => .{ 1.0, 0.018, 0.006 },
    };
}

fn ledLensMaterial(brightness: f32, color: demo.IndicatorColor) Material {
    const level = 0.08 + brightness * 0.92;
    const light_color = indicatorLightColor(color);
    return .{
        .base_color = .{
            light_color[0] * 0.32 * level,
            light_color[1] * 0.32 * level,
            light_color[2] * 0.32 * level,
        },
        .roughness = 0.09,
        .metallic = 0.02,
        .emissive = 1.8 * brightness,
    };
}

fn ledCoreMaterial(brightness: f32, color: demo.IndicatorColor) Material {
    const level = 0.05 + brightness * 0.95;
    const light_color = indicatorLightColor(color);
    return .{
        .base_color = .{
            light_color[0] * 0.72 * level,
            light_color[1] * 0.72 * level,
            light_color[2] * 0.72 * level,
        },
        .roughness = 0.05,
        .metallic = 0,
        .emissive = 4.6 * brightness,
    };
}

fn accentMaterial(accent: demo.Accent) Material {
    return .{
        .base_color = switch (accent) {
            .cyan => .{ 0.055, 0.31, 0.42 },
            .blue => .{ 0.025, 0.10, 0.30 },
            .green => .{ 0.055, 0.32, 0.18 },
            .amber => .{ 0.58, 0.20, 0.025 },
            .gold => .{ 0.62, 0.34, 0.045 },
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

fn projectToWindow(point: [3]f32, pose: CameraPose, viewport_aspect: f32) ?[2]f32 {
    const forward = normalized3(.{
        pose.target[0] - pose.camera[0],
        pose.target[1] - pose.camera[1],
        pose.target[2] - pose.camera[2],
    });
    const right = normalized3(cross3(forward, .{ 0, 1, 0 }));
    const camera_up = cross3(right, forward);
    const relative = [3]f32{
        point[0] - pose.camera[0],
        point[1] - pose.camera[1],
        point[2] - pose.camera[2],
    };
    const depth = dot3(relative, forward);
    if (depth <= 0.01) return null;
    const tangent = @tan(pose.field_of_view_degrees * std.math.pi / 360.0);
    const ndc_x = dot3(relative, right) / (depth * tangent * viewport_aspect);
    const ndc_y = dot3(relative, camera_up) / (depth * tangent);
    const window_x = 2.0 * (studio_viewport.left + (ndc_x + 1.0) * 0.5 * studio_viewport.width) - 1.0;
    const top_fraction = studio_viewport.top + (1.0 - ndc_y) * 0.5 * studio_viewport.height;
    return .{ window_x, 1.0 - 2.0 * top_fraction };
}

fn cross3(a: [3]f32, b: [3]f32) [3]f32 {
    return .{
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    };
}

fn dot3(a: [3]f32, b: [3]f32) f32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

test "semantic pedalboard produces bounded 3D geometry" {
    var mesh = Mesh{};
    try build(&mesh, &demo.rig, .{});
    try std.testing.expect(mesh.len > 30_000);
    try std.testing.expect(mesh.len < Mesh.max_vertices);
    try std.testing.expectEqual(@as(usize, 10), mesh.emissiveLights().len);
    try std.testing.expectEqual(@as(usize, 0), mesh.len % 3);
    for (mesh.items()) |item| {
        for (item.position) |value| try std.testing.expect(std.math.isFinite(value));
        for (item.normal) |value| try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(item.material[0] >= 0.04 and item.material[0] <= 1.0);
        try std.testing.expect(item.material[1] >= 0 and item.material[1] <= 1.0);
        try std.testing.expect(item.material[2] >= 0 and item.material[2] <= 16.0);
    }
    for (mesh.emissiveLights()) |light| {
        try std.testing.expect(light.radius > 0 and light.radius <= 10.0);
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
    try build(&mesh, &rig, .{});
    try std.testing.expect(mesh.len > 35_000);
}

test "each amplifier format projects to a clickable rig-view region" {
    const window_aspect = 1200.0 / 760.0;
    const viewport_aspect = window_aspect * studio_viewport.width / studio_viewport.height;
    for (amplifier_placements) |placement| {
        const projected_center = projectToWindow(equipmentPoint(placement.center), rig_camera, viewport_aspect) orelse return error.ComboBehindCamera;
        try std.testing.expectEqual(placement.id, amplifierAt(projected_center, window_aspect).?);
    }
    try std.testing.expect(!hitTestAmplifier(.{ 0.90, -0.80 }, 1200.0 / 760.0));
}

test "studio equipment shares a physical world scale" {
    const single_width = demo.rig.pedals[0].enclosure.dimensions.width * millimetres_to_world;
    const single_depth = demo.rig.pedals[0].enclosure.dimensions.depth * millimetres_to_world;
    try std.testing.expectApproxEqAbs(@as(f32, 0.35), single_width, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 0.610), single_depth, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f32, 620.0 / 70.0), combo_size[0] / single_width, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 500.0 / 55.0), combo_size[1] / (demo.rig.pedals[0].enclosure.dimensions.height * millimetres_to_world), 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 780.0), bogner_cabinet_size[0] / millimetres_to_world, 0.001);
    try std.testing.expectApproxEqAbs(@as(f32, 740.0), bogner_cabinet_size[1] / millimetres_to_world, 0.001);
    try std.testing.expectEqual(AmplifierFormat.head_and_4x12, amplifierPlacement(.bogner).format);
}

test "studio rug selects the generated base-color texture slot" {
    var mesh = Mesh{};
    try build(&mesh, &demo.rig, .{});
    var textured_vertex_count: usize = 0;
    for (mesh.items()) |item| {
        if (item.material[3] > 0.5) textured_vertex_count += 1;
    }
    try std.testing.expectEqual(@as(usize, 36), textured_vertex_count);
}

test "focused combo remains clickable for direct return navigation" {
    const projected_center = projectToWindow(equipmentPoint(combo_center), amplifier_camera, (1200.0 / 760.0) * studio_viewport.width / studio_viewport.height) orelse return error.ComboBehindCamera;
    try std.testing.expect(hitTestFocusedAmplifier(projected_center, 1200.0 / 760.0, .dumble));
}

test "each focused amplifier exposes its own power switch hit target" {
    const window_aspect = 1200.0 / 760.0;
    const viewport_aspect = window_aspect * studio_viewport.width / studio_viewport.height;
    for (amplifier_placements) |placement| {
        const projected = projectToWindow(
            equipmentPoint(amplifierPowerCanonicalCenter(placement)),
            amplifierCamera(placement.id),
            viewport_aspect,
        ) orelse return error.PowerSwitchBehindCamera;
        try std.testing.expect(hitTestAmplifierPower(projected, window_aspect, placement.id));
    }
}

test "first semantic footswitch is picked at its projected position" {
    const aspect: f32 = 1200.0 / 760.0;
    const placement = pedalPlacement(&demo.rig, 0) orelse return error.MissingFirstPedal;
    const center_world = [3]f32{
        placement.base[0],
        placement.base[1] + placement.size[1] + pedalDetail(0.18),
        placement.base[2] + placement.size[2] * 0.29,
    };
    const projected = projectToWindow(
        equipmentPoint(center_world),
        rig_camera,
        aspect * studio_viewport.width / studio_viewport.height,
    ) orelse return error.FootswitchBehindCamera;
    try std.testing.expect(hitTestPedalFootswitch(projected, aspect, &demo.rig, 0, 0));
    try std.testing.expect(!hitTestPedalFootswitch(.{ -0.95, 0.90 }, aspect, &demo.rig, 0, 0));
}

test "disabled first pedal keeps its LED geometry but removes emission" {
    var mesh = Mesh{};
    const enabled = [_]bool{false};
    try build(&mesh, &demo.rig, .{ .pedal_enabled = &enabled });
    const pedal_light_start = mesh.emissiveLights().len - 6;
    try std.testing.expectEqual(@as(f32, 0.0), mesh.emissiveLights()[pedal_light_start].intensity);
}

test "dual pedal footswitch mask controls each LED independently" {
    var mesh = Mesh{};
    const masks = [_]u8{ 1, 0, 0, 1, 0 };
    try build(&mesh, &demo.rig, .{ .pedal_footswitch_masks = &masks });
    const pedal_light_start = mesh.emissiveLights().len - 6;
    try std.testing.expect(mesh.emissiveLights()[pedal_light_start + 3].intensity > 0);
    try std.testing.expectEqual(@as(f32, 0.0), mesh.emissiveLights()[pedal_light_start + 4].intensity);
    try std.testing.expectEqual(@as([3]f32, .{ 1.0, 0.34, 0.008 }), mesh.emissiveLights()[pedal_light_start + 3].color);
    try std.testing.expectEqual(@as([3]f32, .{ 1.0, 0.018, 0.006 }), mesh.emissiveLights()[pedal_light_start + 4].color);
}

test "effects-loop pedals occupy a centered row behind the input chain" {
    const input_placement = pedalPlacement(&demo.rig, 0) orelse return error.MissingInputPedal;
    const loop_placement = pedalPlacement(&demo.rig, 4) orelse return error.MissingLoopPedal;
    try std.testing.expect(loop_placement.base[2] < input_placement.base[2]);
    try std.testing.expectApproxEqAbs(@as(f32, 0), loop_placement.base[0], 0.0001);
    const loop_front = loop_placement.base[2] + loop_placement.size[2] * 0.5;
    const input_back = input_placement.base[2] - input_placement.size[2] * 0.5;
    try std.testing.expect(loop_front < input_back);
}

test "both King of Tone footswitches are independently pickable" {
    const aspect: f32 = 1200.0 / 760.0;
    const placement = pedalPlacement(&demo.rig, 3) orelse return error.MissingKingOfTone;
    for (0..2) |footswitch_index| {
        const x = placement.base[0] + placement.size[0] *
            ((@as(f32, @floatFromInt(footswitch_index)) + 1.0) / 3.0 - 0.5) * 0.72;
        const center_world = [3]f32{
            x,
            placement.base[1] + placement.size[1] + pedalDetail(0.18),
            placement.base[2] + placement.size[2] * 0.29,
        };
        const projected = projectToWindow(
            equipmentPoint(center_world),
            rig_camera,
            aspect * studio_viewport.width / studio_viewport.height,
        ) orelse return error.FootswitchBehindCamera;
        try std.testing.expect(hitTestPedalFootswitch(
            projected,
            aspect,
            &demo.rig,
            3,
            footswitch_index,
        ));
    }
}

test "first pedal three-way toggle is picked at its projected position" {
    const aspect: f32 = 1200.0 / 760.0;
    const placement = pedalPlacement(&demo.rig, 0) orelse return error.MissingFirstPedal;
    const projected = projectToWindow(
        equipmentPoint(modeSwitchCenter(placement)),
        rig_camera,
        aspect * studio_viewport.width / studio_viewport.height,
    ) orelse return error.ToggleBehindCamera;
    try std.testing.expect(hitTestPedalModeSwitch(projected, aspect, &demo.rig, 0));
    try std.testing.expect(!hitTestPedalModeSwitch(.{ -0.95, 0.90 }, aspect, &demo.rig, 0));
    try std.testing.expect(!hitTestPedalModeSwitch(projected, aspect, &demo.rig, 1));
}
