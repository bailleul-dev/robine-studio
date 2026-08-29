const equipment_state = @import("../core/equipment_state.zig");
const std = @import("std");

const ThreePosition = equipment_state.ThreePosition;

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
