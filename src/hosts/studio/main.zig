const robine = @import("robine");
const platform = @import("platform");
const std = @import("std");

const Studio = struct {
    scene: robine.ui.wireframe.Scene = .{},
    pedalboard_mesh: robine.ui.pedalboard_3d.Mesh = .{},
    view: robine.ui.wireframe.ViewState = .rig,
    amplifier_focused: bool = false,

    fn project(self: *Studio) !void {
        try robine.ui.wireframe.projectView(&self.scene, &robine.model.demo.rig, self.view);
    }

    fn pointerDown(context: *anyopaque, point: [2]f32, window_aspect: f32) bool {
        const self: *Studio = @ptrCast(@alignCast(context));
        if (self.view == .rig and self.amplifier_focused and
            robine.ui.pedalboard_3d.hitTestFocusedAmplifier(point, window_aspect))
        {
            self.amplifier_focused = false;
            return true;
        }
        if (self.view == .rig and !self.amplifier_focused and
            robine.ui.pedalboard_3d.hitTestAmplifier(point, window_aspect))
        {
            self.amplifier_focused = true;
            return true;
        }
        const previous = self.view;
        if (!robine.ui.wireframe.activate(&self.scene, &self.view, point)) return false;
        self.project() catch |err| {
            self.view = previous;
            std.log.err("Scene projection failed after interaction: {s}", .{@errorName(err)});
            return false;
        };
        return true;
    }

    fn geometry(context: *anyopaque) platform.Geometry {
        const self: *Studio = @ptrCast(@alignCast(context));
        return .{
            .line_vertices = self.scene.lines(),
            .fill_vertices = self.scene.fills(),
            .equipment_vertices = self.pedalboard_mesh.items(),
            .equipment_lights = self.pedalboard_mesh.emissiveLights(),
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
    try robine.ui.pedalboard_3d.build(&studio.pedalboard_mesh, &robine.model.demo.rig);
    try studio.project();
    try platform.run(.{
        .title = "Robine Studio — descriptive equipment renderer",
        .width = 1200,
        .height = 760,
        .line_vertices = studio.scene.lines(),
        .fill_vertices = studio.scene.fills(),
        .equipment_vertices = studio.pedalboard_mesh.items(),
        .equipment_lights = studio.pedalboard_mesh.emissiveLights(),
        .equipment_camera = robine.ui.pedalboard_3d.rig_camera,
        .mode = .pedalboard_3d,
        .interaction = .{
            .context = @ptrCast(&studio),
            .pointer_down = &Studio.pointerDown,
            .geometry = &Studio.geometry,
        },
    });
}
