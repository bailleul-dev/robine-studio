pub const Control = struct {
    role: []const u8,
    label: []const u8,
    normalized_value: f32,
};

pub const Enclosure = enum {
    compact,
    standard,
    wide,
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

pub const Pedal = struct {
    role: []const u8,
    name: []const u8,
    controls: []const Control,
    enclosure: Enclosure = .standard,
    presentation: Presentation = .closed,
    accent: Accent,
    footswitch_count: u8 = 1,
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

const compressor_controls = [_]Control{
    .{ .role = "level", .label = "LEVEL", .normalized_value = 0.61 },
    .{ .role = "sensitivity", .label = "SENS", .normalized_value = 0.48 },
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

const pedals = [_]Pedal{
    .{
        .role = "compressor",
        .name = "COMPRESSOR",
        .controls = &compressor_controls,
        .enclosure = .standard,
        .accent = .cyan,
    },
    .{
        .role = "fuzz_service",
        .name = "FUZZ",
        .controls = &fuzz_controls,
        .enclosure = .standard,
        .presentation = .open,
        .accent = .coral,
    },
    .{
        .role = "phaser",
        .name = "PHASER",
        .controls = &phaser_controls,
        .enclosure = .standard,
        .accent = .amber,
    },
    .{
        .role = "modulation",
        .name = "MODULATION",
        .controls = &modulation_controls,
        .enclosure = .wide,
        .accent = .green,
        .footswitch_count = 2,
    },
    .{
        .role = "overdrive",
        .name = "OVERDRIVE",
        .controls = &drive_controls,
        .enclosure = .standard,
        .accent = .violet,
        .footswitch_count = 2,
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
    try std.testing.expectEqual(Presentation.open, rig.pedals[1].presentation);
    try std.testing.expectEqual(@as(u8, 2), rig.cabinet.speaker_count);
}
