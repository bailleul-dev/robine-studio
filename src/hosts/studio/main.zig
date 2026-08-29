const robine = @import("robine");
const platform = @import("platform");
const std = @import("std");

const Studio = struct {
    scene: robine.ui.wireframe.Scene = .{},
    view: robine.ui.wireframe.ViewState = .rig,

    fn project(self: *Studio) !void {
        try robine.ui.wireframe.projectView(&self.scene, &robine.model.demo.rig, self.view);
    }

    fn pointerDown(context: *anyopaque, point: [2]f32) bool {
        const self: *Studio = @ptrCast(@alignCast(context));
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
        };
    }
};

pub fn main() !void {
    var studio = Studio{};
    try studio.project();
    try platform.run(.{
        .title = "Robine Studio — semantic equipment wireframe",
        .width = 1200,
        .height = 760,
        .line_vertices = studio.scene.lines(),
        .fill_vertices = studio.scene.fills(),
        .interaction = .{
            .context = @ptrCast(&studio),
            .pointer_down = &Studio.pointerDown,
            .geometry = &Studio.geometry,
        },
    });
}
