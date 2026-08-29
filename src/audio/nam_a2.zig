const std = @import("std");

pub const layer_count = 23;
pub const head_kernel_size = 16;
pub const leaky_slope: f32 = 0.01;

pub const kernel_sizes = [layer_count]u16{
    6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 15, 15, 6, 6, 6, 6, 6, 6, 6,
};

pub const dilations = [layer_count]u16{
    1, 3, 7, 17, 41, 101, 239, 1, 3, 7, 17, 41, 101, 239, 1, 13, 1, 3, 7, 17, 41, 101, 239,
};

const max_channels = 8;
const max_kernel_size = 15;
const max_conv_weights = max_kernel_size * max_channels * max_channels;

const Layer = struct {
    kernel_size: usize = 0,
    dilation: usize = 0,
    max_lookback: usize = 0,
    conv_weights: [max_conv_weights]f32 = .{0.0} ** max_conv_weights,
    conv_bias: [max_channels]f32 = .{0.0} ** max_channels,
    mixin_weights: [max_channels]f32 = .{0.0} ** max_channels,
    residual_weights: [max_channels * max_channels]f32 = .{0.0} ** (max_channels * max_channels),
    residual_bias: [max_channels]f32 = .{0.0} ** max_channels,
    history: []f32 = &.{},
    ring_size: usize = 0,
    ring_mask: usize = 0,
    write_index: usize = 0,
};

/// A deliberately narrow A2 engine. The fixed shape lets the hot loop keep
/// complete channel vectors in SIMD registers instead of treating each layer
/// as a general convolution or matrix multiplication.
pub const Model = struct {
    allocator: std.mem.Allocator,
    channels: usize,
    layers: []Layer,
    rechannel_weights: [max_channels]f32 = .{0.0} ** max_channels,
    head_weights: [head_kernel_size * max_channels]f32 = .{0.0} ** (head_kernel_size * max_channels),
    head_bias: f32 = 0.0,
    head_scale: f32 = 1.0,
    head_history: []f32 = &.{},
    head_ring_size: usize = 0,
    head_ring_mask: usize = 0,
    head_write_index: usize = 0,
    scratch: []f32 = &.{},
    silence: []f32 = &.{},
    discard: []f32 = &.{},
    block_capacity: usize = 0,

    pub fn init(allocator: std.mem.Allocator, weights: []const f32, channels: usize) !Model {
        if (channels != 3 and channels != 8) return error.UnsupportedA2Channels;
        const layers = try allocator.alloc(Layer, layer_count);
        errdefer allocator.free(layers);
        for (layers, 0..) |*layer, index| {
            layer.* = .{
                .kernel_size = kernel_sizes[index],
                .dilation = dilations[index],
                .max_lookback = (kernel_sizes[index] - 1) * dilations[index],
            };
        }

        var result: Model = .{
            .allocator = allocator,
            .channels = channels,
            .layers = layers,
        };
        errdefer result.deinit();
        var cursor: usize = 0;

        for (0..channels) |out_channel| {
            result.rechannel_weights[out_channel] = try take(weights, &cursor);
        }

        for (result.layers) |*layer| {
            const kernel_size = layer.kernel_size;
            for (0..channels) |out_channel| {
                for (0..channels) |in_channel| {
                    for (0..kernel_size) |tap| {
                        layer.conv_weights[tap * channels * channels + in_channel * channels + out_channel] =
                            try take(weights, &cursor);
                    }
                }
            }
            for (0..channels) |out_channel| {
                layer.conv_bias[out_channel] = try take(weights, &cursor);
            }
            for (0..channels) |out_channel| {
                layer.mixin_weights[out_channel] = try take(weights, &cursor);
            }
            for (0..channels) |out_channel| {
                for (0..channels) |in_channel| {
                    layer.residual_weights[in_channel * channels + out_channel] = try take(weights, &cursor);
                }
            }
            for (0..channels) |out_channel| {
                layer.residual_bias[out_channel] = try take(weights, &cursor);
            }
        }

        for (0..channels) |in_channel| {
            for (0..head_kernel_size) |tap| {
                result.head_weights[tap * channels + in_channel] = try take(weights, &cursor);
            }
        }
        result.head_bias = try take(weights, &cursor);
        result.head_scale = try take(weights, &cursor);
        if (cursor != weights.len) return error.InvalidA2Weights;
        return result;
    }

    pub fn deinit(self: *Model) void {
        for (self.layers) |*layer| {
            if (layer.history.len != 0) self.allocator.free(layer.history);
        }
        self.allocator.free(self.layers);
        if (self.head_history.len != 0) self.allocator.free(self.head_history);
        if (self.scratch.len != 0) self.allocator.free(self.scratch);
        if (self.silence.len != 0) self.allocator.free(self.silence);
        if (self.discard.len != 0) self.allocator.free(self.discard);
        self.* = undefined;
    }

    pub fn prepareBlock(self: *Model, maximum_frames: usize) !void {
        if (maximum_frames == 0) return error.InvalidA2BlockSize;
        if (maximum_frames <= self.block_capacity) return;

        for (self.layers) |*layer| {
            const ring_size = nextPowerOfTwo(layer.max_lookback + maximum_frames);
            const history = try self.allocator.alloc(f32, (ring_size + maximum_frames) * self.channels);
            @memset(history, 0.0);
            if (layer.history.len != 0) self.allocator.free(layer.history);
            layer.history = history;
            layer.ring_size = ring_size;
            layer.ring_mask = ring_size - 1;
            layer.write_index = layer.max_lookback;
        }

        const head_ring_size = nextPowerOfTwo(head_kernel_size - 1 + maximum_frames);
        const head_history = try self.allocator.alloc(
            f32,
            (head_ring_size + maximum_frames) * self.channels,
        );
        @memset(head_history, 0.0);
        if (self.head_history.len != 0) self.allocator.free(self.head_history);
        self.head_history = head_history;
        self.head_ring_size = head_ring_size;
        self.head_ring_mask = head_ring_size - 1;
        self.head_write_index = head_kernel_size - 1;

        const scratch = try self.allocator.alloc(f32, maximum_frames * self.channels * 2);
        if (self.scratch.len != 0) self.allocator.free(self.scratch);
        self.scratch = scratch;
        const silence = try self.allocator.alloc(f32, maximum_frames);
        @memset(silence, 0.0);
        if (self.silence.len != 0) self.allocator.free(self.silence);
        self.silence = silence;
        const discard = try self.allocator.alloc(f32, maximum_frames);
        if (self.discard.len != 0) self.allocator.free(self.discard);
        self.discard = discard;
        self.block_capacity = maximum_frames;
    }

    pub fn reset(self: *Model) void {
        for (self.layers) |*layer| {
            @memset(layer.history, 0.0);
            layer.write_index = layer.max_lookback;
        }
        @memset(self.head_history, 0.0);
        self.head_write_index = head_kernel_size - 1;
    }

    pub fn prewarm(self: *Model) void {
        std.debug.assert(self.block_capacity > 0);
        var remaining = self.prewarmFrames();
        while (remaining > 0) {
            const frames = @min(remaining, self.block_capacity);
            self.processBlock(self.silence[0..frames], self.discard[0..frames]);
            remaining -= frames;
        }
    }

    pub fn processBlock(self: *Model, input: []const f32, output: []f32) void {
        std.debug.assert(input.len == output.len);
        std.debug.assert(input.len > 0 and input.len <= self.block_capacity);
        switch (self.channels) {
            3 => self.processChannels(3, input, output),
            8 => self.processChannels(8, input, output),
            else => unreachable,
        }
    }

    fn processChannels(self: *Model, comptime channels: usize, input: []const f32, output: []f32) void {
        const frames = input.len;
        const plane_size = frames * channels;
        const current = self.scratch[0..plane_size];
        const head_sum = self.scratch[plane_size..][0..plane_size];

        for (input, 0..) |sample, frame| {
            const value: @Vector(channels, f32) = @splat(sample);
            storeVector(channels, current, frame * channels, value * loadVector(
                channels,
                &self.rechannel_weights,
                0,
            ));
        }
        @memset(head_sum, 0.0);

        for (self.layers) |*layer| {
            ringWrite(channels, layer, current, frames, self.block_capacity);
            layerForwardFull(channels, layer, input, current, head_sum, frames);
        }
        self.headForwardFull(channels, head_sum, output, frames);
    }

    fn headForwardFull(
        self: *Model,
        comptime channels: usize,
        head_sum: []const f32,
        output: []f32,
        frames: usize,
    ) void {
        ringWriteRaw(
            channels,
            self.head_history,
            self.head_ring_size,
            self.head_ring_mask,
            &self.head_write_index,
            head_sum,
            frames,
            self.block_capacity,
        );

        for (0..frames) |frame| {
            var sum = self.head_bias;
            inline for (0..head_kernel_size) |tap| {
                const lookback = head_kernel_size - 1 - tap;
                const base = self.head_write_index + self.head_ring_size - frames - lookback;
                const history_index = (base & self.head_ring_mask) + frame;
                const weights = loadVector(channels, &self.head_weights, tap * channels);
                const history = loadVector(channels, self.head_history, history_index * channels);
                sum += @reduce(.Add, weights * history);
            }
            output[frame] = sum * self.head_scale;
        }
    }

    fn headForwardLite(self: *Model, head_sum: []const f32, output: []f32, frames: usize) void {
        ringWriteRaw(
            3,
            self.head_history,
            self.head_ring_size,
            self.head_ring_mask,
            &self.head_write_index,
            head_sum,
            frames,
            self.block_capacity,
        );

        const Vec4 = @Vector(4, f32);
        var frame: usize = 0;
        while (frame + 4 <= frames) : (frame += 4) {
            var sum: Vec4 = @splat(self.head_bias);
            inline for (0..head_kernel_size) |tap| {
                const lookback = head_kernel_size - 1 - tap;
                const base = self.head_write_index + self.head_ring_size - frames - lookback;
                const history_frame = (base & self.head_ring_mask) + frame;
                inline for (0..3) |channel| {
                    sum = @mulAdd(
                        Vec4,
                        @as(Vec4, @splat(self.head_weights[tap * 3 + channel])),
                        gather4(3, self.head_history, history_frame, channel),
                        sum,
                    );
                }
            }
            storeVector(4, output, frame, sum * @as(Vec4, @splat(self.head_scale)));
        }
        while (frame < frames) : (frame += 1) {
            var sum = self.head_bias;
            inline for (0..head_kernel_size) |tap| {
                const lookback = head_kernel_size - 1 - tap;
                const base = self.head_write_index + self.head_ring_size - frames - lookback;
                const history_frame = (base & self.head_ring_mask) + frame;
                inline for (0..3) |channel| {
                    sum += self.head_weights[tap * 3 + channel] *
                        self.head_history[history_frame * 3 + channel];
                }
            }
            output[frame] = sum * self.head_scale;
        }
    }

    fn prewarmFrames(self: Model) usize {
        var result: usize = 1;
        for (self.layers) |layer| result += layer.max_lookback;
        return result + head_kernel_size - 1;
    }
};

fn layerForwardFull(
    comptime channels: usize,
    layer: *Layer,
    input: []const f32,
    current: []f32,
    head_sum: []f32,
    frames: usize,
) void {
    const Vec = @Vector(channels, f32);
    const zero: Vec = @splat(0.0);
    const slope: Vec = @splat(leaky_slope);
    const conv_bias = loadVector(channels, &layer.conv_bias, 0);
    const mixin = loadVector(channels, &layer.mixin_weights, 0);
    const residual_bias = loadVector(channels, &layer.residual_bias, 0);

    var frame: usize = 0;
    while (frame + 4 <= frames) : (frame += 4) {
        var a0 = conv_bias;
        var a1 = conv_bias;
        var a2 = conv_bias;
        var a3 = conv_bias;
        for (0..layer.kernel_size) |tap| {
            const lookback = (layer.kernel_size - 1 - tap) * layer.dilation;
            const base = layer.write_index + layer.ring_size - frames - lookback;
            const history_frame = base & layer.ring_mask;
            for (0..channels) |in_channel| {
                const weights = loadVector(
                    channels,
                    &layer.conv_weights,
                    tap * channels * channels + in_channel * channels,
                );
                a0 = @mulAdd(Vec, weights, @as(Vec, @splat(layer.history[(history_frame + frame) * channels + in_channel])), a0);
                a1 = @mulAdd(Vec, weights, @as(Vec, @splat(layer.history[(history_frame + frame + 1) * channels + in_channel])), a1);
                a2 = @mulAdd(Vec, weights, @as(Vec, @splat(layer.history[(history_frame + frame + 2) * channels + in_channel])), a2);
                a3 = @mulAdd(Vec, weights, @as(Vec, @splat(layer.history[(history_frame + frame + 3) * channels + in_channel])), a3);
            }
        }
        a0 = @mulAdd(Vec, mixin, @as(Vec, @splat(input[frame])), a0);
        a1 = @mulAdd(Vec, mixin, @as(Vec, @splat(input[frame + 1])), a1);
        a2 = @mulAdd(Vec, mixin, @as(Vec, @splat(input[frame + 2])), a2);
        a3 = @mulAdd(Vec, mixin, @as(Vec, @splat(input[frame + 3])), a3);
        a0 = @select(f32, a0 < zero, a0 * slope, a0);
        a1 = @select(f32, a1 < zero, a1 * slope, a1);
        a2 = @select(f32, a2 < zero, a2 * slope, a2);
        a3 = @select(f32, a3 < zero, a3 * slope, a3);
        storeVector(channels, head_sum, frame * channels, loadVector(channels, head_sum, frame * channels) + a0);
        storeVector(channels, head_sum, (frame + 1) * channels, loadVector(channels, head_sum, (frame + 1) * channels) + a1);
        storeVector(channels, head_sum, (frame + 2) * channels, loadVector(channels, head_sum, (frame + 2) * channels) + a2);
        storeVector(channels, head_sum, (frame + 3) * channels, loadVector(channels, head_sum, (frame + 3) * channels) + a3);

        var r0 = residual_bias;
        var r1 = residual_bias;
        var r2 = residual_bias;
        var r3 = residual_bias;
        inline for (0..channels) |in_channel| {
            const weights = loadVector(
                channels,
                &layer.residual_weights,
                in_channel * channels,
            );
            r0 = @mulAdd(Vec, weights, @as(Vec, @splat(a0[in_channel])), r0);
            r1 = @mulAdd(Vec, weights, @as(Vec, @splat(a1[in_channel])), r1);
            r2 = @mulAdd(Vec, weights, @as(Vec, @splat(a2[in_channel])), r2);
            r3 = @mulAdd(Vec, weights, @as(Vec, @splat(a3[in_channel])), r3);
        }
        storeVector(channels, current, frame * channels, loadVector(channels, current, frame * channels) + r0);
        storeVector(channels, current, (frame + 1) * channels, loadVector(channels, current, (frame + 1) * channels) + r1);
        storeVector(channels, current, (frame + 2) * channels, loadVector(channels, current, (frame + 2) * channels) + r2);
        storeVector(channels, current, (frame + 3) * channels, loadVector(channels, current, (frame + 3) * channels) + r3);
    }

    while (frame < frames) : (frame += 1) {
        var activation = conv_bias;
        for (0..layer.kernel_size) |tap| {
            const lookback = (layer.kernel_size - 1 - tap) * layer.dilation;
            const base = layer.write_index + layer.ring_size - frames - lookback;
            const history_frame = (base & layer.ring_mask) + frame;
            for (0..channels) |in_channel| {
                const weights = loadVector(
                    channels,
                    &layer.conv_weights,
                    tap * channels * channels + in_channel * channels,
                );
                activation = @mulAdd(
                    Vec,
                    weights,
                    @as(Vec, @splat(layer.history[history_frame * channels + in_channel])),
                    activation,
                );
            }
        }
        activation = @mulAdd(Vec, mixin, @as(Vec, @splat(input[frame])), activation);
        activation = @select(f32, activation < zero, activation * slope, activation);
        storeVector(
            channels,
            head_sum,
            frame * channels,
            loadVector(channels, head_sum, frame * channels) + activation,
        );
        var residual = residual_bias;
        inline for (0..channels) |in_channel| {
            residual = @mulAdd(
                Vec,
                loadVector(channels, &layer.residual_weights, in_channel * channels),
                @as(Vec, @splat(activation[in_channel])),
                residual,
            );
        }
        storeVector(
            channels,
            current,
            frame * channels,
            loadVector(channels, current, frame * channels) + residual,
        );
    }
}

fn layerForwardLite(
    layer: *Layer,
    input: []const f32,
    current: []f32,
    head_sum: []f32,
    frames: usize,
) void {
    const Vec4 = @Vector(4, f32);
    const zero: Vec4 = @splat(0.0);
    const slope: Vec4 = @splat(leaky_slope);
    var frame: usize = 0;
    while (frame + 4 <= frames) : (frame += 4) {
        var a0: Vec4 = @splat(layer.conv_bias[0]);
        var a1: Vec4 = @splat(layer.conv_bias[1]);
        var a2: Vec4 = @splat(layer.conv_bias[2]);
        for (0..layer.kernel_size) |tap| {
            const lookback = (layer.kernel_size - 1 - tap) * layer.dilation;
            const base = layer.write_index + layer.ring_size - frames - lookback;
            const history_frame = (base & layer.ring_mask) + frame;
            inline for (0..3) |in_channel| {
                const source = gather4(3, layer.history, history_frame, in_channel);
                const weight_offset = tap * 9 + in_channel * 3;
                a0 = @mulAdd(Vec4, @as(Vec4, @splat(layer.conv_weights[weight_offset])), source, a0);
                a1 = @mulAdd(Vec4, @as(Vec4, @splat(layer.conv_weights[weight_offset + 1])), source, a1);
                a2 = @mulAdd(Vec4, @as(Vec4, @splat(layer.conv_weights[weight_offset + 2])), source, a2);
            }
        }
        const condition = loadVector(4, input, frame);
        a0 = @mulAdd(Vec4, @as(Vec4, @splat(layer.mixin_weights[0])), condition, a0);
        a1 = @mulAdd(Vec4, @as(Vec4, @splat(layer.mixin_weights[1])), condition, a1);
        a2 = @mulAdd(Vec4, @as(Vec4, @splat(layer.mixin_weights[2])), condition, a2);
        a0 = @select(f32, a0 < zero, a0 * slope, a0);
        a1 = @select(f32, a1 < zero, a1 * slope, a1);
        a2 = @select(f32, a2 < zero, a2 * slope, a2);

        scatter4(3, head_sum, frame, 0, gather4(3, head_sum, frame, 0) + a0);
        scatter4(3, head_sum, frame, 1, gather4(3, head_sum, frame, 1) + a1);
        scatter4(3, head_sum, frame, 2, gather4(3, head_sum, frame, 2) + a2);

        var r0: Vec4 = @splat(layer.residual_bias[0]);
        var r1: Vec4 = @splat(layer.residual_bias[1]);
        var r2: Vec4 = @splat(layer.residual_bias[2]);
        r0 = @mulAdd(Vec4, @as(Vec4, @splat(layer.residual_weights[0])), a0, r0);
        r1 = @mulAdd(Vec4, @as(Vec4, @splat(layer.residual_weights[1])), a0, r1);
        r2 = @mulAdd(Vec4, @as(Vec4, @splat(layer.residual_weights[2])), a0, r2);
        r0 = @mulAdd(Vec4, @as(Vec4, @splat(layer.residual_weights[3])), a1, r0);
        r1 = @mulAdd(Vec4, @as(Vec4, @splat(layer.residual_weights[4])), a1, r1);
        r2 = @mulAdd(Vec4, @as(Vec4, @splat(layer.residual_weights[5])), a1, r2);
        r0 = @mulAdd(Vec4, @as(Vec4, @splat(layer.residual_weights[6])), a2, r0);
        r1 = @mulAdd(Vec4, @as(Vec4, @splat(layer.residual_weights[7])), a2, r1);
        r2 = @mulAdd(Vec4, @as(Vec4, @splat(layer.residual_weights[8])), a2, r2);
        scatter4(3, current, frame, 0, gather4(3, current, frame, 0) + r0);
        scatter4(3, current, frame, 1, gather4(3, current, frame, 1) + r1);
        scatter4(3, current, frame, 2, gather4(3, current, frame, 2) + r2);
    }

    while (frame < frames) : (frame += 1) {
        var activation = [3]f32{
            layer.conv_bias[0],
            layer.conv_bias[1],
            layer.conv_bias[2],
        };
        for (0..layer.kernel_size) |tap| {
            const lookback = (layer.kernel_size - 1 - tap) * layer.dilation;
            const base = layer.write_index + layer.ring_size - frames - lookback;
            const history_frame = (base & layer.ring_mask) + frame;
            inline for (0..3) |in_channel| {
                const source = layer.history[history_frame * 3 + in_channel];
                const weight_offset = tap * 9 + in_channel * 3;
                activation[0] += layer.conv_weights[weight_offset] * source;
                activation[1] += layer.conv_weights[weight_offset + 1] * source;
                activation[2] += layer.conv_weights[weight_offset + 2] * source;
            }
        }
        inline for (0..3) |channel| {
            activation[channel] += layer.mixin_weights[channel] * input[frame];
            if (activation[channel] < 0.0) activation[channel] *= leaky_slope;
            head_sum[frame * 3 + channel] += activation[channel];
        }
        inline for (0..3) |out_channel| {
            var residual = layer.residual_bias[out_channel];
            inline for (0..3) |in_channel| {
                residual += layer.residual_weights[in_channel * 3 + out_channel] * activation[in_channel];
            }
            current[frame * 3 + out_channel] += residual;
        }
    }
}

fn ringWrite(
    comptime channels: usize,
    layer: *Layer,
    source: []const f32,
    frames: usize,
    maximum_frames: usize,
) void {
    ringWriteRaw(
        channels,
        layer.history,
        layer.ring_size,
        layer.ring_mask,
        &layer.write_index,
        source,
        frames,
        maximum_frames,
    );
}

fn ringWriteRaw(
    comptime channels: usize,
    history: []f32,
    ring_size: usize,
    ring_mask: usize,
    write_index: *usize,
    source: []const f32,
    frames: usize,
    maximum_frames: usize,
) void {
    const first_frames = @min(frames, ring_size - write_index.*);
    @memcpy(
        history[write_index.* * channels ..][0 .. first_frames * channels],
        source[0 .. first_frames * channels],
    );
    if (first_frames < frames) {
        @memcpy(
            history[0 .. (frames - first_frames) * channels],
            source[first_frames * channels .. frames * channels],
        );
    }
    @memcpy(
        history[ring_size * channels ..][0 .. maximum_frames * channels],
        history[0 .. maximum_frames * channels],
    );
    write_index.* = (write_index.* + frames) & ring_mask;
}

fn loadVector(
    comptime channels: usize,
    values: []const f32,
    offset: usize,
) @Vector(channels, f32) {
    return @bitCast(values[offset..][0..channels].*);
}

fn storeVector(
    comptime channels: usize,
    values: []f32,
    offset: usize,
    vector: @Vector(channels, f32),
) void {
    values[offset..][0..channels].* = @bitCast(vector);
}

fn gather4(
    comptime channels: usize,
    values: []const f32,
    first_frame: usize,
    channel: usize,
) @Vector(4, f32) {
    return .{
        values[first_frame * channels + channel],
        values[(first_frame + 1) * channels + channel],
        values[(first_frame + 2) * channels + channel],
        values[(first_frame + 3) * channels + channel],
    };
}

fn scatter4(
    comptime channels: usize,
    values: []f32,
    first_frame: usize,
    channel: usize,
    vector: @Vector(4, f32),
) void {
    values[first_frame * channels + channel] = vector[0];
    values[(first_frame + 1) * channels + channel] = vector[1];
    values[(first_frame + 2) * channels + channel] = vector[2];
    values[(first_frame + 3) * channels + channel] = vector[3];
}

fn take(weights: []const f32, cursor: *usize) !f32 {
    if (cursor.* >= weights.len) return error.InvalidA2Weights;
    defer cursor.* += 1;
    return weights[cursor.*];
}

fn nextPowerOfTwo(value: usize) usize {
    var result: usize = 1;
    while (result < value) result *= 2;
    return result;
}
