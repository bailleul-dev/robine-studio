const audio_contract = @import("audio_contract");
const native_audio = @import("native_audio");
const std = @import("std");

extern "c" fn usleep(microseconds: u32) c_int;

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

const CallbackCounter = struct {
    cycles: std.atomic.Value(u32) = .init(0),
};

fn countAudio(context: *anyopaque, _: audio_contract.ProcessCycle) void {
    const counter: *CallbackCounter = @ptrCast(@alignCast(context));
    _ = counter.cycles.fetchAdd(1, .monotonic);
}

pub fn main() !void {
    var core_audio = native_audio.CoreAudioDriver{};
    var visitor_context: u8 = 0;
    const driver = core_audio.driver();
    std.debug.print("Core Audio input devices\n", .{});
    try driver.enumerate(.input, &visitor_context, printDevice);
    std.debug.print("\nCore Audio output devices\n", .{});
    try driver.enumerate(.output, &visitor_context, printDevice);
    std.debug.print("\nCore Audio duplex devices\n", .{});
    try driver.enumerate(.duplex, &visitor_context, printDevice);

    var callback_counter = CallbackCounter{};
    const opened = try driver.open(
        .{ .direction = .output, .sample_rate = null },
        &callback_counter,
        countAudio,
    );
    defer opened.session.close();
    std.debug.print(
        "\nDefault output negotiation\n  rate: {d:.0} Hz\n  frames: {d} (max {d})\n  channels: {d}\n  format: {any}\n",
        .{
            opened.config.sample_rate,
            opened.config.nominal_frames,
            opened.config.maximum_frames,
            opened.config.output_channels,
            opened.config.output_format,
        },
    );
    try opened.session.start();
    _ = usleep(100_000);
    opened.session.stop();
    std.debug.print(
        "  silent callback cycles: {d}\n",
        .{callback_counter.cycles.load(.monotonic)},
    );
}
