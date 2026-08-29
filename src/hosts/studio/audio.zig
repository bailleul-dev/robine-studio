const assets = @import("audio_assets");
const contract = @import("audio_contract");
const native_audio = @import("native_audio");
const robine = @import("robine");
const std = @import("std");

pub const StartupPlayer = struct {
    allocator: std.mem.Allocator,
    driver: native_audio.CoreAudioDriver = .{},
    source: robine.audio.wav.Audio,
    compressor: robine.audio.nam.Model,
    amplifier: robine.audio.nam.Model,
    cabinet: robine.audio.convolver.Convolver,
    compressor_enabled: *const robine.core.equipment_state.EquipmentSwitch,
    compressor_bypass: robine.audio.bypass.Smoother,
    pedal_block: []f32,
    amplifier_block: []f32,
    opened: ?contract.OpenedSession = null,
    render_frame: usize = 0,

    /// Must be called on the final address of StartupPlayer: CoreAudio retains
    /// `self` as its allocation-free callback context.
    pub fn init(
        self: *StartupPlayer,
        allocator: std.mem.Allocator,
        compressor_enabled: *const robine.core.equipment_state.EquipmentSwitch,
    ) !void {
        self.* = undefined;
        self.allocator = allocator;
        self.driver = .{};
        self.opened = null;
        self.render_frame = 0;
        self.compressor_enabled = compressor_enabled;

        self.source = try robine.audio.wav.decode(allocator, assets.input_wav);
        errdefer self.source.deinit(allocator);
        if (self.source.channels != 1) return error.DevelopmentInputMustBeMono;

        self.compressor = try robine.audio.nam.Model.loadQuality(allocator, assets.first_pedal_nam, .full);
        errdefer self.compressor.deinit();
        self.amplifier = try robine.audio.nam.Model.loadQuality(allocator, assets.default_nam, .full);
        errdefer self.amplifier.deinit();
        if (@abs(self.compressor.sample_rate - self.amplifier.sample_rate) > 0.5 or
            @abs(self.amplifier.sample_rate - @as(f64, @floatFromInt(self.source.sample_rate))) > 0.5)
        {
            return error.SourceAndNamSampleRatesDiffer;
        }
        self.compressor_bypass = try .init(
            compressor_enabled.isEnabled(),
            self.amplifier.sample_rate,
            0.005,
        );

        var cabinet_ir = try robine.audio.wav.decode(allocator, assets.default_cabinet_ir);
        defer cabinet_ir.deinit(allocator);
        if (cabinet_ir.channels != 1) return error.CabinetImpulseMustBeMono;
        if (cabinet_ir.sample_rate != self.source.sample_rate) {
            return error.CabinetAndNamSampleRatesDiffer;
        }
        self.cabinet = try robine.audio.convolver.Convolver.init(
            allocator,
            cabinet_ir.samples,
            64,
        );
        errdefer self.cabinet.deinit();

        const opened = try self.driver.driver().open(
            .{
                .direction = .output,
                .sample_rate = self.amplifier.sample_rate,
                .preferred_frames = 64,
                .input_channels = 0,
                .output_channels = 2,
            },
            self,
            process,
        );
        errdefer opened.session.close();
        if (@abs(opened.config.sample_rate - self.amplifier.sample_rate) > 0.5) {
            std.log.err(
                "CoreAudio negotiated {d:.2} Hz but NAM requires {d:.2} Hz",
                .{ opened.config.sample_rate, self.amplifier.sample_rate },
            );
            return error.OutputAndNamSampleRatesDiffer;
        }
        const format = opened.config.output_format orelse return error.MissingOutputFormat;
        try ensureWritableFormat(format);

        self.pedal_block = try allocator.alloc(f32, opened.config.maximum_frames);
        errdefer allocator.free(self.pedal_block);
        self.amplifier_block = try allocator.alloc(f32, opened.config.maximum_frames);
        errdefer allocator.free(self.amplifier_block);
        try self.compressor.prepareBlock(opened.config.maximum_frames);
        try self.amplifier.prepareBlock(opened.config.maximum_frames);
        self.compressor.prewarm(opened.config.maximum_frames);
        self.amplifier.prewarm(opened.config.maximum_frames);
        self.opened = opened;
        try opened.session.start();
        std.log.info(
            "Playing development guitar through SP Compressor Mid, full amp NAM, and Orange 2x12 V30 / SM57 C: {d:.0} Hz, {d} output channels, {d} frames",
            .{ opened.config.sample_rate, opened.config.output_channels, opened.config.nominal_frames },
        );
    }

    pub fn deinit(self: *StartupPlayer) void {
        if (self.opened) |opened| {
            opened.session.stop();
            opened.session.close();
        }
        self.allocator.free(self.amplifier_block);
        self.allocator.free(self.pedal_block);
        self.cabinet.deinit();
        self.amplifier.deinit();
        self.compressor.deinit();
        self.source.deinit(self.allocator);
        self.* = undefined;
    }

    fn process(context: *anyopaque, cycle: contract.ProcessCycle) void {
        const self: *StartupPlayer = @ptrCast(@alignCast(context));
        const output = cycle.output orelse return;
        const source_frames = self.source.frames();
        const rendered_frames = source_frames + self.cabinet.tailFrames() + self.cabinet.latencyFrames();
        const compressor_enabled = self.compressor_enabled.isEnabled();
        const active_frames = if (self.render_frame < source_frames)
            @min(cycle.frames, source_frames - self.render_frame)
        else
            0;

        if (active_frames > 0) {
            const dry = self.source.samples[self.render_frame..][0..active_frames];
            const pedal = self.pedal_block[0..active_frames];
            self.compressor.processBlock(dry, pedal);
            for (pedal, dry) |*compressed, dry_sample| {
                compressed.* = self.compressor_bypass.process(
                    dry_sample,
                    compressed.*,
                    compressor_enabled,
                );
            }
            self.amplifier.processBlock(pedal, self.amplifier_block[0..active_frames]);
        }

        for (0..cycle.frames) |frame| {
            const amp_output = if (frame < active_frames) self.amplifier_block[frame] else 0.0;
            const absolute_frame = self.render_frame + frame;
            const sample = if (absolute_frame < rendered_frames)
                std.math.clamp(self.cabinet.processSample(amp_output), -1.0, 1.0)
            else
                0.0;

            for (output.channels) |channel| {
                writeSample(channel, output.format, frame, sample);
            }
        }
        self.render_frame += cycle.frames;
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
            const maximum: i64 = if (valid_bits == 64)
                std.math.maxInt(i64)
            else
                (@as(i64, 1) << (valid_bits - 1)) - 1;
            const normalized = std.math.clamp(sample, -1.0, 1.0);
            var value: i64 = if (normalized <= -1.0)
                -maximum
            else if (normalized >= 1.0)
                maximum
            else
                @intFromFloat(@round(@as(f64, normalized) * @as(f64, @floatFromInt(maximum))));
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
