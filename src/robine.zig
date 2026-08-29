pub const model = struct {
    pub const demo = @import("model/demo.zig");
};

pub const audio = struct {
    pub const processor = @import("audio/processor.zig");
};

pub const ui = struct {
    pub const lighting_lab = @import("ui/lighting_lab.zig");
    pub const pedalboard_3d = @import("ui/pedalboard_3d.zig");
    pub const wireframe = @import("ui/wireframe.zig");
};

test {
    _ = audio.processor;
    _ = model.demo;
    _ = ui.lighting_lab;
    _ = ui.pedalboard_3d;
    _ = ui.wireframe;
}
