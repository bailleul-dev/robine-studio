const contract = @import("audio_contract");
const std = @import("std");

const Pcm = opaque {};
const pcm_playback: c_int = 0;
const pcm_access_rw_interleaved: c_int = 3;
const pcm_format_float_le: c_int = 14;

const Alsa = struct {
    library: std.DynLib,
    pcm_open: *const fn (**Pcm, [*:0]const u8, c_int, c_int) callconv(.c) c_int,
    pcm_close: *const fn (*Pcm) callconv(.c) c_int,
    pcm_set_params: *const fn (*Pcm, c_int, c_int, c_uint, c_uint, c_int, c_uint) callconv(.c) c_int,
    pcm_writei: *const fn (*Pcm, *const anyopaque, c_ulong) callconv(.c) c_long,
    pcm_recover: *const fn (*Pcm, c_int, c_int) callconv(.c) c_int,
    pcm_prepare: *const fn (*Pcm) callconv(.c) c_int,

    fn load() !Alsa {
        var library = std.DynLib.open("libasound.so.2") catch return error.AlsaUnavailable;
        errdefer library.close();
        return .{
            .library = library,
            .pcm_open = library.lookup(@TypeOf(@as(Alsa, undefined).pcm_open), "snd_pcm_open") orelse return error.InvalidAlsaLibrary,
            .pcm_close = library.lookup(@TypeOf(@as(Alsa, undefined).pcm_close), "snd_pcm_close") orelse return error.InvalidAlsaLibrary,
            .pcm_set_params = library.lookup(@TypeOf(@as(Alsa, undefined).pcm_set_params), "snd_pcm_set_params") orelse return error.InvalidAlsaLibrary,
            .pcm_writei = library.lookup(@TypeOf(@as(Alsa, undefined).pcm_writei), "snd_pcm_writei") orelse return error.InvalidAlsaLibrary,
            .pcm_recover = library.lookup(@TypeOf(@as(Alsa, undefined).pcm_recover), "snd_pcm_recover") orelse return error.InvalidAlsaLibrary,
            .pcm_prepare = library.lookup(@TypeOf(@as(Alsa, undefined).pcm_prepare), "snd_pcm_prepare") orelse return error.InvalidAlsaLibrary,
        };
    }
};

pub const NativeAudioDriver = struct {
    pub fn driver(self: *NativeAudioDriver) contract.Driver {
        return .{ .context = self, .vtable = &driver_vtable };
    }

    fn enumerate(
        _: *anyopaque,
        direction: contract.Direction,
        visitor_context: *anyopaque,
        visitor: contract.DeviceVisitor,
    ) !void {
        var alsa = try Alsa.load();
        defer alsa.library.close();
        _ = direction;
        try visitor(visitor_context, .{
            .id = "default",
            .name = "ALSA default (PipeWire/PulseAudio compatible)",
            .input_channels = 2,
            .output_channels = 2,
            .is_default_input = true,
            .is_default_output = true,
        });
    }

    fn open(
        _: *anyopaque,
        request: contract.SessionRequest,
        callback_context: *anyopaque,
        callback: contract.ProcessCallback,
    ) !contract.OpenedSession {
        if (request.direction != .output) return error.AlsaOutputOnlyForNow;
        if (request.output_device_id) |id| {
            if (!std.mem.eql(u8, id, "default")) return error.AudioDeviceNotFound;
        }
        const sample_rate: u32 = @intFromFloat(request.sample_rate orelse 48_000.0);
        const frames = request.preferred_frames orelse 512;
        const channels: u16 = @max(request.output_channels, 1);
        var alsa = try Alsa.load();
        errdefer alsa.library.close();
        var pcm: *Pcm = undefined;
        if (alsa.pcm_open(&pcm, "default", pcm_playback, 0) < 0) return error.CannotOpenDefaultAudioOutput;
        errdefer _ = alsa.pcm_close(pcm);
        if (alsa.pcm_set_params(
            pcm,
            pcm_format_float_le,
            pcm_access_rw_interleaved,
            channels,
            sample_rate,
            1,
            40_000,
        ) < 0) return error.CannotConfigureAudioOutput;

        const allocator = std.heap.page_allocator;
        const session = try allocator.create(AlsaSession);
        errdefer allocator.destroy(session);
        const samples = try allocator.alloc(f32, @as(usize, frames) * channels);
        errdefer allocator.free(samples);
        session.* = .{
            .alsa = alsa,
            .pcm = pcm,
            .callback_context = callback_context,
            .callback = callback,
            .frames = frames,
            .channels = channels,
            .samples = samples,
        };
        return .{
            .session = .{ .context = session, .vtable = &session_vtable },
            .config = .{
                .backend = .alsa,
                .sample_rate = @floatFromInt(sample_rate),
                .nominal_frames = frames,
                .maximum_frames = frames,
                .input_channels = 0,
                .output_channels = channels,
                .input_format = null,
                .output_format = .f32_native,
                .clock_relation = .synchronous,
            },
        };
    }
};

const AlsaSession = struct {
    alsa: Alsa,
    pcm: *Pcm,
    callback_context: *anyopaque,
    callback: contract.ProcessCallback,
    frames: u32,
    channels: u16,
    samples: []f32,
    running: std.atomic.Value(bool) = .init(false),
    thread: ?std.Thread = null,

    fn audioThread(self: *AlsaSession) void {
        var channel_views: [64]contract.OutputChannelView = undefined;
        const channel_count = @min(@as(usize, self.channels), channel_views.len);
        const bytes: [*]u8 = @ptrCast(self.samples.ptr);
        for (channel_views[0..channel_count], 0..) |*view, channel| {
            view.* = .{
                .bytes = bytes + channel * @sizeOf(f32),
                .stride_bytes = @intCast(self.channels * @sizeOf(f32)),
            };
        }
        while (self.running.load(.acquire)) {
            @memset(self.samples, 0);
            self.callback(self.callback_context, .{
                .output = .{
                    .channels = channel_views[0..channel_count],
                    .format = .f32_native,
                },
                .frames = self.frames,
            });
            const written = self.alsa.pcm_writei(self.pcm, self.samples.ptr, self.frames);
            if (written < 0) {
                if (self.alsa.pcm_recover(self.pcm, @intCast(written), 1) < 0) {
                    _ = self.alsa.pcm_prepare(self.pcm);
                }
            }
        }
    }
};

fn startSession(context: *anyopaque) !void {
    const self: *AlsaSession = @ptrCast(@alignCast(context));
    if (self.running.swap(true, .acq_rel)) return;
    self.thread = std.Thread.spawn(.{}, AlsaSession.audioThread, .{self}) catch |err| {
        self.running.store(false, .release);
        return err;
    };
}

fn stopSession(context: *anyopaque) void {
    const self: *AlsaSession = @ptrCast(@alignCast(context));
    self.running.store(false, .release);
    if (self.thread) |thread| thread.join();
    self.thread = null;
}

fn restartSession(context: *anyopaque) void {
    const self: *AlsaSession = @ptrCast(@alignCast(context));
    _ = self.alsa.pcm_prepare(self.pcm);
}

fn closeSession(context: *anyopaque) void {
    const self: *AlsaSession = @ptrCast(@alignCast(context));
    stopSession(self);
    _ = self.alsa.pcm_close(self.pcm);
    self.alsa.library.close();
    std.heap.page_allocator.free(self.samples);
    std.heap.page_allocator.destroy(self);
}

const driver_vtable: contract.Driver.VTable = .{
    .backend = .alsa,
    .enumerate = NativeAudioDriver.enumerate,
    .open = NativeAudioDriver.open,
};

const session_vtable: contract.Session.VTable = .{
    .start = startSession,
    .stop = stopSession,
    .request_restart = restartSession,
    .close = closeSession,
};

test "Linux native driver exposes ALSA backend identity" {
    var native = NativeAudioDriver{};
    try std.testing.expectEqual(contract.Backend.alsa, native.driver().backend());
}
