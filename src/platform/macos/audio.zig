const contract = @import("audio_contract");
const std = @import("std");

const c = @cImport({
    @cInclude("CoreAudio/CoreAudio.h");
    @cInclude("CoreFoundation/CoreFoundation.h");
});

const system_object: c.AudioObjectID = c.kAudioObjectSystemObject;
const master_element: c.AudioObjectPropertyElement = c.kAudioObjectPropertyElementMain;
const max_native_channels = 64;

pub const CoreAudioDriver = struct {
    pub fn driver(self: *CoreAudioDriver) contract.Driver {
        return .{ .context = self, .vtable = &driver_vtable };
    }

    fn enumerate(
        _: *anyopaque,
        direction: contract.Direction,
        visitor_context: *anyopaque,
        visitor: contract.DeviceVisitor,
    ) !void {
        const allocator = std.heap.page_allocator;
        const devices = try deviceIds(allocator);
        defer allocator.free(devices);

        const default_input = getDefaultDevice(.input) catch c.kAudioObjectUnknown;
        const default_output = getDefaultDevice(.output) catch c.kAudioObjectUnknown;

        for (devices) |device| {
            const input_channels = channelCount(device, c.kAudioObjectPropertyScopeInput) catch 0;
            const output_channels = channelCount(device, c.kAudioObjectPropertyScopeOutput) catch 0;
            const include = switch (direction) {
                .input => input_channels > 0,
                .output => output_channels > 0,
                .duplex => input_channels > 0 and output_channels > 0,
            };
            if (!include) continue;

            var id_storage: [512]u8 = undefined;
            var name_storage: [512]u8 = undefined;
            const id = try stringProperty(
                device,
                c.kAudioDevicePropertyDeviceUID,
                id_storage[0..],
            );
            const name = try stringProperty(
                device,
                c.kAudioObjectPropertyName,
                name_storage[0..],
            );
            try visitor(visitor_context, .{
                .id = id,
                .name = name,
                .input_channels = @intCast(input_channels),
                .output_channels = @intCast(output_channels),
                .is_default_input = device == default_input,
                .is_default_output = device == default_output,
            });
        }
    }

    fn open(
        _: *anyopaque,
        request: contract.SessionRequest,
        callback_context: *anyopaque,
        callback: contract.ProcessCallback,
    ) !contract.OpenedSession {
        const input_device = switch (request.direction) {
            .input, .duplex => if (request.input_device_id) |id|
                try findDevice(id)
            else
                try getDefaultDevice(.input),
            .output => null,
        };
        const output_device = switch (request.direction) {
            .output, .duplex => if (request.output_device_id) |id|
                try findDevice(id)
            else if (request.input_device_id != null and input_device != null)
                input_device.?
            else
                try getDefaultDevice(.output),
            .input => null,
        };

        if (input_device != null and output_device != null and input_device.? != output_device.?) {
            return error.AsynchronousDevicesNotImplemented;
        }
        const device = input_device orelse output_device orelse return error.NoDeviceSelected;
        const input_channels = if (input_device != null)
            try channelCount(device, c.kAudioObjectPropertyScopeInput)
        else
            0;
        const output_channels = if (output_device != null)
            try channelCount(device, c.kAudioObjectPropertyScopeOutput)
        else
            0;
        if (input_device != null and input_channels == 0) return error.DeviceHasNoInput;
        if (output_device != null and output_channels == 0) return error.DeviceHasNoOutput;
        if (input_channels > max_native_channels or output_channels > max_native_channels) {
            return error.TooManyNativeChannels;
        }

        if (request.sample_rate) |rate| try preferSampleRate(device, rate);
        if (request.preferred_frames) |frames| try preferBufferFrames(device, frames);

        const sample_rate = try numberProperty(
            f64,
            device,
            c.kAudioDevicePropertyNominalSampleRate,
            c.kAudioObjectPropertyScopeGlobal,
        );
        const nominal_frames = try numberProperty(
            u32,
            device,
            c.kAudioDevicePropertyBufferFrameSize,
            c.kAudioObjectPropertyScopeGlobal,
        );
        const maximum_frames = variableMaximumFrames(device) catch nominal_frames;
        const input_format = if (input_device != null)
            try directionFormat(device, c.kAudioObjectPropertyScopeInput)
        else
            null;
        const output_format = if (output_device != null)
            try directionFormat(device, c.kAudioObjectPropertyScopeOutput)
        else
            null;

        const session = try std.heap.page_allocator.create(CoreAudioSession);
        errdefer std.heap.page_allocator.destroy(session);
        session.* = .{
            .device = device,
            .direction = request.direction,
            .callback_context = callback_context,
            .callback = callback,
            .input_format = input_format,
            .output_format = output_format,
        };
        try osStatus(c.AudioDeviceCreateIOProcID(
            device,
            CoreAudioSession.ioProc,
            session,
            &session.io_proc_id,
        ));
        errdefer _ = c.AudioDeviceDestroyIOProcID(device, session.io_proc_id);

        return .{
            .session = .{ .context = session, .vtable = &session_vtable },
            .config = .{
                .backend = .core_audio,
                .sample_rate = sample_rate,
                .nominal_frames = nominal_frames,
                .maximum_frames = @max(nominal_frames, maximum_frames),
                .input_channels = @intCast(input_channels),
                .output_channels = @intCast(output_channels),
                .input_format = input_format,
                .output_format = output_format,
                .clock_relation = .synchronous,
            },
        };
    }

    const driver_vtable: contract.Driver.VTable = .{
        .backend = .core_audio,
        .enumerate = enumerate,
        .open = open,
    };
};

const CoreAudioSession = struct {
    device: c.AudioDeviceID,
    direction: contract.Direction,
    callback_context: *anyopaque,
    callback: contract.ProcessCallback,
    input_format: ?contract.SampleFormat,
    output_format: ?contract.SampleFormat,
    io_proc_id: c.AudioDeviceIOProcID = null,
    input_views: [max_native_channels]contract.InputChannelView = undefined,
    output_views: [max_native_channels]contract.OutputChannelView = undefined,
    running: bool = false,

    fn cast(context: *anyopaque) *CoreAudioSession {
        return @ptrCast(@alignCast(context));
    }

    fn start(context: *anyopaque) !void {
        const self = cast(context);
        if (self.running) return;
        try osStatus(c.AudioDeviceStart(self.device, self.io_proc_id));
        self.running = true;
    }

    fn stop(context: *anyopaque) void {
        const self = cast(context);
        if (!self.running) return;
        _ = c.AudioDeviceStop(self.device, self.io_proc_id);
        self.running = false;
    }

    fn requestRestart(context: *anyopaque) void {
        const self = cast(context);
        self.stop();
        self.start() catch {};
    }

    fn close(context: *anyopaque) void {
        const self = cast(context);
        self.stop();
        _ = c.AudioDeviceDestroyIOProcID(self.device, self.io_proc_id);
        std.heap.page_allocator.destroy(self);
    }

    fn ioProc(
        _: c.AudioObjectID,
        now: [*c]const c.AudioTimeStamp,
        input_data: [*c]const c.AudioBufferList,
        input_time: [*c]const c.AudioTimeStamp,
        output_data: [*c]c.AudioBufferList,
        output_time: [*c]const c.AudioTimeStamp,
        client_data: ?*anyopaque,
    ) callconv(.c) c.OSStatus {
        const self: *CoreAudioSession = @ptrCast(@alignCast(client_data.?));

        const frames = self.frameCount(input_data, output_data) orelse return 0;
        var input: ?contract.InputBuffer = null;
        var output: ?contract.OutputBuffer = null;

        if (self.direction != .output and self.input_format != null) {
            const count = self.buildInputViews(input_data, self.input_format.?);
            if (count > 0) input = .{
                .channels = self.input_views[0..count],
                .format = self.input_format.?,
            };
        }
        if (self.direction != .input and self.output_format != null) {
            const count = self.buildOutputViews(output_data, self.output_format.?);
            if (count > 0) output = .{
                .channels = self.output_views[0..count],
                .format = self.output_format.?,
            };
        }

        if (input == null and output == null) return 0;
        self.callback(self.callback_context, .{
            .input = input,
            .output = output,
            .frames = frames,
            .time = streamTime(now, input_time, output_time),
        });
        return 0;
    }

    fn frameCount(
        self: *CoreAudioSession,
        input_data: [*c]const c.AudioBufferList,
        output_data: [*c]const c.AudioBufferList,
    ) ?u32 {
        if (self.direction != .output and self.input_format) |format| {
            if (framesFromList(input_data, format)) |frames| return frames;
        }
        if (self.direction != .input and self.output_format) |format| {
            if (framesFromList(output_data, format)) |frames| return frames;
        }
        return null;
    }

    fn buildInputViews(
        self: *CoreAudioSession,
        list: [*c]const c.AudioBufferList,
        format: contract.SampleFormat,
    ) usize {
        const buffers: [*]const c.AudioBuffer = @ptrCast(&list.*.mBuffers);
        var count: usize = 0;
        for (buffers[0..list.*.mNumberBuffers]) |buffer| {
            const data = buffer.mData orelse continue;
            const base: [*]const u8 = @ptrCast(data);
            const stride: u16 = @intCast(buffer.mNumberChannels * format.container_bytes);
            var channel: u32 = 0;
            while (channel < buffer.mNumberChannels and count < max_native_channels) : (channel += 1) {
                self.input_views[count] = .{
                    .bytes = base + channel * format.container_bytes,
                    .stride_bytes = stride,
                };
                count += 1;
            }
        }
        return count;
    }

    fn buildOutputViews(
        self: *CoreAudioSession,
        list: [*c]c.AudioBufferList,
        format: contract.SampleFormat,
    ) usize {
        const buffers: [*]c.AudioBuffer = @ptrCast(&list.*.mBuffers);
        var count: usize = 0;
        for (buffers[0..list.*.mNumberBuffers]) |buffer| {
            const data = buffer.mData orelse continue;
            const base: [*]u8 = @ptrCast(data);
            const stride: u16 = @intCast(buffer.mNumberChannels * format.container_bytes);
            var channel: u32 = 0;
            while (channel < buffer.mNumberChannels and count < max_native_channels) : (channel += 1) {
                self.output_views[count] = .{
                    .bytes = base + channel * format.container_bytes,
                    .stride_bytes = stride,
                };
                count += 1;
            }
        }
        return count;
    }
};

const session_vtable: contract.Session.VTable = .{
    .start = CoreAudioSession.start,
    .stop = CoreAudioSession.stop,
    .request_restart = CoreAudioSession.requestRestart,
    .close = CoreAudioSession.close,
};

fn address(
    selector: c.AudioObjectPropertySelector,
    scope: c.AudioObjectPropertyScope,
) c.AudioObjectPropertyAddress {
    return .{
        .mSelector = selector,
        .mScope = scope,
        .mElement = master_element,
    };
}

fn osStatus(status: c.OSStatus) !void {
    if (status != 0) return error.CoreAudioFailure;
}

fn numberProperty(
    comptime T: type,
    object: c.AudioObjectID,
    selector: c.AudioObjectPropertySelector,
    scope: c.AudioObjectPropertyScope,
) !T {
    var value: T = undefined;
    var size: u32 = @sizeOf(T);
    var property = address(selector, scope);
    try osStatus(c.AudioObjectGetPropertyData(object, &property, 0, null, &size, &value));
    return value;
}

fn setNumberProperty(
    comptime T: type,
    object: c.AudioObjectID,
    selector: c.AudioObjectPropertySelector,
    value: T,
) !void {
    var property = address(selector, c.kAudioObjectPropertyScopeGlobal);
    var settable: c.Boolean = 0;
    try osStatus(c.AudioObjectIsPropertySettable(object, &property, &settable));
    if (settable == 0) return error.PropertyNotSettable;
    var mutable_value = value;
    try osStatus(c.AudioObjectSetPropertyData(
        object,
        &property,
        0,
        null,
        @sizeOf(T),
        &mutable_value,
    ));
}

fn preferSampleRate(device: c.AudioDeviceID, requested: f64) !void {
    if (!std.math.isFinite(requested) or requested <= 0.0) return error.InvalidSampleRate;
    const actual = try numberProperty(
        f64,
        device,
        c.kAudioDevicePropertyNominalSampleRate,
        c.kAudioObjectPropertyScopeGlobal,
    );
    if (@abs(actual - requested) < 0.5) return;
    try setNumberProperty(f64, device, c.kAudioDevicePropertyNominalSampleRate, requested);
}

fn preferBufferFrames(device: c.AudioDeviceID, requested: u32) !void {
    if (requested == 0) return error.InvalidBufferFrameCount;
    const actual = try numberProperty(
        u32,
        device,
        c.kAudioDevicePropertyBufferFrameSize,
        c.kAudioObjectPropertyScopeGlobal,
    );
    if (actual == requested) return;
    try setNumberProperty(u32, device, c.kAudioDevicePropertyBufferFrameSize, requested);
}

fn variableMaximumFrames(device: c.AudioDeviceID) !u32 {
    return numberProperty(
        u32,
        device,
        c.kAudioDevicePropertyUsesVariableBufferFrameSizes,
        c.kAudioObjectPropertyScopeGlobal,
    );
}

fn deviceIds(allocator: std.mem.Allocator) ![]c.AudioDeviceID {
    var property = address(
        c.kAudioHardwarePropertyDevices,
        c.kAudioObjectPropertyScopeGlobal,
    );
    var bytes: u32 = 0;
    try osStatus(c.AudioObjectGetPropertyDataSize(system_object, &property, 0, null, &bytes));
    const count = bytes / @sizeOf(c.AudioDeviceID);
    const devices = try allocator.alloc(c.AudioDeviceID, count);
    errdefer allocator.free(devices);
    try osStatus(c.AudioObjectGetPropertyData(system_object, &property, 0, null, &bytes, devices.ptr));
    return devices;
}

fn getDefaultDevice(direction: contract.Direction) !c.AudioDeviceID {
    const selector: c.AudioObjectPropertySelector = switch (direction) {
        .input => c.kAudioHardwarePropertyDefaultInputDevice,
        .output => c.kAudioHardwarePropertyDefaultOutputDevice,
        .duplex => return error.InvalidDefaultDeviceDirection,
    };
    const device = try numberProperty(
        c.AudioDeviceID,
        system_object,
        selector,
        c.kAudioObjectPropertyScopeGlobal,
    );
    if (device == c.kAudioObjectUnknown) return error.DefaultDeviceUnavailable;
    return device;
}

fn findDevice(uid: []const u8) !c.AudioDeviceID {
    const allocator = std.heap.page_allocator;
    const devices = try deviceIds(allocator);
    defer allocator.free(devices);
    for (devices) |device| {
        var storage: [512]u8 = undefined;
        const candidate = stringProperty(
            device,
            c.kAudioDevicePropertyDeviceUID,
            storage[0..],
        ) catch continue;
        if (std.mem.eql(u8, uid, candidate)) return device;
    }
    return error.DeviceNotFound;
}

fn stringProperty(
    object: c.AudioObjectID,
    selector: c.AudioObjectPropertySelector,
    storage: []u8,
) ![]const u8 {
    if (storage.len == 0) return error.EmptyStringStorage;
    var property = address(selector, c.kAudioObjectPropertyScopeGlobal);
    var value: c.CFStringRef = null;
    var size: u32 = @sizeOf(c.CFStringRef);
    try osStatus(c.AudioObjectGetPropertyData(object, &property, 0, null, &size, &value));
    const string = value orelse return error.MissingStringProperty;
    defer c.CFRelease(string);
    if (c.CFStringGetCString(
        string,
        storage.ptr,
        @intCast(storage.len),
        c.kCFStringEncodingUTF8,
    ) == 0) return error.StringPropertyTooLong;
    return std.mem.sliceTo(storage, 0);
}

fn channelCount(device: c.AudioDeviceID, scope: c.AudioObjectPropertyScope) !u32 {
    var property = address(c.kAudioDevicePropertyStreamConfiguration, scope);
    var size: u32 = 0;
    try osStatus(c.AudioObjectGetPropertyDataSize(device, &property, 0, null, &size));
    const storage = try std.heap.page_allocator.alignedAlloc(u8, .of(c.AudioBufferList), size);
    defer std.heap.page_allocator.free(storage);
    try osStatus(c.AudioObjectGetPropertyData(device, &property, 0, null, &size, storage.ptr));
    const list: *const c.AudioBufferList = @ptrCast(storage.ptr);
    const buffers: [*]const c.AudioBuffer = @ptrCast(&list.mBuffers);
    var channels: u32 = 0;
    for (buffers[0..list.mNumberBuffers]) |buffer| channels += buffer.mNumberChannels;
    return channels;
}

fn directionFormat(
    device: c.AudioDeviceID,
    scope: c.AudioObjectPropertyScope,
) !contract.SampleFormat {
    var property = address(c.kAudioDevicePropertyStreams, scope);
    var size: u32 = 0;
    try osStatus(c.AudioObjectGetPropertyDataSize(device, &property, 0, null, &size));
    if (size == 0) return error.NoAudioStreams;
    const stream_count = size / @sizeOf(c.AudioStreamID);
    const streams = try std.heap.page_allocator.alloc(c.AudioStreamID, stream_count);
    defer std.heap.page_allocator.free(streams);
    try osStatus(c.AudioObjectGetPropertyData(device, &property, 0, null, &size, streams.ptr));

    var common: ?contract.SampleFormat = null;
    for (streams) |stream| {
        var format_property = address(
            c.kAudioStreamPropertyVirtualFormat,
            c.kAudioObjectPropertyScopeGlobal,
        );
        var asbd: c.AudioStreamBasicDescription = undefined;
        var asbd_size: u32 = @sizeOf(c.AudioStreamBasicDescription);
        try osStatus(c.AudioObjectGetPropertyData(
            stream,
            &format_property,
            0,
            null,
            &asbd_size,
            &asbd,
        ));
        const format = try formatFromAsbd(asbd);
        if (common) |existing| {
            if (!std.meta.eql(existing, format)) return error.HeterogeneousStreamFormats;
        } else {
            common = format;
        }
    }
    return common orelse error.NoAudioStreams;
}

fn formatFromAsbd(asbd: c.AudioStreamBasicDescription) !contract.SampleFormat {
    if (asbd.mFormatID != c.kAudioFormatLinearPCM) return error.UnsupportedNativeFormat;
    const is_float = asbd.mFormatFlags & c.kAudioFormatFlagIsFloat != 0;
    const is_signed = asbd.mFormatFlags & c.kAudioFormatFlagIsSignedInteger != 0;
    if (!is_float and !is_signed) return error.UnsupportedNativeFormat;
    const bytes_per_sample = asbd.mBitsPerChannel / 8;
    const format: contract.SampleFormat = .{
        .kind = if (is_float) .floating_point else .signed_integer,
        .container_bytes = @intCast(bytes_per_sample),
        .valid_bits = @intCast(asbd.mBitsPerChannel),
        .byte_order = if (asbd.mFormatFlags & c.kAudioFormatFlagIsBigEndian != 0)
            .big
        else
            .little,
        .aligned_high = asbd.mFormatFlags & c.kAudioFormatFlagIsAlignedHigh != 0,
    };
    try format.validate();
    return format;
}

fn framesFromList(
    list: anytype,
    format: contract.SampleFormat,
) ?u32 {
    const buffers: [*]const c.AudioBuffer = @ptrCast(&list.*.mBuffers);
    for (buffers[0..list.*.mNumberBuffers]) |buffer| {
        if (buffer.mData == null or buffer.mNumberChannels == 0) continue;
        const bytes_per_frame = buffer.mNumberChannels * format.container_bytes;
        if (bytes_per_frame == 0) continue;
        return buffer.mDataByteSize / bytes_per_frame;
    }
    return null;
}

fn streamTime(
    now: [*c]const c.AudioTimeStamp,
    input_time: [*c]const c.AudioTimeStamp,
    output_time: [*c]const c.AudioTimeStamp,
) contract.StreamTime {
    var result: contract.StreamTime = .{};
    if (now != null and now.*.mFlags & c.kAudioTimeStampSampleTimeValid != 0) {
        result.valid |= contract.TimeValidity.sample_position;
        result.sample_position = @intFromFloat(now.*.mSampleTime);
    }
    if (now != null and now.*.mFlags & c.kAudioTimeStampHostTimeValid != 0) {
        result.valid |= contract.TimeValidity.monotonic_ns;
        result.monotonic_ns = c.AudioConvertHostTimeToNanos(now.*.mHostTime);
    }
    if (input_time != null and input_time.*.mFlags & c.kAudioTimeStampHostTimeValid != 0) {
        result.valid |= contract.TimeValidity.input_acquisition_ns;
        result.input_acquisition_ns = c.AudioConvertHostTimeToNanos(input_time.*.mHostTime);
    }
    if (output_time != null and output_time.*.mFlags & c.kAudioTimeStampHostTimeValid != 0) {
        result.valid |= contract.TimeValidity.output_presentation_ns;
        result.output_presentation_ns = c.AudioConvertHostTimeToNanos(output_time.*.mHostTime);
    }
    return result;
}

test "Core Audio driver exposes the common backend identity" {
    var core_audio = CoreAudioDriver{};
    try std.testing.expectEqual(contract.Backend.core_audio, core_audio.driver().backend());
}
