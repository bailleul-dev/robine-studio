const std = @import("std");

pub const PrepareSpec = struct {
    sample_rate: f64,
    max_frames: u32,
    input_channels: u16,
    output_channels: u16,

    pub fn validate(self: PrepareSpec) !void {
        if (!std.math.isFinite(self.sample_rate) or self.sample_rate <= 0.0) {
            return error.InvalidSampleRate;
        }
        if (self.max_frames == 0) return error.InvalidMaximumFrameCount;
        if (self.input_channels == 0 and self.output_channels == 0) {
            return error.EmptyChannelLayout;
        }
    }
};

pub const ParameterEvent = struct {
    id: u32,
    normalized_value: f32,
    sample_offset: u32 = 0,
};

/// Canonical host-independent processing buffers.
///
/// The host owns the outer channel lists and every sample slice. All channels
/// contain at least `frames` contiguous, non-interleaved f32 samples.
pub const AudioBlock = struct {
    inputs: []const []const f32,
    outputs: []const []f32,
    frames: usize,

    pub fn validate(self: AudioBlock) !void {
        if (self.frames == 0) return error.EmptyAudioBlock;
        for (self.inputs) |channel| {
            if (channel.len < self.frames) return error.ShortInputChannel;
        }
        for (self.outputs) |channel| {
            if (channel.len < self.frames) return error.ShortOutputChannel;
        }
    }

    pub fn clearOutputs(self: AudioBlock) void {
        for (self.outputs) |channel| @memset(channel[0..self.frames], 0.0);
    }
};

pub const ProcessContext = struct {
    audio: AudioBlock,
    events: []const ParameterEvent = &.{},
};

/// Type-erased DSP instance shared by standalone, CLAP, VST3, and offline hosts.
/// `process` is infallible by design: a real-time failure produces bounded
/// telemetry and silence rather than unwinding through a native callback.
pub const Processor = struct {
    context: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        prepare: *const fn (context: *anyopaque, spec: PrepareSpec) anyerror!void,
        activate: *const fn (context: *anyopaque) anyerror!void,
        reset: *const fn (context: *anyopaque) void,
        process: *const fn (context: *anyopaque, process_context: ProcessContext) void,
        deactivate: *const fn (context: *anyopaque) void,
        latency_frames: *const fn (context: *const anyopaque) u32,
        tail_frames: *const fn (context: *const anyopaque) ?u64,
    };

    pub fn prepare(self: Processor, spec: PrepareSpec) !void {
        try spec.validate();
        try self.vtable.prepare(self.context, spec);
    }

    pub fn activate(self: Processor) !void {
        try self.vtable.activate(self.context);
    }

    pub fn reset(self: Processor) void {
        self.vtable.reset(self.context);
    }

    pub fn process(self: Processor, context: ProcessContext) void {
        self.vtable.process(self.context, context);
    }

    pub fn deactivate(self: Processor) void {
        self.vtable.deactivate(self.context);
    }

    pub fn latencyFrames(self: Processor) u32 {
        return self.vtable.latency_frames(self.context);
    }

    pub fn tailFrames(self: Processor) ?u64 {
        return self.vtable.tail_frames(self.context);
    }
};

test "processor contract processes planar f32 without ownership transfer" {
    const Gain = struct {
        gain: f32,
        prepared: bool = false,
        active: bool = false,

        fn processor(self: *@This()) Processor {
            return .{ .context = self, .vtable = &vtable };
        }

        fn cast(context: *anyopaque) *@This() {
            return @ptrCast(@alignCast(context));
        }

        fn prepare(context: *anyopaque, spec: PrepareSpec) !void {
            try spec.validate();
            cast(context).prepared = true;
        }

        fn activate(context: *anyopaque) !void {
            const self = cast(context);
            if (!self.prepared) return error.NotPrepared;
            self.active = true;
        }

        fn reset(_: *anyopaque) void {}

        fn process(context: *anyopaque, process_context: ProcessContext) void {
            const self = cast(context);
            if (!self.active or process_context.audio.inputs.len == 0) {
                process_context.audio.clearOutputs();
                return;
            }
            const input = process_context.audio.inputs[0];
            for (process_context.audio.outputs) |output| {
                for (output[0..process_context.audio.frames], input[0..process_context.audio.frames]) |*out, in| {
                    out.* = in * self.gain;
                }
            }
        }

        fn deactivate(context: *anyopaque) void {
            cast(context).active = false;
        }

        fn latencyFrames(_: *const anyopaque) u32 {
            return 0;
        }

        fn tailFrames(_: *const anyopaque) ?u64 {
            return 0;
        }

        const vtable: Processor.VTable = .{
            .prepare = prepare,
            .activate = activate,
            .reset = reset,
            .process = process,
            .deactivate = deactivate,
            .latency_frames = latencyFrames,
            .tail_frames = tailFrames,
        };
    };

    var gain = Gain{ .gain = 0.5 };
    const processor = gain.processor();
    try processor.prepare(.{
        .sample_rate = 48_000.0,
        .max_frames = 4,
        .input_channels = 1,
        .output_channels = 2,
    });
    try processor.activate();

    const input = [_]f32{ -1.0, -0.5, 0.5, 1.0 };
    var left: [4]f32 = undefined;
    var right: [4]f32 = undefined;
    const inputs = [_][]const f32{input[0..]};
    const outputs = [_][]f32{ left[0..], right[0..] };
    const block: AudioBlock = .{ .inputs = &inputs, .outputs = &outputs, .frames = 4 };
    try block.validate();
    processor.process(.{ .audio = block });

    try std.testing.expectEqualSlices(f32, &.{ -0.5, -0.25, 0.25, 0.5 }, &left);
    try std.testing.expectEqualSlices(f32, &left, &right);
}
