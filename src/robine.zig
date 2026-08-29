pub const model = struct {
    pub const demo = @import("model/demo.zig");
};

pub const audio = struct {
    pub const convolver = @import("audio/convolver.zig");
    pub const nam = @import("audio/nam.zig");
    pub const processor = @import("audio/processor.zig");
    pub const wav = @import("audio/wav.zig");
};

pub const ui = struct {
    pub const lighting_lab = @import("ui/lighting_lab.zig");
    pub const pedalboard_3d = @import("ui/pedalboard_3d.zig");
    pub const wireframe = @import("ui/wireframe.zig");
};

test {
    _ = audio.convolver;
    _ = audio.nam;
    _ = audio.processor;
    _ = audio.wav;
    _ = model.demo;
    _ = ui.lighting_lab;
    _ = ui.pedalboard_3d;
    _ = ui.wireframe;
}
