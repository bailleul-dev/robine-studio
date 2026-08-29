const std = @import("std");

pub const Audio = struct {
    sample_rate: u32,
    channels: u16,
    samples: []f32,

    pub fn deinit(self: *Audio, allocator: std.mem.Allocator) void {
        allocator.free(self.samples);
        self.* = undefined;
    }

    pub fn frames(self: Audio) usize {
        return self.samples.len / self.channels;
    }
};

const Format = struct {
    encoding: u16,
    channels: u16,
    sample_rate: u32,
    block_align: u16,
    bits_per_sample: u16,
};

/// Decode a RIFF/WAVE PCM fixture into normalized interleaved f32 samples.
/// The first audio milestone deliberately accepts only integer PCM; unsupported
/// assets fail during startup rather than entering a fallback conversion path.
pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) !Audio {
    if (bytes.len < 12 or
        !std.mem.eql(u8, bytes[0..4], "RIFF") or
        !std.mem.eql(u8, bytes[8..12], "WAVE"))
    {
        return error.InvalidWaveFile;
    }

    var format: ?Format = null;
    var audio_bytes: ?[]const u8 = null;
    var cursor: usize = 12;
    while (cursor + 8 <= bytes.len) {
        const chunk_id = bytes[cursor..][0..4];
        const chunk_size: usize = readU32(bytes[cursor + 4 ..][0..4]);
        const data_start = cursor + 8;
        const data_end = std.math.add(usize, data_start, chunk_size) catch return error.InvalidWaveFile;
        if (data_end > bytes.len) return error.InvalidWaveFile;
        const chunk = bytes[data_start..data_end];

        if (std.mem.eql(u8, chunk_id, "fmt ")) {
            if (chunk.len < 16) return error.InvalidWaveFormat;
            format = .{
                .encoding = readU16(chunk[0..2]),
                .channels = readU16(chunk[2..4]),
                .sample_rate = readU32(chunk[4..8]),
                .block_align = readU16(chunk[12..14]),
                .bits_per_sample = readU16(chunk[14..16]),
            };
        } else if (std.mem.eql(u8, chunk_id, "data")) {
            audio_bytes = chunk;
        }

        cursor = data_end + (chunk_size & 1);
    }

    const fmt = format orelse return error.MissingWaveFormat;
    const data = audio_bytes orelse return error.MissingWaveData;
    if (fmt.encoding != 1) return error.UnsupportedWaveEncoding;
    if (fmt.channels == 0 or fmt.sample_rate == 0) return error.InvalidWaveFormat;
    if (fmt.bits_per_sample != 16 and fmt.bits_per_sample != 24 and fmt.bits_per_sample != 32) {
        return error.UnsupportedWaveBitDepth;
    }

    const bytes_per_sample: usize = fmt.bits_per_sample / 8;
    const expected_align = std.math.mul(usize, fmt.channels, bytes_per_sample) catch
        return error.InvalidWaveFormat;
    if (fmt.block_align != expected_align or data.len % expected_align != 0) {
        return error.InvalidWaveDataAlignment;
    }

    const sample_count = data.len / bytes_per_sample;
    const samples = try allocator.alloc(f32, sample_count);
    errdefer allocator.free(samples);
    for (samples, 0..) |*sample, index| {
        const source = data[index * bytes_per_sample ..][0..bytes_per_sample];
        sample.* = switch (fmt.bits_per_sample) {
            16 => @as(f32, @floatFromInt(@as(i16, @bitCast(readU16(source[0..2]))))) / 32_768.0,
            24 => decodePcm24(source[0..3]),
            32 => @as(f32, @floatFromInt(@as(i32, @bitCast(readU32(source[0..4]))))) / 2_147_483_648.0,
            else => unreachable,
        };
    }

    return .{
        .sample_rate = fmt.sample_rate,
        .channels = fmt.channels,
        .samples = samples,
    };
}

fn decodePcm24(bytes: []const u8) f32 {
    var raw: u32 = @as(u32, bytes[0]) |
        (@as(u32, bytes[1]) << 8) |
        (@as(u32, bytes[2]) << 16);
    if (raw & 0x0080_0000 != 0) raw |= 0xff00_0000;
    const signed: i32 = @bitCast(raw);
    return @as(f32, @floatFromInt(signed)) / 8_388_608.0;
}

fn readU16(bytes: *const [2]u8) u16 {
    return std.mem.readInt(u16, bytes, .little);
}

fn readU32(bytes: *const [4]u8) u32 {
    return std.mem.readInt(u32, bytes, .little);
}

test "PCM24 conversion preserves signed full scale and zero" {
    try std.testing.expectApproxEqAbs(@as(f32, -1.0), decodePcm24(&.{ 0x00, 0x00, 0x80 }), 0.000001);
    try std.testing.expectEqual(@as(f32, 0.0), decodePcm24(&.{ 0x00, 0x00, 0x00 }));
    try std.testing.expectApproxEqAbs(@as(f32, 1.0), decodePcm24(&.{ 0xff, 0xff, 0x7f }), 0.000001);
}
