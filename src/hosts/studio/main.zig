const robine = @import("robine");
const platform = @import("platform");
const std = @import("std");
const studio_audio = @import("audio.zig");

const Studio = struct {
    scene: robine.ui.wireframe.Scene = .{},
    pedalboard_mesh: robine.ui.pedalboard_3d.Mesh = .{},
    view: robine.ui.wireframe.ViewState = .rig,
    amplifier_focused: bool = false,
    first_pedal_enabled: robine.core.equipment_state.EquipmentSwitch = .init(true),
    first_pedal_mode: robine.core.equipment_state.EquipmentModeSwitch = .init(.middle),
    tumnus_enabled: robine.core.equipment_state.EquipmentSwitch = .init(true),
    big_muff_enabled: robine.core.equipment_state.EquipmentSwitch = .init(true),
    king_orange_enabled: robine.core.equipment_state.EquipmentSwitch = .init(true),
    king_red_enabled: robine.core.equipment_state.EquipmentSwitch = .init(true),
    reverb_enabled: robine.core.equipment_state.EquipmentSwitch = .init(true),
    equipment_revision: u64 = 0,

    fn project(self: *Studio) !void {
        try robine.ui.wireframe.projectStudioView(&self.scene, &robine.model.demo.rig, self.view, self.amplifier_focused);
    }

    fn rebuildPedalboard(self: *Studio) !void {
        const enabled = [_]bool{
            self.first_pedal_enabled.isEnabled(),
            self.tumnus_enabled.isEnabled(),
            self.big_muff_enabled.isEnabled(),
            self.king_orange_enabled.isEnabled() or self.king_red_enabled.isEnabled(),
            self.reverb_enabled.isEnabled(),
        };
        const modes = [_]robine.core.equipment_state.ThreePosition{self.first_pedal_mode.position()};
        const footswitch_masks = [_]u8{
            @intFromBool(self.first_pedal_enabled.isEnabled()),
            @intFromBool(self.tumnus_enabled.isEnabled()),
            @intFromBool(self.big_muff_enabled.isEnabled()),
            @as(u8, @intFromBool(self.king_orange_enabled.isEnabled())) |
                (@as(u8, @intFromBool(self.king_red_enabled.isEnabled())) << 1),
            @intFromBool(self.reverb_enabled.isEnabled()),
        };
        try robine.ui.pedalboard_3d.build(
            &self.pedalboard_mesh,
            &robine.model.demo.rig,
            .{
                .pedal_enabled = &enabled,
                .pedal_modes = &modes,
                .pedal_footswitch_masks = &footswitch_masks,
            },
        );
        self.equipment_revision +%= 1;
    }

    fn pointerDown(context: *anyopaque, point: [2]f32, window_aspect: f32) bool {
        const self: *Studio = @ptrCast(@alignCast(context));
        if (self.scene.actionAt(point)) |action| {
            const previous_view = self.view;
            const previous_focus = self.amplifier_focused;
            switch (action) {
                .show_rig => {
                    self.view = .rig;
                    self.amplifier_focused = false;
                },
                .show_amplifier => {
                    self.view = .rig;
                    self.amplifier_focused = true;
                },
                .show_lighting_lab => {
                    self.view = .lighting_lab;
                    self.amplifier_focused = false;
                },
            }
            if (self.view == previous_view and self.amplifier_focused == previous_focus) return false;
            self.project() catch |err| {
                self.view = previous_view;
                self.amplifier_focused = previous_focus;
                std.log.err("Scene projection failed after view change: {s}", .{@errorName(err)});
                return false;
            };
            return true;
        }
        if (self.view == .rig and self.amplifier_focused and
            robine.ui.pedalboard_3d.hitTestFocusedAmplifier(point, window_aspect))
        {
            self.amplifier_focused = false;
            self.project() catch |err| {
                self.amplifier_focused = true;
                std.log.err("Scene projection failed after amplifier return: {s}", .{@errorName(err)});
                return false;
            };
            return true;
        }
        if (self.view == .rig and !self.amplifier_focused and
            robine.ui.pedalboard_3d.hitTestPedalModeSwitch(
                point,
                window_aspect,
                &robine.model.demo.rig,
                0,
            ))
        {
            const previous = self.first_pedal_mode.position();
            _ = self.first_pedal_mode.cycle();
            self.rebuildPedalboard() catch |err| {
                self.first_pedal_mode.setPosition(previous);
                std.log.err("Pedal projection failed after mode change: {s}", .{@errorName(err)});
                return false;
            };
            return true;
        }
        if (self.view == .rig and !self.amplifier_focused and
            robine.ui.pedalboard_3d.hitTestPedalFootswitch(
                point,
                window_aspect,
                &robine.model.demo.rig,
                0,
                0,
            ))
        {
            const previous = self.first_pedal_enabled.isEnabled();
            _ = self.first_pedal_enabled.toggle();
            self.rebuildPedalboard() catch |err| {
                self.first_pedal_enabled.setEnabled(previous);
                std.log.err("Pedal projection failed after bypass change: {s}", .{@errorName(err)});
                return false;
            };
            return true;
        }
        if (self.view == .rig and !self.amplifier_focused) {
            const pedal_indices = [_]usize{ 1, 2, 4 };
            const states = [_]*robine.core.equipment_state.EquipmentSwitch{
                &self.tumnus_enabled,
                &self.big_muff_enabled,
                &self.reverb_enabled,
            };
            for (pedal_indices, states) |pedal_index, state| {
                if (robine.ui.pedalboard_3d.hitTestPedalFootswitch(
                    point,
                    window_aspect,
                    &robine.model.demo.rig,
                    pedal_index,
                    0,
                )) {
                    const previous = state.isEnabled();
                    _ = state.toggle();
                    self.rebuildPedalboard() catch |err| {
                        state.setEnabled(previous);
                        std.log.err("Pedal projection failed after bypass change: {s}", .{@errorName(err)});
                        return false;
                    };
                    return true;
                }
            }
            inline for (0..2) |footswitch_index| {
                if (robine.ui.pedalboard_3d.hitTestPedalFootswitch(
                    point,
                    window_aspect,
                    &robine.model.demo.rig,
                    3,
                    footswitch_index,
                )) {
                    const state = if (footswitch_index == 0)
                        &self.king_orange_enabled
                    else
                        &self.king_red_enabled;
                    const previous = state.isEnabled();
                    _ = state.toggle();
                    self.rebuildPedalboard() catch |err| {
                        state.setEnabled(previous);
                        std.log.err("King of Tone projection failed after channel change: {s}", .{@errorName(err)});
                        return false;
                    };
                    return true;
                }
            }
        }
        if (self.view == .rig and !self.amplifier_focused and
            robine.ui.pedalboard_3d.hitTestAmplifier(point, window_aspect))
        {
            self.amplifier_focused = true;
            self.project() catch |err| {
                self.amplifier_focused = false;
                std.log.err("Scene projection failed after amplifier focus: {s}", .{@errorName(err)});
                return false;
            };
            return true;
        }
        return false;
    }

    fn geometry(context: *anyopaque) platform.Geometry {
        const self: *Studio = @ptrCast(@alignCast(context));
        return .{
            .line_vertices = self.scene.lines(),
            .fill_vertices = self.scene.fills(),
            .equipment_vertices = self.pedalboard_mesh.items(),
            .equipment_lights = self.pedalboard_mesh.emissiveLights(),
            .equipment_revision = self.equipment_revision,
            .equipment_camera = if (self.amplifier_focused)
                robine.ui.pedalboard_3d.amplifier_camera
            else
                robine.ui.pedalboard_3d.rig_camera,
            .mode = switch (self.view) {
                .rig => .pedalboard_3d,
                .amplifier => .wireframe,
                .lighting_lab => .lighting_lab,
            },
        };
    }
};

pub fn main() !void {
    var studio = Studio{};
    try studio.rebuildPedalboard();
    try studio.project();

    var startup_player: studio_audio.StartupPlayer = undefined;
    try startup_player.init(
        std.heap.page_allocator,
        &studio.first_pedal_enabled,
        &studio.first_pedal_mode,
        &studio.tumnus_enabled,
        &studio.big_muff_enabled,
        &studio.king_orange_enabled,
        &studio.king_red_enabled,
        &studio.reverb_enabled,
    );
    defer startup_player.deinit();

    try platform.run(.{
        .title = "Robine Studio — descriptive equipment renderer",
        .width = 1200,
        .height = 760,
        .line_vertices = studio.scene.lines(),
        .fill_vertices = studio.scene.fills(),
        .equipment_vertices = studio.pedalboard_mesh.items(),
        .equipment_lights = studio.pedalboard_mesh.emissiveLights(),
        .equipment_revision = studio.equipment_revision,
        .equipment_camera = robine.ui.pedalboard_3d.rig_camera,
        .mode = .pedalboard_3d,
        .interaction = .{
            .context = @ptrCast(&studio),
            .pointer_down = &Studio.pointerDown,
            .geometry = &Studio.geometry,
        },
    });
}
