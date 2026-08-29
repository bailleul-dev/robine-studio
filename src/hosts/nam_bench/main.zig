const assets = @import("audio_assets");
const robine = @import("robine");
const std = @import("std");

const block_frames: usize = 512;

pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa;
    var source = try robine.audio.wav.decode(allocator, assets.input_wav);
    defer source.deinit(allocator);
    if (source.channels != 1) return error.BenchmarkInputMustBeMono;

    var compressor = try robine.audio.nam.Model.loadQuality(allocator, assets.first_pedal_nam, .full);
    defer compressor.deinit();
    try compressor.prepareBlock(block_frames);
    compressor.prewarm(block_frames);
    var tumnus = try robine.audio.nam.Model.loadQuality(allocator, assets.tumnus_deluxe_default_nam, .full);
    defer tumnus.deinit();
    try tumnus.prepareBlock(block_frames);
    tumnus.prewarm(block_frames);
    var big_muff = try robine.audio.nam.Model.loadQuality(allocator, assets.op_amp_big_muff_default_nam, .full);
    defer big_muff.deinit();
    try big_muff.prepareBlock(block_frames);
    big_muff.prewarm(block_frames);
    var king_of_tone = try robine.audio.nam.Model.loadQuality(allocator, assets.king_of_tone_both_nam, .full);
    defer king_of_tone.deinit();
    try king_of_tone.prepareBlock(block_frames);
    king_of_tone.prewarm(block_frames);
    var amplifier = try robine.audio.nam.Model.loadQuality(allocator, assets.default_nam, .full);
    defer amplifier.deinit();
    try amplifier.prepareBlock(block_frames);
    amplifier.prewarm(block_frames);

    var cabinet_ir = try robine.audio.wav.decode(allocator, assets.default_cabinet_ir);
    defer cabinet_ir.deinit(allocator);
    if (cabinet_ir.channels != 1) return error.BenchmarkCabinetMustBeMono;
    if (cabinet_ir.sample_rate != source.sample_rate) return error.BenchmarkSampleRatesDiffer;
    var cabinets = [2]robine.audio.convolver.Convolver{
        try robine.audio.convolver.Convolver.init(allocator, cabinet_ir.samples, 64),
        try robine.audio.convolver.Convolver.init(allocator, cabinet_ir.samples, 64),
    };
    defer for (&cabinets) |*cabinet| cabinet.deinit();

    var reverb_ir = try robine.audio.wav.decode(allocator, assets.skysurfer_hall_medium_ir);
    defer reverb_ir.deinit(allocator);
    if (reverb_ir.channels != 2 or reverb_ir.sample_rate != source.sample_rate) {
        return error.BenchmarkReverbFormatMismatch;
    }
    const reverb_frames = reverb_ir.frames();
    const reverb_left = try allocator.alloc(f32, reverb_frames);
    defer allocator.free(reverb_left);
    const reverb_right = try allocator.alloc(f32, reverb_frames);
    defer allocator.free(reverb_right);
    for (0..reverb_frames) |frame| {
        reverb_left[frame] = reverb_ir.samples[frame * 2];
        reverb_right[frame] = reverb_ir.samples[frame * 2 + 1];
    }
    var reverb = try robine.audio.reverb.HybridStereoConvolver.init(allocator, reverb_left, reverb_right, .{});
    defer reverb.deinit();
    reverb.prewarm();
    for (&cabinets) |*cabinet| {
        for (0..cabinet.partition_size) |_| _ = cabinet.processSample(0.0);
        cabinet.reset();
    }

    const started = std.Io.Clock.awake.now(init.io).nanoseconds;
    var checksum: f64 = 0.0;
    var peak: f32 = 0.0;
    var clipped_samples: usize = 0;
    var deadline_misses: usize = 0;
    var maximum_block_ns: i96 = 0;
    var pedal_block: [block_frames]f32 = undefined;
    var tumnus_block: [block_frames]f32 = undefined;
    var big_muff_block: [block_frames]f32 = undefined;
    var king_of_tone_block: [block_frames]f32 = undefined;
    var amplifier_block: [block_frames]f32 = undefined;
    var offset: usize = 0;
    while (offset < source.samples.len) {
        const block_started = std.Io.Clock.awake.now(init.io).nanoseconds;
        const frames = @min(block_frames, source.samples.len - offset);
        compressor.processBlock(source.samples[offset..][0..frames], pedal_block[0..frames]);
        tumnus.processBlock(pedal_block[0..frames], tumnus_block[0..frames]);
        big_muff.processBlock(tumnus_block[0..frames], big_muff_block[0..frames]);
        king_of_tone.processBlock(big_muff_block[0..frames], king_of_tone_block[0..frames]);
        amplifier.processBlock(king_of_tone_block[0..frames], amplifier_block[0..frames]);
        for (amplifier_block[0..frames]) |sample| {
            const wet = reverb.processSample(sample);
            for (&cabinets, wet) |*cabinet, channel| {
                const cabinet_sample = cabinet.processSample(sample + channel * assets.reverb_return_gain) * assets.monitor_output_gain;
                checksum += cabinet_sample;
                peak = @max(peak, @abs(cabinet_sample));
                clipped_samples += @intFromBool(@abs(cabinet_sample) >= 1.0);
            }
        }
        const block_elapsed_ns = std.Io.Clock.awake.now(init.io).nanoseconds - block_started;
        maximum_block_ns = @max(maximum_block_ns, block_elapsed_ns);
        const block_deadline_ns: i96 = @intFromFloat(
            @as(f64, @floatFromInt(frames)) * @as(f64, std.time.ns_per_s) /
                @as(f64, @floatFromInt(source.sample_rate)),
        );
        deadline_misses += @intFromBool(block_elapsed_ns >= block_deadline_ns);
        offset += frames;
    }
    const elapsed_ns = std.Io.Clock.awake.now(init.io).nanoseconds - started;
    const elapsed_seconds = @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s;
    const audio_seconds = @as(f64, @floatFromInt(source.frames())) / @as(f64, @floatFromInt(source.sample_rate));
    const realtime_factor = audio_seconds / elapsed_seconds;

    std.debug.print(
        "Full-quality production chain benchmark\n  pedals: SP Compressor + Tumnus + Big Muff + King of Tone (full A2)\n  amp: Dumble ODS (full A2)\n  effects loop: Skysurfer Hall 3 Medium (stereo, {d} frames)\n  cabinet: stereo Orange 2x12 V30 / SM57 C (24,000 taps/channel)\n  block: {d} frames\n  audio: {d:.3} s\n  render: {d:.3} s\n  speed: {d:.2}x realtime\n  peak: {d:.3}\n  clipped: {d}/{d}\n  deadline misses: {d}\n  worst block: {d:.3} ms\n  checksum: {d:.9}\n",
        .{
            reverb_frames,
            block_frames,
            audio_seconds,
            elapsed_seconds,
            realtime_factor,
            peak,
            clipped_samples,
            source.frames() * 2,
            deadline_misses,
            @as(f64, @floatFromInt(maximum_block_ns)) / std.time.ns_per_ms,
            checksum,
        },
    );
    if (clipped_samples != 0) return error.FullProductionChainClips;
    if (elapsed_seconds >= audio_seconds) return error.FullPedalChainAmpAndCabinetMissRealtimeDeadline;
}
