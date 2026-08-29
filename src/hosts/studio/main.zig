const robine = @import("robine");
const platform = @import("platform");

pub fn main() !void {
    var scene = robine.ui.wireframe.Scene{};
    try robine.ui.wireframe.project(&scene, &robine.model.demo.rig);
    try platform.run(.{
        .title = "Robine Studio — semantic equipment wireframe",
        .width = 1200,
        .height = 760,
        .line_vertices = scene.lines(),
        .fill_vertices = scene.fills(),
    });
}
