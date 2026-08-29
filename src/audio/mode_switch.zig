const equipment_state = @import("../core/equipment_state.zig");
const std = @import("std");

const ThreePosition = equipment_state.ThreePosition;

/// Coordinates any discrete processor selection through the dry point without
/// evaluating the outgoing and incoming neural models concurrently.
pub fn DiscreteTransition(comptime State: type) type {
    return struct {
        const Self = @This();

        active: State,

        pub fn init(initial: State) Self {
            return .{ .active = initial };
        }

        pub fn activeState(self: Self) State {
            return self.active;
        }

        pub fn wantsWet(self: Self, requested: State, bypass: State) bool {
            return self.active != bypass and requested == self.active;
        }

        pub fn completeWhenDry(self: *Self, requested: State, wet_mix: f32) ?State {
            if (requested == self.active or wet_mix > 0.0) return null;
            self.active = requested;
            return requested;
        }
    };
}

/// Coordinates a discrete processor change through the dry point of an
/// existing wet/dry smoother. This avoids evaluating two expensive neural
/// models concurrently on the real-time thread.
pub const Transition = struct {
    active: ThreePosition,

    pub fn init(initial: ThreePosition) Transition {
        return .{ .active = initial };
    }

    pub fn activePosition(self: Transition) ThreePosition {
        return self.active;
    }

    pub fn wantsWet(self: Transition, enabled: bool, requested: ThreePosition) bool {
        return enabled and requested == self.active;
    }

    /// Returns the newly selected position exactly once, after the wet path is
    /// fully silent. The caller can then reset that model before the next block.
    pub fn completeWhenDry(
        self: *Transition,
        requested: ThreePosition,
        wet_mix: f32,
    ) ?ThreePosition {
        if (requested == self.active or wet_mix > 0.0) return null;
        self.active = requested;
        return requested;
    }
};

test "mode transition fades out before selecting and fades in afterward" {
    var transition = Transition.init(.middle);
    try std.testing.expect(transition.wantsWet(true, .middle));
    try std.testing.expect(!transition.wantsWet(true, .high));
    try std.testing.expectEqual(@as(?ThreePosition, null), transition.completeWhenDry(.high, 0.1));
    try std.testing.expectEqual(ThreePosition.high, transition.completeWhenDry(.high, 0.0).?);
    try std.testing.expect(transition.wantsWet(true, .high));
    try std.testing.expect(!transition.wantsWet(false, .high));
}

test "discrete transition supports bypass plus three captured states" {
    const State = enum { bypass, orange, red, both };
    const StateTransition = DiscreteTransition(State);
    var transition = StateTransition.init(.both);
    try std.testing.expect(transition.wantsWet(.both, .bypass));
    try std.testing.expect(!transition.wantsWet(.orange, .bypass));
    try std.testing.expectEqual(@as(?State, null), transition.completeWhenDry(.orange, 0.2));
    try std.testing.expectEqual(State.orange, transition.completeWhenDry(.orange, 0.0).?);
    try std.testing.expect(transition.wantsWet(.orange, .bypass));
    try std.testing.expectEqual(State.bypass, transition.completeWhenDry(.bypass, 0.0).?);
    try std.testing.expect(!transition.wantsWet(.bypass, .bypass));
}
