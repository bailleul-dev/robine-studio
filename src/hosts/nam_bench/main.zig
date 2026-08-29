const assets = @import("audio_assets");
const robine = @import("robine");
const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var source = try robine.audio.wav.decode(allocator, assets.input_wav);
    defer source.deinit(allocator);
    if (source.channels != 1) return error.BenchmarkInputMustBeMono;

    var model = try robine.audio.nam.Model.loadQuality(allocator, assets.default_nam, .full);
    defer model.deinit();
    model.prewarm(64);

    var cabinet_ir = try robine.audio.wav.decode(allocator, assets.default_cabinet_ir);
    defer cabinet_ir.deinit(allocator);
    if (cabinet_ir.channels != 1) return error.BenchmarkCabinetMustBeMono;
    if (cabinet_ir.sample_rate != source.sample_rate) return error.BenchmarkSampleRatesDiffer;
    var cabinet = try robine.audio.convolver.Convolver.init(allocator, cabinet_ir.samples, 64);
    defer cabinet.deinit();

    const started = std.Io.Clock.awake.now(init.io).nanoseconds;
    var checksum: f64 = 0.0;
    for (source.samples) |sample| checksum += cabinet.processSample(model.processSample(sample));
    const elapsed_ns = std.Io.Clock.awake.now(init.io).nanoseconds - started;
    const elapsed_seconds = @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s;
    const audio_seconds = @as(f64, @floatFromInt(source.frames())) / @as(f64, @floatFromInt(source.sample_rate));
    const realtime_factor = audio_seconds / elapsed_seconds;

    std.debug.print(
        "NAM full-quality + cabinet benchmark\n  cabinet: Orange 2x12 V30 / SM57 C (24,000 taps)\n  audio: {d:.3} s\n  render: {d:.3} s\n  speed: {d:.2}x realtime\n  checksum: {d:.9}\n",
        .{ audio_seconds, elapsed_seconds, realtime_factor, checksum },
    );
    if (elapsed_seconds >= audio_seconds) return error.FullNamAndCabinetMissRealtimeDeadline;
}
