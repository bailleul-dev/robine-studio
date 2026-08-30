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

pub const ThreePosition = enum(u8) {
    low,
    middle,
    high,

    pub fn next(self: ThreePosition) ThreePosition {
        return switch (self) {
            .low => .middle,
            .middle => .high,
            .high => .low,
        };
    }
};

pub const EquipmentModeSwitch = struct {
    value: std.atomic.Value(u8),

    pub fn init(initial_position: ThreePosition) EquipmentModeSwitch {
        return .{ .value = .init(@intFromEnum(initial_position)) };
    }

    pub fn position(self: *const EquipmentModeSwitch) ThreePosition {
        return @enumFromInt(self.value.load(.acquire));
    }

    pub fn setPosition(self: *EquipmentModeSwitch, position_value: ThreePosition) void {
        self.value.store(@intFromEnum(position_value), .release);
    }

    pub fn cycle(self: *EquipmentModeSwitch) ThreePosition {
        const result = self.position().next();
        self.setPosition(result);
        return result;
    }
};

pub const AmplifierId = enum(u8) {
    bogner,
    dumble,
    mesa,
};

/// UI-owned exclusive amplifier selection observed by the audio callback.
/// Selecting one identifier implicitly powers down the other amplifiers.
pub const AmplifierSelector = struct {
    value: std.atomic.Value(u8),

    pub fn init(initial: AmplifierId) AmplifierSelector {
        return .{ .value = .init(@intFromEnum(initial)) };
    }

    pub fn selected(self: *const AmplifierSelector) AmplifierId {
        return @enumFromInt(self.value.load(.acquire));
    }

    pub fn select(self: *AmplifierSelector, amplifier: AmplifierId) void {
        self.value.store(@intFromEnum(amplifier), .release);
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

test "three-position equipment selector cycles deterministically" {
    var state = EquipmentModeSwitch.init(.middle);
    try std.testing.expectEqual(ThreePosition.middle, state.position());
    try std.testing.expectEqual(ThreePosition.high, state.cycle());
    try std.testing.expectEqual(ThreePosition.low, state.cycle());
    try std.testing.expectEqual(ThreePosition.middle, state.cycle());
}

test "amplifier selection is exclusive and atomically observable" {
    var selector = AmplifierSelector.init(.dumble);
    try std.testing.expectEqual(AmplifierId.dumble, selector.selected());
    selector.select(.bogner);
    try std.testing.expectEqual(AmplifierId.bogner, selector.selected());
    selector.select(.mesa);
    try std.testing.expectEqual(AmplifierId.mesa, selector.selected());
}
