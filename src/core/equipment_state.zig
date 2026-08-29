const std = @import("std");

/// One UI-owned equipment switch observed by the real-time audio thread.
///
/// The atomic transports only the canonical boolean state. Audio smoothing and
/// visual projection remain consumer concerns.
pub const EquipmentSwitch = struct {
    value: std.atomic.Value(u8),

    pub fn init(enabled: bool) EquipmentSwitch {
        return .{ .value = .init(@intFromBool(enabled)) };
    }

    pub fn isEnabled(self: *const EquipmentSwitch) bool {
        return self.value.load(.acquire) != 0;
    }

    pub fn setEnabled(self: *EquipmentSwitch, enabled: bool) void {
        self.value.store(@intFromBool(enabled), .release);
    }

    pub fn toggle(self: *EquipmentSwitch) bool {
        const enabled = !self.isEnabled();
        self.setEnabled(enabled);
        return enabled;
    }
};

test "equipment switch exposes one canonical state across consumers" {
    var state = EquipmentSwitch.init(true);
    try std.testing.expect(state.isEnabled());
    try std.testing.expect(!state.toggle());
    try std.testing.expect(!state.isEnabled());
    state.setEnabled(true);
    try std.testing.expect(state.isEnabled());
}
