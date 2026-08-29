const assets = @import("audio_assets");
const contract = @import("audio_contract");
const native_audio = @import("native_audio");
const robine = @import("robine");
const std = @import("std");

pub const StartupPlayer = struct {
    allocator: std.mem.Allocator,
    driver: native_audio.CoreAudioDriver = .{},
    source: robine.audio.wav.Audio,
    model: robine.audio.nam.Model,
    opened: ?contract.OpenedSession = null,
    source_frame: usize = 0,

    /// Must be called on the final address of StartupPlayer: CoreAudio retains
    /// `self` as its allocation-free callback context.
    pub fn init(self: *StartupPlayer, allocator: std.mem.Allocator) !void {
        self.* = undefined;
        self.allocator = allocator;
        self.driver = .{};
        self.opened = null;
        self.source_frame = 0;

        self.source = try robine.audio.wav.decode(allocator, assets.input_wav);
        errdefer self.source.deinit(allocator);
        if (self.source.channels != 1) return error.DevelopmentInputMustBeMono;

        self.model = try robine.audio.nam.Model.load(allocator, assets.default_nam);
        errdefer self.model.deinit();
        if (@abs(self.model.sample_rate - @as(f64, @floatFromInt(self.source.sample_rate))) > 0.5) {
            return error.SourceAndNamSampleRatesDiffer;
        }

        const opened = try self.driver.driver().open(
            .{
                .direction = .output,
                .sample_rate = self.model.sample_rate,
                .preferred_frames = 64,
                .input_channels = 0,
                .output_channels = 2,
            },
            self,
            process,
        );
        errdefer opened.session.close();
        if (@abs(opened.config.sample_rate - self.model.sample_rate) > 0.5) {
            std.log.err(
                "CoreAudio negotiated {d:.2} Hz but NAM requires {d:.2} Hz",
                .{ opened.config.sample_rate, self.model.sample_rate },
            );
            return error.OutputAndNamSampleRatesDiffer;
        }
        const format = opened.config.output_format orelse return error.MissingOutputFormat;
        try ensureWritableFormat(format);

        self.model.prewarm(opened.config.maximum_frames);
        self.opened = opened;
        try opened.session.start();
        std.log.info(
            "Playing development guitar through NAM: {d:.0} Hz, {d} output channels, {d} frames",
            .{ opened.config.sample_rate, opened.config.output_channels, opened.config.nominal_frames },
        );
    }

    pub fn deinit(self: *StartupPlayer) void {
        if (self.opened) |opened| {
            opened.session.stop();
            opened.session.close();
        }
        self.model.deinit();
        self.source.deinit(self.allocator);
        self.* = undefined;
    }

    fn process(context: *anyopaque, cycle: contract.ProcessCycle) void {
        const self: *StartupPlayer = @ptrCast(@alignCast(context));
        const output = cycle.output orelse return;
        const source_frames = self.source.frames();

        for (0..cycle.frames) |frame| {
            const sample = if (self.source_frame < source_frames) signal: {
                const dry = self.source.samples[self.source_frame * self.source.channels];
                self.source_frame += 1;
                break :signal std.math.clamp(self.model.processSample(dry), -1.0, 1.0);
            } else 0.0;

            for (output.channels) |channel| {
                writeSample(channel, output.format, frame, sample);
            }
        }
    }
};

fn ensureWritableFormat(format: contract.SampleFormat) !void {
    switch (format.kind) {
        .floating_point => if (format.container_bytes != 4 and format.container_bytes != 8) {
            return error.UnsupportedOutputFormat;
        },
        .signed_integer => if (format.container_bytes != 1 and format.container_bytes != 2 and
            format.container_bytes != 3 and format.container_bytes != 4 and format.container_bytes != 8)
        {
            return error.UnsupportedOutputFormat;
        },
    }
}

fn writeSample(
    channel: contract.OutputChannelView,
    format: contract.SampleFormat,
    frame_index: usize,
    sample: f32,
) void {
    const destination = channel.bytes + frame_index * channel.stride_bytes;
    const order: std.builtin.Endian = switch (format.byte_order) {
        .big => .big,
        .little => .little,
        .native => native_endian,
    };
    switch (format.kind) {
        .floating_point => switch (format.container_bytes) {
            4 => std.mem.writeInt(u32, destination[0..4], @bitCast(sample), order),
            8 => std.mem.writeInt(u64, destination[0..8], @bitCast(@as(f64, sample)), order),
            else => unreachable,
        },
        .signed_integer => {
            const valid_bits: u6 = @intCast(format.valid_bits);
            const maximum: i64 = (@as(i64, 1) << (valid_bits - 1)) - 1;
            var value: i64 = @intFromFloat(@round(std.math.clamp(sample, -1.0, 1.0) * @as(f32, @floatFromInt(maximum))));
            if (format.aligned_high) value <<= @intCast(format.container_bytes * 8 - format.valid_bits);
            const bits: u64 = @bitCast(value);
            switch (format.container_bytes) {
                1 => destination[0] = @truncate(bits),
                2 => std.mem.writeInt(u16, destination[0..2], @truncate(bits), order),
                3 => if (order == .little) {
                    destination[0] = @truncate(bits);
                    destination[1] = @truncate(bits >> 8);
                    destination[2] = @truncate(bits >> 16);
                } else {
                    destination[0] = @truncate(bits >> 16);
                    destination[1] = @truncate(bits >> 8);
                    destination[2] = @truncate(bits);
                },
                4 => std.mem.writeInt(u32, destination[0..4], @truncate(bits), order),
                8 => std.mem.writeInt(u64, destination[0..8], bits, order),
                else => unreachable,
            }
        },
    }
}

const native_endian: std.builtin.Endian = @import("builtin").cpu.arch.endian();
