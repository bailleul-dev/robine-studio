const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const os = target.result.os.tag;
    if (os != .macos and os != .linux) {
        @panic("Robine Studio currently supports macOS and Linux");
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
        .root_source_file = b.path(if (os == .macos)
            "src/platform/macos/audio.zig"
        else
            "src/platform/linux/audio.zig"),
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
        .root_source_file = b.path(if (os == .macos)
            "src/platform/macos/app.zig"
        else
            "src/platform/linux/app.zig"),
        .target = target,
        .optimize = optimize,
    });
    platform.addImport("robine", robine);
    const ui_assets = b.createModule(.{
        .root_source_file = b.path("resources/ui/assets.zig"),
        .target = target,
        .optimize = optimize,
    });
    platform.addImport("ui_assets", ui_assets);

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
    if (os == .macos) {
        studio.root_module.linkFramework("AppKit", .{});
        studio.root_module.linkFramework("CoreGraphics", .{});
        studio.root_module.linkFramework("Metal", .{});
        studio.root_module.linkFramework("MetalKit", .{});
        studio.root_module.linkFramework("QuartzCore", .{});
        studio.root_module.linkFramework("CoreAudio", .{});
        studio.root_module.linkFramework("CoreFoundation", .{});
        studio.root_module.linkSystemLibrary("objc", .{});
    } else {
        studio.root_module.link_libc = true;
        studio.root_module.linkSystemLibrary("X11", .{});
        studio.root_module.linkSystemLibrary("GL", .{});
        studio.root_module.linkSystemLibrary("dl", .{});
    }
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
    if (os == .macos) {
        audio_probe.root_module.linkFramework("CoreAudio", .{});
        audio_probe.root_module.linkFramework("CoreFoundation", .{});
    } else {
        audio_probe.root_module.link_libc = true;
        audio_probe.root_module.linkSystemLibrary("dl", .{});
    }
    b.installArtifact(audio_probe);

    const run_audio_probe = b.addRunArtifact(audio_probe);
    const audio_probe_step = b.step("audio-probe", "List native audio devices");
    audio_probe_step.dependOn(&run_audio_probe.step);

    const nam_bench_module = b.createModule(.{
        .root_source_file = b.path("src/hosts/nam_bench/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    nam_bench_module.addImport("robine", robine);
    nam_bench_module.addImport("audio_assets", audio_assets);
    const nam_bench = b.addExecutable(.{
        .name = "robine-nam-bench",
        .root_module = nam_bench_module,
    });
    const run_nam_bench = b.addRunArtifact(nam_bench);
    const nam_bench_step = b.step("nam-bench", "Benchmark full-quality NAM fixture rendering");
    nam_bench_step.dependOn(&run_nam_bench.step);

    const a2_bench_module = b.createModule(.{
        .root_source_file = b.path("src/hosts/a2_bench/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    a2_bench_module.addImport("robine", robine);
    a2_bench_module.addImport("audio_assets", audio_assets);
    const a2_bench = b.addExecutable(.{
        .name = "robine-a2-bench",
        .root_module = a2_bench_module,
    });
    const run_a2_bench = b.addRunArtifact(a2_bench);
    const a2_bench_step = b.step("a2-bench", "Benchmark specialized A2-Lite and A2-Full kernels");
    a2_bench_step.dependOn(&run_a2_bench.step);

    const run_step = b.step("run-studio", "Run Robine Studio");
    if (os == .macos) {
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
        run_step.dependOn(&run_command.step);
    } else {
        const run_studio = b.addRunArtifact(studio);
        run_step.dependOn(&run_studio.step);
    }

    const tests = b.addTest(.{ .root_module = robine });
    const run_tests = b.addRunArtifact(tests);
    const platform_audio_tests = b.addTest(.{ .root_module = platform_audio });
    const run_platform_audio_tests = b.addRunArtifact(platform_audio_tests);
    const native_audio_tests = b.addTest(.{ .root_module = native_audio });
    if (os == .macos) {
        native_audio_tests.root_module.linkFramework("CoreAudio", .{});
        native_audio_tests.root_module.linkFramework("CoreFoundation", .{});
    } else {
        native_audio_tests.root_module.link_libc = true;
        native_audio_tests.root_module.linkSystemLibrary("dl", .{});
    }
    const run_native_audio_tests = b.addRunArtifact(native_audio_tests);
    const studio_audio_test_module = b.createModule(.{
        .root_source_file = b.path("src/hosts/studio/audio.zig"),
        .target = target,
        .optimize = optimize,
    });
    studio_audio_test_module.addImport("robine", robine);
    studio_audio_test_module.addImport("audio_contract", platform_audio);
    studio_audio_test_module.addImport("native_audio", native_audio);
    studio_audio_test_module.addImport("audio_assets", audio_assets);
    const studio_audio_tests = b.addTest(.{ .root_module = studio_audio_test_module });
    if (os == .macos) {
        studio_audio_tests.root_module.linkFramework("CoreAudio", .{});
        studio_audio_tests.root_module.linkFramework("CoreFoundation", .{});
    } else {
        studio_audio_tests.root_module.link_libc = true;
        studio_audio_tests.root_module.linkSystemLibrary("dl", .{});
    }
    const run_studio_audio_tests = b.addRunArtifact(studio_audio_tests);
    const test_step = b.step("test", "Run Robine model, UI, and audio contract tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(&run_platform_audio_tests.step);
    test_step.dependOn(&run_native_audio_tests.step);
    test_step.dependOn(&run_studio_audio_tests.step);
}
