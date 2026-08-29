const std = @import("std");

const Complex = struct {
    re: f32 = 0.0,
    im: f32 = 0.0,

    fn multiply(a: Complex, b: Complex) Complex {
        return .{
            .re = a.re * b.re - a.im * b.im,
            .im = a.re * b.im + a.im * b.re,
        };
    }
};

/// Uniformly partitioned overlap-add FIR convolver.
///
/// `processSample` has `partition_size` samples of deterministic latency. All
/// FFT plans, spectra, and streaming buffers are allocated by `init`; the
/// real-time path performs no allocation and preserves every IR tap.
pub const Convolver = struct {
    allocator: std.mem.Allocator,
    partition_size: usize,
    fft_size: usize,
    partition_count: usize,
    impulse_frames: usize,
    impulse_spectra: []Complex,
    input_spectra: []Complex,
    input_block: []f32,
    output_block: []f32,
    overlap: []f32,
    scratch: []Complex,
    accumulator: []Complex,
    input_fill: usize = 0,
    output_read: usize = 0,
    spectrum_write: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        impulse: []const f32,
        partition_size: usize,
    ) !Convolver {
        if (impulse.len == 0) return error.EmptyImpulseResponse;
        if (partition_size == 0 or !std.math.isPowerOfTwo(partition_size)) {
            return error.InvalidConvolutionPartitionSize;
        }
        const fft_size = std.math.mul(usize, partition_size, 2) catch
            return error.ConvolutionSizeOverflow;
        const partition_count = std.math.divCeil(usize, impulse.len, partition_size) catch unreachable;
        const spectrum_count = std.math.mul(usize, partition_count, fft_size) catch
            return error.ConvolutionSizeOverflow;

        const impulse_spectra = try allocator.alloc(Complex, spectrum_count);
        errdefer allocator.free(impulse_spectra);
        const input_spectra = try allocator.alloc(Complex, spectrum_count);
        errdefer allocator.free(input_spectra);
        @memset(input_spectra, .{});
        const input_block = try allocator.alloc(f32, partition_size);
        errdefer allocator.free(input_block);
        @memset(input_block, 0.0);
        const output_block = try allocator.alloc(f32, partition_size);
        errdefer allocator.free(output_block);
        @memset(output_block, 0.0);
        const overlap = try allocator.alloc(f32, partition_size);
        errdefer allocator.free(overlap);
        @memset(overlap, 0.0);
        const scratch = try allocator.alloc(Complex, fft_size);
        errdefer allocator.free(scratch);
        const accumulator = try allocator.alloc(Complex, fft_size);
        errdefer allocator.free(accumulator);

        for (0..partition_count) |partition| {
            @memset(scratch, .{});
            const start = partition * partition_size;
            const end = @min(start + partition_size, impulse.len);
            for (impulse[start..end], 0..) |sample, index| scratch[index].re = sample;
            fft(scratch, false);
            @memcpy(
                impulse_spectra[partition * fft_size ..][0..fft_size],
                scratch,
            );
        }

        return .{
            .allocator = allocator,
            .partition_size = partition_size,
            .fft_size = fft_size,
            .partition_count = partition_count,
            .impulse_frames = impulse.len,
            .impulse_spectra = impulse_spectra,
            .input_spectra = input_spectra,
            .input_block = input_block,
            .output_block = output_block,
            .overlap = overlap,
            .scratch = scratch,
            .accumulator = accumulator,
        };
    }

    pub fn deinit(self: *Convolver) void {
        self.allocator.free(self.impulse_spectra);
        self.allocator.free(self.input_spectra);
        self.allocator.free(self.input_block);
        self.allocator.free(self.output_block);
        self.allocator.free(self.overlap);
        self.allocator.free(self.scratch);
        self.allocator.free(self.accumulator);
        self.* = undefined;
    }

    pub fn reset(self: *Convolver) void {
        @memset(self.input_spectra, .{});
        @memset(self.input_block, 0.0);
        @memset(self.output_block, 0.0);
        @memset(self.overlap, 0.0);
        self.input_fill = 0;
        self.output_read = 0;
        self.spectrum_write = 0;
    }

    pub fn latencyFrames(self: Convolver) usize {
        return self.partition_size;
    }

    pub fn tailFrames(self: Convolver) usize {
        return self.impulse_frames - 1;
    }

    pub fn processSample(self: *Convolver, input: f32) f32 {
        const output = self.output_block[self.output_read];
        self.output_read += 1;
        self.input_block[self.input_fill] = input;
        self.input_fill += 1;

        if (self.input_fill == self.partition_size) {
            std.debug.assert(self.output_read == self.partition_size);
            self.processBlock();
            self.input_fill = 0;
            self.output_read = 0;
        }
        return output;
    }

    fn processBlock(self: *Convolver) void {
        @memset(self.scratch, .{});
        for (self.input_block, 0..) |sample, index| self.scratch[index].re = sample;
        fft(self.scratch, false);
        @memcpy(
            self.input_spectra[self.spectrum_write * self.fft_size ..][0..self.fft_size],
            self.scratch,
        );

        @memset(self.accumulator, .{});
        var input_partition = self.spectrum_write;
        for (0..self.partition_count) |impulse_partition| {
            const impulse_spectrum = self.impulse_spectra[impulse_partition * self.fft_size ..][0..self.fft_size];
            const input_spectrum = self.input_spectra[input_partition * self.fft_size ..][0..self.fft_size];
            for (self.accumulator, impulse_spectrum, input_spectrum) |*sum, impulse_bin, input_bin| {
                const product = Complex.multiply(impulse_bin, input_bin);
                sum.re += product.re;
                sum.im += product.im;
            }
            input_partition = if (input_partition == 0) self.partition_count - 1 else input_partition - 1;
        }

        fft(self.accumulator, true);
        for (0..self.partition_size) |index| {
            self.output_block[index] = self.accumulator[index].re + self.overlap[index];
            self.overlap[index] = self.accumulator[self.partition_size + index].re;
        }
        self.spectrum_write += 1;
        if (self.spectrum_write == self.partition_count) self.spectrum_write = 0;
    }
};

fn fft(values: []Complex, inverse: bool) void {
    std.debug.assert(std.math.isPowerOfTwo(values.len));
    var reversed: usize = 0;
    for (1..values.len) |index| {
        var bit = values.len >> 1;
        while (reversed & bit != 0) : (bit >>= 1) reversed ^= bit;
        reversed ^= bit;
        if (index < reversed) std.mem.swap(Complex, &values[index], &values[reversed]);
    }

    var length: usize = 2;
    while (length <= values.len) : (length <<= 1) {
        const direction: f32 = if (inverse) 1.0 else -1.0;
        const angle = direction * 2.0 * std.math.pi / @as(f32, @floatFromInt(length));
        const step = Complex{ .re = @cos(angle), .im = @sin(angle) };
        const half = length / 2;
        var start: usize = 0;
        while (start < values.len) : (start += length) {
            var rotation = Complex{ .re = 1.0 };
            for (0..half) |offset| {
                const even = values[start + offset];
                const odd = Complex.multiply(values[start + offset + half], rotation);
                values[start + offset] = .{ .re = even.re + odd.re, .im = even.im + odd.im };
                values[start + offset + half] = .{ .re = even.re - odd.re, .im = even.im - odd.im };
                rotation = Complex.multiply(rotation, step);
            }
        }
    }

    if (inverse) {
        const scale = 1.0 / @as(f32, @floatFromInt(values.len));
        for (values) |*value| {
            value.re *= scale;
            value.im *= scale;
        }
    }
}

test "partitioned convolver preserves the complete FIR with fixed latency" {
    const allocator = std.testing.allocator;
    const impulse = [_]f32{ 0.5, -0.25, 0.125, 0.0625, -0.03125, 0.015625 };
    const input = [_]f32{ 1.0, -0.5, 0.25, 0.75, -1.0, 0.0, 0.5 };
    const partition_size = 4;
    var convolver = try Convolver.init(allocator, &impulse, partition_size);
    defer convolver.deinit();

    const direct_frames = input.len + impulse.len - 1;
    var expected = [_]f32{0.0} ** direct_frames;
    for (input, 0..) |sample, input_index| {
        for (impulse, 0..) |tap, tap_index| expected[input_index + tap_index] += sample * tap;
    }

    const rendered_frames = partition_size + direct_frames;
    for (0..rendered_frames) |index| {
        const sample = if (index < input.len) input[index] else 0.0;
        const actual = convolver.processSample(sample);
        const delayed = if (index < partition_size) 0.0 else expected[index - partition_size];
        try std.testing.expectApproxEqAbs(delayed, actual, 0.00001);
    }
}
