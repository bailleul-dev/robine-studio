pub const Control = struct {
    role: []const u8,
    label: []const u8,
    normalized_value: f32,
};

pub const PedalFormFactor = enum {
    mini,
    single,
    double,
    custom,
};

pub const DimensionsMm = struct {
    width: f32,
    depth: f32,
    height: f32,
};

pub const PedalEnclosure = struct {
    id: []const u8,
    form_factor: PedalFormFactor,
    footprint_units: f32,
    dimensions: DimensionsMm,
};

pub const JackSurface = enum {
    left_side,
    right_side,
    top,
};

pub const SurfaceSlot = enum {
    start,
    center,
    end,
};

pub const PortRole = enum {
    input,
    output,
};

pub const PedalPort = struct {
    id: []const u8,
    role: PortRole,
    surface: JackSurface,
    slot: SurfaceSlot,
};

pub const enclosures = struct {
    pub const mini = PedalEnclosure{
        .id = "generic.mini",
        .form_factor = .mini,
        .footprint_units = 0.65,
        .dimensions = .{ .width = 45, .depth = 95, .height = 48 },
    };
    pub const single = PedalEnclosure{
        .id = "generic.single",
        .form_factor = .single,
        .footprint_units = 1,
        .dimensions = .{ .width = 70, .depth = 122, .height = 55 },
    };
    pub const double = PedalEnclosure{
        .id = "generic.double",
        .form_factor = .double,
        .footprint_units = 2,
        .dimensions = .{ .width = 145, .depth = 122, .height = 55 },
    };
};

pub const Presentation = enum {
    closed,
    open,
};

pub const Accent = enum {
    cyan,
    green,
    amber,
    violet,
    coral,
};

pub const AudioProcessor = struct {
    format: enum { nam },
    resource_id: []const u8,
    capture_variant: []const u8,
};

pub const ThreeWaySwitch = struct {
    role: []const u8,
    label: []const u8,
    positions: [3][]const u8,
    default_position: @import("../core/equipment_state.zig").ThreePosition,
    movement: enum { front_to_back },
};

pub const Pedal = struct {
    role: []const u8,
    name: []const u8,
    controls: []const Control,
    ports: []const PedalPort,
    enclosure: PedalEnclosure = enclosures.single,
    presentation: Presentation = .closed,
    accent: Accent,
    footswitch_count: u8 = 1,
    indicator_brightness: f32 = 1.0,
    processor: ?AudioProcessor = null,
    mode_switch: ?ThreeWaySwitch = null,
};

pub const Amplifier = struct {
    name: []const u8,
    controls: []const Control,
};

pub const Cabinet = struct {
    name: []const u8,
    speaker_count: u8,
};

pub const Endpoint = union(enum) {
    rig_input,
    pedal_input: usize,
    pedal_output: usize,
    amplifier_input,
};

pub const Connection = struct {
    from: Endpoint,
    to: Endpoint,
};

pub const Rig = struct {
    amplifier: Amplifier,
    cabinet: Cabinet,
    pedals: []const Pedal,
    connections: []const Connection,
};

const amp_controls = [_]Control{
    .{ .role = "gain", .label = "GAIN", .normalized_value = 0.72 },
    .{ .role = "bass", .label = "BASS", .normalized_value = 0.55 },
    .{ .role = "middle", .label = "MID", .normalized_value = 0.61 },
    .{ .role = "treble", .label = "TREBLE", .normalized_value = 0.48 },
    .{ .role = "presence", .label = "PRES", .normalized_value = 0.66 },
    .{ .role = "master", .label = "MASTER", .normalized_value = 0.42 },
};

const fuzz_controls = [_]Control{
    .{ .role = "output", .label = "OUTPUT", .normalized_value = 0.58 },
    .{ .role = "distortion", .label = "DIST", .normalized_value = 0.76 },
};

const phaser_controls = [_]Control{
    .{ .role = "intensity", .label = "INTENSITY", .normalized_value = 0.36 },
    .{ .role = "speed", .label = "SPEED", .normalized_value = 0.69 },
};

const modulation_controls = [_]Control{
    .{ .role = "depth", .label = "DEPTH", .normalized_value = 0.22 },
    .{ .role = "shape", .label = "SHAPE", .normalized_value = 0.67 },
    .{ .role = "wave", .label = "WAVE", .normalized_value = 0.51 },
    .{ .role = "rate", .label = "RATE", .normalized_value = 0.74 },
};

const drive_controls = [_]Control{
    .{ .role = "tone", .label = "TONE", .normalized_value = 0.42 },
    .{ .role = "contour", .label = "CONTOUR", .normalized_value = 0.55 },
    .{ .role = "volume", .label = "VOLUME", .normalized_value = 0.63 },
    .{ .role = "gain", .label = "GAIN", .normalized_value = 0.78 },
};

const side_ports = [_]PedalPort{
    .{ .id = "audio.input", .role = .input, .surface = .right_side, .slot = .start },
    .{ .id = "audio.output", .role = .output, .surface = .left_side, .slot = .start },
};

const pedals = [_]Pedal{
    .{
        .role = "compressor",
        .name = "SP COMPRESSOR",
        .controls = &.{},
        .ports = &side_ports,
        .enclosure = enclosures.single,
        .accent = .cyan,
        .processor = .{
            .format = .nam,
            .resource_id = "nam.sp-compressor",
            .capture_variant = "mid",
        },
        .mode_switch = .{
            .role = "compression_range",
            .label = "RANGE",
            .positions = .{ "LOW", "MID", "HIGH" },
            .default_position = .middle,
            .movement = .front_to_back,
        },
    },
    .{
        .role = "fuzz_service",
        .name = "FUZZ",
        .controls = &fuzz_controls,
        .ports = &side_ports,
        .enclosure = enclosures.single,
        .accent = .coral,
        .indicator_brightness = 0.82,
    },
    .{
        .role = "phaser",
        .name = "PHASER",
        .controls = &phaser_controls,
        .ports = &side_ports,
        .enclosure = enclosures.single,
        .accent = .amber,
        .indicator_brightness = 0.72,
    },
    .{
        .role = "modulation",
        .name = "MODULATION",
        .controls = &modulation_controls,
        .ports = &side_ports,
        .enclosure = enclosures.double,
        .accent = .green,
        .footswitch_count = 2,
        .indicator_brightness = 0.90,
    },
    .{
        .role = "overdrive",
        .name = "OVERDRIVE",
        .controls = &drive_controls,
        .ports = &side_ports,
        .enclosure = enclosures.single,
        .accent = .violet,
        .footswitch_count = 2,
        .indicator_brightness = 1.0,
    },
};

const connections = [_]Connection{
    .{ .from = .rig_input, .to = .{ .pedal_input = 0 } },
    .{ .from = .{ .pedal_output = 0 }, .to = .{ .pedal_input = 1 } },
    .{ .from = .{ .pedal_output = 1 }, .to = .{ .pedal_input = 2 } },
    .{ .from = .{ .pedal_output = 2 }, .to = .{ .pedal_input = 3 } },
    .{ .from = .{ .pedal_output = 3 }, .to = .{ .pedal_input = 4 } },
    .{ .from = .{ .pedal_output = 4 }, .to = .amplifier_input },
};

pub const rig = Rig{
    .amplifier = .{ .name = "ROBINE 50", .controls = &amp_controls },
    .cabinet = .{ .name = "2 × 12 CABINET", .speaker_count = 2 },
    .pedals = &pedals,
    .connections = &connections,
};

test "demo rig is connected semantically" {
    const std = @import("std");
    try std.testing.expectEqual(@as(usize, 5), rig.pedals.len);
    try std.testing.expectEqual(rig.pedals.len + 1, rig.connections.len);
    try std.testing.expectEqual(Presentation.closed, rig.pedals[1].presentation);
    try std.testing.expectEqual(PedalFormFactor.double, rig.pedals[3].enclosure.form_factor);
    try std.testing.expectEqual(@as(f32, 2), rig.pedals[3].enclosure.footprint_units);
    try std.testing.expectEqual(JackSurface.right_side, rig.pedals[0].ports[0].surface);
    try std.testing.expectEqual(JackSurface.left_side, rig.pedals[0].ports[1].surface);
    try std.testing.expectEqual(JackSurface.right_side, rig.pedals[1].ports[0].surface);
    try std.testing.expectEqual(JackSurface.left_side, rig.pedals[1].ports[1].surface);
    try std.testing.expectEqual(JackSurface.right_side, rig.pedals[3].ports[0].surface);
    try std.testing.expectEqual(JackSurface.left_side, rig.pedals[3].ports[1].surface);
    try std.testing.expectEqual(PortRole.output, rig.pedals[3].ports[1].role);
    try std.testing.expectEqual(@as(u8, 2), rig.cabinet.speaker_count);
    try std.testing.expectEqualStrings("nam.sp-compressor", rig.pedals[0].processor.?.resource_id);
    try std.testing.expectEqualStrings("mid", rig.pedals[0].processor.?.capture_variant);
    try std.testing.expectEqualStrings("MID", rig.pedals[0].mode_switch.?.positions[1]);
    try std.testing.expectEqual(
        @import("../core/equipment_state.zig").ThreePosition.middle,
        rig.pedals[0].mode_switch.?.default_position,
    );
    for (rig.pedals) |pedal| {
        try std.testing.expect(pedal.indicator_brightness >= 0 and pedal.indicator_brightness <= 1);
    }
}
