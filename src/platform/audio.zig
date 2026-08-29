const std = @import("std");

pub const Backend = enum {
    core_audio,
    asio,
    pipewire,
    alsa,
    fake,
};

pub const Direction = enum {
    input,
    output,
    duplex,
};

pub const SampleKind = enum {
    floating_point,
    signed_integer,
};

pub const ByteOrder = enum {
    native,
    little,
    big,
};

/// Describes linear PCM without losing ASIO's integer-in-container variants
/// such as 24 valid bits in a 32-bit slot.
pub const SampleFormat = struct {
    kind: SampleKind,
    container_bytes: u8,
    valid_bits: u8,
    byte_order: ByteOrder = .native,
    aligned_high: bool = false,

    pub const f32_native: SampleFormat = .{
        .kind = .floating_point,
        .container_bytes = 4,
        .valid_bits = 32,
    };

    pub const f64_native: SampleFormat = .{
        .kind = .floating_point,
        .container_bytes = 8,
        .valid_bits = 64,
    };

    pub fn validate(self: SampleFormat) !void {
        if (self.container_bytes == 0) return error.EmptySampleContainer;
        if (self.valid_bits == 0 or self.valid_bits > self.container_bytes * 8) {
            return error.InvalidValidBitCount;
        }
        if (self.kind == .floating_point and
            !((self.container_bytes == 4 and self.valid_bits == 32) or
                (self.container_bytes == 8 and self.valid_bits == 64)))
        {
            return error.UnsupportedFloatingPointFormat;
        }
    }
};

pub const ClockRelation = enum {
    synchronous,
    asynchronous,
    unknown,
};

/// A channel view can represent planar or interleaved native storage. For a
/// planar buffer `stride_bytes` is one sample; for an interleaved buffer it is
/// one complete frame.
pub const InputChannelView = struct {
    bytes: [*]const u8,
    stride_bytes: u16,
};

pub const OutputChannelView = struct {
    bytes: [*]u8,
    stride_bytes: u16,
};

pub const InputBuffer = struct {
    channels: []const InputChannelView,
    format: SampleFormat,
};

pub const OutputBuffer = struct {
    channels: []const OutputChannelView,
    format: SampleFormat,
};

pub const TimeValidity = struct {
    pub const sample_position: u8 = 1 << 0;
    pub const monotonic_ns: u8 = 1 << 1;
    pub const input_acquisition_ns: u8 = 1 << 2;
    pub const output_presentation_ns: u8 = 1 << 3;
};

pub const StreamTime = struct {
    valid: u8 = 0,
    sample_position: i64 = 0,
    monotonic_ns: u64 = 0,
    input_acquisition_ns: u64 = 0,
    output_presentation_ns: u64 = 0,

    pub fn has(self: StreamTime, flag: u8) bool {
        return self.valid & flag != 0;
    }
};

pub const CycleStatus = struct {
    pub const input_discontinuity: u32 = 1 << 0;
    pub const output_underrun: u32 = 1 << 1;
    pub const overload: u32 = 1 << 2;
    pub const clock_changed: u32 = 1 << 3;
    pub const input_silence: u32 = 1 << 4;
};

pub const ProcessCycle = struct {
    input: ?InputBuffer = null,
    output: ?OutputBuffer = null,
    frames: u32,
    time: StreamTime = .{},
    status: u32 = 0,

    pub fn validate(self: ProcessCycle) !void {
        if (self.frames == 0) return error.EmptyProcessCycle;
        if (self.input == null and self.output == null) return error.NoAudioBuffers;
        if (self.input) |input| {
            try input.format.validate();
            for (input.channels) |channel| {
                if (channel.stride_bytes < input.format.container_bytes) {
                    return error.InvalidInputStride;
                }
            }
        }
        if (self.output) |output| {
            try output.format.validate();
            for (output.channels) |channel| {
                if (channel.stride_bytes < output.format.container_bytes) {
                    return error.InvalidOutputStride;
                }
            }
        }
    }
};

pub const ProcessCallback = *const fn (context: *anyopaque, cycle: ProcessCycle) void;

pub const DeviceDescriptor = struct {
    /// Stable only within the backend that produced it. The visitor owns no copy.
    id: []const u8,
    name: []const u8,
    input_channels: u16,
    output_channels: u16,
    is_default_input: bool = false,
    is_default_output: bool = false,
};

pub const DeviceVisitor = *const fn (context: *anyopaque, descriptor: DeviceDescriptor) anyerror!void;

pub const SessionRequest = struct {
    direction: Direction = .duplex,
    input_device_id: ?[]const u8 = null,
    output_device_id: ?[]const u8 = null,
    sample_rate: ?f64 = 48_000.0,
    preferred_frames: ?u32 = null,
    input_channels: u16 = 1,
    output_channels: u16 = 2,
};

pub const NegotiatedConfig = struct {
    backend: Backend,
    sample_rate: f64,
    nominal_frames: u32,
    maximum_frames: u32,
    input_channels: u16,
    output_channels: u16,
    input_format: ?SampleFormat,
    output_format: ?SampleFormat,
    clock_relation: ClockRelation,
};

pub const Session = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        start: *const fn (context: *anyopaque) anyerror!void,
        stop: *const fn (context: *anyopaque) void,
        request_restart: *const fn (context: *anyopaque) void,
        close: *const fn (context: *anyopaque) void,
    };

    pub fn start(self: Session) !void {
        try self.vtable.start(self.context);
    }

    pub fn stop(self: Session) void {
        self.vtable.stop(self.context);
    }

    pub fn requestRestart(self: Session) void {
        self.vtable.request_restart(self.context);
    }

    pub fn close(self: Session) void {
        self.vtable.close(self.context);
    }
};

pub const OpenedSession = struct {
    session: Session,
    config: NegotiatedConfig,
};

pub const Driver = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        backend: Backend,
        enumerate: *const fn (
            context: *anyopaque,
            direction: Direction,
            visitor_context: *anyopaque,
            visitor: DeviceVisitor,
        ) anyerror!void,
        open: *const fn (
            context: *anyopaque,
            request: SessionRequest,
            callback_context: *anyopaque,
            callback: ProcessCallback,
        ) anyerror!OpenedSession,
    };

    pub fn backend(self: Driver) Backend {
        return self.vtable.backend;
    }

    pub fn enumerate(
        self: Driver,
        direction: Direction,
        visitor_context: *anyopaque,
        visitor: DeviceVisitor,
    ) !void {
        try self.vtable.enumerate(self.context, direction, visitor_context, visitor);
    }

    pub fn open(
        self: Driver,
        request: SessionRequest,
        callback_context: *anyopaque,
        callback: ProcessCallback,
    ) !OpenedSession {
        return self.vtable.open(self.context, request, callback_context, callback);
    }
};

test "native cycle represents interleaved input and planar output" {
    const input = [_]f32{ 0.1, 0.2, 0.3, 0.4 };
    var left = [_]f32{ 0.0, 0.0 };
    var right = [_]f32{ 0.0, 0.0 };

    const input_bytes: [*]const u8 = @ptrCast(&input);
    const left_bytes: [*]u8 = @ptrCast(&left);
    const right_bytes: [*]u8 = @ptrCast(&right);
    const input_channels = [_]InputChannelView{
        .{ .bytes = input_bytes, .stride_bytes = 8 },
        .{ .bytes = input_bytes + 4, .stride_bytes = 8 },
    };
    const output_channels = [_]OutputChannelView{
        .{ .bytes = left_bytes, .stride_bytes = 4 },
        .{ .bytes = right_bytes, .stride_bytes = 4 },
    };

    const cycle: ProcessCycle = .{
        .input = .{ .channels = &input_channels, .format = .f32_native },
        .output = .{ .channels = &output_channels, .format = .f32_native },
        .frames = 2,
        .time = .{
            .valid = TimeValidity.sample_position | TimeValidity.monotonic_ns,
            .sample_position = 1024,
            .monotonic_ns = 50_000,
        },
    };

    try cycle.validate();
    try std.testing.expect(cycle.time.has(TimeValidity.sample_position));
    try std.testing.expect(!cycle.time.has(TimeValidity.output_presentation_ns));
}
