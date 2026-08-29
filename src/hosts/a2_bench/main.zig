const assets = @import("audio_assets");
const robine = @import("robine");
const std = @import("std");

const iterations: usize = 3;
const block_sizes = [_]usize{ 64, 128, 256, 512 };

fn lessThan(_: void, lhs: i96, rhs: i96) bool {
    return lhs < rhs;
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var source = try robine.audio.wav.decode(allocator, assets.input_wav);
    defer source.deinit(allocator);
    if (source.channels != 1) return error.BenchmarkInputMustBeMono;

    std.debug.print("Robine specialized A2 kernel benchmark ({d} Hz, {d} iterations)\n", .{
        source.sample_rate,
        iterations,
    });
    try benchmarkQuality(init, source.samples, source.sample_rate, .lightweight, "A2-Lite / 3 channels");
    try benchmarkQuality(init, source.samples, source.sample_rate, .full, "A2-Full / 8 channels");
}

fn benchmarkQuality(
    init: std.process.Init,
    input: []const f32,
    sample_rate: u32,
    quality: robine.audio.nam.Model.Quality,
    label: []const u8,
) !void {
    const allocator = init.gpa;
    std.debug.print("\n{s}\n", .{label});
    std.debug.print("  block      p50      p99      max     realtime\n", .{});
    for (block_sizes) |block_frames| {
        var model = try robine.audio.nam.Model.loadQuality(allocator, assets.default_nam, quality);
        defer model.deinit();
        try model.prepareBlock(block_frames);
        model.prewarm(block_frames);
        var output: [block_sizes[block_sizes.len - 1]]f32 = undefined;
        const blocks_per_iteration = (input.len + block_frames - 1) / block_frames;
        const timings = try allocator.alloc(i96, blocks_per_iteration * iterations);
        defer allocator.free(timings);
        var timing_index: usize = 0;
        var checksum: f64 = 0.0;
        for (0..iterations) |_| {
            var offset: usize = 0;
            while (offset < input.len) {
                const frames = @min(block_frames, input.len - offset);
                const started = std.Io.Clock.awake.now(init.io).nanoseconds;
                model.processBlock(input[offset..][0..frames], output[0..frames]);
                timings[timing_index] = std.Io.Clock.awake.now(init.io).nanoseconds - started;
                timing_index += 1;
                checksum += output[frames - 1];
                offset += frames;
            }
        }
        std.mem.sort(i96, timings, {}, lessThan);
        const p50 = timings[timings.len / 2];
        const p99 = timings[(timings.len * 99) / 100];
        const maximum = timings[timings.len - 1];
        const deadline_ns = @as(f64, @floatFromInt(block_frames)) * std.time.ns_per_s /
            @as(f64, @floatFromInt(sample_rate));
        std.debug.print(
            "  {d: >5}  {d: >7.2}  {d: >7.2}  {d: >7.2} us  {d: >7.2}x  [{d:.6}]\n",
            .{
                block_frames,
                nanosecondsToMicroseconds(p50),
                nanosecondsToMicroseconds(p99),
                nanosecondsToMicroseconds(maximum),
                deadline_ns / @as(f64, @floatFromInt(p50)),
                checksum,
            },
        );
    }
}

fn nanosecondsToMicroseconds(value: i96) f64 {
    return @as(f64, @floatFromInt(value)) / std.time.ns_per_us;
}
