const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    if (target.result.os.tag != .macos) {
        @panic("the first Robine Studio host currently targets macOS");
    }

    const robine = b.addModule("robine", .{
        .root_source_file = b.path("src/robine.zig"),
        .target = target,
        .optimize = optimize,
    });

    const platform_audio = b.createModule(.{
        .root_source_file = b.path("src/platform/audio.zig"),
        .target = target,
        .optimize = optimize,
    });

    const native_audio = b.createModule(.{
        .root_source_file = b.path("src/platform/macos/audio.zig"),
        .target = target,
        .optimize = optimize,
    });
    native_audio.addImport("audio_contract", platform_audio);

    const audio_assets = b.createModule(.{
        .root_source_file = b.path("resources/audio/dev_assets.zig"),
        .target = target,
        .optimize = optimize,
    });

    const platform = b.createModule(.{
        .root_source_file = b.path("src/platform/macos/app.zig"),
        .target = target,
        .optimize = optimize,
    });
    platform.addImport("robine", robine);

    const studio_module = b.createModule(.{
        .root_source_file = b.path("src/hosts/studio/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    studio_module.addImport("robine", robine);
    studio_module.addImport("platform", platform);
    studio_module.addImport("audio_contract", platform_audio);
    studio_module.addImport("native_audio", native_audio);
    studio_module.addImport("audio_assets", audio_assets);

    const studio = b.addExecutable(.{
        .name = "robine-studio",
        .root_module = studio_module,
    });
    studio.root_module.linkFramework("AppKit", .{});
    studio.root_module.linkFramework("CoreGraphics", .{});
    studio.root_module.linkFramework("Metal", .{});
    studio.root_module.linkFramework("MetalKit", .{});
    studio.root_module.linkFramework("QuartzCore", .{});
    studio.root_module.linkFramework("CoreAudio", .{});
    studio.root_module.linkFramework("CoreFoundation", .{});
    studio.root_module.linkSystemLibrary("objc", .{});
    b.installArtifact(studio);

    const audio_probe_module = b.createModule(.{
        .root_source_file = b.path("src/hosts/audio_probe/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    audio_probe_module.addImport("audio_contract", platform_audio);
    audio_probe_module.addImport("native_audio", native_audio);
    const audio_probe = b.addExecutable(.{
        .name = "robine-audio-probe",
        .root_module = audio_probe_module,
    });
    audio_probe.root_module.link_libc = true;
    audio_probe.root_module.linkFramework("CoreAudio", .{});
    audio_probe.root_module.linkFramework("CoreFoundation", .{});
    b.installArtifact(audio_probe);

    const run_audio_probe = b.addRunArtifact(audio_probe);
    const audio_probe_step = b.step("audio-probe", "List Core Audio duplex devices");
    audio_probe_step.dependOn(&run_audio_probe.step);

    const install_app_binary = b.addInstallFileWithDir(
        studio.getEmittedBin(),
        .{ .custom = "Robine Studio.app/Contents/MacOS" },
        "robine-studio",
    );
    const install_app_plist = b.addInstallFileWithDir(
        b.path("resources/macos/Info.plist"),
        .{ .custom = "Robine Studio.app/Contents" },
        "Info.plist",
    );
    b.getInstallStep().dependOn(&install_app_binary.step);
    b.getInstallStep().dependOn(&install_app_plist.step);

    const run_command = b.addSystemCommand(&.{ "open", "-n" });
    run_command.addArg(b.getInstallPath(.prefix, "Robine Studio.app"));
    run_command.step.dependOn(&install_app_binary.step);
    run_command.step.dependOn(&install_app_plist.step);
    const run_step = b.step("run-studio", "Run Robine Studio");
    run_step.dependOn(&run_command.step);

    const tests = b.addTest(.{ .root_module = robine });
    const run_tests = b.addRunArtifact(tests);
    const platform_audio_tests = b.addTest(.{ .root_module = platform_audio });
    const run_platform_audio_tests = b.addRunArtifact(platform_audio_tests);
    const native_audio_tests = b.addTest(.{ .root_module = native_audio });
    native_audio_tests.root_module.linkFramework("CoreAudio", .{});
    native_audio_tests.root_module.linkFramework("CoreFoundation", .{});
    const run_native_audio_tests = b.addRunArtifact(native_audio_tests);
    const test_step = b.step("test", "Run Robine model, UI, and audio contract tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_platform_audio_tests.step);
    test_step.dependOn(&run_native_audio_tests.step);
}
