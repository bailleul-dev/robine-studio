const audio_contract = @import("audio_contract");
const native_audio = @import("native_audio");
const std = @import("std");

fn printDevice(_: *anyopaque, device: audio_contract.DeviceDescriptor) !void {
    std.debug.print(
        "{s}\n  id: {s}\n  inputs: {d}{s}\n  outputs: {d}{s}\n",
        .{
            device.name,
            device.id,
            device.input_channels,
            if (device.is_default_input) " (default)" else "",
            device.output_channels,
            if (device.is_default_output) " (default)" else "",
        },
    );
}

pub fn main() !void {
    var core_audio = native_audio.CoreAudioDriver{};
    var visitor_context: u8 = 0;
    std.debug.print("Core Audio devices\n", .{});
    try core_audio.driver().enumerate(
        .duplex,
        &visitor_context,
        printDevice,
    );
}
