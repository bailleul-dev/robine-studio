pub const model = struct {
    pub const demo = @import("model/demo.zig");
};

pub const ui = struct {
    pub const lighting_lab = @import("ui/lighting_lab.zig");
    pub const wireframe = @import("ui/wireframe.zig");
};

test {
    _ = model.demo;
    _ = ui.lighting_lab;
    _ = ui.wireframe;
}
