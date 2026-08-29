const assets = @import("audio_assets");
const contract = @import("audio_contract");
const native_audio = @import("native_audio");
const robine = @import("robine");
const std = @import("std");

const KingOfToneMode = enum {
    bypass,
    orange,
    red,
    both,

    fn fromSwitches(orange_enabled: bool, red_enabled: bool) KingOfToneMode {
        if (orange_enabled and red_enabled) return .both;
        if (orange_enabled) return .orange;
        if (red_enabled) return .red;
        return .bypass;
    }

    fn modelIndex(self: KingOfToneMode) ?usize {
        return switch (self) {
            .bypass => null,
            .orange => 0,
            .red => 1,
            .both => 2,
        };
    }
};

const KingOfToneTransition = robine.audio.mode_switch.DiscreteTransition(KingOfToneMode);
const AmplifierId = robine.core.equipment_state.AmplifierId;
const AmplifierTransition = robine.audio.mode_switch.DiscreteTransition(AmplifierId);

pub const StartupPlayer = struct {
    allocator: std.mem.Allocator,
    driver: native_audio.CoreAudioDriver = .{},
    source: robine.audio.wav.Audio,
    compressors: [3]robine.audio.nam.Model,
    tumnus: robine.audio.nam.Model,
    big_muff: robine.audio.nam.Model,
    king_of_tone_models: [3]robine.audio.nam.Model,
    amplifiers: [3]robine.audio.nam.Model,
    reverb: robine.audio.reverb.HybridStereoConvolver,
    cabinets: [3][2]robine.audio.convolver.Convolver,
    compressor_enabled: *const robine.core.equipment_state.EquipmentSwitch,
    compressor_mode: *const robine.core.equipment_state.EquipmentModeSwitch,
    tumnus_enabled: *const robine.core.equipment_state.EquipmentSwitch,
    big_muff_enabled: *const robine.core.equipment_state.EquipmentSwitch,
    king_orange_enabled: *const robine.core.equipment_state.EquipmentSwitch,
    king_red_enabled: *const robine.core.equipment_state.EquipmentSwitch,
    reverb_enabled: *const robine.core.equipment_state.EquipmentSwitch,
    amplifier_selector: *const robine.core.equipment_state.AmplifierSelector,
    compressor_bypass: robine.audio.bypass.Smoother,
    tumnus_bypass: robine.audio.bypass.Smoother,
    big_muff_bypass: robine.audio.bypass.Smoother,
    mode_transition: robine.audio.mode_switch.Transition,
    king_of_tone_bypass: robine.audio.bypass.Smoother,
    king_of_tone_transition: KingOfToneTransition,
    amplifier_power: robine.audio.bypass.Smoother,
    amplifier_transition: AmplifierTransition,
    reverb_bypass: [2]robine.audio.bypass.Smoother,
    pedal_block: []f32,
    tumnus_block: []f32,
    big_muff_block: []f32,
    king_of_tone_block: []f32,
    amplifier_block: []f32,
    opened: ?contract.OpenedSession = null,
    render_frame: usize = 0,
    sample_rate: f64,

    /// Must be called on the final address of StartupPlayer: CoreAudio retains
    /// `self` as its allocation-free callback context.
    pub fn init(
        self: *StartupPlayer,
        allocator: std.mem.Allocator,
        compressor_enabled: *const robine.core.equipment_state.EquipmentSwitch,
        compressor_mode: *const robine.core.equipment_state.EquipmentModeSwitch,
        tumnus_enabled: *const robine.core.equipment_state.EquipmentSwitch,
        big_muff_enabled: *const robine.core.equipment_state.EquipmentSwitch,
        king_orange_enabled: *const robine.core.equipment_state.EquipmentSwitch,
        king_red_enabled: *const robine.core.equipment_state.EquipmentSwitch,
        reverb_enabled: *const robine.core.equipment_state.EquipmentSwitch,
        amplifier_selector: *const robine.core.equipment_state.AmplifierSelector,
    ) !void {
        self.* = undefined;
        self.allocator = allocator;
        self.driver = .{};
        self.opened = null;
        self.render_frame = 0;
        self.compressor_enabled = compressor_enabled;
        self.compressor_mode = compressor_mode;
        self.tumnus_enabled = tumnus_enabled;
        self.big_muff_enabled = big_muff_enabled;
        self.king_orange_enabled = king_orange_enabled;
        self.king_red_enabled = king_red_enabled;
        self.reverb_enabled = reverb_enabled;
        self.amplifier_selector = amplifier_selector;

        self.source = try robine.audio.wav.decode(allocator, assets.input_wav);
        errdefer self.source.deinit(allocator);
        if (self.source.channels != 1) return error.DevelopmentInputMustBeMono;

        const compressor_assets = [3][]const u8{
            assets.first_pedal_low_nam,
            assets.first_pedal_mid_nam,
            assets.first_pedal_high_nam,
        };
        var initialized_compressors: usize = 0;
        errdefer for (self.compressors[0..initialized_compressors]) |*compressor| compressor.deinit();
        for (&self.compressors, compressor_assets) |*compressor, model_bytes| {
            compressor.* = try robine.audio.nam.Model.loadQuality(allocator, model_bytes, .full);
            initialized_compressors += 1;
        }

        self.tumnus = try robine.audio.nam.Model.loadQuality(allocator, assets.tumnus_deluxe_default_nam, .full);
        errdefer self.tumnus.deinit();
        self.big_muff = try robine.audio.nam.Model.loadQuality(allocator, assets.op_amp_big_muff_default_nam, .full);
        errdefer self.big_muff.deinit();

        const king_of_tone_assets = [3][]const u8{
            assets.king_of_tone_orange_nam,
            assets.king_of_tone_red_nam,
            assets.king_of_tone_both_nam,
        };
        var initialized_king_models: usize = 0;
        errdefer for (self.king_of_tone_models[0..initialized_king_models]) |*model| model.deinit();
        for (&self.king_of_tone_models, king_of_tone_assets) |*model, model_bytes| {
            model.* = try robine.audio.nam.Model.loadQuality(allocator, model_bytes, .full);
            initialized_king_models += 1;
        }
        var initialized_amplifiers: usize = 0;
        errdefer for (self.amplifiers[0..initialized_amplifiers]) |*amplifier| amplifier.deinit();
        for (&self.amplifiers, assets.amplifier_catalog) |*amplifier, asset| {
            amplifier.* = try robine.audio.nam.Model.loadQuality(allocator, asset.nam, .full);
            initialized_amplifiers += 1;
        }
        self.sample_rate = self.amplifiers[0].sample_rate;
        if (@abs(self.sample_rate - @as(f64, @floatFromInt(self.source.sample_rate))) > 0.5) {
            return error.SourceAndNamSampleRatesDiffer;
        }
        for (self.amplifiers) |amplifier| {
            if (@abs(amplifier.sample_rate - self.sample_rate) > 0.5) {
                return error.AmplifierSampleRatesDiffer;
            }
        }
        for (self.compressors) |compressor| {
            if (@abs(compressor.sample_rate - self.sample_rate) > 0.5) {
                return error.SourceAndNamSampleRatesDiffer;
            }
        }
        if (@abs(self.tumnus.sample_rate - self.sample_rate) > 0.5 or
            @abs(self.big_muff.sample_rate - self.sample_rate) > 0.5)
        {
            return error.SourceAndNamSampleRatesDiffer;
        }
        for (self.king_of_tone_models) |model| {
            if (@abs(model.sample_rate - self.sample_rate) > 0.5) {
                return error.SourceAndNamSampleRatesDiffer;
            }
        }
        self.compressor_bypass = try .init(
            compressor_enabled.isEnabled(),
            self.sample_rate,
            0.005,
        );
        self.mode_transition = .init(compressor_mode.position());
        self.tumnus_bypass = try .init(tumnus_enabled.isEnabled(), self.sample_rate, 0.005);
        self.big_muff_bypass = try .init(big_muff_enabled.isEnabled(), self.sample_rate, 0.005);
        const initial_king_mode = KingOfToneMode.fromSwitches(
            king_orange_enabled.isEnabled(),
            king_red_enabled.isEnabled(),
        );
        self.king_of_tone_bypass = try .init(
            initial_king_mode != .bypass,
            self.sample_rate,
            0.005,
        );
        self.king_of_tone_transition = .init(initial_king_mode);
        self.amplifier_power = try .init(true, self.sample_rate, 0.010);
        self.amplifier_transition = .init(amplifier_selector.selected());

        var reverb_ir = try robine.audio.wav.decode(allocator, assets.skysurfer_hall_medium_ir);
        defer reverb_ir.deinit(allocator);
        if (reverb_ir.channels != 2) return error.ReverbImpulseMustBeStereo;
        if (reverb_ir.sample_rate != self.source.sample_rate) return error.ReverbAndNamSampleRatesDiffer;
        const reverb_frames = reverb_ir.frames();
        const reverb_left = try allocator.alloc(f32, reverb_frames);
        defer allocator.free(reverb_left);
        const reverb_right = try allocator.alloc(f32, reverb_frames);
        defer allocator.free(reverb_right);
        for (0..reverb_frames) |frame| {
            reverb_left[frame] = reverb_ir.samples[frame * 2];
            reverb_right[frame] = reverb_ir.samples[frame * 2 + 1];
        }
        self.reverb = try robine.audio.reverb.HybridStereoConvolver.init(
            allocator,
            reverb_left,
            reverb_right,
            .{},
        );
        errdefer self.reverb.deinit();
        self.reverb_bypass = .{
            try .init(reverb_enabled.isEnabled(), self.sample_rate, 0.005),
            try .init(reverb_enabled.isEnabled(), self.sample_rate, 0.005),
        };

        var initialized_cabinets: usize = 0;
        errdefer {
            var remaining = initialized_cabinets;
            cleanup: for (&self.cabinets) |*stereo_cabinets| {
                for (stereo_cabinets) |*cabinet| {
                    if (remaining == 0) break :cleanup;
                    cabinet.deinit();
                    remaining -= 1;
                }
            }
        }
        for (&self.cabinets, assets.amplifier_catalog) |*stereo_cabinets, asset| {
            var cabinet_ir = try robine.audio.wav.decode(allocator, asset.cabinet_ir);
            defer cabinet_ir.deinit(allocator);
            if (cabinet_ir.channels != 1) return error.CabinetImpulseMustBeMono;
            if (cabinet_ir.sample_rate != self.source.sample_rate) {
                return error.CabinetAndNamSampleRatesDiffer;
            }
            for (stereo_cabinets) |*cabinet| {
                cabinet.* = try robine.audio.convolver.Convolver.init(allocator, cabinet_ir.samples, 64);
                initialized_cabinets += 1;
            }
        }

        const opened = try self.driver.driver().open(
            .{
                .direction = .output,
                .sample_rate = self.sample_rate,
                .preferred_frames = 512,
                .input_channels = 0,
                .output_channels = 2,
            },
            self,
            process,
        );
        errdefer opened.session.close();
        if (@abs(opened.config.sample_rate - self.sample_rate) > 0.5) {
            std.log.err(
                "CoreAudio negotiated {d:.2} Hz but NAM requires {d:.2} Hz",
                .{ opened.config.sample_rate, self.sample_rate },
            );
            return error.OutputAndNamSampleRatesDiffer;
        }
        const format = opened.config.output_format orelse return error.MissingOutputFormat;
        try ensureWritableFormat(format);

        self.pedal_block = try allocator.alloc(f32, opened.config.maximum_frames);
        errdefer allocator.free(self.pedal_block);
        self.tumnus_block = try allocator.alloc(f32, opened.config.maximum_frames);
        errdefer allocator.free(self.tumnus_block);
        self.big_muff_block = try allocator.alloc(f32, opened.config.maximum_frames);
        errdefer allocator.free(self.big_muff_block);
        self.king_of_tone_block = try allocator.alloc(f32, opened.config.maximum_frames);
        errdefer allocator.free(self.king_of_tone_block);
        self.amplifier_block = try allocator.alloc(f32, opened.config.maximum_frames);
        errdefer allocator.free(self.amplifier_block);
        for (&self.compressors) |*compressor| try compressor.prepareBlock(opened.config.maximum_frames);
        try self.tumnus.prepareBlock(opened.config.maximum_frames);
        try self.big_muff.prepareBlock(opened.config.maximum_frames);
        for (&self.king_of_tone_models) |*model| try model.prepareBlock(opened.config.maximum_frames);
        for (&self.amplifiers) |*amplifier| try amplifier.prepareBlock(opened.config.maximum_frames);
        for (&self.compressors) |*compressor| compressor.prewarm(opened.config.maximum_frames);
        self.tumnus.prewarm(opened.config.maximum_frames);
        self.big_muff.prewarm(opened.config.maximum_frames);
        for (&self.king_of_tone_models) |*model| model.prewarm(opened.config.maximum_frames);
        for (&self.amplifiers) |*amplifier| amplifier.prewarm(opened.config.maximum_frames);
        self.reverb.prewarm();
        for (&self.cabinets) |*stereo_cabinets| {
            for (stereo_cabinets) |*cabinet| {
                for (0..cabinet.partition_size) |_| _ = cabinet.processSample(0.0);
                cabinet.reset();
            }
        }
        self.opened = opened;
        try opened.session.start();
        std.log.info(
            "Playing selectable full chain: SP Compressor, Tumnus Deluxe, Big Muff, King of Tone, Bogner/Dumble/Mesa, Skysurfer Hall, and matched cabinets: {d:.0} Hz, {d} output channels, {d} frames",
            .{ opened.config.sample_rate, opened.config.output_channels, opened.config.nominal_frames },
        );
    }

    pub fn deinit(self: *StartupPlayer) void {
        if (self.opened) |opened| {
            opened.session.stop();
            opened.session.close();
        }
        self.allocator.free(self.amplifier_block);
        self.allocator.free(self.king_of_tone_block);
        self.allocator.free(self.big_muff_block);
        self.allocator.free(self.tumnus_block);
        self.allocator.free(self.pedal_block);
        for (&self.cabinets) |*stereo_cabinets| {
            for (stereo_cabinets) |*cabinet| cabinet.deinit();
        }
        self.reverb.deinit();
        for (&self.amplifiers) |*amplifier| amplifier.deinit();
        for (&self.king_of_tone_models) |*model| model.deinit();
        self.big_muff.deinit();
        self.tumnus.deinit();
        for (&self.compressors) |*compressor| compressor.deinit();
        self.source.deinit(self.allocator);
        self.* = undefined;
    }

    fn process(context: *anyopaque, cycle: contract.ProcessCycle) void {
        const self: *StartupPlayer = @ptrCast(@alignCast(context));
        const output = cycle.output orelse return;
        const source_frames = self.source.frames();
        const requested_amplifier = self.amplifier_selector.selected();
        const active_amplifier = self.amplifier_transition.activeState();
        const active_amplifier_index: usize = @intFromEnum(active_amplifier);
        const active_cabinets = &self.cabinets[active_amplifier_index];
        const rendered_frames = source_frames + self.reverb.tailFrames() + self.reverb.latencyFrames() +
            active_cabinets[0].tailFrames() + active_cabinets[0].latencyFrames();
        const compressor_enabled = self.compressor_enabled.isEnabled();
        const requested_mode = self.compressor_mode.position();
        const render_wet = self.mode_transition.wantsWet(compressor_enabled, requested_mode);
        const requested_king_mode = KingOfToneMode.fromSwitches(
            self.king_orange_enabled.isEnabled(),
            self.king_red_enabled.isEnabled(),
        );
        const render_king_wet = self.king_of_tone_transition.wantsWet(requested_king_mode, .bypass);
        const active_frames = if (self.render_frame < source_frames)
            @min(cycle.frames, source_frames - self.render_frame)
        else
            0;

        if (active_frames > 0) {
            const dry = self.source.samples[self.render_frame..][0..active_frames];
            const pedal = self.pedal_block[0..active_frames];
            const active_index: usize = @intFromEnum(self.mode_transition.activePosition());
            self.compressors[active_index].processBlock(dry, pedal);
            for (pedal, dry) |*compressed, dry_sample| {
                compressed.* = self.compressor_bypass.process(
                    dry_sample,
                    compressed.*,
                    render_wet,
                );
            }
            if (self.mode_transition.completeWhenDry(
                requested_mode,
                self.compressor_bypass.wetMix(),
            )) |new_mode| {
                self.compressors[@intFromEnum(new_mode)].reset();
            }
            const tumnus_output = self.tumnus_block[0..active_frames];
            self.tumnus.processBlock(pedal, tumnus_output);
            const tumnus_enabled = self.tumnus_enabled.isEnabled();
            for (tumnus_output, pedal) |*wet_sample, dry_sample| {
                wet_sample.* = self.tumnus_bypass.process(dry_sample, wet_sample.*, tumnus_enabled);
            }
            const big_muff_output = self.big_muff_block[0..active_frames];
            self.big_muff.processBlock(tumnus_output, big_muff_output);
            const big_muff_enabled = self.big_muff_enabled.isEnabled();
            for (big_muff_output, tumnus_output) |*wet_sample, dry_sample| {
                wet_sample.* = self.big_muff_bypass.process(dry_sample, wet_sample.*, big_muff_enabled);
            }
            const king_output = self.king_of_tone_block[0..active_frames];
            const active_king_mode = self.king_of_tone_transition.activeState();
            if (active_king_mode.modelIndex()) |model_index| {
                self.king_of_tone_models[model_index].processBlock(big_muff_output, king_output);
            } else {
                @memcpy(king_output, big_muff_output);
            }
            for (king_output, big_muff_output) |*wet_sample, dry_sample| {
                wet_sample.* = self.king_of_tone_bypass.process(
                    dry_sample,
                    wet_sample.*,
                    render_king_wet,
                );
            }
            if (self.king_of_tone_transition.completeWhenDry(
                requested_king_mode,
                self.king_of_tone_bypass.wetMix(),
            )) |new_mode| {
                if (new_mode.modelIndex()) |model_index| {
                    self.king_of_tone_models[model_index].reset();
                }
            }
            self.amplifiers[active_amplifier_index].processBlock(king_output, self.amplifier_block[0..active_frames]);
            for (self.amplifier_block[0..active_frames]) |*sample| {
                sample.* = self.amplifier_power.process(
                    0.0,
                    sample.*,
                    requested_amplifier == active_amplifier,
                );
            }
        }

        for (0..cycle.frames) |frame| {
            const amp_output = if (frame < active_frames) self.amplifier_block[frame] else 0.0;
            const absolute_frame = self.render_frame + frame;
            const wet = self.reverb.processSample(amp_output);
            const reverb_enabled = self.reverb_enabled.isEnabled();
            var stereo = [2]f32{
                mixEffectLoop(&self.reverb_bypass[0], amp_output, wet[0], reverb_enabled),
                mixEffectLoop(&self.reverb_bypass[1], amp_output, wet[1], reverb_enabled),
            };
            for (&stereo, active_cabinets) |*sample, *cabinet| {
                sample.* = if (absolute_frame < rendered_frames)
                    std.math.clamp(cabinet.processSample(sample.*) * assets.monitor_output_gain, -1.0, 1.0)
                else
                    0.0;
            }

            for (output.channels, 0..) |channel, channel_index| {
                writeSample(channel, output.format, frame, stereo[channel_index & 1]);
            }
        }
        if (self.amplifier_transition.completeWhenDry(
            requested_amplifier,
            self.amplifier_power.wetMix(),
        )) |new_amplifier| {
            const new_index: usize = @intFromEnum(new_amplifier);
            self.amplifiers[new_index].reset();
            for (&self.cabinets[new_index]) |*cabinet| cabinet.reset();
        }
        self.render_frame += cycle.frames;
    }
};

fn mixEffectLoop(
    smoother: *robine.audio.bypass.Smoother,
    dry: f32,
    wet_return: f32,
    enabled: bool,
) f32 {
    // The effects loop is parallel. The dry path is a unity-gain wire and never
    // enters the crossfade; bypass only fades the reverb return to silence.
    const wet = smoother.process(0.0, wet_return * assets.reverb_return_gain, enabled);
    return dry + wet;
}

test "reverb bypass always preserves the dry effects-loop path" {
    var smoother = try robine.audio.bypass.Smoother.init(true, 1_000.0, 0.004);
    var sample: f32 = 0.0;
    for (0..4) |_| {
        sample = mixEffectLoop(&smoother, 0.25, 100.0, false);
    }
    try std.testing.expectEqual(
        @as(f32, 0.25),
        sample,
    );
    try std.testing.expectEqual(@as(f32, 0.0), smoother.wetMix());
}

test "reverb transition never crossfades or attenuates the dry path" {
    var smoother = try robine.audio.bypass.Smoother.init(true, 1_000.0, 0.004);
    for (0..4) |_| {
        try std.testing.expectEqual(
            @as(f32, -0.375),
            mixEffectLoop(&smoother, -0.375, 0.0, false),
        );
    }
    try std.testing.expectEqual(@as(f32, 0.0), smoother.wetMix());
}

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
