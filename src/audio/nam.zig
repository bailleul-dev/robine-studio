const std = @import("std");
const nam_a2 = @import("nam_a2.zig");

const max_channels = 16;
const max_kernel_taps = 64;

const NamFile = struct {
    version: []const u8,
    architecture: []const u8,
    config: ContainerConfig,
    sample_rate: f64,
};

const ContainerConfig = struct {
    submodels: []Submodel,
};

const Submodel = struct {
    max_value: f64,
    model: WaveNetFile,
};

const WaveNetFile = struct {
    version: []const u8,
    architecture: []const u8,
    config: WaveNetConfig,
    weights: []f32,
    sample_rate: f64,
};

const WaveNetConfig = struct {
    layers: []LayerArrayConfig,
    head: ?std.json.Value = null,
    head_scale: f32,
};

const HeadConfig = struct {
    out_channels: u16,
    kernel_size: u16,
    bias: bool,
};

const PointwiseConfig = struct {
    active: bool,
    out_channels: u16 = 0,
    groups: u16,
};

const ActivationConfig = struct {
    type: []const u8,
    negative_slope: f32,
};

const LayerArrayConfig = struct {
    input_size: u16,
    condition_size: u16,
    head: HeadConfig,
    channels: u16,
    kernel_sizes: []u16,
    dilations: []u16,
    activation: []ActivationConfig,
    bottleneck: u16,
    head1x1: PointwiseConfig,
    layer1x1: PointwiseConfig,
    groups_input: u16,
    groups_input_mixin: u16,
    gating_mode: [][]const u8,
};

const Conv1x1 = struct {
    in_channels: usize,
    out_channels: usize,
    weights: []const f32,
    bias: []const f32,

    fn load(
        weights: []const f32,
        cursor: *usize,
        in_channels: usize,
        out_channels: usize,
        with_bias: bool,
    ) !Conv1x1 {
        const weight_count = std.math.mul(usize, in_channels, out_channels) catch
            return error.InvalidNamDimensions;
        const bias_count: usize = if (with_bias) out_channels else 0;
        const end = std.math.add(usize, cursor.*, weight_count + bias_count) catch
            return error.InvalidNamWeights;
        if (end > weights.len) return error.InvalidNamWeights;
        const result: Conv1x1 = .{
            .in_channels = in_channels,
            .out_channels = out_channels,
            .weights = weights[cursor.* .. cursor.* + weight_count],
            .bias = weights[cursor.* + weight_count .. end],
        };
        cursor.* = end;
        return result;
    }

    fn process(self: Conv1x1, input: []const f32, output: []f32) void {
        std.debug.assert(input.len == self.in_channels);
        std.debug.assert(output.len == self.out_channels);
        for (output, 0..) |*value, out_index| {
            var sum: f32 = if (self.bias.len == 0) 0.0 else self.bias[out_index];
            const row = self.weights[out_index * self.in_channels ..][0..self.in_channels];
            for (row, input) |weight, sample| sum += weight * sample;
            value.* = sum;
        }
    }
};

const Conv1d = struct {
    allocator: std.mem.Allocator,
    in_channels: usize,
    out_channels: usize,
    kernel_size: usize,
    dilation: usize,
    history_frames: usize,
    write_index: usize = 0,
    weights: []const f32,
    bias: []const f32,
    history: []f32,

    fn load(
        allocator: std.mem.Allocator,
        weights: []const f32,
        cursor: *usize,
        in_channels: usize,
        out_channels: usize,
        kernel_size: usize,
        dilation: usize,
        with_bias: bool,
    ) !Conv1d {
        if (kernel_size == 0 or kernel_size > max_kernel_taps or dilation == 0) {
            return error.InvalidNamDimensions;
        }
        const channel_weights = std.math.mul(usize, in_channels, out_channels) catch
            return error.InvalidNamDimensions;
        const weight_count = std.math.mul(usize, channel_weights, kernel_size) catch
            return error.InvalidNamDimensions;
        const bias_count: usize = if (with_bias) out_channels else 0;
        const end = std.math.add(usize, cursor.*, weight_count + bias_count) catch
            return error.InvalidNamWeights;
        if (end > weights.len) return error.InvalidNamWeights;
        const history_frames = std.math.add(
            usize,
            std.math.mul(usize, kernel_size - 1, dilation) catch return error.InvalidNamDimensions,
            1,
        ) catch return error.InvalidNamDimensions;
        const history = try allocator.alloc(f32, history_frames * in_channels);
        @memset(history, 0.0);
        const result: Conv1d = .{
            .allocator = allocator,
            .in_channels = in_channels,
            .out_channels = out_channels,
            .kernel_size = kernel_size,
            .dilation = dilation,
            .history_frames = history_frames,
            .weights = weights[cursor.* .. cursor.* + weight_count],
            .bias = weights[cursor.* + weight_count .. end],
            .history = history,
        };
        cursor.* = end;
        return result;
    }

    fn deinit(self: *Conv1d) void {
        self.allocator.free(self.history);
        self.* = undefined;
    }

    fn reset(self: *Conv1d) void {
        @memset(self.history, 0.0);
        self.write_index = 0;
    }

    fn process(self: *Conv1d, input: []const f32, output: []f32) void {
        std.debug.assert(input.len == self.in_channels);
        std.debug.assert(output.len == self.out_channels);
        for (input, 0..) |sample, channel| {
            self.history[channel * self.history_frames + self.write_index] = sample;
        }

        var tap_positions: [max_kernel_taps]usize = undefined;
        for (tap_positions[0..self.kernel_size], 0..) |*position, tap| {
            const lookback = (self.kernel_size - 1 - tap) * self.dilation;
            position.* = if (self.write_index >= lookback)
                self.write_index - lookback
            else
                self.write_index + self.history_frames - lookback;
        }

        for (output, 0..) |*value, out_index| {
            var sum: f32 = if (self.bias.len == 0) 0.0 else self.bias[out_index];
            for (0..self.in_channels) |in_index| {
                const history = self.history[in_index * self.history_frames ..][0..self.history_frames];
                const weight_start = (out_index * self.in_channels + in_index) * self.kernel_size;
                const weights = self.weights[weight_start..][0..self.kernel_size];
                for (weights, tap_positions[0..self.kernel_size]) |weight, history_index| {
                    sum += weight * history[history_index];
                }
            }
            value.* = sum;
        }
        self.write_index += 1;
        if (self.write_index == self.history_frames) self.write_index = 0;
    }

    /// Processes planar channel data while preserving the exact causal state
    /// used by `process`. Time is the contiguous inner dimension so release
    /// builds can vectorize the dominant multiply-accumulate loops.
    fn processPlanar(self: *Conv1d, input: []const f32, output: []f32, frames: usize) void {
        std.debug.assert(input.len >= self.in_channels * frames);
        std.debug.assert(output.len >= self.out_channels * frames);
        for (0..self.out_channels) |out_index| {
            const bias: f32 = if (self.bias.len == 0) 0.0 else self.bias[out_index];
            @memset(output[out_index * frames ..][0..frames], bias);
            for (0..self.in_channels) |in_index| {
                const history = self.history[in_index * self.history_frames ..][0..self.history_frames];
                const input_channel = input[in_index * frames ..][0..frames];
                const output_channel = output[out_index * frames ..][0..frames];
                const weight_start = (out_index * self.in_channels + in_index) * self.kernel_size;
                const weights = self.weights[weight_start..][0..self.kernel_size];
                for (weights, 0..) |weight, tap| {
                    const lookback = (self.kernel_size - 1 - tap) * self.dilation;
                    const history_output_frames = @min(lookback, frames);
                    for (output_channel[0..history_output_frames], 0..) |*sample, frame| {
                        const ago = lookback - frame;
                        const history_index = if (self.write_index >= ago)
                            self.write_index - ago
                        else
                            self.write_index + self.history_frames - ago;
                        sample.* += weight * history[history_index];
                    }
                    if (lookback < frames) {
                        for (output_channel[lookback..], input_channel[0 .. frames - lookback]) |*sample, source| {
                            sample.* += weight * source;
                        }
                    }
                }
            }
        }

        for (0..frames) |frame| {
            for (0..self.in_channels) |channel| {
                self.history[channel * self.history_frames + self.write_index] = input[channel * frames + frame];
            }
            self.write_index += 1;
            if (self.write_index == self.history_frames) self.write_index = 0;
        }
    }
};

const Layer = struct {
    conv: Conv1d,
    input_mixin: Conv1x1,
    layer1x1: Conv1x1,
    negative_slope: f32,

    fn deinit(self: *Layer) void {
        self.conv.deinit();
        self.* = undefined;
    }

    fn reset(self: *Layer) void {
        self.conv.reset();
    }
};

/// Native Zig implementation of the causal WaveNet subset emitted by the
/// supplied TONE3000 pack. It intentionally rejects unsupported NAM features.
pub const Model = struct {
    allocator: std.mem.Allocator,
    parsed: std.json.Parsed(NamFile),
    channels: usize,
    sample_rate: f64,
    rechannel: Conv1x1,
    layers: []Layer,
    head: Conv1d,
    head_scale: f32,
    a2: ?nam_a2.Model = null,
    block_scratch: []f32 = &.{},
    block_capacity: usize = 0,

    pub const Quality = enum {
        lightweight,
        full,
    };

    pub fn load(allocator: std.mem.Allocator, bytes: []const u8) !Model {
        return loadQuality(allocator, bytes, .full);
    }

    pub fn loadQuality(allocator: std.mem.Allocator, bytes: []const u8, quality: Quality) !Model {
        var parsed = try std.json.parseFromSlice(NamFile, allocator, bytes, .{
            .ignore_unknown_fields = true,
        });
        errdefer parsed.deinit();

        if (!std.mem.eql(u8, parsed.value.version, "0.7.0")) return error.UnsupportedNamVersion;
        if (!std.mem.eql(u8, parsed.value.architecture, "SlimmableContainer")) {
            return error.UnsupportedNamArchitecture;
        }
        if (parsed.value.config.submodels.len == 0) return error.EmptyNamContainer;

        // NAM Core defaults a SlimmableContainer to its final model. Standalone
        // playback may explicitly select the first low-latency submodel.
        const submodel_index: usize = switch (quality) {
            .lightweight => 0,
            .full => parsed.value.config.submodels.len - 1,
        };
        const submodel = &parsed.value.config.submodels[submodel_index].model;
        if (!std.mem.eql(u8, submodel.version, "0.7.0")) return error.UnsupportedNamVersion;
        if (!std.mem.eql(u8, submodel.architecture, "WaveNet")) return error.UnsupportedNamArchitecture;
        if (submodel.sample_rate != parsed.value.sample_rate) return error.NamSampleRateMismatch;
        if (submodel.config.layers.len != 1 or submodel.config.head != null) {
            return error.UnsupportedWaveNetTopology;
        }

        const config = &submodel.config.layers[0];
        const channels: usize = config.channels;
        if (channels == 0 or channels > max_channels or config.bottleneck != channels or
            config.input_size != 1 or config.condition_size != 1 or
            config.head.out_channels != 1 or !config.head.bias or
            config.head1x1.active or !config.layer1x1.active or
            config.groups_input != 1 or config.groups_input_mixin != 1 or
            config.layer1x1.groups != 1)
        {
            return error.UnsupportedWaveNetTopology;
        }
        const layer_count = config.kernel_sizes.len;
        if (layer_count == 0 or config.dilations.len != layer_count or
            config.activation.len != layer_count or config.gating_mode.len != layer_count)
        {
            return error.InvalidWaveNetConfig;
        }
        for (config.activation, config.gating_mode) |activation, gating| {
            if (!std.mem.eql(u8, activation.type, "LeakyReLU") or
                !std.mem.eql(u8, gating, "none"))
            {
                return error.UnsupportedWaveNetActivation;
            }
        }

        const weights = submodel.weights;
        var cursor: usize = 0;
        const rechannel = try Conv1x1.load(weights, &cursor, 1, channels, false);

        const layers = try allocator.alloc(Layer, layer_count);
        errdefer allocator.free(layers);
        var initialized_layers: usize = 0;
        errdefer for (layers[0..initialized_layers]) |*layer| layer.deinit();
        for (layers, 0..) |*layer, index| {
            const conv = try Conv1d.load(
                allocator,
                weights,
                &cursor,
                channels,
                channels,
                config.kernel_sizes[index],
                config.dilations[index],
                true,
            );
            errdefer {
                var mutable = conv;
                mutable.deinit();
            }
            layer.* = .{
                .conv = conv,
                .input_mixin = try Conv1x1.load(weights, &cursor, 1, channels, false),
                .layer1x1 = try Conv1x1.load(weights, &cursor, channels, channels, true),
                .negative_slope = config.activation[index].negative_slope,
            };
            initialized_layers += 1;
        }

        var head = try Conv1d.load(
            allocator,
            weights,
            &cursor,
            channels,
            1,
            config.head.kernel_size,
            1,
            true,
        );
        errdefer head.deinit();
        if (cursor >= weights.len) return error.InvalidNamWeights;
        const head_scale = weights[cursor];
        cursor += 1;
        if (cursor != weights.len) return error.InvalidNamWeights;

        var a2: ?nam_a2.Model = if (isA2Shape(config))
            try nam_a2.Model.init(allocator, weights, channels)
        else
            null;
        errdefer if (a2) |*fast| fast.deinit();

        return .{
            .allocator = allocator,
            .parsed = parsed,
            .channels = channels,
            .sample_rate = submodel.sample_rate,
            .rechannel = rechannel,
            .layers = layers,
            .head = head,
            .head_scale = head_scale,
            .a2 = a2,
        };
    }

    pub fn deinit(self: *Model) void {
        for (self.layers) |*layer| layer.deinit();
        self.allocator.free(self.layers);
        self.head.deinit();
        if (self.a2) |*fast| fast.deinit();
        if (self.block_scratch.len != 0) self.allocator.free(self.block_scratch);
        self.parsed.deinit();
        self.* = undefined;
    }

    pub fn reset(self: *Model) void {
        for (self.layers) |*layer| layer.reset();
        self.head.reset();
        if (self.a2) |*fast| fast.reset();
    }

    pub fn prewarm(self: *Model, block_size: usize) void {
        const frames = @max(block_size, 1);
        const required = self.prewarmFrames();
        const rounded = std.math.divCeil(usize, required, frames) catch unreachable;
        for (0..rounded * frames) |_| _ = self.processSample(0.0);
        if (self.a2) |*fast| {
            if (fast.block_capacity != 0) fast.prewarm();
        }
    }

    /// Allocates reusable planar scratch outside the real-time callback.
    pub fn prepareBlock(self: *Model, maximum_frames: usize) !void {
        if (maximum_frames == 0) return error.InvalidNamBlockSize;
        if (maximum_frames <= self.block_capacity) return;
        const sample_count = std.math.mul(usize, maximum_frames, self.channels * 4) catch
            return error.InvalidNamBlockSize;
        const scratch = try self.allocator.alloc(f32, sample_count);
        if (self.block_scratch.len != 0) self.allocator.free(self.block_scratch);
        self.block_scratch = scratch;
        self.block_capacity = maximum_frames;
        if (self.a2) |*fast| try fast.prepareBlock(maximum_frames);
    }

    pub fn process(self: *Model, input: []const f32, output: []f32) void {
        std.debug.assert(output.len >= input.len);
        for (input, output[0..input.len]) |sample, *result| result.* = self.processSample(sample);
    }

    /// Block-equivalent WaveNet evaluation for mono input and output.
    /// `prepareBlock` must be called with at least `input.len` before entering
    /// the real-time thread.
    pub fn processBlock(self: *Model, input: []const f32, output: []f32) void {
        std.debug.assert(input.len == output.len);
        const frames = input.len;
        std.debug.assert(frames > 0 and frames <= self.block_capacity);
        if (self.a2) |*fast| {
            fast.processBlock(input, output);
            return;
        }
        const plane_samples = self.channels * frames;
        const current = self.block_scratch[0..plane_samples];
        const z = self.block_scratch[plane_samples..][0..plane_samples];
        const residual = self.block_scratch[plane_samples * 2 ..][0..plane_samples];
        const head_sum = self.block_scratch[plane_samples * 3 ..][0..plane_samples];
        @memset(head_sum, 0.0);

        for (0..self.channels) |channel| {
            const bias: f32 = if (self.rechannel.bias.len == 0) 0.0 else self.rechannel.bias[channel];
            const weight = self.rechannel.weights[channel];
            for (current[channel * frames ..][0..frames], input) |*sample, scalar| {
                sample.* = bias + weight * scalar;
            }
        }

        for (self.layers) |*layer| {
            layer.conv.processPlanar(current, z, frames);
            for (0..self.channels) |channel| {
                const mix_bias: f32 = if (layer.input_mixin.bias.len == 0) 0.0 else layer.input_mixin.bias[channel];
                const mix_weight = layer.input_mixin.weights[channel];
                const z_channel = z[channel * frames ..][0..frames];
                const head_channel = head_sum[channel * frames ..][0..frames];
                for (z_channel, head_channel, input) |*value, *head_value, scalar| {
                    value.* += mix_bias + mix_weight * scalar;
                    if (value.* < 0.0) value.* *= layer.negative_slope;
                    head_value.* += value.*;
                }
            }

            for (0..self.channels) |out_channel| {
                const bias: f32 = if (layer.layer1x1.bias.len == 0) 0.0 else layer.layer1x1.bias[out_channel];
                @memset(residual[out_channel * frames ..][0..frames], bias);
                for (0..self.channels) |in_channel| {
                    const weight = layer.layer1x1.weights[out_channel * self.channels + in_channel];
                    const source = z[in_channel * frames ..][0..frames];
                    const destination = residual[out_channel * frames ..][0..frames];
                    for (destination, source) |*value, sample| value.* += weight * sample;
                }
                const current_channel = current[out_channel * frames ..][0..frames];
                const residual_channel = residual[out_channel * frames ..][0..frames];
                for (current_channel, residual_channel) |*value, addition| value.* += addition;
            }
        }

        self.head.processPlanar(head_sum, output, frames);
        for (output) |*sample| sample.* *= self.head_scale;
    }

    pub fn processSample(self: *Model, input: f32) f32 {
        var current: [max_channels]f32 = undefined;
        var z: [max_channels]f32 = undefined;
        var mixin: [max_channels]f32 = undefined;
        var residual: [max_channels]f32 = undefined;
        var head_sum: [max_channels]f32 = undefined;
        @memset(head_sum[0..self.channels], 0.0);

        const scalar = [1]f32{input};
        self.rechannel.process(&scalar, current[0..self.channels]);
        for (self.layers) |*layer| {
            layer.conv.process(current[0..self.channels], z[0..self.channels]);
            layer.input_mixin.process(&scalar, mixin[0..self.channels]);
            for (0..self.channels) |channel| {
                z[channel] += mixin[channel];
                if (z[channel] < 0.0) z[channel] *= layer.negative_slope;
                head_sum[channel] += z[channel];
            }
            layer.layer1x1.process(z[0..self.channels], residual[0..self.channels]);
            for (0..self.channels) |channel| current[channel] += residual[channel];
        }

        var output: [1]f32 = undefined;
        self.head.process(head_sum[0..self.channels], &output);
        return self.head_scale * output[0];
    }

    fn prewarmFrames(self: Model) usize {
        var result: usize = 1;
        for (self.layers) |layer| result += (layer.conv.kernel_size - 1) * layer.conv.dilation;
        result += self.head.kernel_size - 1;
        return result;
    }
};

fn isA2Shape(config: *const LayerArrayConfig) bool {
    if ((config.channels != 3 and config.channels != 8) or
        config.head.kernel_size != nam_a2.head_kernel_size or
        config.kernel_sizes.len != nam_a2.layer_count or
        config.dilations.len != nam_a2.layer_count or
        config.activation.len != nam_a2.layer_count)
    {
        return false;
    }
    if (!std.mem.eql(u16, config.kernel_sizes, &nam_a2.kernel_sizes) or
        !std.mem.eql(u16, config.dilations, &nam_a2.dilations))
    {
        return false;
    }
    for (config.activation) |activation| {
        if (activation.negative_slope != nam_a2.leaky_slope) return false;
    }
    return true;
}

test "causal convolution follows NAM oldest-to-newest weight order" {
    const allocator = std.testing.allocator;
    const weights = [_]f32{ 1.0, 10.0, 100.0 };
    var cursor: usize = 0;
    var conv = try Conv1d.load(allocator, &weights, &cursor, 1, 1, 3, 1, false);
    defer conv.deinit();

    var output: [1]f32 = undefined;
    conv.process(&.{1.0}, &output);
    try std.testing.expectEqual(@as(f32, 100.0), output[0]);
    conv.process(&.{2.0}, &output);
    try std.testing.expectEqual(@as(f32, 210.0), output[0]);
    conv.process(&.{3.0}, &output);
    try std.testing.expectEqual(@as(f32, 321.0), output[0]);
}

test "block WaveNet evaluation matches sample evaluation" {
    const wav = @import("wav.zig");
    const allocator = std.testing.allocator;
    const model_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "resources/audio/models/nam/dumble-ods-102-ford-hyper-accuracy-plus/SLAMMIN_DUMBLE_FORD_CLN_MAIN_S.nam",
        allocator,
        .limited(2 * 1024 * 1024),
    );
    defer allocator.free(model_bytes);
    var sample_model = try Model.load(allocator, model_bytes);
    defer sample_model.deinit();
    var block_model = try Model.load(allocator, model_bytes);
    defer block_model.deinit();
    try block_model.prepareBlock(64);

    const wav_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "resources/audio/fixtures/inputs/celestial-guitar-48k-mono.wav",
        allocator,
        .limited(8 * 1024 * 1024),
    );
    defer allocator.free(wav_bytes);
    var source = try wav.decode(allocator, wav_bytes);
    defer source.deinit(allocator);
    sample_model.prewarm(64);
    block_model.prewarm(64);

    var expected: [256]f32 = undefined;
    var actual: [256]f32 = undefined;
    sample_model.process(source.samples[0..expected.len], &expected);
    for (0..4) |block| {
        const start = block * 64;
        block_model.processBlock(source.samples[start..][0..64], actual[start..][0..64]);
    }
    for (expected, actual) |sample, block| {
        try std.testing.expectApproxEqAbs(sample, block, 0.000002);
    }
}

test "Dumble full model agrees with NAM Core reference samples" {
    const wav = @import("wav.zig");
    const allocator = std.testing.allocator;
    const model_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "resources/audio/models/nam/dumble-ods-102-ford-hyper-accuracy-plus/SLAMMIN_DUMBLE_FORD_CLN_MAIN_S.nam",
        allocator,
        .limited(2 * 1024 * 1024),
    );
    defer allocator.free(model_bytes);
    var model = try Model.load(
        allocator,
        model_bytes,
    );
    defer model.deinit();
    const wav_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "resources/audio/fixtures/inputs/celestial-guitar-48k-mono.wav",
        allocator,
        .limited(8 * 1024 * 1024),
    );
    defer allocator.free(wav_bytes);
    var input = try wav.decode(
        allocator,
        wav_bytes,
    );
    defer input.deinit(allocator);

    try std.testing.expectEqual(@as(f64, 48_000.0), model.sample_rate);
    try std.testing.expectEqual(@as(u32, 48_000), input.sample_rate);
    try std.testing.expectEqual(@as(u16, 1), input.channels);
    model.prewarm(64);

    const references = [_]struct { index: usize, value: f32 }{
        .{ .index = 0, .value = -0.000034245644201291725 },
        .{ .index = 63, .value = -0.00003411207580938935 },
        .{ .index = 255, .value = -0.00003424419992370531 },
        .{ .index = 1023, .value = -0.000034471431717975065 },
        .{ .index = 2047, .value = 0.00015691669250372797 },
    };
    var reference_index: usize = 0;
    for (input.samples[0 .. references[references.len - 1].index + 1], 0..) |sample, index| {
        const output = model.processSample(sample);
        if (index == references[reference_index].index) {
            try std.testing.expectApproxEqAbs(references[reference_index].value, output, 0.000002);
            reference_index += 1;
            if (reference_index == references.len) break;
        }
    }
}

test "Dumble lightweight model agrees with NAM Core reference samples" {
    const wav = @import("wav.zig");
    const allocator = std.testing.allocator;
    const model_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "resources/audio/models/nam/dumble-ods-102-ford-hyper-accuracy-plus/SLAMMIN_DUMBLE_FORD_CLN_MAIN_S.nam",
        allocator,
        .limited(2 * 1024 * 1024),
    );
    defer allocator.free(model_bytes);
    var model = try Model.loadQuality(allocator, model_bytes, .lightweight);
    defer model.deinit();
    const wav_bytes = try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        "resources/audio/fixtures/inputs/celestial-guitar-48k-mono.wav",
        allocator,
        .limited(8 * 1024 * 1024),
    );
    defer allocator.free(wav_bytes);
    var input = try wav.decode(allocator, wav_bytes);
    defer input.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 3), model.channels);
    model.prewarm(64);
    const references = [_]struct { index: usize, value: f32 }{
        .{ .index = 0, .value = 0.00043589476263150573 },
        .{ .index = 63, .value = 0.00043617613846436143 },
        .{ .index = 255, .value = 0.0004358842270448804 },
        .{ .index = 1023, .value = 0.00043544586515054107 },
        .{ .index = 2047, .value = 0.0007064516539685428 },
    };
    var reference_index: usize = 0;
    for (input.samples[0 .. references[references.len - 1].index + 1], 0..) |sample, index| {
        const output = model.processSample(sample);
        if (index == references[reference_index].index) {
            try std.testing.expectApproxEqAbs(references[reference_index].value, output, 0.000002);
            reference_index += 1;
            if (reference_index == references.len) break;
        }
    }
}
