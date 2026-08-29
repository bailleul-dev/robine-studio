const convolution = @import("convolver.zig");
const std = @import("std");

const Complex = convolution.Complex;

/// Stereo, uniformly partitioned convolution with one shared input history.
/// This halves the forward-FFT and input-history cost versus two independent
/// convolvers while preserving both channels of a true-stereo IR.
pub const StereoConvolver = struct {
    allocator: std.mem.Allocator,
    partition_size: usize,
    fft_size: usize,
    partition_count: usize,
    impulse_frames: usize,
    left_impulse_spectra: []Complex,
    right_impulse_spectra: []Complex,
    input_spectra: []Complex,
    input_block: []f32,
    left_output: []f32,
    right_output: []f32,
    left_overlap: []f32,
    right_overlap: []f32,
    scratch: []Complex,
    left_accumulator: []Complex,
    right_accumulator: []Complex,
    input_fill: usize = 0,
    output_read: usize = 0,
    spectrum_write: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        left_impulse: []const f32,
        right_impulse: []const f32,
        partition_size: usize,
    ) !StereoConvolver {
        if (left_impulse.len == 0 or left_impulse.len != right_impulse.len) {
            return error.InvalidStereoImpulseResponse;
        }
        if (partition_size == 0 or !std.math.isPowerOfTwo(partition_size)) {
            return error.InvalidConvolutionPartitionSize;
        }
        const fft_size = try std.math.mul(usize, partition_size, 2);
        const partition_count = std.math.divCeil(usize, left_impulse.len, partition_size) catch unreachable;
        const spectrum_count = try std.math.mul(usize, partition_count, fft_size);

        const left_spectra = try allocator.alloc(Complex, spectrum_count);
        errdefer allocator.free(left_spectra);
        const right_spectra = try allocator.alloc(Complex, spectrum_count);
        errdefer allocator.free(right_spectra);
        const input_spectra = try allocator.alloc(Complex, spectrum_count);
        errdefer allocator.free(input_spectra);
        @memset(input_spectra, .{});
        const input_block = try allocator.alloc(f32, partition_size);
        errdefer allocator.free(input_block);
        @memset(input_block, 0.0);
        const left_output = try allocator.alloc(f32, partition_size);
        errdefer allocator.free(left_output);
        @memset(left_output, 0.0);
        const right_output = try allocator.alloc(f32, partition_size);
        errdefer allocator.free(right_output);
        @memset(right_output, 0.0);
        const left_overlap = try allocator.alloc(f32, partition_size);
        errdefer allocator.free(left_overlap);
        @memset(left_overlap, 0.0);
        const right_overlap = try allocator.alloc(f32, partition_size);
        errdefer allocator.free(right_overlap);
        @memset(right_overlap, 0.0);
        const scratch = try allocator.alloc(Complex, fft_size);
        errdefer allocator.free(scratch);
        const left_accumulator = try allocator.alloc(Complex, fft_size);
        errdefer allocator.free(left_accumulator);
        const right_accumulator = try allocator.alloc(Complex, fft_size);
        errdefer allocator.free(right_accumulator);

        for (0..partition_count) |partition| {
            const start = partition * partition_size;
            const end = @min(start + partition_size, left_impulse.len);
            @memset(scratch, .{});
            for (left_impulse[start..end], 0..) |sample, index| scratch[index].re = sample;
            convolution.fft(scratch, false);
            @memcpy(left_spectra[partition * fft_size ..][0..fft_size], scratch);
            @memset(scratch, .{});
            for (right_impulse[start..end], 0..) |sample, index| scratch[index].re = sample;
            convolution.fft(scratch, false);
            @memcpy(right_spectra[partition * fft_size ..][0..fft_size], scratch);
        }

        return .{
            .allocator = allocator,
            .partition_size = partition_size,
            .fft_size = fft_size,
            .partition_count = partition_count,
            .impulse_frames = left_impulse.len,
            .left_impulse_spectra = left_spectra,
            .right_impulse_spectra = right_spectra,
            .input_spectra = input_spectra,
            .input_block = input_block,
            .left_output = left_output,
            .right_output = right_output,
            .left_overlap = left_overlap,
            .right_overlap = right_overlap,
            .scratch = scratch,
            .left_accumulator = left_accumulator,
            .right_accumulator = right_accumulator,
        };
    }

    pub fn deinit(self: *StereoConvolver) void {
        self.allocator.free(self.left_impulse_spectra);
        self.allocator.free(self.right_impulse_spectra);
        self.allocator.free(self.input_spectra);
        self.allocator.free(self.input_block);
        self.allocator.free(self.left_output);
        self.allocator.free(self.right_output);
        self.allocator.free(self.left_overlap);
        self.allocator.free(self.right_overlap);
        self.allocator.free(self.scratch);
        self.allocator.free(self.left_accumulator);
        self.allocator.free(self.right_accumulator);
        self.* = undefined;
    }

    pub fn reset(self: *StereoConvolver) void {
        @memset(self.input_spectra, .{});
        @memset(self.input_block, 0.0);
        @memset(self.left_output, 0.0);
        @memset(self.right_output, 0.0);
        @memset(self.left_overlap, 0.0);
        @memset(self.right_overlap, 0.0);
        self.input_fill = 0;
        self.output_read = 0;
        self.spectrum_write = 0;
    }

    pub fn processSample(self: *StereoConvolver, input: f32) [2]f32 {
        const output = [2]f32{ self.left_output[self.output_read], self.right_output[self.output_read] };
        self.output_read += 1;
        self.input_block[self.input_fill] = input;
        self.input_fill += 1;
        if (self.input_fill == self.partition_size) {
            self.processBlock();
            self.input_fill = 0;
            self.output_read = 0;
        }
        return output;
    }

    fn processBlock(self: *StereoConvolver) void {
        @memset(self.scratch, .{});
        for (self.input_block, 0..) |sample, index| self.scratch[index].re = sample;
        convolution.fft(self.scratch, false);
        @memcpy(self.input_spectra[self.spectrum_write * self.fft_size ..][0..self.fft_size], self.scratch);
        @memset(self.left_accumulator, .{});
        @memset(self.right_accumulator, .{});

        var input_partition = self.spectrum_write;
        for (0..self.partition_count) |impulse_partition| {
            const input_spectrum = self.input_spectra[input_partition * self.fft_size ..][0..self.fft_size];
            const left_spectrum = self.left_impulse_spectra[impulse_partition * self.fft_size ..][0..self.fft_size];
            const right_spectrum = self.right_impulse_spectra[impulse_partition * self.fft_size ..][0..self.fft_size];
            for (self.left_accumulator, self.right_accumulator, left_spectrum, right_spectrum, input_spectrum) |*left_sum, *right_sum, left_bin, right_bin, input_bin| {
                const left_product = Complex.multiply(left_bin, input_bin);
                const right_product = Complex.multiply(right_bin, input_bin);
                left_sum.re += left_product.re;
                left_sum.im += left_product.im;
                right_sum.re += right_product.re;
                right_sum.im += right_product.im;
            }
            input_partition = if (input_partition == 0) self.partition_count - 1 else input_partition - 1;
        }

        convolution.fft(self.left_accumulator, true);
        convolution.fft(self.right_accumulator, true);
        for (0..self.partition_size) |index| {
            self.left_output[index] = self.left_accumulator[index].re + self.left_overlap[index];
            self.right_output[index] = self.right_accumulator[index].re + self.right_overlap[index];
            self.left_overlap[index] = self.left_accumulator[self.partition_size + index].re;
            self.right_overlap[index] = self.right_accumulator[self.partition_size + index].re;
        }
        self.spectrum_write = (self.spectrum_write + 1) % self.partition_count;
    }
};

pub const DelayLine = struct {
    allocator: std.mem.Allocator,
    samples: []f32,
    index: usize = 0,

    pub fn init(allocator: std.mem.Allocator, frames: usize) !DelayLine {
        const samples = try allocator.alloc(f32, frames);
        @memset(samples, 0.0);
        return .{ .allocator = allocator, .samples = samples };
    }

    pub fn deinit(self: *DelayLine) void {
        self.allocator.free(self.samples);
        self.* = undefined;
    }

    pub fn processSample(self: *DelayLine, input: f32) f32 {
        if (self.samples.len == 0) return input;
        const output = self.samples[self.index];
        self.samples[self.index] = input;
        self.index = (self.index + 1) % self.samples.len;
        return output;
    }

    pub fn reset(self: *DelayLine) void {
        @memset(self.samples, 0.0);
        self.index = 0;
    }
};

pub const HybridConfig = struct {
    early_frames: usize = 2048,
    early_partition: usize = 64,
    late_partition: usize = 512,
};

/// Non-uniform stereo convolution: a low-latency early response and a large
/// partition tail. The stages are aligned sample-exactly at the early-stage
/// latency, so no IR frames are omitted or moved.
pub const HybridStereoConvolver = struct {
    early: StereoConvolver,
    late: StereoConvolver,
    left_late_delay: DelayLine,
    right_late_delay: DelayLine,
    impulse_frames: usize,

    pub fn init(
        allocator: std.mem.Allocator,
        left_impulse: []const f32,
        right_impulse: []const f32,
        config: HybridConfig,
    ) !HybridStereoConvolver {
        if (left_impulse.len != right_impulse.len or config.early_frames == 0 or
            config.early_frames >= left_impulse.len or
            config.early_partition + config.early_frames < config.late_partition)
        {
            return error.InvalidHybridConvolutionConfiguration;
        }
        var early = try StereoConvolver.init(
            allocator,
            left_impulse[0..config.early_frames],
            right_impulse[0..config.early_frames],
            config.early_partition,
        );
        errdefer early.deinit();
        var late = try StereoConvolver.init(
            allocator,
            left_impulse[config.early_frames..],
            right_impulse[config.early_frames..],
            config.late_partition,
        );
        errdefer late.deinit();
        const alignment_delay = config.early_partition + config.early_frames - config.late_partition;
        var left_delay = try DelayLine.init(allocator, alignment_delay);
        errdefer left_delay.deinit();
        var right_delay = try DelayLine.init(allocator, alignment_delay);
        errdefer right_delay.deinit();
        return .{
            .early = early,
            .late = late,
            .left_late_delay = left_delay,
            .right_late_delay = right_delay,
            .impulse_frames = left_impulse.len,
        };
    }

    pub fn deinit(self: *HybridStereoConvolver) void {
        self.right_late_delay.deinit();
        self.left_late_delay.deinit();
        self.late.deinit();
        self.early.deinit();
        self.* = undefined;
    }

    pub fn processSample(self: *HybridStereoConvolver, input: f32) [2]f32 {
        const early = self.early.processSample(input);
        const late = self.late.processSample(input);
        return .{
            early[0] + self.left_late_delay.processSample(late[0]),
            early[1] + self.right_late_delay.processSample(late[1]),
        };
    }

    pub fn reset(self: *HybridStereoConvolver) void {
        self.early.reset();
        self.late.reset();
        self.left_late_delay.reset();
        self.right_late_delay.reset();
    }

    pub fn prewarm(self: *HybridStereoConvolver) void {
        const frames = @max(self.early.partition_size, self.late.partition_size);
        for (0..frames) |_| _ = self.processSample(0.0);
        self.reset();
    }

    pub fn latencyFrames(self: HybridStereoConvolver) usize {
        return self.early.partition_size;
    }

    pub fn tailFrames(self: HybridStereoConvolver) usize {
        return self.impulse_frames - 1;
    }
};

test "hybrid stereo convolution preserves and aligns the complete response" {
    const allocator = std.testing.allocator;
    const left = [_]f32{ 0.5, 0.25, -0.1, 0.05, 0.4, -0.2, 0.1, 0.03, -0.01, 0.02, 0.04, -0.05 };
    const right = [_]f32{ -0.2, 0.1, 0.3, 0.05, -0.1, 0.2, 0.06, -0.02, 0.08, 0.01, -0.03, 0.07 };
    const input = [_]f32{ 1.0, -0.5, 0.25, 0.75, -1.0 };
    var convolver = try HybridStereoConvolver.init(allocator, &left, &right, .{
        .early_frames = 8,
        .early_partition = 4,
        .late_partition = 8,
    });
    defer convolver.deinit();

    const direct_frames = input.len + left.len - 1;
    var expected_left = [_]f32{0.0} ** direct_frames;
    var expected_right = [_]f32{0.0} ** direct_frames;
    for (input, 0..) |sample, input_index| {
        for (left, right, 0..) |left_tap, right_tap, tap_index| {
            expected_left[input_index + tap_index] += sample * left_tap;
            expected_right[input_index + tap_index] += sample * right_tap;
        }
    }
    const rendered_frames = direct_frames + convolver.latencyFrames();
    for (0..rendered_frames) |index| {
        const actual = convolver.processSample(if (index < input.len) input[index] else 0.0);
        const left_expected = if (index < convolver.latencyFrames()) 0.0 else expected_left[index - convolver.latencyFrames()];
        const right_expected = if (index < convolver.latencyFrames()) 0.0 else expected_right[index - convolver.latencyFrames()];
        try std.testing.expectApproxEqAbs(left_expected, actual[0], 0.00002);
        try std.testing.expectApproxEqAbs(right_expected, actual[1], 0.00002);
    }
}
