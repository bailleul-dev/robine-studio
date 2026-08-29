pub const model = struct {
    pub const demo = @import("model/demo.zig");
};

pub const ui = struct {
    pub const wireframe = @import("ui/wireframe.zig");
};

test {
    _ = model.demo;
    _ = ui.wireframe;
}
