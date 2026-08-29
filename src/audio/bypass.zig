const std = @import("std");

/// Click-free wet/dry transition driven by a canonical external bypass state.
pub const Smoother = struct {
    wet_mix: f32,
    maximum_delta: f32,

    pub fn init(enabled: bool, sample_rate: f64, transition_seconds: f64) !Smoother {
        if (!std.math.isFinite(sample_rate) or sample_rate <= 0 or
            !std.math.isFinite(transition_seconds) or transition_seconds <= 0)
        {
            return error.InvalidBypassTransition;
        }
        return .{
            .wet_mix = if (enabled) 1.0 else 0.0,
            .maximum_delta = @floatCast(1.0 / (sample_rate * transition_seconds)),
        };
    }

    pub fn process(self: *Smoother, dry: f32, wet: f32, enabled: bool) f32 {
        const target: f32 = if (enabled) 1.0 else 0.0;
        if (self.wet_mix < target) {
            self.wet_mix = @min(self.wet_mix + self.maximum_delta, target);
        } else if (self.wet_mix > target) {
            self.wet_mix = @max(self.wet_mix - self.maximum_delta, target);
        }
        return dry + (wet - dry) * self.wet_mix;
    }

    pub fn wetMix(self: Smoother) f32 {
        return self.wet_mix;
    }
};

test "bypass smoother reaches both endpoints without overshoot" {
    var smoother = try Smoother.init(false, 100.0, 0.04);
    try std.testing.expectEqual(@as(f32, 0.25), smoother.process(0.0, 1.0, true));
    try std.testing.expectEqual(@as(f32, 0.50), smoother.process(0.0, 1.0, true));
    try std.testing.expectEqual(@as(f32, 0.75), smoother.process(0.0, 1.0, true));
    try std.testing.expectEqual(@as(f32, 1.00), smoother.process(0.0, 1.0, true));
    try std.testing.expectEqual(@as(f32, 0.75), smoother.process(0.0, 1.0, false));
    _ = smoother.process(0.0, 1.0, false);
    _ = smoother.process(0.0, 1.0, false);
    _ = smoother.process(0.0, 1.0, false);
    try std.testing.expectEqual(@as(f32, 0.0), smoother.wetMix());
}
