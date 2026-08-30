const contract = @import("audio_contract");
const std = @import("std");

const ca = struct {
    pub const OSStatus = i32;
    pub const Boolean = u8;
    pub const AudioObjectID = u32;
    pub const AudioDeviceID = AudioObjectID;
    pub const AudioStreamID = AudioObjectID;
    pub const AudioObjectPropertySelector = u32;
    pub const AudioObjectPropertyScope = u32;
    pub const AudioObjectPropertyElement = u32;
    pub const CFStringRef = ?*const anyopaque;

    pub const AudioObjectPropertyAddress = extern struct {
        mSelector: AudioObjectPropertySelector,
        mScope: AudioObjectPropertyScope,
        mElement: AudioObjectPropertyElement,
    };

    pub const AudioBuffer = extern struct {
        mNumberChannels: u32,
        mDataByteSize: u32,
        mData: ?*anyopaque,
    };

    pub const AudioBufferList = extern struct {
        mNumberBuffers: u32,
        mBuffers: [1]AudioBuffer,
    };

    pub const SMPTETime = extern struct {
        mSubframes: i16,
        mSubframeDivisor: i16,
        mCounter: u32,
        mType: u32,
        mFlags: u32,
        mHours: i16,
        mMinutes: i16,
        mSeconds: i16,
        mFrames: i16,
    };

    pub const AudioTimeStamp = extern struct {
        mSampleTime: f64,
        mHostTime: u64,
        mRateScalar: f64,
        mWordClockTime: u64,
        mSMPTETime: SMPTETime,
        mFlags: u32,
        mReserved: u32,
    };

    pub const AudioStreamBasicDescription = extern struct {
        mSampleRate: f64,
        mFormatID: u32,
        mFormatFlags: u32,
        mBytesPerPacket: u32,
        mFramesPerPacket: u32,
        mBytesPerFrame: u32,
        mChannelsPerFrame: u32,
        mBitsPerChannel: u32,
        mReserved: u32,
    };

    pub const kAudioObjectUnknown: AudioObjectID = 0;
    pub const kAudioObjectSystemObject: AudioObjectID = 1;
    pub const kAudioObjectPropertyElementMain: AudioObjectPropertyElement = 0;
    pub const kAudioObjectPropertyScopeGlobal = fourcc("glob");
    pub const kAudioObjectPropertyScopeInput = fourcc("inpt");
    pub const kAudioObjectPropertyScopeOutput = fourcc("outp");
    pub const kAudioObjectPropertyName = fourcc("lnam");
    pub const kAudioDevicePropertyDeviceUID = fourcc("uid ");
    pub const kAudioDevicePropertyNominalSampleRate = fourcc("nsrt");
    pub const kAudioDevicePropertyStreams = fourcc("stm#");
    pub const kAudioDevicePropertyBufferFrameSize = fourcc("fsiz");
    pub const kAudioDevicePropertyStreamConfiguration = fourcc("slay");
    pub const kAudioStreamPropertyVirtualFormat = fourcc("sfmt");
    pub const kAudioFormatLinearPCM = fourcc("lpcm");
    pub const kAudioFormatFlagIsFloat: u32 = 1 << 0;
    pub const kAudioFormatFlagIsBigEndian: u32 = 1 << 1;
    pub const kAudioFormatFlagIsSignedInteger: u32 = 1 << 2;
    pub const kAudioFormatFlagIsAlignedHigh: u32 = 1 << 4;
    pub const kAudioFormatFlagIsNonInterleaved: u32 = 1 << 5;
    pub const kAudioTimeStampSampleTimeValid: u32 = 1 << 0;
    pub const kAudioTimeStampHostTimeValid: u32 = 1 << 1;
    pub const kCFStringEncodingUTF8: u32 = 0x08000100;

    pub extern "c" fn CFRelease(value: *const anyopaque) void;
    pub extern "c" fn CFStringGetCString(
        string: *const anyopaque,
        buffer: [*]u8,
        buffer_size: isize,
        encoding: u32,
    ) Boolean;
    pub extern "c" fn AudioConvertHostTimeToNanos(host_time: u64) u64;
};

const AudioDeviceIOProc = *const fn (
    device: ca.AudioObjectID,
    now: [*c]const ca.AudioTimeStamp,
    input_data: [*c]const ca.AudioBufferList,
    input_time: [*c]const ca.AudioTimeStamp,
    output_data: [*c]ca.AudioBufferList,
    output_time: [*c]const ca.AudioTimeStamp,
    client_data: ?*anyopaque,
) callconv(.c) ca.OSStatus;
const AudioDeviceIOProcID = ?AudioDeviceIOProc;

extern "c" fn AudioObjectGetPropertyDataSize(
    object: ca.AudioObjectID,
    property: *const ca.AudioObjectPropertyAddress,
    qualifier_size: u32,
    qualifier_data: ?*const anyopaque,
    data_size: *u32,
) ca.OSStatus;
extern "c" fn AudioObjectGetPropertyData(
    object: ca.AudioObjectID,
    property: *const ca.AudioObjectPropertyAddress,
    qualifier_size: u32,
    qualifier_data: ?*const anyopaque,
    data_size: *u32,
    data: *anyopaque,
) ca.OSStatus;
extern "c" fn AudioObjectIsPropertySettable(
    object: ca.AudioObjectID,
    property: *const ca.AudioObjectPropertyAddress,
    settable: *ca.Boolean,
) ca.OSStatus;
extern "c" fn AudioObjectSetPropertyData(
    object: ca.AudioObjectID,
    property: *const ca.AudioObjectPropertyAddress,
    qualifier_size: u32,
    qualifier_data: ?*const anyopaque,
    data_size: u32,
    data: *const anyopaque,
) ca.OSStatus;
extern "c" fn AudioDeviceCreateIOProcID(
    device: ca.AudioObjectID,
    io_proc: AudioDeviceIOProc,
    client_data: ?*anyopaque,
    io_proc_id: *AudioDeviceIOProcID,
) ca.OSStatus;
extern "c" fn AudioDeviceDestroyIOProcID(
    device: ca.AudioObjectID,
    io_proc_id: AudioDeviceIOProcID,
) ca.OSStatus;
extern "c" fn AudioDeviceStart(
    device: ca.AudioObjectID,
    io_proc_id: AudioDeviceIOProcID,
) ca.OSStatus;
extern "c" fn AudioDeviceStop(
    device: ca.AudioObjectID,
    io_proc_id: AudioDeviceIOProcID,
) ca.OSStatus;

fn fourcc(comptime value: *const [4]u8) u32 {
    return (@as(u32, value[0]) << 24) |
        (@as(u32, value[1]) << 16) |
        (@as(u32, value[2]) << 8) |
        @as(u32, value[3]);
}

const kAudioHardwarePropertyDevices = fourcc("dev#");
const kAudioHardwarePropertyDefaultInputDevice = fourcc("dIn ");
const kAudioHardwarePropertyDefaultOutputDevice = fourcc("dOut");
const kAudioDevicePropertyUsesVariableBufferFrameSizes = fourcc("vfsz");

const system_object: ca.AudioObjectID = ca.kAudioObjectSystemObject;
const master_element: ca.AudioObjectPropertyElement = ca.kAudioObjectPropertyElementMain;
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

        const default_input = getDefaultDevice(.input) catch ca.kAudioObjectUnknown;
        const default_output = getDefaultDevice(.output) catch ca.kAudioObjectUnknown;

        for (devices) |device| {
            const input_channels = channelCount(device, ca.kAudioObjectPropertyScopeInput) catch 0;
            const output_channels = channelCount(device, ca.kAudioObjectPropertyScopeOutput) catch 0;
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
                ca.kAudioDevicePropertyDeviceUID,
                id_storage[0..],
            );
            const name = try stringProperty(
                device,
                ca.kAudioObjectPropertyName,
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
            try channelCount(device, ca.kAudioObjectPropertyScopeInput)
        else
            0;
        const output_channels = if (output_device != null)
            try channelCount(device, ca.kAudioObjectPropertyScopeOutput)
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
            ca.kAudioDevicePropertyNominalSampleRate,
            ca.kAudioObjectPropertyScopeGlobal,
        );
        const nominal_frames = try numberProperty(
            u32,
            device,
            ca.kAudioDevicePropertyBufferFrameSize,
            ca.kAudioObjectPropertyScopeGlobal,
        );
        const maximum_frames = variableMaximumFrames(device) catch nominal_frames;
        const input_format = if (input_device != null)
            try directionFormat(device, ca.kAudioObjectPropertyScopeInput)
        else
            null;
        const output_format = if (output_device != null)
            try directionFormat(device, ca.kAudioObjectPropertyScopeOutput)
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
        try osStatus(AudioDeviceCreateIOProcID(
            device,
            CoreAudioSession.ioProc,
            session,
            &session.io_proc_id,
        ));
        errdefer _ = AudioDeviceDestroyIOProcID(device, session.io_proc_id);

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

pub const NativeAudioDriver = CoreAudioDriver;

const CoreAudioSession = struct {
    device: ca.AudioDeviceID,
    direction: contract.Direction,
    callback_context: *anyopaque,
    callback: contract.ProcessCallback,
    input_format: ?contract.SampleFormat,
    output_format: ?contract.SampleFormat,
    io_proc_id: AudioDeviceIOProcID = null,
    input_views: [max_native_channels]contract.InputChannelView = undefined,
    output_views: [max_native_channels]contract.OutputChannelView = undefined,
    running: bool = false,

    fn cast(context: *anyopaque) *CoreAudioSession {
        return @ptrCast(@alignCast(context));
    }

    fn start(context: *anyopaque) !void {
        const self = cast(context);
        if (self.running) return;
        try osStatus(AudioDeviceStart(self.device, self.io_proc_id));
        self.running = true;
    }

    fn stop(context: *anyopaque) void {
        const self = cast(context);
        if (!self.running) return;
        _ = AudioDeviceStop(self.device, self.io_proc_id);
        self.running = false;
    }

    fn requestRestart(context: *anyopaque) void {
        const self = cast(context);
        CoreAudioSession.stop(self);
        CoreAudioSession.start(self) catch {};
    }

    fn close(context: *anyopaque) void {
        const self = cast(context);
        CoreAudioSession.stop(self);
        _ = AudioDeviceDestroyIOProcID(self.device, self.io_proc_id);
        std.heap.page_allocator.destroy(self);
    }

    fn ioProc(
        _: ca.AudioObjectID,
        now: [*c]const ca.AudioTimeStamp,
        input_data: [*c]const ca.AudioBufferList,
        input_time: [*c]const ca.AudioTimeStamp,
        output_data: [*c]ca.AudioBufferList,
        output_time: [*c]const ca.AudioTimeStamp,
        client_data: ?*anyopaque,
    ) callconv(.c) ca.OSStatus {
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
        input_data: [*c]const ca.AudioBufferList,
        output_data: [*c]const ca.AudioBufferList,
    ) ?u32 {
        if (self.direction != .output) {
            if (self.input_format) |format| {
                if (framesFromList(input_data, format)) |frames| return frames;
            }
        }
        if (self.direction != .input) {
            if (self.output_format) |format| {
                if (framesFromList(output_data, format)) |frames| return frames;
            }
        }
        return null;
    }

    fn buildInputViews(
        self: *CoreAudioSession,
        list: [*c]const ca.AudioBufferList,
        format: contract.SampleFormat,
    ) usize {
        const buffers: [*]const ca.AudioBuffer = @ptrCast(&list.*.mBuffers);
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
        list: [*c]ca.AudioBufferList,
        format: contract.SampleFormat,
    ) usize {
        const buffers: [*]ca.AudioBuffer = @ptrCast(&list.*.mBuffers);
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
    selector: ca.AudioObjectPropertySelector,
    scope: ca.AudioObjectPropertyScope,
) ca.AudioObjectPropertyAddress {
    return .{
        .mSelector = selector,
        .mScope = scope,
        .mElement = master_element,
    };
}

fn osStatus(status: ca.OSStatus) !void {
    if (status != 0) return error.CoreAudioFailure;
}

fn numberProperty(
    comptime T: type,
    object: ca.AudioObjectID,
    selector: ca.AudioObjectPropertySelector,
    scope: ca.AudioObjectPropertyScope,
) !T {
    var value: T = undefined;
    var size: u32 = @sizeOf(T);
    var property = address(selector, scope);
    try osStatus(AudioObjectGetPropertyData(
        object,
        &property,
        0,
        null,
        &size,
        @ptrCast(&value),
    ));
    return value;
}

fn setNumberProperty(
    comptime T: type,
    object: ca.AudioObjectID,
    selector: ca.AudioObjectPropertySelector,
    value: T,
) !void {
    var property = address(selector, ca.kAudioObjectPropertyScopeGlobal);
    var settable: ca.Boolean = 0;
    try osStatus(AudioObjectIsPropertySettable(object, &property, &settable));
    if (settable == 0) return error.PropertyNotSettable;
    var mutable_value = value;
    try osStatus(AudioObjectSetPropertyData(
        object,
        &property,
        0,
        null,
        @sizeOf(T),
        &mutable_value,
    ));
}

fn preferSampleRate(device: ca.AudioDeviceID, requested: f64) !void {
    if (!std.math.isFinite(requested) or requested <= 0.0) return error.InvalidSampleRate;
    const actual = try numberProperty(
        f64,
        device,
        ca.kAudioDevicePropertyNominalSampleRate,
        ca.kAudioObjectPropertyScopeGlobal,
    );
    if (@abs(actual - requested) < 0.5) return;
    try setNumberProperty(f64, device, ca.kAudioDevicePropertyNominalSampleRate, requested);
}

fn preferBufferFrames(device: ca.AudioDeviceID, requested: u32) !void {
    if (requested == 0) return error.InvalidBufferFrameCount;
    const actual = try numberProperty(
        u32,
        device,
        ca.kAudioDevicePropertyBufferFrameSize,
        ca.kAudioObjectPropertyScopeGlobal,
    );
    if (actual == requested) return;
    try setNumberProperty(u32, device, ca.kAudioDevicePropertyBufferFrameSize, requested);
}

fn variableMaximumFrames(device: ca.AudioDeviceID) !u32 {
    return numberProperty(
        u32,
        device,
        kAudioDevicePropertyUsesVariableBufferFrameSizes,
        ca.kAudioObjectPropertyScopeGlobal,
    );
}

fn deviceIds(allocator: std.mem.Allocator) ![]ca.AudioDeviceID {
    var property = address(
        kAudioHardwarePropertyDevices,
        ca.kAudioObjectPropertyScopeGlobal,
    );
    var bytes: u32 = 0;
    try osStatus(AudioObjectGetPropertyDataSize(system_object, &property, 0, null, &bytes));
    const count = bytes / @sizeOf(ca.AudioDeviceID);
    const devices = try allocator.alloc(ca.AudioDeviceID, count);
    errdefer allocator.free(devices);
    try osStatus(AudioObjectGetPropertyData(system_object, &property, 0, null, &bytes, devices.ptr));
    return devices;
}

fn getDefaultDevice(direction: contract.Direction) !ca.AudioDeviceID {
    const selector: ca.AudioObjectPropertySelector = switch (direction) {
        .input => kAudioHardwarePropertyDefaultInputDevice,
        .output => kAudioHardwarePropertyDefaultOutputDevice,
        .duplex => return error.InvalidDefaultDeviceDirection,
    };
    const device = try numberProperty(
        ca.AudioDeviceID,
        system_object,
        selector,
        ca.kAudioObjectPropertyScopeGlobal,
    );
    if (device == ca.kAudioObjectUnknown) return error.DefaultDeviceUnavailable;
    return device;
}

fn findDevice(uid: []const u8) !ca.AudioDeviceID {
    const allocator = std.heap.page_allocator;
    const devices = try deviceIds(allocator);
    defer allocator.free(devices);
    for (devices) |device| {
        var storage: [512]u8 = undefined;
        const candidate = stringProperty(
            device,
            ca.kAudioDevicePropertyDeviceUID,
            storage[0..],
        ) catch continue;
        if (std.mem.eql(u8, uid, candidate)) return device;
    }
    return error.DeviceNotFound;
}

fn stringProperty(
    object: ca.AudioObjectID,
    selector: ca.AudioObjectPropertySelector,
    storage: []u8,
) ![]const u8 {
    if (storage.len == 0) return error.EmptyStringStorage;
    var property = address(selector, ca.kAudioObjectPropertyScopeGlobal);
    var value: ca.CFStringRef = null;
    var size: u32 = @sizeOf(ca.CFStringRef);
    try osStatus(AudioObjectGetPropertyData(
        object,
        &property,
        0,
        null,
        &size,
        @ptrCast(&value),
    ));
    const string = value orelse return error.MissingStringProperty;
    defer ca.CFRelease(string);
    if (ca.CFStringGetCString(
        string,
        storage.ptr,
        @intCast(storage.len),
        ca.kCFStringEncodingUTF8,
    ) == 0) return error.StringPropertyTooLong;
    return std.mem.sliceTo(storage, 0);
}

fn channelCount(device: ca.AudioDeviceID, scope: ca.AudioObjectPropertyScope) !u32 {
    var property = address(ca.kAudioDevicePropertyStreamConfiguration, scope);
    var size: u32 = 0;
    try osStatus(AudioObjectGetPropertyDataSize(device, &property, 0, null, &size));
    const storage = try std.heap.page_allocator.alignedAlloc(u8, .of(ca.AudioBufferList), size);
    defer std.heap.page_allocator.free(storage);
    try osStatus(AudioObjectGetPropertyData(device, &property, 0, null, &size, storage.ptr));
    const list: *const ca.AudioBufferList = @ptrCast(storage.ptr);
    const buffers: [*]const ca.AudioBuffer = @ptrCast(&list.mBuffers);
    var channels: u32 = 0;
    for (buffers[0..list.mNumberBuffers]) |buffer| channels += buffer.mNumberChannels;
    return channels;
}

fn directionFormat(
    device: ca.AudioDeviceID,
    scope: ca.AudioObjectPropertyScope,
) !contract.SampleFormat {
    var property = address(ca.kAudioDevicePropertyStreams, scope);
    var size: u32 = 0;
    try osStatus(AudioObjectGetPropertyDataSize(device, &property, 0, null, &size));
    if (size == 0) return error.NoAudioStreams;
    const stream_count = size / @sizeOf(ca.AudioStreamID);
    const streams = try std.heap.page_allocator.alloc(ca.AudioStreamID, stream_count);
    defer std.heap.page_allocator.free(streams);
    try osStatus(AudioObjectGetPropertyData(device, &property, 0, null, &size, streams.ptr));

    var common: ?contract.SampleFormat = null;
    for (streams) |stream| {
        var format_property = address(
            ca.kAudioStreamPropertyVirtualFormat,
            ca.kAudioObjectPropertyScopeGlobal,
        );
        var asbd: ca.AudioStreamBasicDescription = undefined;
        var asbd_size: u32 = @sizeOf(ca.AudioStreamBasicDescription);
        try osStatus(AudioObjectGetPropertyData(
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

fn formatFromAsbd(asbd: ca.AudioStreamBasicDescription) !contract.SampleFormat {
    if (asbd.mFormatID != ca.kAudioFormatLinearPCM) return error.UnsupportedNativeFormat;
    const is_float = asbd.mFormatFlags & ca.kAudioFormatFlagIsFloat != 0;
    const is_signed = asbd.mFormatFlags & ca.kAudioFormatFlagIsSignedInteger != 0;
    if (!is_float and !is_signed) return error.UnsupportedNativeFormat;
    const non_interleaved = asbd.mFormatFlags & ca.kAudioFormatFlagIsNonInterleaved != 0;
    const bytes_per_sample = if (non_interleaved)
        asbd.mBytesPerFrame
    else if (asbd.mChannelsPerFrame > 0)
        asbd.mBytesPerFrame / asbd.mChannelsPerFrame
    else
        0;
    const format: contract.SampleFormat = .{
        .kind = if (is_float) .floating_point else .signed_integer,
        .container_bytes = @intCast(bytes_per_sample),
        .valid_bits = @intCast(asbd.mBitsPerChannel),
        .byte_order = if (asbd.mFormatFlags & ca.kAudioFormatFlagIsBigEndian != 0)
            .big
        else
            .little,
        .aligned_high = asbd.mFormatFlags & ca.kAudioFormatFlagIsAlignedHigh != 0,
    };
    try format.validate();
    return format;
}

fn framesFromList(
    list: anytype,
    format: contract.SampleFormat,
) ?u32 {
    const buffers: [*]const ca.AudioBuffer = @ptrCast(&list.*.mBuffers);
    for (buffers[0..list.*.mNumberBuffers]) |buffer| {
        if (buffer.mData == null or buffer.mNumberChannels == 0) continue;
        const bytes_per_frame = buffer.mNumberChannels * format.container_bytes;
        if (bytes_per_frame == 0) continue;
        return buffer.mDataByteSize / bytes_per_frame;
    }
    return null;
}

fn streamTime(
    now: [*c]const ca.AudioTimeStamp,
    input_time: [*c]const ca.AudioTimeStamp,
    output_time: [*c]const ca.AudioTimeStamp,
) contract.StreamTime {
    var result: contract.StreamTime = .{};
    if (now != null and now.*.mFlags & ca.kAudioTimeStampSampleTimeValid != 0) {
        result.valid |= contract.TimeValidity.sample_position;
        result.sample_position = @intFromFloat(now.*.mSampleTime);
    }
    if (now != null and now.*.mFlags & ca.kAudioTimeStampHostTimeValid != 0) {
        result.valid |= contract.TimeValidity.monotonic_ns;
        result.monotonic_ns = ca.AudioConvertHostTimeToNanos(now.*.mHostTime);
    }
    if (input_time != null and input_time.*.mFlags & ca.kAudioTimeStampHostTimeValid != 0) {
        result.valid |= contract.TimeValidity.input_acquisition_ns;
        result.input_acquisition_ns = ca.AudioConvertHostTimeToNanos(input_time.*.mHostTime);
    }
    if (output_time != null and output_time.*.mFlags & ca.kAudioTimeStampHostTimeValid != 0) {
        result.valid |= contract.TimeValidity.output_presentation_ns;
        result.output_presentation_ns = ca.AudioConvertHostTimeToNanos(output_time.*.mHostTime);
    }
    return result;
}

test "Core Audio driver exposes the common backend identity" {
    var core_audio = CoreAudioDriver{};
    try std.testing.expectEqual(contract.Backend.core_audio, core_audio.driver().backend());
}
